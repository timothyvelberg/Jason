//
//  FavoriteAppsProvider.swift
//  Jason
//
//  Created by Timothy Velberg on 09/10/2025.
//
//  Provider for favorite/pinned applications


import Foundation
import AppKit

class FavoriteAppsProvider: ObservableObject, FunctionProvider {
    
    // MARK: - FunctionProvider Protocol
    
    var providerId: String {
        return "favorite-apps"
    }
    
    var providerName: String {
        return "Favorites"
    }
    
    var providerIcon: NSImage {
        return NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil) ?? NSImage()
    }
    
    // MARK: - Properties
    
    // Cache resolved apps to avoid repeated lookups
    private var resolvedApps: [AppInfo] = []
    weak var appSwitcherManager: AppSwitcherManager?
    
    // MARK: - App Info Structure
    
    struct AppInfo {
        let bundleIdentifier: String
        let name: String
        let icon: NSImage
        let url: URL
        let customIconName: String?  // Optional custom icon override
    }
    
    // MARK: - Initialization
    
    init() {
        print("FavoriteAppsProvider initialized")
        loadFavoriteApps()
    }
    
    // MARK: - App Loading
    
    private func loadFavoriteApps() {
        resolvedApps.removeAll()
        
        // Load favorite apps from database
        let favorites = DatabaseManager.shared.getFavoriteApps()
        
        print("[FavoriteAppsProvider] Loaded \(favorites.count) favorite apps from database")
        
        for favorite in favorites {
            if let appInfo = findApp(
                bundleIdentifier: favorite.bundleIdentifier,
                customName: favorite.displayName,
                iconOverride: favorite.iconOverride
            ) {
                resolvedApps.append(appInfo)
//                print("✅ Found favorite app: \(appInfo.name)")
            } else {
                print("⚠️ Could not find app with bundle ID: \(favorite.bundleIdentifier)")
            }
        }
        
        print("[FavoriteAppsProvider] Resolved \(resolvedApps.count) favorite apps")
    }
    
    private func findApp(bundleIdentifier: String, customName: String?, iconOverride: String?) -> AppInfo? {
        // Try to find app using NSWorkspace
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        
        guard let bundle = Bundle(url: appURL) else {
            return nil
        }
        
        // Use custom name if provided, otherwise get from bundle
        let appName = customName ?? (
            bundle.infoDictionary?["CFBundleName"] as? String ??
            bundle.infoDictionary?["CFBundleDisplayName"] as? String ??
            appURL.deletingPathExtension().lastPathComponent
        )
        
        // Get icon - use override if specified, otherwise system icon
        let appIcon: NSImage
        if let iconOverride = iconOverride {
            // Try to load custom SF Symbol
            if let customIcon = NSImage(systemSymbolName: iconOverride, accessibilityDescription: nil) {
                appIcon = customIcon
            } else {
                // Fall back to app's icon
                appIcon = NSWorkspace.shared.icon(forFile: appURL.path)
            }
        } else {
            appIcon = NSWorkspace.shared.icon(forFile: appURL.path)
        }
        
        return AppInfo(
            bundleIdentifier: bundleIdentifier,
            name: appName,
            icon: appIcon,
            url: appURL,
            customIconName: iconOverride
        )
    }
    
    // MARK: - FunctionProvider Methods
    
    func provideFunctions() -> [FunctionNode] {
        // Convert favorite apps to FunctionNodes with explicit interaction model
        let appNodes = resolvedApps.map { appInfo in
            FunctionNode(
                id: "fav-\(appInfo.bundleIdentifier)",
                name: appInfo.name,
                type: .app,
                icon: appInfo.icon,
                preferredLayout: nil,
                showLabel: true,
                // EXPLICIT INTERACTION MODEL:
                onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                    self?.launchApp(appInfo)
                }),
                onRightClick: ModifierAwareInteraction(base: .doNothing),  // Could add "Remove from Favorites" context menu later
                onMiddleClick: ModifierAwareInteraction(base: .executeKeepOpen { [weak self] in
                    self?.launchApp(appInfo)
                }),
                onBoundaryCross: ModifierAwareInteraction(base: .doNothing),
                onHover: {
                    print("Hovering over favorite: \(appInfo.name)")
                },
                onHoverExit: {
                    print("Left favorite: \(appInfo.name)")
                }
            )
        }
        
        // Return as a single category node
        return [
            FunctionNode(
                id: providerId,
                name: providerName,
                type: .category,
                icon: providerIcon,
                children: appNodes,
                
                preferredLayout: .partialSlice,  // Use partial slice for compact display
                slicePositioning: .center,

                // EXPLICIT INTERACTION MODEL:
                onLeftClick: ModifierAwareInteraction(base: .expand),           // Click to expand favorites
                onRightClick: ModifierAwareInteraction(base: .expand),          // Right-click also expands
                onMiddleClick: ModifierAwareInteraction(base: .expand),         // Middle-click expands
                onBoundaryCross: ModifierAwareInteraction(base: .expand),       // Auto-expand on boundary cross
                onHover: {
                    print("⭐ Hovering over Favorites category")
                },
                onHoverExit: {
                    print("⭐ Left Favorites category")
                }
            )
        ]
    }
    
    func refresh() {
        // Reload favorite apps from database
        print("🔄 [FavoriteAppsProvider] Refreshing favorite apps")
        loadFavoriteApps()
    }
    
    // MARK: - App Actions
    
    private func launchApp(_ appInfo: AppInfo) {
        print("🚀 Launching favorite app: \(appInfo.name)")
        
        // Track app launch in database
        DatabaseManager.shared.updateAppAccess(bundleIdentifier: appInfo.bundleIdentifier)
        
        // Launch the app
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true  // Bring app to front
        
        NSWorkspace.shared.openApplication(at: appInfo.url, configuration: configuration) { app, error in
            if let error = error {
                print("❌ Failed to launch \(appInfo.name): \(error.localizedDescription)")
            } else if let app = app {
                print("✅ Successfully launched \(appInfo.name)")
                
                // 🆕 Update MRU tracking so the app appears at the top of the list
                self.appSwitcherManager?.recordAppUsage(app)
                print("📊 Updated MRU tracking for \(appInfo.name)")
            }
        }
    }
    
    // MARK: - Favorites Management (Database-backed)
    
    /// Add app to favorites (saves to database)
    func addFavorite(bundleIdentifier: String, displayName: String? = nil, iconOverride: String? = nil) -> Bool {
        // Try to find the app first to get its name
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            print("⚠️ [FavoriteAppsProvider] Could not find app: \(bundleIdentifier)")
            return false
        }
        
        guard let bundle = Bundle(url: appURL) else {
            print("⚠️ [FavoriteAppsProvider] Could not load bundle: \(bundleIdentifier)")
            return false
        }
        
        // Get app name
        let appName = displayName ?? (
            bundle.infoDictionary?["CFBundleName"] as? String ??
            bundle.infoDictionary?["CFBundleDisplayName"] as? String ??
            appURL.deletingPathExtension().lastPathComponent
        )
        
        // Add to database
        let success = DatabaseManager.shared.addFavoriteApp(
            bundleIdentifier: bundleIdentifier,
            displayName: appName,
            iconOverride: iconOverride
        )
        
        if success {
            print("➕ [FavoriteAppsProvider] Added to favorites: \(appName)")
            // Reload apps to reflect changes
            loadFavoriteApps()
        } else {
            print("⚠️ [FavoriteAppsProvider] Failed to add favorite (may already exist)")
        }
        
        return success
    }
    
    /// Remove app from favorites (removes from database)
    func removeFavorite(bundleIdentifier: String) -> Bool {
        let success = DatabaseManager.shared.removeFavoriteApp(bundleIdentifier: bundleIdentifier)
        
        if success {
            print("➖ [FavoriteAppsProvider] Removed from favorites: \(bundleIdentifier)")
            // Reload apps to reflect changes
            loadFavoriteApps()
        }
        
        return success
    }
    
    /// Update favorite app settings (display name and icon)
    func updateFavorite(bundleIdentifier: String, displayName: String, iconOverride: String?) -> Bool {
        let success = DatabaseManager.shared.updateFavoriteApp(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            iconOverride: iconOverride
        )
        
        if success {
            print("✏️ [FavoriteAppsProvider] Updated favorite: \(displayName)")
            // Reload apps to reflect changes
            loadFavoriteApps()
        }
        
        return success
    }
    
    /// Reorder favorites (updates sort_order in database)
    func reorderFavorites(from: Int, to: Int) -> Bool {
        let favorites = DatabaseManager.shared.getFavoriteApps()
        
        guard favorites.indices.contains(from),
              favorites.indices.contains(to) else {
            return false
        }
        
        // Create mutable array of favorites
        var reordered = favorites
        let item = reordered.remove(at: from)
        reordered.insert(item, at: to)
        
        // Update sort_order for all items
        var success = true
        for (index, favorite) in reordered.enumerated() {
            if !DatabaseManager.shared.reorderFavoriteApps(
                bundleIdentifier: favorite.bundleIdentifier,
                newSortOrder: index
            ) {
                success = false
            }
        }
        
        if success {
            print("🔄 [FavoriteAppsProvider] Reordered favorites")
            // Reload apps to reflect changes
            loadFavoriteApps()
        }
        
        return success
    }
}
