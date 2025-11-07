//
//  CircularUIInstanceManager.swift
//  Jason
//
//  Created by Timothy Velberg on 07/11/2025.
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
    
    // MARK: - Dependencies
    
    private let configurationManager = RingConfigurationManager.shared
    
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
        
        // TODO: Step 2 - Create new instance with configuration
        // This will be enabled once CircularUIManager has init(configuration:)
        // let instance = CircularUIManager(configuration: config)
        // instances[config.id] = instance
        
        print("   ⚠️ Instance creation not yet implemented (Step 2 pending)")
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
    
    // MARK: - Debugging & Diagnostics
    
    /// Print current state for debugging
    func printDebugInfo() {
        print("🔍 [InstanceManager] Debug Info:")
        print("   Total instances: \(instances.count)")
        
        for (configId, instance) in instances.sorted(by: { $0.key < $1.key }) {
            let visibleStatus = instance.isVisible ? "👁️ VISIBLE" : "😴 hidden"
            print("   - Config \(configId): \(visibleStatus)")
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
        
        instance.show()
    }
    
    /// Show a specific instance by shortcut
    /// - Parameter shortcut: The keyboard shortcut
    func show(forShortcut shortcut: String) {
        guard let instance = getInstance(forShortcut: shortcut) else {
            print("❌ [InstanceManager] Cannot show - no instance for shortcut '\(shortcut)'")
            return
        }
        
        instance.show()
    }
    
    /// Hide all visible instances
    func hideAll() {
        print("🙈 [InstanceManager] Hiding all visible instances")
        
        for instance in visibleInstances {
            instance.hide()
        }
    }
}
