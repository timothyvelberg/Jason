//
//  FirstLaunchConfiguration.swift
//  Jason
//
//  Creates sensible default ring configurations on first launch
//  Now supports multiple triggers per ring
//

import Foundation
import AppKit

class FirstLaunchConfiguration {
    
    // MARK: - Default Shortcuts
    
    /// Helper to create a keyboard trigger tuple
    private static func keyboardTrigger(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        isHoldMode: Bool = false,
        autoExecuteOnRelease: Bool = true
    ) -> (type: String, keyCode: UInt16?, modifierFlags: UInt, buttonNumber: Int32?, swipeDirection: String?, fingerCount: Int?, isHoldMode: Bool, autoExecuteOnRelease: Bool) {
        return (
            type: "keyboard",
            keyCode: keyCode,
            modifierFlags: modifiers.rawValue,
            buttonNumber: nil,
            swipeDirection: nil,
            fingerCount: nil,
            isHoldMode: isHoldMode,
            autoExecuteOnRelease: autoExecuteOnRelease
        )
    }
    
    /// Helper to create a trackpad trigger tuple
    private static func trackpadTrigger(
        direction: String,
        fingerCount: Int,
        modifiers: NSEvent.ModifierFlags = [],
        isHoldMode: Bool = false,
        autoExecuteOnRelease: Bool = true
    ) -> (type: String, keyCode: UInt16?, modifierFlags: UInt, buttonNumber: Int32?, swipeDirection: String?, fingerCount: Int?, isHoldMode: Bool, autoExecuteOnRelease: Bool) {
        return (
            type: "trackpad",
            keyCode: nil,
            modifierFlags: modifiers.rawValue,
            buttonNumber: nil,
            swipeDirection: direction,
            fingerCount: fingerCount,
            isHoldMode: isHoldMode,
            autoExecuteOnRelease: autoExecuteOnRelease
        )
    }
    
    /// Helper to create a mouse trigger tuple
    private static func mouseTrigger(
        buttonNumber: Int32,
        modifiers: NSEvent.ModifierFlags = [],
        isHoldMode: Bool = false,
        autoExecuteOnRelease: Bool = true
    ) -> (type: String, keyCode: UInt16?, modifierFlags: UInt, buttonNumber: Int32?, swipeDirection: String?, fingerCount: Int?, isHoldMode: Bool, autoExecuteOnRelease: Bool) {
        return (
            type: "mouse",
            keyCode: nil,
            modifierFlags: modifiers.rawValue,
            buttonNumber: buttonNumber,
            swipeDirection: nil,
            fingerCount: nil,
            isHoldMode: isHoldMode,
            autoExecuteOnRelease: autoExecuteOnRelease
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
            print("[FirstLaunch] Configurations already exist (\(existingConfigs.count))")
            return
        }
        
        print("[FirstLaunch] No configurations found - creating default 'Everything' ring")
        
        // Create default "Everything" ring with keyboard + trackpad triggers
        do {
            let defaultConfig = try configManager.createConfiguration(
                name: "Everything",
                shortcut: "Ctrl+Shift+D",  // For display only
                ringRadius: 80.0,
                centerHoleRadius: 56.0,
                iconSize: 32.0,
                triggers: [
                    keyboardTrigger(keyCode: 2, modifiers: [.control, .shift])  // Ctrl+Shift+D
                ],
                providers: [
                    (type: "FavoriteFolderProvider", order: 1, displayMode: "parent", angle: nil),
                    (type: "RemindersProvider", order: 2, displayMode: "parent", angle: nil),
                    (type: "ClipboardHistoryProvider", order: 3, displayMode: "parent", angle: nil),
                    (type: "FavoriteFilesProvider", order: 4, displayMode: "parent", angle: nil),
                    (type: "CalendarProvider", order: 5, displayMode: "parent", angle: nil)
                ]
            )
            print("   Created '\(defaultConfig.name)' - \(defaultConfig.triggersSummary)")
            
            let appsDirectRing = try configManager.createConfiguration(
                name: "Quick Apps (Direct)",
                shortcut: "Ctrl+Shift+Q",  // For display
                ringRadius: 80.0,
                centerHoleRadius: 56.0,
                iconSize: 32.0,
                triggers: [
                    keyboardTrigger(keyCode: 12, modifiers: [.control, .shift])  // Ctrl+Shift+Q
                ],
                providers: [
                    (type: "CombinedAppsProvider", order: 1, displayMode: "direct", angle: nil)
                ]
            )
            
            print("   Created '\(appsDirectRing.name)' - \(appsDirectRing.triggersSummary)")
            print("   Created default configurations")
            
        } catch {
            print("   Failed to create default configuration: \(error)")
            
            // This is a critical error - app can't function without at least one ring
            fatalError("Failed to create default ring configuration: \(error)")
        }
    }
    
    /// Reset all configurations and recreate defaults
    @MainActor
    static func resetToDefaults() {
        let configManager = RingConfigurationManager.shared
        
        print("[FirstLaunch] Resetting to default configuration...")
        
        // Load all existing configs
        configManager.loadConfigurations()
        let existingConfigs = configManager.getAllConfigurations()
        
        // Delete all existing configurations
        for config in existingConfigs {
            do {
                try configManager.deleteConfiguration(id: config.id)
                print("   Deleted configuration: \(config.name)")
            } catch {
                print("   Failed to delete \(config.name): \(error)")
            }
        }
        
        // Recreate default
        ensureDefaultConfiguration()
        
        print("   Reset complete")
    }
}
