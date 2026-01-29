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
    @Published private(set) var instances: [Int: any UIManager] = [:]
    
    /// Track which instance is currently visible (nil if none are visible)
    private(set) var activeInstanceId: Int? = nil
    
    // MARK: - Dependencies
    
    private let configurationManager = RingConfigurationManager.shared
    private let hotkeyManager = HotkeyManager()
    
    // MARK: - Initialization
    
    private init() {
        print("[Circular InstanceManager] Initialized")
    }
    
    // MARK: - Instance Creation
    
    /// Create CircularUIManager instances for all active configurations
    /// - Parameter configurations: Array of configurations to instantiate
    func createInstances(for configurations: [StoredRingConfiguration]) {
        print("[InstanceManager] Creating instances for \(configurations.count) configuration(s)")
        
        for config in configurations where config.isActive {
            createOrUpdateInstance(for: config)
        }
        
        print("[InstanceManager] Now managing \(instances.count) instance(s)")
    }
    
    /// Create or update a single CircularUIManager instance
    /// - Parameter config: The configuration to instantiate/update
    func createOrUpdateInstance(for config: StoredRingConfiguration) {
        let action = instances[config.id] != nil ? "Updating" : "Creating"
        print("[InstanceManager] \(action) instance for '\(config.name)' (ID: \(config.id))")
        
        // Remove old instance if it exists (to ensure clean state)
        if instances[config.id] != nil {
            removeInstance(forConfigId: config.id)
        }
        
        // Create new instance with configuration
        let instance: any UIManager

        switch config.presentationMode {
        case .ring:
            instance = CircularUIManager(configuration: config)
        case .panel:
            instance = PanelUIManager(configuration: config)
        }
        
        instances[config.id] = instance
        
        // Setup the instance so it's ready to use immediately
        instance.setup()
        print("   Instance created and setup complete")
    }
    
    // MARK: - Instance Retrieval
    
    /// Get a CircularUIManager instance by configuration ID
    /// - Parameter configId: The configuration ID
    /// - Returns: The CircularUIManager instance if it exists, nil otherwise
    func getInstance(forConfigId configId: Int) -> (any UIManager)? {
        return instances[configId]
    }
    
    /// Get a CircularUIManager instance by keyboard shortcut
    /// - Parameter shortcut: The keyboard shortcut (e.g., "Cmd+Shift+A")
    /// - Returns: The CircularUIManager instance if found, nil otherwise
    func getInstance(forShortcut shortcut: String) -> (any UIManager)? {
        // Find config with matching shortcut
        guard let config = configurationManager.getConfiguration(forShortcut: shortcut) else {
            print("⚠️ [InstanceManager] No configuration found for shortcut: \(shortcut)")
            return nil
        }
        
        return instances[config.id]
    }
    
    /// Get the first active instance (useful for fallback/default behavior)
    /// - Returns: The first CircularUIManager instance, or nil if none exist
    func getFirstInstance() -> (any UIManager)? {
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
        registerInputTriggers()
    }
    
    // MARK: - Input Trigger Management

    /// Register all triggers for all active instances
    func registerInputTriggers() {
        print("[InstanceManager] Registering input triggers for all instances...")
        
        // Unregister existing first
        hotkeyManager.unregisterAllShortcuts()
        hotkeyManager.unregisterAllMouseButtons()
        hotkeyManager.unregisterAllSwipes()
        hotkeyManager.unregisterAllCircles()
        
        let activeConfigs = configurationManager.getActiveConfigurations()
        
        for config in activeConfigs {
            // Skip configs with no triggers
            guard config.hasTriggers else {
                print("   Skipping '\(config.name)' - no triggers configured")
                continue
            }
            
            // Register each trigger for this config
            for trigger in config.triggers {
                registerTrigger(trigger, forConfig: config)
            }
        }
        
        print("[InstanceManager] Registration complete!")
    }
    
    /// Register a single trigger for a configuration
    private func registerTrigger(_ trigger: TriggerConfiguration, forConfig config: StoredRingConfiguration) {
        switch trigger.triggerType {
        case "keyboard":
            registerKeyboardTrigger(trigger, forConfig: config)
        case "mouse":
            registerMouseTrigger(trigger, forConfig: config)
        case "trackpad":
            registerTrackpadTrigger(trigger, forConfig: config)
        default:
            print("   ⚠️ Unknown trigger type '\(trigger.triggerType)' for '\(config.name)'")
        }
    }
    
    /// Register a keyboard trigger
    private func registerKeyboardTrigger(_ trigger: TriggerConfiguration, forConfig config: StoredRingConfiguration) {
        guard let keyCode = trigger.keyCode else {
            print("   ⚠️ Keyboard trigger missing keyCode for '\(config.name)'")
            return
        }
        
        if trigger.isHoldMode {
            print("[InstanceManager] Registering keyboard HOLD: \(trigger.displayDescription) for '\(config.name)'")
            
            hotkeyManager.registerShortcut(
                keyCode: keyCode,
                modifierFlags: trigger.modifierFlags,
                isHoldMode: true,
                forConfigId: config.id,
                onPress: { [weak self] in
                    print("🔽 [InstanceManager] Hold key PRESSED for '\(config.name)'")
                    self?.showInHoldMode(configId: config.id, trigger: trigger)
                },
                onRelease: { [weak self] in
                    print("🔼 [InstanceManager] Hold key RELEASED for '\(config.name)'")
                    self?.hideFromHoldMode(configId: config.id)
                }
            )
        } else {
            print("[InstanceManager] Registering keyboard TAP: \(trigger.displayDescription) for '\(config.name)'")
            
            hotkeyManager.registerShortcut(
                keyCode: keyCode,
                modifierFlags: trigger.modifierFlags,
                isHoldMode: false,
                forConfigId: config.id,
                onPress: { [weak self] in
                    print("🎯 [InstanceManager] Keyboard triggered for '\(config.name)'")
                    self?.show(configId: config.id)
                }
            )
        }
    }
    
    /// Register a mouse button trigger
    private func registerMouseTrigger(_ trigger: TriggerConfiguration, forConfig config: StoredRingConfiguration) {
        guard let buttonNumber = trigger.buttonNumber else {
            print("   ⚠️ Mouse trigger missing buttonNumber for '\(config.name)'")
            return
        }
        
        if trigger.isHoldMode {
            print("   ⚠️ Mouse button hold mode not yet implemented for '\(config.name)'")
            return
        }
        
        print("[InstanceManager] Registering mouse TAP: \(trigger.displayDescription) for '\(config.name)'")
        
        hotkeyManager.registerMouseButton(
            buttonNumber: buttonNumber,
            modifierFlags: trigger.modifierFlags,
            forConfigId: config.id
        ) { [weak self] in
            print("🎯 [InstanceManager] Mouse button triggered for '\(config.name)'")
            self?.show(configId: config.id)
        }
    }
    
    /// Register a trackpad gesture trigger
    private func registerTrackpadTrigger(_ trigger: TriggerConfiguration, forConfig config: StoredRingConfiguration) {
        guard let swipeDirection = trigger.swipeDirection,
              let fingerCount = trigger.fingerCount else {
            print("   ⚠️ Trackpad trigger missing direction/fingerCount for '\(config.name)'")
            return
        }
        
        if trigger.isHoldMode {
            print("   ⚠️ Trackpad hold mode not yet implemented for '\(config.name)'")
            return
        }
        
        // Circle gestures
        if swipeDirection == "circleClockwise" || swipeDirection == "circleCounterClockwise" {
            let direction: RotationDirection = swipeDirection == "circleClockwise" ? .clockwise : .counterClockwise
            
            print("[InstanceManager] Registering circle gesture: \(trigger.displayDescription) for '\(config.name)'")
            
            hotkeyManager.registerCircle(
                direction: direction,
                fingerCount: fingerCount,
                modifierFlags: trigger.modifierFlags,
                forConfigId: config.id
            ) { [weak self] triggerDirection in
                print("🎯 [InstanceManager] Circle gesture triggered for '\(config.name)'")
                self?.show(configId: config.id, triggerDirection: triggerDirection)
            }
            return
        }
        
        // Two-finger tap gestures
        if swipeDirection == "twoFingerTapLeft" || swipeDirection == "twoFingerTapRight" {
            let side: TapSide = swipeDirection == "twoFingerTapLeft" ? .left : .right
            
            print("[InstanceManager] Registering two-finger tap: \(trigger.displayDescription) for '\(config.name)'")
            
            hotkeyManager.registerTwoFingerTap(
                side: side,
                modifierFlags: trigger.modifierFlags,
                forConfigId: config.id
            ) { [weak self] _ in
                print("🎯 [InstanceManager] Two-finger tap triggered for '\(config.name)'")
                self?.show(configId: config.id)
            }
            return
        }
        
        // Standard swipe gestures
        print("[InstanceManager] Registering trackpad swipe: \(trigger.displayDescription) for '\(config.name)'")
        
        hotkeyManager.registerSwipe(
            direction: swipeDirection,
            fingerCount: fingerCount,
            modifierFlags: trigger.modifierFlags,
            forConfigId: config.id
        ) { [weak self] in
            print("🎯 [InstanceManager] Trackpad gesture triggered for '\(config.name)'")
            self?.show(configId: config.id)
        }
    }
    
    func startHotkeyMonitoring() {
        print("[InstanceManager] Starting hotkey monitoring...")
        
        // Wire up UI visibility check
        hotkeyManager.isUIVisible = { [weak self] in
            return self?.hasVisibleInstance ?? false
        }
        
        // Wire up hide callback (for Escape key)
        hotkeyManager.onHide = { [weak self] in
            self?.hideActive()
        }
        
        hotkeyManager.onArrowDown = { [weak self] in
            guard let instance = self?.getActiveInstance(),
                  let panelManager = instance.listPanelManager,
                  panelManager.isVisible else { return }
            
            panelManager.moveSelectionDown(in: panelManager.activePanelLevel)
        }

        hotkeyManager.onArrowUp = { [weak self] in
            guard let instance = self?.getActiveInstance(),
                  let panelManager = instance.listPanelManager,
                  panelManager.isVisible else { return }
            
            panelManager.moveSelectionUp(in: panelManager.activePanelLevel)
        }

        hotkeyManager.onArrowRight = { [weak self] in
            guard let instance = self?.getActiveInstance(),
                  let panelManager = instance.listPanelManager,
                  panelManager.isVisible else { return }
            
            panelManager.enterPreviewPanel()
        }

        hotkeyManager.onArrowLeft = { [weak self] in
            guard let instance = self?.getActiveInstance(),
                  let panelManager = instance.listPanelManager,
                  panelManager.isVisible else { return }
            
            panelManager.exitToParentPanel()
        }
        
        hotkeyManager.onCharacterInput = { [weak self] character in
            guard let instance = self?.getActiveInstance(),
                  let panelManager = instance.listPanelManager,
                  panelManager.isVisible else { return }
            
            panelManager.handleCharacterInput(character)
        }
        hotkeyManager.onEnter = { [weak self] in
            guard let instance = self?.getActiveInstance(),
                  let panelManager = instance.listPanelManager,
                  panelManager.isVisible else { return }
            
            panelManager.executeSelectedItem()
        }
        
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
    var visibleInstances: [any UIManager] {
        return instances.values.filter { $0.isVisible }
    }
}

// MARK: - Convenience Extensions

extension CircularUIInstanceManager {
    
    /// Show a specific instance by configuration ID
    /// - Parameter configId: The configuration ID
    func show(configId: Int, triggerDirection: RotationDirection? = nil) {
        guard let instance = getInstance(forConfigId: configId) else {
            print("❌ [InstanceManager] Cannot show - no instance for config \(configId)")
            return
        }
        
        // Toggle: if this instance is already visible, hide it
        if instance.isVisible && activeInstanceId == configId {
            print("🔄 [InstanceManager] Toggle OFF - hiding already visible instance (config \(configId))")
            instance.hide()
            activeInstanceId = nil
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
        instance.show(triggerDirection: triggerDirection)
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
    func getActiveInstance() -> (any UIManager)? {
        guard let activeId = activeInstanceId else { return nil }
        return getInstance(forConfigId: activeId)
    }
    
    /// Check if a specific instance is currently active
    /// - Parameter configId: The configuration ID to check
    /// - Returns: True if this instance is currently active, false otherwise
    func isInstanceActive(_ configId: Int) -> Bool {
        return activeInstanceId == configId
    }
    
    // MARK: - Hold Mode Support
    
    /// Show an instance in hold mode (sets isInHoldMode flag)
    /// - Parameters:
    ///   - configId: The configuration ID
    ///   - trigger: The trigger that activated this ring (for auto-execute settings)
    private func showInHoldMode(configId: Int, trigger: TriggerConfiguration? = nil) {
        guard let instance = getInstance(forConfigId: configId) else {
            print("❌ [InstanceManager] Cannot show in hold mode - no instance for config \(configId)")
            return
        }
        
        // Set hold mode flag and active trigger BEFORE showing
        instance.isInHoldMode = true
        instance.activeTrigger = trigger
        
        // Hide currently active instance if different
        if let currentActiveId = activeInstanceId, currentActiveId != configId {
            print("🔄 [InstanceManager] Hiding previous instance (config \(currentActiveId)) for hold mode")
            if let previousInstance = getInstance(forConfigId: currentActiveId) {
                previousInstance.hide()
            }
        }
        
        // Update active instance tracking
        activeInstanceId = configId
        print("✅ [InstanceManager] Setting active instance to config \(configId) (HOLD MODE)")
        
        // Show the new instance
        instance.show()
    }
    
    /// Hide an instance from hold mode (only if it's currently in hold mode)
    /// - Parameter configId: The configuration ID
    private func hideFromHoldMode(configId: Int) {
        guard let instance = getInstance(forConfigId: configId) else {
            print("❌ [InstanceManager] Cannot hide from hold mode - no instance for config \(configId)")
            return
        }
        
        // Only hide if instance is actually in hold mode
        guard instance.isInHoldMode else {
            print("⚠️ [InstanceManager] Instance \(configId) not in hold mode - skipping hide")
            return
        }
        
        print("🔄 [InstanceManager] Hiding instance from hold mode (config \(configId))")
        
        // Hide the instance
        instance.hide()
        
        // Clear active instance tracking
        if activeInstanceId == configId {
            activeInstanceId = nil
        }
    }
    
    // MARK: - Helper Methods
    
    /// Format a keyboard shortcut for display
    /// - Parameters:
    ///   - keyCode: The key code
    ///   - modifiers: The modifier flags
    /// - Returns: A formatted string like "⌃⇧K"
    private func formatShortcut(keyCode: UInt16, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        // Add key name
        let keyName = keyCodeToString(keyCode)
        parts.append(keyName)
        
        return parts.joined()
    }
    
    /// Convert key code to readable string
    /// - Parameter keyCode: The key code
    /// - Returns: A readable key name
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 40: return "K"
        case 49: return "Space"
        case 50: return "`"
        case 53: return "Esc"
        // Function keys
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 105: return "F13"
        case 107: return "F14"
        case 113: return "F15"
        case 106: return "F16"
        case 64: return "F17"
        case 79: return "F18"
        case 80: return "F19"
        default: return "[\(keyCode)]"
        }
    }
}
