//
//  CircularUIInstanceManager.swift
//  Jason
//
//  Manages multiple CircularUIManager instances, each tied to a ring configuration.
//  Handles instance lifecycle: creation, updates, and removal based on active configs.
//

import Foundation
import AppKit
import SwiftUI

@MainActor
class CircularUIInstanceManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = CircularUIInstanceManager()
    
    // MARK: - Published State
    
    /// Dictionary of active instances, keyed by configuration ID
    @Published private(set) var instances: [Int: CircularUIManager] = [:]
    
    /// Track which instance is currently visible (nil if none are visible)
    private(set) var activeInstanceId: Int? = nil
    
    // MARK: - Dependencies
    
    private let configurationManager = RingConfigurationManager.shared
    private let hotkeyManager = HotkeyManager()
    
    // MARK: - Initialization
    
    private init() {
        print("🎛️ [InstanceManager] Initialized")
    }
    
    // MARK: - Instance Creation
    
    /// Create CircularUIManager instances for all active configurations
    /// - Parameter configurations: Array of configurations to instantiate
    func createInstances(for configurations: [StoredRingConfiguration]) {
        print("🔧 [InstanceManager] Creating instances for \(configurations.count) configuration(s)")
        
        for config in configurations where config.isActive {
            createOrUpdateInstance(for: config)
        }
        
        print("✅ [InstanceManager] Now managing \(instances.count) instance(s)")
    }
    
    /// Create or update a single CircularUIManager instance
    /// - Parameter config: The configuration to instantiate/update
    func createOrUpdateInstance(for config: StoredRingConfiguration) {
        let action = instances[config.id] != nil ? "Updating" : "Creating"
        print("🔧 [InstanceManager] \(action) instance for '\(config.name)' (ID: \(config.id))")
        
        // Remove old instance if it exists (to ensure clean state)
        if instances[config.id] != nil {
            removeInstance(forConfigId: config.id)
        }
        
        // Create new instance with configuration
        let instance = CircularUIManager(configuration: config)
        instances[config.id] = instance
        
        print("   ✅ Instance created with:")
        print("      - Shortcut: \(config.shortcut)")
        print("      - Ring Radius: \(config.ringRadius)")
        print("      - Icon Size: \(config.iconSize)")
        print("      - Providers: \(config.providers.count)")
    }
    
    // MARK: - Instance Retrieval
    
    /// Get a CircularUIManager instance by configuration ID
    /// - Parameter configId: The configuration ID
    /// - Returns: The CircularUIManager instance if it exists, nil otherwise
    func getInstance(forConfigId configId: Int) -> CircularUIManager? {
        return instances[configId]
    }
    
    /// Get a CircularUIManager instance by keyboard shortcut
    /// - Parameter shortcut: The keyboard shortcut (e.g., "Cmd+Shift+A")
    /// - Returns: The CircularUIManager instance if found, nil otherwise
    func getInstance(forShortcut shortcut: String) -> CircularUIManager? {
        // Find config with matching shortcut
        guard let config = configurationManager.getConfiguration(forShortcut: shortcut) else {
            print("⚠️ [InstanceManager] No configuration found for shortcut: \(shortcut)")
            return nil
        }
        
        return instances[config.id]
    }
    
    /// Get the first active instance (useful for fallback/default behavior)
    /// - Returns: The first CircularUIManager instance, or nil if none exist
    func getFirstInstance() -> CircularUIManager? {
        guard let firstConfig = configurationManager.getActiveConfigurations().first else {
            return nil
        }
        return instances[firstConfig.id]
    }
    
    // MARK: - Instance Removal
    
    /// Remove a CircularUIManager instance
    /// - Parameter configId: The configuration ID to remove
    func removeInstance(forConfigId configId: Int) {
        guard let instance = instances[configId] else {
            print("⚠️ [InstanceManager] No instance found for config ID: \(configId)")
            return
        }
        
        print("🗑️ [InstanceManager] Removing instance for config ID: \(configId)")
        
        // Hide UI if visible
        if instance.isVisible {
            instance.hide()
        }
        
        // Clear active instance tracking if this was the active instance
        if activeInstanceId == configId {
            activeInstanceId = nil
            print("   ⚠️ Removed active instance, cleared activeInstanceId")
        }
        
        // Remove from dictionary
        instances.removeValue(forKey: configId)
        
        print("   ✅ Instance removed, \(instances.count) remaining")
    }
    
    /// Remove all instances
    func removeAllInstances() {
        print("🗑️ [InstanceManager] Removing all \(instances.count) instance(s)")
        
        // Hide all visible UIs
        for (_, instance) in instances {
            if instance.isVisible {
                instance.hide()
            }
        }
        
        // Clear dictionary
        instances.removeAll()
        
        // Clear active instance tracking
        activeInstanceId = nil
        
        print("   ✅ All instances removed")
    }
    
    // MARK: - Configuration Change Handling
    
    /// Handle configuration updates by recreating affected instances
    /// - Parameter updatedConfig: The updated configuration
    func handleConfigurationUpdate(_ updatedConfig: StoredRingConfiguration) {
        print("🔄 [InstanceManager] Handling update for config: '\(updatedConfig.name)'")
        
        if updatedConfig.isActive {
            // Active config - create/update instance
            createOrUpdateInstance(for: updatedConfig)
        } else {
            // Inactive config - remove instance
            removeInstance(forConfigId: updatedConfig.id)
        }
    }
    
    /// Sync instances with current active configurations
    /// Call this when configurations are added/removed/changed
    func syncWithConfigurations() {
        print("🔄 [InstanceManager] Syncing instances with configurations")
        
        let activeConfigs = configurationManager.getActiveConfigurations()
        let activeConfigIds = Set(activeConfigs.map { $0.id })
        let currentInstanceIds = Set(instances.keys)
        
        // Remove instances for configs that are no longer active
        let toRemove = currentInstanceIds.subtracting(activeConfigIds)
        for configId in toRemove {
            removeInstance(forConfigId: configId)
        }
        
        // Create/update instances for active configs
        for config in activeConfigs {
            createOrUpdateInstance(for: config)
        }
        
        print("   ✅ Sync complete: \(instances.count) active instance(s)")
    }
    
    // MARK: - Keyboard Shortcut Management
    
    /// Register keyboard shortcuts for all active instances
    func registerShortcuts() {
        print("⌨️ [InstanceManager] Registering shortcuts for all instances...")
        
        // Unregister existing first
        hotkeyManager.unregisterAllShortcuts()
        
        let activeConfigs = configurationManager.getActiveConfigurations()
        
        for config in activeConfigs {
            // Skip configs without shortcuts
            guard let keyCode = config.keyCode,
                  let modifierFlags = config.modifierFlags else {
                print("   ⏭️ Skipping '\(config.name)' - no shortcut configured")
                continue
            }
            
            hotkeyManager.registerShortcut(
                keyCode: keyCode,
                modifierFlags: modifierFlags,
                forConfigId: config.id
            ) { [weak self] in
                // When shortcut is pressed, show this ring
                print("🎯 [InstanceManager] Shortcut triggered for '\(config.name)' (ID: \(config.id))")
                self?.show(configId: config.id)
            }
            
            print("   ✅ \(config.shortcutDescription) → \(config.name)")
        }
        
        print("✅ [InstanceManager] Registration complete!")
    }
    
    /// Start monitoring for hotkeys
    func startHotkeyMonitoring() {
        print("🎹 [InstanceManager] Starting hotkey monitoring...")
        hotkeyManager.startMonitoring()
    }
    
    /// Stop monitoring for hotkeys
    func stopHotkeyMonitoring() {
        print("🛑 [InstanceManager] Stopping hotkey monitoring...")
        hotkeyManager.stopMonitoring()
    }
    
    // MARK: - Debugging & Diagnostics
    
    /// Print current state for debugging
    func printDebugInfo() {
        print("🔍 [InstanceManager] Debug Info:")
        print("   Total instances: \(instances.count)")
        print("   Active instance ID: \(activeInstanceId?.description ?? "none")")
        
        for (configId, instance) in instances.sorted(by: { $0.key < $1.key }) {
            let visibleStatus = instance.isVisible ? "👁️ VISIBLE" : "😴 hidden"
            let activeMarker = (configId == activeInstanceId) ? " ⭐️ ACTIVE" : ""
            print("   - Config \(configId): \(visibleStatus)\(activeMarker)")
        }
    }
    
    /// Check if any instance is currently visible
    var hasVisibleInstance: Bool {
        return instances.values.contains { $0.isVisible }
    }
    
    /// Get all currently visible instances
    var visibleInstances: [CircularUIManager] {
        return instances.values.filter { $0.isVisible }
    }
}

// MARK: - Convenience Extensions

extension CircularUIInstanceManager {
    
    /// Show a specific instance by configuration ID
    /// - Parameter configId: The configuration ID
    func show(configId: Int) {
        guard let instance = getInstance(forConfigId: configId) else {
            print("❌ [InstanceManager] Cannot show - no instance for config \(configId)")
            return
        }
        
        // Hide currently active instance if different
        if let currentActiveId = activeInstanceId, currentActiveId != configId {
            print("🔄 [InstanceManager] Hiding previous instance (config \(currentActiveId))")
            if let previousInstance = getInstance(forConfigId: currentActiveId) {
                previousInstance.hide()
            }
        }
        
        // Update active instance tracking
        activeInstanceId = configId
        print("✅ [InstanceManager] Setting active instance to config \(configId)")
        
        // Show the new instance
        instance.show()
    }
    
    /// Show a specific instance by shortcut
    /// - Parameter shortcut: The keyboard shortcut
    func show(forShortcut shortcut: String) {
        // Find config with matching shortcut
        guard let config = configurationManager.getConfiguration(forShortcut: shortcut) else {
            print("❌ [InstanceManager] Cannot show - no configuration for shortcut '\(shortcut)'")
            return
        }
        
        // Use the coordinated show method
        show(configId: config.id)
    }
    
    /// Hide all visible instances
    func hideAll() {
        print("🙈 [InstanceManager] Hiding all visible instances")
        
        for instance in visibleInstances {
            instance.hide()
        }
        
        // Clear active instance tracking
        activeInstanceId = nil
    }
    
    /// Hide the currently active instance
    func hideActive() {
        guard let activeId = activeInstanceId else {
            print("⚠️ [InstanceManager] No active instance to hide")
            return
        }
        
        print("🔄 [InstanceManager] Hiding active instance (config \(activeId))")
        
        if let activeInstance = getInstance(forConfigId: activeId) {
            activeInstance.hide()
        }
        
        activeInstanceId = nil
    }
    
    /// Get the currently active instance (the one that should handle notifications)
    /// - Returns: The active CircularUIManager instance, or nil if none is active
    func getActiveInstance() -> CircularUIManager? {
        guard let activeId = activeInstanceId else { return nil }
        return getInstance(forConfigId: activeId)
    }
    
    /// Check if a specific instance is currently active
    /// - Parameter configId: The configuration ID to check
    /// - Returns: True if this instance is currently active, false otherwise
    func isInstanceActive(_ configId: Int) -> Bool {
        return activeInstanceId == configId
    }
}
