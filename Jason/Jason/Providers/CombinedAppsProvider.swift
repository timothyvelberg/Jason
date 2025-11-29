//
//  CombinedAppsProvider.swift
//  Jason
//
//  Created by Timothy Velberg on 02/11/2025.
//
//  Provider that combines favorite apps and running apps into a single unified list

import Foundation
import AppKit

class CombinedAppsProvider: ObservableObject, FunctionProvider {
    
    // MARK: - FunctionProvider Protocol
    
    var providerId: String {
        return "combined-apps"
    }
    
    var providerName: String {
        return "Applications"
    }
    
    var providerIcon: NSImage {
        return NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: nil) ?? NSImage()
    }
    
    // MARK: - Properties
    
    ///This now references AppSwitcherManager.shared (set by ProviderFactory)
    weak var appSwitcherManager: AppSwitcherManager?
    weak var circularUIManager: CircularUIManager?
    
    // MARK: - App Entry Structure
    
    private struct AppEntry {
        let bundleIdentifier: String
        let name: String
        let icon: NSImage
        let url: URL
        let isFavorite: Bool
        let isRunning: Bool
        let runningApp: NSRunningApplication?
        let customIconName: String?
        let sortOrder: Int? // Only for favorites
        let badge: String?
        
    }
    
    private var appEntries: [AppEntry] = []
    
    // MARK: - Initialization
    
    init() {
        print("🔄 CombinedAppsProvider initialized")
        loadApps()
        
        // 🆕 REMOVED: NSWorkspace notification listeners
        // AppSwitcherManager.shared already monitors apps and posts unified notifications
        // This prevents duplicate notifications when multiple CombinedAppsProvider instances exist
    }
    
    // 🆕 REMOVED: deinit - no notification cleanup needed
    
    // MARK: - App Loading
    
    private func loadApps() {
        var entries: [AppEntry] = []
        
        // 1. Get favorite apps from database (in sort_order)
        let favorites = DatabaseManager.shared.getFavoriteApps()
//        print("📋 [CombinedApps] Loaded \(favorites.count) favorite apps from database")
        
        // 2. Get running apps from AppSwitcherManager (already deduplicated!)
        // This ensures we use the same source of truth as AppSwitcherManager
        let runningApps = AppSwitcherManager.shared.runningApps
//        print("🏃 [CombinedApps] Found \(runningApps.count) running apps")
        
        // Create a map of running apps by bundle ID for quick lookup
        // AppSwitcherManager already deduplicates, so we just create the map
        let runningAppsMap: [String: NSRunningApplication] = Dictionary(
            uniqueKeysWithValues: runningApps.compactMap { app in
                guard let bundleId = app.bundleIdentifier else { return nil }
                return (bundleId, app)
            }
        )
        
        // 3. Add favorite apps first (in database order)
        for (index, favorite) in favorites.enumerated() {
            if let appEntry = createAppEntry(
                bundleIdentifier: favorite.bundleIdentifier,
                customName: favorite.displayName,
                iconOverride: favorite.iconOverride,
                isFavorite: true,
                sortOrder: index,
                runningAppsMap: runningAppsMap
            ) {
                entries.append(appEntry)
            }
        }
        
        // 4. Add non-favorite running apps (alphabetically sorted for consistency)
        let favoriteBundleIds = Set(favorites.map { $0.bundleIdentifier })
        // Use deduplicated map instead of original runningApps array (which can have duplicate PIDs)
        let nonFavoriteRunningApps = Array(runningAppsMap.values)
            .filter { app in
                guard let bundleId = app.bundleIdentifier else { return false }
                return !favoriteBundleIds.contains(bundleId)
            }
            .sorted { app1, app2 in
                let name1 = app1.localizedName ?? ""
                let name2 = app2.localizedName ?? ""
                return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
            }
        
        for runningApp in nonFavoriteRunningApps {
            guard let bundleId = runningApp.bundleIdentifier else { continue }
            
            if let appEntry = createAppEntry(
                bundleIdentifier: bundleId,
                customName: nil,
                iconOverride: nil,
                isFavorite: false,
                sortOrder: nil,
                runningAppsMap: runningAppsMap
            ) {
                entries.append(appEntry)
            }
        }
        
        appEntries = entries
        
        let favoriteCount = entries.filter { $0.isFavorite }.count
        let runningNonFavoriteCount = entries.filter { !$0.isFavorite && $0.isRunning }.count
        
        print("[CombinedApps] Total apps: \(appEntries.count)")
        print("   Favorites: \(favoriteCount)")
        print("   Non-favorites: \(runningNonFavoriteCount)")
        print("   Source: AppSwitcherManager (\(runningApps.count) deduplicated apps)")
    }
    
    private func createAppEntry(
        bundleIdentifier: String,
        customName: String?,
        iconOverride: String?,
        isFavorite: Bool,
        sortOrder: Int?,
        runningAppsMap: [String: NSRunningApplication]
    ) -> AppEntry? {
        // Check if app is running
        let runningApp = runningAppsMap[bundleIdentifier]
        let isRunning = runningApp != nil
        
        // Get app URL
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            // If app is running, we can still get info from the running instance
            if let runningApp = runningApp {
                let name = customName ?? runningApp.localizedName ?? "Unknown"
                let icon: NSImage
                if let iconOverride = iconOverride,
                   let customIcon = NSImage(systemSymbolName: iconOverride, accessibilityDescription: nil) {
                    icon = customIcon
                } else {
                    icon = runningApp.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!
                }
                
                return AppEntry(
                    bundleIdentifier: bundleIdentifier,
                    name: name,
                    icon: icon,
                    url: runningApp.bundleURL ?? URL(fileURLWithPath: "/"),
                    isFavorite: isFavorite,
                    isRunning: true,
                    runningApp: runningApp,
                    customIconName: iconOverride,
                    sortOrder: sortOrder,
                    badge: DockBadgeReader.shared.getBadge(forBundleIdentifier: bundleIdentifier)
                )
            }
            
            // App not found and not running - skip it
            if isFavorite {
                print("⚠️ [CombinedApps] Favorite app not found: \(bundleIdentifier)")
            }
            return nil
        }
        
        guard let bundle = Bundle(url: appURL) else {
            return nil
        }
        
        // Get app name
        let name: String
        if let customName = customName {
            name = customName
        } else if let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
            name = bundleName
        } else if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
            name = displayName
        } else {
            name = appURL.deletingPathExtension().lastPathComponent
        }
        
        // Get app icon
        let icon: NSImage
        if let iconOverride = iconOverride,
           let customIcon = NSImage(systemSymbolName: iconOverride, accessibilityDescription: nil) {
            icon = customIcon
        } else if isRunning, let runningApp = runningApp, let appIcon = runningApp.icon {
            icon = appIcon
        } else {
            // Try to get icon from file system
            let fileIcon = NSWorkspace.shared.icon(forFile: appURL.path)
            
            // Validate icon - check if it's valid by checking size
            // Invalid/missing icons typically have zero size
            if fileIcon.size.width > 0 && fileIcon.size.height > 0 {
                icon = fileIcon
            } else {
                // Fallback: use generic application icon
                print("⚠️ [CombinedApps] Failed to load icon for \(name), using fallback")
                icon = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
            }
        }
        
        return AppEntry(
            bundleIdentifier: bundleIdentifier,
            name: name,
            icon: icon,
            url: appURL,
            isFavorite: isFavorite,
            isRunning: isRunning,
            runningApp: runningApp,
            customIconName: iconOverride,
            sortOrder: sortOrder,
            badge: isRunning ? DockBadgeReader.shared.getBadge(forBundleIdentifier: bundleIdentifier) : nil
        )
    }
    
    // MARK: - FunctionProvider Protocol
    
    func provideFunctions() -> [FunctionNode] {
        // Create nodes for each app
        let appNodes: [FunctionNode] = appEntries.map { entry in
            // Get AppSwitcherManager for context actions
            // 🆕 CHANGED: This is now AppSwitcherManager.shared
            let manager = appSwitcherManager
            
            var contextActions: [FunctionNode] = []
            
            // Add app-specific actions if running
            if entry.isRunning, let runningApp = entry.runningApp, let manager = manager {
                contextActions = [
                    StandardContextActions.bringToFront(runningApp, manager: manager),
                    StandardContextActions.quitApp(runningApp, manager: manager),
                    StandardContextActions.hideApp(runningApp, manager: manager)
                ]
            }
            
            // Add favorite management actions
            if entry.isFavorite {
                contextActions.append(
                    createRemoveFromFavoritesAction(bundleIdentifier: entry.bundleIdentifier, name: entry.name)
                )
            } else if entry.isRunning {
                // Only show "Add to Favorites" for running apps
                contextActions.append(
                    createAddToFavoritesAction(bundleIdentifier: entry.bundleIdentifier, name: entry.name)
                )
            }
            
            return FunctionNode(
                id: "combined-app-\(entry.bundleIdentifier)",
                name: entry.name,
                type: .app,
                icon: entry.icon,
                contextActions: contextActions.isEmpty ? nil : contextActions,
                slicePositioning: .center,
                metadata: [
                    "isRunning": entry.isRunning,
                    "badge": entry.badge as Any
                ],
                providerId: providerId,
                onLeftClick: ModifierAwareInteraction(
                        base: .execute { [weak self] in
                            self?.launchOrSwitchToApp(entry)
                        },
                        shift: .executeKeepOpen { [weak self] in
                            self?.launchOrSwitchToApp(entry)
                        },
                        command: .executeKeepOpen { [weak self] in
                            // Cmd+Click = Quit the app (if running)
                            if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: entry.bundleIdentifier).first {
                                print("🚪 [Cmd+Click] Quitting app: \(entry.name)")
                                self?.appSwitcherManager?.quitApp(runningApp)
                            }
                        }
                    ),
                onRightClick: ModifierAwareInteraction(base: contextActions.isEmpty ? .doNothing : .expand),
                onMiddleClick: ModifierAwareInteraction(base: .executeKeepOpen { [weak self] in
                    self?.launchOrSwitchToApp(entry)
                }),
                onBoundaryCross: ModifierAwareInteraction(base: .doNothing)

            )
        }
        
        return [
            FunctionNode(
                id: providerId,
                name: providerName,
                type: .category,
                icon: providerIcon,
                children: appNodes,
                preferredLayout: .partialSlice,
//                parentAngleSize: 180.0, // setting 180 degree item
                slicePositioning: .center,
                providerId: providerId,
                onLeftClick: ModifierAwareInteraction(base: .expand),
                onRightClick: ModifierAwareInteraction(base: .execute { [weak self] in
                    self?.openApplicationsFolder()
                }),
                onMiddleClick: ModifierAwareInteraction(base: .expand),
                onBoundaryCross: ModifierAwareInteraction(base: .expand)
            )
        ]
    }
    
    func refresh() {
        print("🔄 [CombinedApps] Refreshing apps")
        loadApps()
    }
    
    // MARK: - App Actions
    
    private func launchOrSwitchToApp(_ entry: AppEntry) {
        if entry.isRunning, let runningApp = entry.runningApp {
            // App is already running - switch to it
            print("🔄 Switching to running app: \(entry.name)")
            
            // Record app usage in MRU tracker
            // 🆕 CHANGED: Now using shared instance
            appSwitcherManager?.recordAppUsage(runningApp)
            
            // Hide UI and switch to app
            circularUIManager?.hideAndSwitchTo(app: runningApp)
            
        } else {
            // App is not running - launch it
            print("🚀 Launching app: \(entry.name)")
            
            // Track app launch in database if it's a favorite
            if entry.isFavorite {
                DatabaseManager.shared.updateAppAccess(bundleIdentifier: entry.bundleIdentifier)
            }
            
            // Ignore focus changes temporarily to prevent UI from hiding during launch
            circularUIManager?.ignoreFocusChangesTemporarily(duration: 0.5)
            
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            
            NSWorkspace.shared.openApplication(at: entry.url, configuration: configuration) { app, error in
                if let error = error {
                    print("❌ Failed to launch \(entry.name): \(error.localizedDescription)")
                } else if let app = app {
                    print("✅ Successfully launched \(entry.name)")
                    
                    // Update MRU tracking
                    // 🆕 CHANGED: Now using shared instance
                    self.appSwitcherManager?.recordAppUsage(app)
                    
                    // 🆕 REMOVED: No need to refresh and post notification here
                    // AppSwitcherManager.shared will detect the launch and post ONE notification
                    // which all CombinedAppsProvider instances will receive via CircularUIManager
                }
            }
        }
    }
    
    private func openApplicationsFolder() {
        let applicationsURL = URL(fileURLWithPath: "/Applications")
        NSWorkspace.shared.open(applicationsURL)
    }
    
    // MARK: - Favorite Management Actions

    private func createAddToFavoritesAction(bundleIdentifier: String, name: String) -> FunctionNode {
        return FunctionNode(
            id: "add-favorite-\(bundleIdentifier)",
            name: "Add to Favorites",
            type: .action,
            icon: NSImage(systemSymbolName: "star", accessibilityDescription: nil) ?? NSImage(),
            onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                print("⭐ Adding \(name) to favorites")
                let success = DatabaseManager.shared.addFavoriteApp(
                    bundleIdentifier: bundleIdentifier,
                    displayName: name,
                    iconOverride: nil
                )
                if success {
                    print("✅ Added \(name) to favorites")
                    self?.refresh()
                    NotificationCenter.default.postProviderUpdate(providerId: self?.providerId ?? "combined-apps")
                }
            }),
            onRightClick: ModifierAwareInteraction(base: .doNothing),
            onMiddleClick: ModifierAwareInteraction(base: .doNothing),
            onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
        )
    }

    private func createRemoveFromFavoritesAction(bundleIdentifier: String, name: String) -> FunctionNode {
        return FunctionNode(
            id: "remove-favorite-\(bundleIdentifier)",
            name: "Remove from Favorites",
            type: .action,
            icon: NSImage(systemSymbolName: "star.slash", accessibilityDescription: nil) ?? NSImage(),
            onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                print("⭐ Removing \(name) from favorites")
                let success = DatabaseManager.shared.removeFavoriteApp(bundleIdentifier: bundleIdentifier)
                if success {
                    print("✅ Removed \(name) from favorites")
                    self?.refresh()
                    NotificationCenter.default.postProviderUpdate(providerId: self?.providerId ?? "combined-apps")
                }
            }),
            onRightClick: ModifierAwareInteraction(base: .doNothing),
            onMiddleClick: ModifierAwareInteraction(base: .doNothing),
            onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
        )
    }
}
