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
    
    // MARK: - Favorite Apps Configuration
    
    // Store favorite apps by bundle identifier
    @Published var favoriteAppBundleIds: [String] = [
        // Default favorites - customize these!
        "com.vivaldi.Vivaldi",
        "net.whatsapp.WhatsApp",
        "com.anthropic.claudefordesktop",
        "org.blenderfoundation.blender",
        "com.bambulab.bambu-studio",
        "com.openai.chat",
        "com.spotify.client",
        "com.seriflabs.affinitydesigner2",
        "com.seriflabs.affinityphoto2",
        "com.tinyspeck.slackmacgap",
        "co.zeit.hyper",
        "com.apple.dt.Xcode",
        "com.figma.Desktop",

        
    ]
    
    // Cache resolved apps to avoid repeated lookups
    private var resolvedApps: [AppInfo] = []
    
    // MARK: - App Info Structure
    
    struct AppInfo {
        let bundleIdentifier: String
        let name: String
        let icon: NSImage
        let url: URL
    }
    
    // MARK: - Initialization
    
    init() {
        print("🌟 FavoriteAppsProvider initialized")
        loadFavoriteApps()
    }
    
    // MARK: - App Loading
    
    private func loadFavoriteApps() {
        resolvedApps.removeAll()
        
        for bundleId in favoriteAppBundleIds {
            if let appInfo = findApp(bundleIdentifier: bundleId) {
                resolvedApps.append(appInfo)
//                print("✅ Found favorite app: \(appInfo.name)")
            } else {
                print("⚠️ Could not find app with bundle ID: \(bundleId)")
            }
        }
        
//        print("🌟 Loaded \(resolvedApps.count) favorite apps")
    }
    
    private func findApp(bundleIdentifier: String) -> AppInfo? {
        // Try to find app using NSWorkspace
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        
        guard let bundle = Bundle(url: appURL) else {
            return nil
        }
        
        let appName = bundle.infoDictionary?["CFBundleName"] as? String ??
                      bundle.infoDictionary?["CFBundleDisplayName"] as? String ??
                      appURL.deletingPathExtension().lastPathComponent
        
        let appIcon = NSWorkspace.shared.icon(forFile: appURL.path)
        
        return AppInfo(
            bundleIdentifier: bundleIdentifier,
            name: appName,
            icon: appIcon,
            url: appURL
        )
    }
    
    // MARK: - FunctionProvider Methods
    
    func provideFunctions() -> [FunctionNode] {
        // Convert favorite apps to FunctionNodes with explicit interaction model
        let appNodes = resolvedApps.map { appInfo in
            FunctionNode(
                id: "fav-\(appInfo.bundleIdentifier)",
                name: appInfo.name,
                icon: appInfo.icon,
                preferredLayout: nil,
                showLabel: true,
                // EXPLICIT INTERACTION MODEL:
                onLeftClick: .execute { [weak self] in
                    self?.launchApp(appInfo)
                },
                onRightClick: .doNothing,  // Could add "Remove from Favorites" context menu later
                onMiddleClick: .executeKeepOpen { [weak self] in
                    self?.launchApp(appInfo)
                },
                onBoundaryCross: .doNothing,
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
                icon: providerIcon,
                children: appNodes,
                
                preferredLayout: .partialSlice,  // Use partial slice for compact display

                // EXPLICIT INTERACTION MODEL:
                onLeftClick: .expand,           // Click to expand favorites
                onRightClick: .expand,          // Right-click also expands
                onMiddleClick: .expand,         // Middle-click expands
                onBoundaryCross: .expand,       // Auto-expand on boundary cross
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
        // Reload favorite apps (useful if app list changes)
        loadFavoriteApps()
    }
    
    // MARK: - App Actions
    
    private func launchApp(_ appInfo: AppInfo) {
        print("🚀 Launching favorite app: \(appInfo.name)")
        
        // Launch the app
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true  // Bring app to front
        
        NSWorkspace.shared.openApplication(at: appInfo.url, configuration: configuration) { app, error in
            if let error = error {
                print("❌ Failed to launch \(appInfo.name): \(error.localizedDescription)")
            } else if let app = app {
                print("✅ Successfully launched \(appInfo.name)")
            }
        }
    }
    
    private func openFavoritesManager() {
        // Future: Could open a UI to manage favorites
        // For now, just log
        print("💡 Favorites manager not yet implemented")
        print("Current favorites: \(resolvedApps.map { $0.name }.joined(separator: ", "))")
    }
    
    // MARK: - Favorites Management
    
    func addFavorite(bundleIdentifier: String) {
        guard !favoriteAppBundleIds.contains(bundleIdentifier) else {
            print("⚠️ App already in favorites: \(bundleIdentifier)")
            return
        }
        
        favoriteAppBundleIds.append(bundleIdentifier)
        print("➕ Added to favorites: \(bundleIdentifier)")
        
        // Reload apps
        loadFavoriteApps()
        
        // TODO: Persist to UserDefaults or a config file
    }
    
    func removeFavorite(bundleIdentifier: String) {
        favoriteAppBundleIds.removeAll { $0 == bundleIdentifier }
        print("➖ Removed from favorites: \(bundleIdentifier)")
        
        // Reload apps
        loadFavoriteApps()
        
        // TODO: Persist to UserDefaults or a config file
    }
    
    func reorderFavorites(from: Int, to: Int) {
        guard favoriteAppBundleIds.indices.contains(from),
              favoriteAppBundleIds.indices.contains(to) else {
            return
        }
        
        let item = favoriteAppBundleIds.remove(at: from)
        favoriteAppBundleIds.insert(item, at: to)
        
        print("🔄 Reordered favorites")
        
        // Reload apps
        loadFavoriteApps()
        
        // TODO: Persist to UserDefaults or a config file
    }
}

// MARK: - Persistence Extension (Future)

extension FavoriteAppsProvider {
    
    // Keys for UserDefaults
    private static let favoritesKey = "com.jason.favoriteApps"
    
    // Load favorites from persistent storage
    func loadFavoritesFromStorage() {
        if let stored = UserDefaults.standard.array(forKey: Self.favoritesKey) as? [String] {
            favoriteAppBundleIds = stored
            print("📥 Loaded \(stored.count) favorites from storage")
            loadFavoriteApps()
        }
    }
    
    // Save favorites to persistent storage
    func saveFavoritesToStorage() {
        UserDefaults.standard.set(favoriteAppBundleIds, forKey: Self.favoritesKey)
        print("💾 Saved \(favoriteAppBundleIds.count) favorites to storage")
    }
}
