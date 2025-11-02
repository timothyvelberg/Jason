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
    
    weak var appSwitcherManager: AppSwitcherManager?
    weak var circularUIManager: CircularUIManager?
    private var refreshTimer: Timer?
    
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
    }
    
    private var appEntries: [AppEntry] = []
    
    // MARK: - Initialization
    
    init() {
        print("🔄 CombinedAppsProvider initialized")
        loadApps()
        
        // Listen for app launch/quit notifications
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }
    
    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        stopAutoRefresh()
    }
    
    // MARK: - App Loading
    
    private func loadApps() {
        var entries: [AppEntry] = []
        
        // 1. Get favorite apps from database (in sort_order)
        let favorites = DatabaseManager.shared.getFavoriteApps()
        print("📋 [CombinedApps] Loaded \(favorites.count) favorite apps from database")
        
        // 2. Get running apps
        let runningApps = NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular &&
            app.bundleIdentifier != Bundle.main.bundleIdentifier
        }
        print("🏃 [CombinedApps] Found \(runningApps.count) running apps")
        
        // Create a map of running apps by bundle ID for quick lookup
        let runningAppsMap = Dictionary(uniqueKeysWithValues: runningApps.compactMap { app -> (String, NSRunningApplication)? in
            guard let bundleId = app.bundleIdentifier else { return nil }
            return (bundleId, app)
        })
        
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
        let nonFavoriteRunningApps = runningApps
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
        
        print("✅ [CombinedApps] Total apps: \(appEntries.count)")
        print("   ⭐ Favorites: \(favoriteCount) (running: \(entries.filter { $0.isFavorite && $0.isRunning }.count))")
        print("   🏃 Non-favorite running: \(runningNonFavoriteCount)")
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
                    sortOrder: sortOrder
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
        let appName = customName ?? (
            bundle.infoDictionary?["CFBundleName"] as? String ??
            bundle.infoDictionary?["CFBundleDisplayName"] as? String ??
            appURL.deletingPathExtension().lastPathComponent
        )
        
        // Get icon
        let appIcon: NSImage
        if let iconOverride = iconOverride,
           let customIcon = NSImage(systemSymbolName: iconOverride, accessibilityDescription: nil) {
            appIcon = customIcon
        } else {
            appIcon = NSWorkspace.shared.icon(forFile: appURL.path)
        }
        
        return AppEntry(
            bundleIdentifier: bundleIdentifier,
            name: appName,
            icon: appIcon,
            url: appURL,
            isFavorite: isFavorite,
            isRunning: isRunning,
            runningApp: runningApp,
            customIconName: iconOverride,
            sortOrder: sortOrder
        )
    }
    
    // MARK: - FunctionProvider Methods
    
    func provideFunctions() -> [FunctionNode] {
        let appNodes = appEntries.map { entry in
            // Create context actions
            var contextActions: [FunctionNode] = []
            
            if entry.isRunning, let runningApp = entry.runningApp, let manager = appSwitcherManager {
                // Running app actions (only if manager exists)
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
                icon: entry.icon,
                contextActions: contextActions.isEmpty ? nil : contextActions,
                itemAngleSize: 16,
                slicePositioning: .center,
                providerId: providerId,
                // EXPLICIT INTERACTION MODEL:
                onLeftClick: .execute { [weak self] in
                    self?.launchOrSwitchToApp(entry)
                },
                onRightClick: contextActions.isEmpty ? .doNothing : .expand,
                onMiddleClick: .executeKeepOpen { [weak self] in
                    self?.launchOrSwitchToApp(entry)
                },
                onBoundaryCross: .doNothing,
                onHover: {
                    print("Hovering over \(entry.name) (⭐: \(entry.isFavorite), 🏃: \(entry.isRunning))")
                },
                onHoverExit: {
                    print("Left \(entry.name)")
                }
            )
        }
        
        return [
            FunctionNode(
                id: providerId,
                name: providerName,
                icon: providerIcon,
                children: appNodes,
                preferredLayout: .partialSlice,
                slicePositioning: .center,
                providerId: providerId,
                onLeftClick: .expand,
                onRightClick: .execute { [weak self] in
                    self?.openApplicationsFolder()
                },
                onMiddleClick: .expand,
                onBoundaryCross: .expand,
                onHover: {
                    print("📱 Hovering over Applications category")
                },
                onHoverExit: {
                    print("📱 Left Applications category")
                }
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
                    self.appSwitcherManager?.recordAppUsage(app)
                    
                    // Refresh to update running state
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.refresh()
                        NotificationCenter.default.postProviderUpdate(providerId: self.providerId)
                    }
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
            icon: NSImage(systemSymbolName: "star", accessibilityDescription: nil) ?? NSImage(),
            onLeftClick: .execute { [weak self] in
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
            },
            onRightClick: .doNothing,
            onMiddleClick: .doNothing,
            onBoundaryCross: .doNothing
        )
    }
    
    private func createRemoveFromFavoritesAction(bundleIdentifier: String, name: String) -> FunctionNode {
        return FunctionNode(
            id: "remove-favorite-\(bundleIdentifier)",
            name: "Remove from Favorites",
            icon: NSImage(systemSymbolName: "star.slash", accessibilityDescription: nil) ?? NSImage(),
            onLeftClick: .execute { [weak self] in
                print("⭐ Removing \(name) from favorites")
                let success = DatabaseManager.shared.removeFavoriteApp(bundleIdentifier: bundleIdentifier)
                if success {
                    print("✅ Removed \(name) from favorites")
                    self?.refresh()
                    NotificationCenter.default.postProviderUpdate(providerId: self?.providerId ?? "combined-apps")
                }
            },
            onRightClick: .doNothing,
            onMiddleClick: .doNothing,
            onBoundaryCross: .doNothing
        )
    }
    
    // MARK: - Auto Refresh
    
    func startAutoRefresh() {
        stopAutoRefresh()
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Save current state
            let oldAppCount = self.appEntries.count
            let oldBundleIds = Set(self.appEntries.map { $0.bundleIdentifier })
            
            // Reload
            self.loadApps()
            
            // Check if there were changes
            let newBundleIds = Set(self.appEntries.map { $0.bundleIdentifier })
            
            if oldAppCount != self.appEntries.count || oldBundleIds != newBundleIds {
                print("🔄 [CombinedApps] Changes detected via timer - posting update")
                NotificationCenter.default.postProviderUpdate(providerId: self.providerId)
            }
        }
        
        print("✅ [CombinedApps] Auto-refresh timer started (1 second interval)")
    }
    
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        print("🛑 [CombinedApps] Auto-refresh timer stopped")
    }
    
    // MARK: - App Launch/Quit Notifications
    
    @objc private func handleAppLaunched(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.activationPolicy == .regular,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }
        
        print("🚀 [CombinedApps] App launched: \(app.localizedName ?? "Unknown")")
        refresh()
        NotificationCenter.default.postProviderUpdate(providerId: providerId)
    }
    
    @objc private func handleAppTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        
        print("🛑 [CombinedApps] App terminated: \(app.localizedName ?? "Unknown")")
        refresh()
        NotificationCenter.default.postProviderUpdate(providerId: providerId)
    }
}
