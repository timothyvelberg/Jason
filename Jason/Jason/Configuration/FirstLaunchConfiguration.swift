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
                    (type: "CombinedAppsProvider", order: 1, displayMode: "parent", angle: nil),
                    (type: "FavoriteFilesProvider", order: 2,displayMode: "parent", nil),
                    (type: "FinderLogic", order: 3,displayMode: "parent", angle: nil),
                    (type: "SystemActionsProvider", order: 4, displayMode: "parent", angle: nil)
                ]
            )
            print("   Created '\(defaultConfig.name)' - \(defaultConfig.shortcutDescription)")
            
            let appsDirectRing = try configManager.createConfiguration(
                name: "Quick Apps (Direct)",
                shortcut: "Ctrl+Shift+Q",  // For display
                ringRadius: 80.0,
                centerHoleRadius: 56.0,
                iconSize: 32.0,
                keyCode: DefaultShortcut.ctrlShiftQ.keyCode,
                modifierFlags: DefaultShortcut.ctrlShiftQ.modifierFlags,
                providers: [
                    (type: "CombinedAppsProvider", order: 1, displayMode: "direct", angle: nil)
                ]
            )
            
            print("   Created '\(appsDirectRing.name)' - \(appsDirectRing.shortcutDescription)")
            print("   ✅ Created default configurations")
            
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
            let folderRing = try configManager.createConfiguration(
                name: "My Folders",
                shortcut: "Ctrl+Shift+A",  // For display
                ringRadius: 80.0,
                centerHoleRadius: 56.0,
                iconSize: 32.0,
                keyCode: DefaultShortcut.ctrlShiftA.keyCode,
                modifierFlags: DefaultShortcut.ctrlShiftA.modifierFlags,
                providers: [
                    (type: "FinderLogic", order: 1, displayMode: "direct", angle: nil)
                ]
            )
            print("   ✅ Created '\(folderRing.name)' - \(folderRing.shortcutDescription)")

            
            let filesRing = try configManager.createConfiguration(
                name: "My Files",
                shortcut: "Ctrl+Shift+F",  // For display
                ringRadius: 80.0,
                centerHoleRadius: 56.0,
                iconSize: 32.0,
                keyCode: DefaultShortcut.ctrlShiftF.keyCode,
                modifierFlags: DefaultShortcut.ctrlShiftF.modifierFlags,
                providers: [
                    (type: "FavoriteFilesProvider", order: 1, displayMode: "direct", angle: nil)
                ]
            )
            print("   ✅ Created '\(filesRing.name)' - \(filesRing.shortcutDescription)")
  
            let everythingDirectRing = try configManager.createConfiguration(
                name: "Everything Direct",
                shortcut: "Ctrl+Shift+W",  // For display
                ringRadius: 80.0,
                centerHoleRadius: 56.0,
                iconSize: 32.0,
                keyCode: 13,  // "W"
                modifierFlags: NSEvent.ModifierFlags([.control, .shift]).rawValue,
                providers: [
                    (type: "CombinedAppsProvider", order: 1, displayMode: "direct", angle: nil),
                    (type: "FinderLogic", order: 2, displayMode: "direct", nil)
                ]
            )
            print("   ✅ Created '\(everythingDirectRing.name)' - \(everythingDirectRing.shortcutDescription)")

            
            // Reload configurations after all database updates
            // This ensures the in-memory configs reflect all displayMode changes
            configManager.loadConfigurations()
            
            print("   example configurations")
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
