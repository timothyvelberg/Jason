//
//  HotkeyManager.swift
//  Jason
//
//  Created by Timothy Velberg on 05/11/2025.
//

import Foundation
import AppKit

/// Manages all keyboard shortcuts and modifier key tracking for the circular UI
class HotkeyManager {
    
    // MARK: - Callbacks
    
    /// Called when Escape is pressed while UI is visible
    var onHide: (() -> Void)?
    
    /// Called when Shift is pressed (for preview toggle)
    var onShiftPressed: (() -> Void)?
    
    /// Called when Ctrl is released in app switcher mode
    var onCtrlReleasedInAppSwitcher: (() -> Void)?
    
    /// Called when the hold key is pressed (show UI while held)
    var onHoldKeyPressed: (() -> Void)?
    
    /// Called when the hold key is released (hide UI)
    var onHoldKeyReleased: (() -> Void)?
    
    /// Query function to check if UI is currently visible
    var isUIVisible: (() -> Bool)?
    
    /// Query function to check if in app switcher mode
    var isInAppSwitcherMode: (() -> Bool)?
    
    // MARK: - Configuration
    
    /// Key code for hold-to-show functionality (nil = disabled)
    var holdKeyCode: UInt16? = nil
    
    /// Check if the hold key is currently physically pressed
    var isHoldKeyPhysicallyPressed: Bool {
        return isHoldKeyCurrentlyPressed
    }
    
    // MARK: - State Tracking
    
    private var wasShiftPressed: Bool = false
    private var wasCtrlPressed: Bool = false
    private var isHoldKeyCurrentlyPressed: Bool = false
    private var requiresReleaseBeforeNextShow: Bool = false  // Prevents re-show while key still held
    
    // MARK: - Dynamic Shortcuts
    
    /// Registered shortcuts: [configId: (keyCode, modifierFlags, callback)]
    private var registeredShortcuts: [Int: (keyCode: UInt16, modifierFlags: UInt, callback: () -> Void)] = [:]
    
    // MARK: - Event Monitors
    
    private var globalKeyMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var localKeyMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyUpMonitor: Any?  // For hold key release
    private var localKeyUpMonitor: Any?   // For hold key release
    
    // MARK: - Initialization
    
    init() {
        print("⌨️ [HotkeyManager] Initialized")
    }
    
    deinit {
        stopMonitoring()
        print("🧹 [HotkeyManager] Deallocated")
    }
    
    // MARK: - Public Interface
    
    /// Start monitoring for hotkeys
    func startMonitoring() {
        guard globalKeyMonitor == nil else {
            print("⚠️ [HotkeyManager] Already monitoring")
            return
        }
        
        // Listen for global key events (keyDown only)
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        
        // Listen for global key up events (for hold key release)
        globalKeyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyUp]) { [weak self] event in
            self?.handleKeyUpEvent(event)
        }
        
        // Listen for global modifier key changes
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        
        // Listen for local key events (when our window is active)
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }
        
        // Listen for local key up events (for hold key release)
        localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyUp]) { [weak self] event in
            self?.handleKeyUpEvent(event)
            return event
        }
        
        // Listen for local modifier changes
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
        
        print("✅ [HotkeyManager] Monitoring started")
        if holdKeyCode != nil {
            print("   Hold key configured → Hold to show, release to hide")
        }
        
        // Log all registered shortcuts with details
        if !registeredShortcuts.isEmpty {
            print("   📋 Registered shortcuts:")
            for (configId, registration) in registeredShortcuts {
                let display = formatShortcut(keyCode: registration.keyCode, modifiers: registration.modifierFlags)
                print("      Config \(configId): \(display) (keyCode=\(registration.keyCode), modifiers=\(registration.modifierFlags))")
            }
        } else {
            print("   ⚠️ No shortcuts registered yet!")
        }
    }
    
    /// Stop monitoring for hotkeys
    func stopMonitoring() {
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
        
        if let monitor = globalKeyUpMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyUpMonitor = nil
        }
        
        if let monitor = globalFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            globalFlagsMonitor = nil
        }
        
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        
        if let monitor = localKeyUpMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyUpMonitor = nil
        }
        
        if let monitor = localFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            localFlagsMonitor = nil
        }
        
        print("🛑 [HotkeyManager] Monitoring stopped")
    }
    
    /// Reset internal state (call when UI hides)
    func resetState() {
        wasShiftPressed = false
        wasCtrlPressed = false
        isHoldKeyCurrentlyPressed = false
        // Note: requiresReleaseBeforeNextShow is NOT reset here
        // It persists until the key is actually released (keyUp event)
    }
    
    // MARK: - Configuration Methods
    
    /// Configure the hold-to-show key
    /// - Parameter keyCode: The key code to use (e.g., KeyCode.space), or nil to disable
    func setHoldKey(_ keyCode: UInt16?) {
        holdKeyCode = keyCode
        if let keyCode = keyCode {
            print("⚙️ [HotkeyManager] Hold key configured: keyCode \(keyCode)")
        } else {
            print("⚙️ [HotkeyManager] Hold-to-show disabled")
        }
    }
    
    /// Require the hold key to be released before allowing the next show
    /// Call this when an action is executed while the hold key is still pressed
    func requireReleaseBeforeNextShow() {
        requiresReleaseBeforeNextShow = true
        print("🔒 [HotkeyManager] Hold key must be released before next show")
    }
    
    // MARK: - Dynamic Shortcut Registration
    
    /// Register a keyboard shortcut for a ring configuration
    /// - Parameters:
    ///   - keyCode: The key code
    ///   - modifierFlags: The modifier flags bitfield
    ///   - configId: The ring configuration ID
    ///   - callback: The callback to execute when shortcut is pressed
    func registerShortcut(
        keyCode: UInt16,
        modifierFlags: UInt,
        forConfigId configId: Int,
        callback: @escaping () -> Void
    ) {
        let shortcutDisplay = formatShortcut(keyCode: keyCode, modifiers: modifierFlags)
        print("📝 [HotkeyManager] Attempting to register shortcut for config \(configId):")
        print("   Display: \(shortcutDisplay)")
        print("   KeyCode: \(keyCode)")
        print("   Modifiers: \(modifierFlags) (raw value)")
        print("   Modifiers: \(NSEvent.ModifierFlags(rawValue: modifierFlags)) (flags)")
        
        // Check for conflicts with existing shortcuts
        for (existingId, existing) in registeredShortcuts {
            if existing.keyCode == keyCode && existing.modifierFlags == modifierFlags {
                let existingDisplay = formatShortcut(keyCode: existing.keyCode, modifiers: existing.modifierFlags)
                print("⚠️ [HotkeyManager] Shortcut conflict!")
                print("   Existing: Config \(existingId) with \(existingDisplay)")
                print("   New: Config \(configId) with \(shortcutDisplay)")
                print("   Unregistering old shortcut...")
                unregisterShortcut(forConfigId: existingId)
                break
            }
        }
        
        // Store registration
        registeredShortcuts[configId] = (keyCode, modifierFlags, callback)
        
        print("✅ [HotkeyManager] Successfully registered shortcut for config \(configId): \(shortcutDisplay)")
        print("   Total registered shortcuts: \(registeredShortcuts.count)")
    }
    
    /// Unregister a shortcut
    func unregisterShortcut(forConfigId configId: Int) {
        if let _ = registeredShortcuts.removeValue(forKey: configId) {
            print("🗑️ [HotkeyManager] Unregistered shortcut for config \(configId)")
        }
    }
    
    /// Unregister all shortcuts
    func unregisterAllShortcuts() {
        let count = registeredShortcuts.count
        registeredShortcuts.removeAll()
        print("🗑️ [HotkeyManager] Unregistered all \(count) shortcut(s)")
    }
    
    // MARK: - Private Handlers
    
    private func handleKeyEvent(_ event: NSEvent) {
        let isUIVisible = isUIVisible?() ?? false
        
        // Log every key event for debugging
        let eventModifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        print("🔍 [HotkeyManager] Key event: keyCode=\(event.keyCode), modifiers=\(eventModifiers.rawValue), UI visible=\(isUIVisible)")
        
        // Hold key pressed (if configured)
        if let holdKeyCode = holdKeyCode, event.keyCode == holdKeyCode && !isHoldKeyCurrentlyPressed {
            // Check if we need to wait for a release first
            if requiresReleaseBeforeNextShow {
                print("⌨️ [HotkeyManager] Hold key pressed but waiting for release - ignoring")
                return
            }
            
            print("⌨️ [HotkeyManager] Hold key pressed")
            isHoldKeyCurrentlyPressed = true
            onHoldKeyPressed?()
            return
        }
        
        // Escape = Hide UI (only when UI is visible)
        if event.keyCode == 53 && isUIVisible {
            print("⌨️ [HotkeyManager] Escape pressed")
            onHide?()
            return
        }
        
        // Check dynamic shortcuts (only when UI is hidden)
        if !isUIVisible {
            print("🔍 [HotkeyManager] Checking \(registeredShortcuts.count) registered shortcut(s)...")
            
            for (configId, registration) in registeredShortcuts {
                let registeredModifiers = NSEvent.ModifierFlags(rawValue: registration.modifierFlags)
                
                print("   🔍 Config \(configId): keyCode=\(registration.keyCode) (want \(event.keyCode)), modifiers=\(registeredModifiers.rawValue) (have \(eventModifiers.rawValue))")
                
                if event.keyCode == registration.keyCode &&
                   eventModifiers == registeredModifiers {
                    print("✅ [HotkeyManager] Dynamic shortcut MATCHED for config \(configId)!")
                    registration.callback()
                    return
                } else {
                    if event.keyCode != registration.keyCode {
                        print("   ❌ KeyCode mismatch: \(event.keyCode) != \(registration.keyCode)")
                    }
                    if eventModifiers != registeredModifiers {
                        print("   ❌ Modifier mismatch: \(eventModifiers.rawValue) != \(registeredModifiers.rawValue)")
                    }
                }
            }
            
            print("⚠️ [HotkeyManager] No matching shortcut found")
        } else {
            print("🔍 [HotkeyManager] UI is visible, skipping shortcut check")
        }
    }
    
    private func handleKeyUpEvent(_ event: NSEvent) {
        // Hold key released (if configured and was pressed)
        if let holdKeyCode = holdKeyCode, event.keyCode == holdKeyCode {
            print("⌨️ [HotkeyManager] Hold key released")
            
            // Clear the "requires release" flag now that key is actually released
            if requiresReleaseBeforeNextShow {
                requiresReleaseBeforeNextShow = false
                print("🔓 Hold key released - ready for next show")
            }
            
            // Only trigger hide callback if key was actually pressed (not just waiting for release)
            if isHoldKeyCurrentlyPressed {
                isHoldKeyCurrentlyPressed = false
                onHoldKeyReleased?()
            }
            return
        }
    }
    
    private func handleFlagsChanged(_ event: NSEvent) {
        // Only process flag changes when UI is visible
        guard isUIVisible?() ?? false else { return }
        
        let isShiftPressed = event.modifierFlags.contains(.shift)
        let isCtrlPressed = event.modifierFlags.contains(.control)
        
        // Handle Ctrl release in App Switcher Mode
        let inAppSwitcherMode = isInAppSwitcherMode?() ?? false
        if inAppSwitcherMode && wasCtrlPressed && !isCtrlPressed {
            print("⌨️ [HotkeyManager] Ctrl released in app switcher mode")
            onCtrlReleasedInAppSwitcher?()
            wasCtrlPressed = false
            return
        }
        
        // Track Ctrl state
        wasCtrlPressed = isCtrlPressed
        
        // Only trigger on SHIFT press (transition from not-pressed to pressed)
        if isShiftPressed && !wasShiftPressed {
            print("⌨️ [HotkeyManager] Shift pressed")
            onShiftPressed?()
        }
        
        wasShiftPressed = isShiftPressed
    }
    
    // MARK: - Helper Methods
    
    /// Format a shortcut for display (helper for logging)
    private func formatShortcut(keyCode: UInt16, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        parts.append(keyCodeToString(keyCode))
        
        return parts.joined()
    }
    
    /// Convert key code to string (helper for display)
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
        default: return "[\(keyCode)]"
        }
    }
}

// MARK: - Hotkey Configuration

extension HotkeyManager {
    /// Key codes for reference
    struct KeyCode {
        static let escape: UInt16 = 53
        static let k: UInt16 = 40
        static let graveAccent: UInt16 = 50  // ` / ~
        
        // Function keys for hold-to-show (recommended - no conflicts)
        static let f13: UInt16 = 105
        static let f14: UInt16 = 107
        static let f15: UInt16 = 113
        static let f16: UInt16 = 106
        static let f17: UInt16 = 64
        static let f18: UInt16 = 79
        static let f19: UInt16 = 80
        
        // Other keys for hold-to-show
        static let space: UInt16 = 49
        static let tab: UInt16 = 48
        static let f: UInt16 = 3
        static let g: UInt16 = 5
        static let h: UInt16 = 4
    }
}
