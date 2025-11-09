//
//  FirstLaunchConfiguration.swift
//  Jason
//
//  Creates sensible default ring configurations on first launch
//  Now includes keyboard shortcuts with raw key codes and modifier flags
//

import Foundation
import AppKit

class FirstLaunchConfiguration {
    
    // MARK: - Default Shortcuts
    
    /// Default keyboard shortcuts (using raw key codes + modifiers)
    private struct DefaultShortcut {
        let keyCode: UInt16
        let modifierFlags: UInt
        
        // Common shortcuts for ring configurations
        static let ctrlShiftD = DefaultShortcut(
            keyCode: 2, // "D"
            modifierFlags: NSEvent.ModifierFlags([.control, .shift]).rawValue
        )
        
        static let ctrlShiftA = DefaultShortcut(
            keyCode: 0, //"A"
            modifierFlags: NSEvent.ModifierFlags([.control, .shift]).rawValue
        )
        
        static let ctrlShiftF = DefaultShortcut(
            keyCode: 3,  // "F"
            modifierFlags: NSEvent.ModifierFlags([.control, .shift]).rawValue
        )
        
        static let ctrlShiftE = DefaultShortcut(
            keyCode: 14,  // "E"
            modifierFlags: NSEvent.ModifierFlags([.control, .shift]).rawValue
        )
        
        static let ctrlShiftQ = DefaultShortcut(
            keyCode: 12,  // "Q"
            modifierFlags: NSEvent.ModifierFlags([.control, .shift]).rawValue
        )
    }
    
    // MARK: - First Launch Setup
    
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
        
        // Create default "Everything" ring with Cmd+Shift+SpaceCmd+Shift+SpaceCmd+Shift+SpaceCmd+Shift+Space
        do {
            let defaultConfig = try configManager.createConfiguration(
                name: "Everything",
                shortcut: "Cmd+Shift+D",  // For display only
                ringRadius: 80.0,
                centerHoleRadius: 56.0,
                iconSize: 32.0,
                keyCode: DefaultShortcut.ctrlShiftD.keyCode,
                modifierFlags: DefaultShortcut.ctrlShiftD.modifierFlags,
                providers: [
                    ("CombinedAppsProvider", 1, nil),
                    ("FavoriteFilesProvider", 2, nil),
                    ("FinderLogic", 3, nil)
                ]
            )
            
            print("   ✅ Created default configuration:")
            print("      - ID: \(defaultConfig.id)")
            print("      - Name: \(defaultConfig.name)")
            print("      - Shortcut: \(defaultConfig.shortcutDescription)")
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
            // Example 1: Apps-only ring with Ctrl+Shift+A (PARENT MODE)
            let appsRing = try configManager.createConfiguration(
                name: "Quick Apps (Parent)",
                shortcut: "Ctrl+Shift+A",  // For display
                ringRadius: 80.0,
                centerHoleRadius: 56.0,
                iconSize: 44.0,
                keyCode: DefaultShortcut.ctrlShiftA.keyCode,
                modifierFlags: DefaultShortcut.ctrlShiftA.modifierFlags,
                providers: [
                    ("CombinedAppsProvider", 1, nil)
                ]
            )
            print("   ✅ Created '\(appsRing.name)' - \(appsRing.shortcutDescription)")
            print("      Display Mode: parent (shows 'Applications' category)")
            
            // Example 2: Apps-only ring with Ctrl+Shift+Q (DIRECT MODE)
            let appsDirectRing = try configManager.createConfiguration(
                name: "Quick Apps (Direct)",
                shortcut: "Ctrl+Shift+Q",  // For display
                ringRadius: 80.0,
                centerHoleRadius: 56.0,
                iconSize: 44.0,
                keyCode: DefaultShortcut.ctrlShiftQ.keyCode,
                modifierFlags: DefaultShortcut.ctrlShiftQ.modifierFlags,
                providers: [
                    ("CombinedAppsProvider", 1, nil)
                ]
            )
            
            // Set display mode to "direct" for immediate app access
            let directSuccess = DatabaseManager.shared.updateProviderDisplayMode(
                ringId: appsDirectRing.id,
                providerType: "CombinedAppsProvider",
                displayMode: "direct"
            )
            
            if directSuccess {
                print("   ✅ Created '\(appsDirectRing.name)' - \(appsDirectRing.shortcutDescription)")
                print("      Display Mode: direct (shows apps immediately)")
            } else {
                print("   ⚠️ Created ring but failed to set direct mode")
            }
            
            // 🔧 CRITICAL: Reload configurations after database update
            // This ensures the in-memory configs reflect the displayMode change
            configManager.loadConfigurations()
            
            // Example 3: Files-focused ring with Ctrl+Shift+F
            let filesRing = try configManager.createConfiguration(
                name: "My Files",
                shortcut: "Ctrl+Shift+F",  // For display
                ringRadius: 80.0,
                centerHoleRadius: 56.0,
                iconSize: 32.0,
                keyCode: DefaultShortcut.ctrlShiftF.keyCode,
                modifierFlags: DefaultShortcut.ctrlShiftF.modifierFlags,
                providers: [
                    ("FavoriteFilesProvider", 1, nil),
                    ("FinderLogic", 2, nil)
                ]
            )
            print("   ✅ Created '\(filesRing.name)' - \(filesRing.shortcutDescription)")
            
            // Example 4: Files & Actions ring with Ctrl+Shift+E
            let filesActionsRing = try configManager.createConfiguration(
                name: "Files & Actions",
                shortcut: "Ctrl+Shift+E",  // For display
                ringRadius: 80.0,
                centerHoleRadius: 56.0,
                iconSize: 38.0,
                keyCode: DefaultShortcut.ctrlShiftE.keyCode,
                modifierFlags: DefaultShortcut.ctrlShiftE.modifierFlags,
                providers: [
                    ("FavoriteFilesProvider", 1, nil),
                    ("SystemActionsProvider", 2, nil)
                ]
            )
            print("   ✅ Created '\(filesActionsRing.name)' - \(filesActionsRing.shortcutDescription)")
            
            print("   ✅ Created 4 example configurations")
            print("   📊 Display Mode Comparison:")
            print("      • Parent Mode (Ctrl+Shift+A): Ring 0 shows 'Applications' → Ring 1 shows apps")
            print("      • Direct Mode (Ctrl+Shift+Q): Ring 0 shows apps immediately")
            
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
