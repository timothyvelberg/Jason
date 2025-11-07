//
//  FirstLaunchConfiguration.swift
//  Jason
//
//  Creates a sensible default ring configuration on first launch
//

import Foundation

class FirstLaunchConfiguration {
    
    /// Ensure at least one ring configuration exists
    /// Call this on app launch before creating instances
    @MainActor
    static func ensureDefaultConfiguration() {
        let configManager = RingConfigurationManager.shared
        
        // Load existing configurations
        configManager.loadConfigurations()
        let existingConfigs = configManager.getAllConfigurations()
        
        // If any configurations exist, we're done
        guard existingConfigs.isEmpty else {
            print("✅ [FirstLaunch] Configurations already exist (\(existingConfigs.count))")
            return
        }
        
        print("🆕 [FirstLaunch] No configurations found - creating default 'Everything' ring")
        
        // Create default "Everything" ring with all providers
        do {
            let defaultConfig = try configManager.createConfiguration(
                name: "Everything",
                shortcut: "Cmd+Shift+Space",
                ringRadius: 80.0,  // Smaller ring (was 300.0)
                centerHoleRadius: 40.0,
                iconSize: 32.0,     // Smaller icons (was 64.0)
                providers: [
                    ("CombinedAppsProvider", 1, nil),
                    ("FavoriteFilesProvider", 2, nil),
                    ("FinderLogic", 3, nil)
                ]
            )
            
            print("   ✅ Created default configuration:")
            print("      - ID: \(defaultConfig.id)")
            print("      - Name: \(defaultConfig.name)")
            print("      - Shortcut: \(defaultConfig.shortcut)")
            print("      - Providers: \(defaultConfig.providers.count)")
            
        } catch {
            print("   ❌ Failed to create default configuration: \(error)")
            
            // This is a critical error - app can't function without at least one ring
            fatalError("Failed to create default ring configuration: \(error)")
        }
    }
    
    /// Create example configurations for development/testing
    /// Call this manually if you want pre-made rings for testing
    @MainActor
    static func createExampleConfigurations() {
        let configManager = RingConfigurationManager.shared
        
        print("🎨 [FirstLaunch] Creating example configurations...")
        
        do {
            // Example 1: Apps-only ring
            let appsRing = try configManager.createConfiguration(
                name: "Apps",
                shortcut: "Cmd+Shift+A",
                ringRadius: 100.0,  // Compact for apps
                iconSize: 32.0,
                providers: [
                    ("CombinedAppsProvider", 1, nil)
                ]
            )
            print("   ✅ Created 'Apps' ring (ID: \(appsRing.id))")
            
            // Example 2: Files-focused ring
            let filesRing = try configManager.createConfiguration(
                name: "Files",
                shortcut: "Cmd+Shift+F",
                ringRadius: 100.0,  // Slightly bigger for files
                iconSize: 32.0,
                providers: [
                    ("FavoriteFilesProvider", 1, nil),
                    ("FinderLogic", 2, nil)
                ]
            )
            print("   ✅ Created 'Files' ring (ID: \(filesRing.id))")
            
            // Example 3: System actions ring
            let systemRing = try configManager.createConfiguration(
                name: "System",
                shortcut: "Cmd+Shift+S",
                ringRadius: 100.0,  // Small - fewer items
                iconSize: 32.0,
                providers: [
                    ("SystemActionsProvider", 1, nil)
                ]
            )
            print("   ✅ Created 'System' ring (ID: \(systemRing.id))")
            
            print("   ✅ Created \(3) example configurations")
            
        } catch {
            print("   ⚠️ Failed to create some example configurations: \(error)")
        }
    }
    
    /// Reset all configurations and recreate defaults
    /// ⚠️ WARNING: This deletes ALL existing configurations!
    @MainActor
    static func resetToDefaults() {
        let configManager = RingConfigurationManager.shared
        
        print("🔄 [FirstLaunch] Resetting to default configuration...")
        
        // Load all existing configs
        configManager.loadConfigurations()
        let existingConfigs = configManager.getAllConfigurations()
        
        // Delete all existing configurations
        for config in existingConfigs {
            do {
                try configManager.deleteConfiguration(id: config.id)
                print("   🗑️ Deleted configuration: \(config.name)")
            } catch {
                print("   ❌ Failed to delete \(config.name): \(error)")
            }
        }
        
        // Recreate default
        ensureDefaultConfiguration()
        
        print("   ✅ Reset complete")
    }
}

