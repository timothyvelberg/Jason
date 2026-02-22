//
//  DockBadgeReader.swift
//  Jason
//
//  Reads dock badge counts from running applications
//  Uses Accessibility API to read badges directly from the Dock
//

import Foundation
import AppKit

/// Reads dock badge counts from running applications using Accessibility API
class DockBadgeReader {
    
    // MARK: - Singleton
    
    static let shared = DockBadgeReader()
    
    // MARK: - State
    
    /// Cached badges: [bundleIdentifier: badgeText]
    private var cachedBadges: [String: String] = [:]
    
    /// Last refresh timestamp
    private var lastRefresh: Date = .distantPast
    
    /// Cache duration
    private let cacheDuration: TimeInterval = 2.0
    
    /// Whether we have accessibility permission
    var isAvailable: Bool {
        return PermissionManager.shared.hasAccessibilityAccess
    }
    
    // MARK: - Initialization
    
    private init() {
        if PermissionManager.shared.hasAccessibilityAccess {
            print("[DockBadgeReader] Accessibility API available")
        } else {
            print("[DockBadgeReader] Accessibility permission not granted")
        }
    }
    
    // MARK: - Public API
    
    /// Get badge for a specific bundle identifier
    /// Returns nil if no badge, or the badge string (number, "•", or text)
    func getBadge(forBundleIdentifier bundleId: String) -> String? {
        refreshCacheIfNeeded()
        return cachedBadges[bundleId]
    }
    
    /// Get all app badges: [bundleIdentifier: badgeText]
    func getAllBadges() -> [String: String] {
        refreshCacheIfNeeded()
        return cachedBadges
    }
    
    /// Check if an app has any badge
    func hasBadge(bundleIdentifier: String) -> Bool {
        return getBadge(forBundleIdentifier: bundleIdentifier) != nil
    }
    
    /// Force refresh the cache (call when ring shows or app events occur)
    func forceRefresh() {
        lastRefresh = .distantPast
        refreshCacheIfNeeded()
    }
    
    // MARK: - Private Methods
    
    private func refreshCacheIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastRefresh) > cacheDuration else {
            return
        }
        
        cachedBadges = fetchAllBadges()
        lastRefresh = now
    }
    
    private func fetchAllBadges() -> [String: String] {
        guard isAvailable else {
            return [:]
        }
        
        // Build a map of app name -> bundle ID from running apps
        let appNameToBundleId = buildAppNameMap()
        
        // Read badges from Dock
        let dockBadges = readDockBadges()
        
        // Convert app names to bundle IDs
        var badges: [String: String] = [:]
        for (appName, badge) in dockBadges {
            if let bundleId = appNameToBundleId[appName] {
                badges[bundleId] = badge
            } else {
                // Try case-insensitive match
                let lowercaseName = appName.lowercased()
                if let match = appNameToBundleId.first(where: { $0.key.lowercased() == lowercaseName }) {
                    badges[match.value] = badge
                }
            }
        }
        
        return badges
    }
    
    /// Build a map of app display name -> bundle ID from running apps
    private func buildAppNameMap() -> [String: String] {
        var map: [String: String] = [:]
        
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleId = app.bundleIdentifier,
                  let name = app.localizedName else {
                continue
            }
            
            // Strip invisible Unicode characters (e.g., left-to-right mark U+200E)
            let cleanName = name.filter { !$0.isInvisible }
            
            map[cleanName] = bundleId
        }
        
        return map
    }
    
    /// Read badges directly from the Dock via Accessibility API
    private func readDockBadges() -> [String: String] {
        guard let dockApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dock" }) else {
            return [:]
        }
        
        let dockElement = AXUIElementCreateApplication(dockApp.processIdentifier)
        
        var childrenRef: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(dockElement, kAXChildrenAttribute as CFString, &childrenRef)
        
        guard childrenResult == .success, let children = childrenRef as? [AXUIElement] else {
            return [:]
        }
        
        var badges: [String: String] = [:]
        
        for child in children {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
            
            if (roleRef as? String) == "AXList" {
                var listChildrenRef: CFTypeRef?
                let listResult = AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &listChildrenRef)
                
                if listResult == .success, let listChildren = listChildrenRef as? [AXUIElement] {
                    for item in listChildren {
                        var titleRef: CFTypeRef?
                        AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleRef)
                        guard let title = titleRef as? String, !title.isEmpty else {
                            continue
                        }
                        
                        var statusRef: CFTypeRef?
                        AXUIElementCopyAttributeValue(item, "AXStatusLabel" as CFString, &statusRef)
                        
                        if let badge = statusRef as? String, !badge.isEmpty {
                            badges[title] = badge
                        }
                    }
                }
            }
        }
        
        return badges
    }
}

// MARK: - Character Extension

private extension Character {
    /// Returns true if this character is an invisible Unicode control character
    var isInvisible: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        // Common invisible characters:
        // U+200E (LTR mark), U+200F (RTL mark), U+200B (zero-width space),
        // U+FEFF (BOM/zero-width no-break space), etc.
        return scalar.properties.isDefaultIgnorableCodePoint
    }
}
