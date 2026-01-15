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
        return NSImage(named: "parent-apps") ?? NSImage()
    }
    
    // MARK: - Stable Display Order
    
    /// Tracks the stable display order of apps by bundle ID
    /// Only changes when apps are added (append) or removed (close non-favorite)
    private var displayedBundleIds: [String] = []
    // Track db order for reorder detection
    private var lastFavoritesOrder: [String] = []
    
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
    }
    
    // MARK: - App Loading
    
    private func loadApps() {
        // 1. Get current data sources
        let favorites = DatabaseManager.shared.getFavoriteApps()
        let currentFavoritesOrder = favorites.map { $0.bundleIdentifier }
        let favoriteBundleIds = Set(currentFavoritesOrder)
        
        // 2. Check if favorites were reordered in settings (not add/remove)
        let lastSet = Set(lastFavoritesOrder)
        let currentSet = Set(currentFavoritesOrder)

        if lastSet == currentSet && lastFavoritesOrder != currentFavoritesOrder {
            print("🔀 [CombinedApps] Favorites reordered in settings - rebuilding display order")
            displayedBundleIds = []
        }
        lastFavoritesOrder = currentFavoritesOrder
        
        let runningApps = AppSwitcherManager.shared.runningApps
        let runningAppsMap: [String: NSRunningApplication] = Dictionary(
            uniqueKeysWithValues: runningApps.compactMap { app in
                guard let bundleId = app.bundleIdentifier else { return nil }
                return (bundleId, app)
            }
        )
        let runningBundleIds = Set(runningAppsMap.keys)
        
        // 3. Calculate valid bundle IDs (should be displayed)
        // Valid = is favorite OR is running
        let validBundleIds = favoriteBundleIds.union(runningBundleIds)
        
        // 4. Update display order
        if displayedBundleIds.isEmpty {
            // First load: favorites first (in db order), then running non-favorites (alphabetically)
            displayedBundleIds = currentFavoritesOrder
            
            let nonFavoriteRunning = runningApps
                .filter { app in
                    guard let bundleId = app.bundleIdentifier else { return false }
                    return !favoriteBundleIds.contains(bundleId)
                }
                .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
                .compactMap { $0.bundleIdentifier }
            
            displayedBundleIds.append(contentsOf: nonFavoriteRunning)
        } else {
            // Subsequent load: maintain order, remove invalid, append new
            
            // Remove items that are no longer valid (not favorite AND not running)
            displayedBundleIds = displayedBundleIds.filter { validBundleIds.contains($0) }
            
            // Find new items (valid but not in display list)
            let currentSet = Set(displayedBundleIds)
            let newBundleIds = validBundleIds.subtracting(currentSet)
            
            // Append new items (newly launched apps) - sort alphabetically
            let sortedNew = newBundleIds.sorted { id1, id2 in
                let name1 = runningAppsMap[id1]?.localizedName ?? id1
                let name2 = runningAppsMap[id2]?.localizedName ?? id2
                return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
            }
            displayedBundleIds.append(contentsOf: sortedNew)
        }
        
        // 5. Build app entries in display order
        let favoritesMap: [String: (displayName: String?, iconOverride: String?)] = Dictionary(
            uniqueKeysWithValues: favorites.map { ($0.bundleIdentifier, ($0.displayName, $0.iconOverride)) }
        )
        
        var entries: [AppEntry] = []
        
        for bundleId in displayedBundleIds {
            let isFavorite = favoriteBundleIds.contains(bundleId)
            let favorite = favoritesMap[bundleId]
            
            if let appEntry = createAppEntry(
                bundleIdentifier: bundleId,
                customName: favorite?.displayName,
                iconOverride: favorite?.iconOverride,
                isFavorite: isFavorite,
                sortOrder: nil,
                runningAppsMap: runningAppsMap
            ) {
                entries.append(appEntry)
            }
        }
        
        appEntries = entries
        
        let favoriteCount = entries.filter { $0.isFavorite }.count
        let runningCount = entries.filter { $0.isRunning }.count
        
        print("[CombinedApps] Total apps: \(appEntries.count)")
        print("   Favorites: \(favoriteCount)")
        print("   Running: \(runningCount)")
        print("   Display order maintained: \(displayedBundleIds.count) items")
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
        
        // Normalization size - use a size large enough for quality at all ring sizes
        let iconNormalizationSize: CGFloat = 128
        
        // Get app URL
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            // If app is running, we can still get info from the running instance
            if let runningApp = runningApp {
                let name = customName ?? runningApp.localizedName ?? "Unknown"
                let icon: NSImage
                if let iconOverride = iconOverride,
                   let customIcon = NSImage(systemSymbolName: iconOverride, accessibilityDescription: nil) {
                    icon = customIcon.normalized(to: iconNormalizationSize)
                } else {
                    icon = (runningApp.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!)
                        .normalized(to: iconNormalizationSize)
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
        
        // Get app icon (normalized to consistent size)
        let icon: NSImage
        if let iconOverride = iconOverride,
           let customIcon = NSImage(systemSymbolName: iconOverride, accessibilityDescription: nil) {
            icon = customIcon.normalized(to: iconNormalizationSize)
        } else if isRunning, let runningApp = runningApp, let appIcon = runningApp.icon {
            icon = appIcon.normalized(to: iconNormalizationSize)
        } else {
            // Try to get icon from file system
            let fileIcon = NSWorkspace.shared.icon(forFile: appURL.path)
            
            // Validate icon - check if it's valid by checking size
            // Invalid/missing icons typically have zero size
            if fileIcon.size.width > 0 && fileIcon.size.height > 0 {
                icon = fileIcon.normalized(to: iconNormalizationSize)
            } else {
                // Fallback: use generic application icon
                print("⚠️ [CombinedApps] Failed to load icon for \(name), using fallback")
                icon = (NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage())
                    .normalized(to: iconNormalizationSize)
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
                childDisplayMode: .panel,
                preferredLayout: .partialSlice,
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
                    
                
                    //using shared instance
                    self.appSwitcherManager?.recordAppUsage(app)
            
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
            onLeftClick: ModifierAwareInteraction(base: .executeKeepOpen { [weak self] in
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
            onLeftClick: ModifierAwareInteraction(base: .executeKeepOpen { [weak self] in
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

// MARK: - NSImage Extension for Icon Normalization

extension NSImage {
    /// Creates a new image rasterized at the exact target size.
    /// This ensures consistent display regardless of what representations
    /// the source image contains (fixes Electron app icons on low-DPI displays).
    func normalized(to size: CGFloat) -> NSImage {
        let targetSize = NSSize(width: size, height: size)
        
        // Create a new image at the target size
        let normalizedImage = NSImage(size: targetSize)
        
        normalizedImage.lockFocus()
        
        // Enable high-quality interpolation for smooth scaling
        NSGraphicsContext.current?.imageInterpolation = .high
        
        // Draw the source image scaled to fill the target size
        self.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: self.size),
            operation: .copy,
            fraction: 1.0
        )
        
        normalizedImage.unlockFocus()
        
        // Mark as template if source was template (preserves SF Symbol behavior)
        normalizedImage.isTemplate = self.isTemplate
        
        return normalizedImage
    }
}
