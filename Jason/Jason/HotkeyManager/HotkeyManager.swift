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
    
    var onHide: (() -> Void)?
    var onTildePressed: (() -> Void)?
    var onCtrlReleasedInAppSwitcher: (() -> Void)?
    var isUIVisible: (() -> Bool)?
    var isInAppSwitcherMode: (() -> Bool)?
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onArrowLeft: (() -> Void)?
    var onArrowRight: (() -> Void)?
    var onCharacterInput: ((String) -> Void)?
    var onEnter: (() -> Void)?
    var onEscapePressed: (() -> Bool)?
    var onBackspace: (() -> Void)?
    var onDeleteWord: (() -> Void)?
    var onDeleteAll: (() -> Void)?
    
    // MARK: - Configuration
    
    var holdKeyCode: UInt16? = nil
    
    // MARK: - State Tracking
    
    var wasShiftPressed: Bool = false
    var wasCtrlPressed: Bool = false
    var requiresReleaseBeforeNextShow: Bool = false
    var activeHoldRegistration: Int? = nil
    var activeModifierHoldRegistration: Int? = nil
    var currentSustainMask: UInt = 0
    
    // MARK: - Event Monitors
    
    var globalKeyMonitor: Any?
    var globalFlagsMonitor: Any?
    var localKeyMonitor: Any?
    var localFlagsMonitor: Any?
    var globalKeyUpMonitor: Any?
    var localKeyUpMonitor: Any?
    var globalSwipeMonitor: Any?
    
    // MARK: - Keyboard Event Tap
    
    var keyboardEventTap: CFMachPort?
    var keyboardRunLoopSource: CFRunLoopSource?
    
    // MARK: - Mouse Monitoring
    
    var mouseEventTap: CFMachPort?
    var mouseRunLoopSource: CFRunLoopSource?
    
    // MARK: - Multitouch
    
    var multitouchCoordinator: MultitouchCoordinator?
    
    // MARK: - Registrations
    
    var registeredMouseButtons: [Int: (buttonNumber: Int32, modifierFlags: UInt, callback: () -> Void)] = [:]
    var registeredSwipes: [Int: (direction: String, fingerCount: Int, modifierFlags: UInt, callback: () -> Void)] = [:]
    var registeredShortcuts: [Int: KeyboardRegistration] = [:]
    var registeredTwoFingerTaps: [Int: (side: TapSide, modifierFlags: UInt, callback: (TapSide) -> Void)] = [:]
    var registeredCircles: [Int: (direction: RotationDirection, fingerCount: Int, modifierFlags: UInt, callback: (RotationDirection) -> Void)] = [:]

    struct KeyboardRegistration {
        let keyCode: UInt16
        let modifierFlags: UInt
        let isHoldMode: Bool
        let isModifierHoldMode: Bool
        let sustainModifierMask: UInt
        let onPress: () -> Void
        let onRelease: (() -> Void)?
    }
    
    // MARK: - Initialization
    
    init() {
        print("[HotkeyManager] Initialized")
    }
    
    deinit {
        stopMonitoring()
        print("[HotkeyManager] Deallocated")
    }
    
    // MARK: - Public Interface
    
    func startMonitoring() {
        guard globalKeyMonitor == nil else {
            print("[HotkeyManager] Already monitoring")
            return
        }
        
        let hasAccessibility = PermissionManager.shared.hasAccessibilityAccess
        
        if !hasAccessibility {
            print("[HotkeyManager] No accessibility permission - advanced features disabled")
        }
        
        if hasAccessibility {
            startKeyboardEventTap()
        } else {
            print("[HotkeyManager] Skipping keyboard event tap (no accessibility permission)")
        }
        
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            let handled = self?.handleKeyEvent(event) ?? false
            return handled ? nil : event
        }
        
        localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyUp]) { [weak self] event in
            self?.handleKeyUpEvent(event)
            return event
        }
        
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
        
        globalSwipeMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.swipe]) { [weak self] event in
            self?.handleSwipeEvent(event)
        }
        
        if !registeredShortcuts.isEmpty {
            print("   Registered shortcuts:")
            for (configId, registration) in registeredShortcuts {
                let display = formatShortcut(keyCode: registration.keyCode, modifiers: registration.modifierFlags)
                print("      Config \(configId): \(display) (keyCode=\(registration.keyCode), modifiers=\(registration.modifierFlags))")
            }
        } else {
            print("   No shortcuts registered yet!")
        }
        
        if !registeredMouseButtons.isEmpty {
            print("   Registered mouse buttons:")
            for (configId, registration) in registeredMouseButtons {
                let display = formatMouseButton(buttonNumber: registration.buttonNumber, modifiers: registration.modifierFlags)
                print("      Config \(configId): \(display) (button=\(registration.buttonNumber), modifiers=\(registration.modifierFlags))")
            }
            if mouseEventTap == nil && hasAccessibility {
                startMouseMonitoring()
            } else if !hasAccessibility {
                print("   Cannot monitor mouse buttons - no accessibility permission")
            }
        }
        
        // Calibration trigger: Ctrl+9
        registerShortcut(keyCode: 25, modifierFlags: NSEvent.ModifierFlags.control.rawValue, forConfigId: 99999) { [weak self] in
            print("Starting circle calibration...")
            self?.startCircleCalibration()
        }
        
        if multitouchCoordinator == nil {
            startCircleMonitoring()
        }
    }
    
    func stopMonitoring() {
        if let monitor = globalKeyMonitor { NSEvent.removeMonitor(monitor); globalKeyMonitor = nil }
        if let monitor = globalKeyUpMonitor { NSEvent.removeMonitor(monitor); globalKeyUpMonitor = nil }
        if let monitor = globalFlagsMonitor { NSEvent.removeMonitor(monitor); globalFlagsMonitor = nil }
        if let monitor = localKeyMonitor { NSEvent.removeMonitor(monitor); localKeyMonitor = nil }
        if let monitor = localKeyUpMonitor { NSEvent.removeMonitor(monitor); localKeyUpMonitor = nil }
        if let monitor = localFlagsMonitor { NSEvent.removeMonitor(monitor); localFlagsMonitor = nil }
        if let monitor = globalSwipeMonitor { NSEvent.removeMonitor(monitor); globalSwipeMonitor = nil }
        
        stopCircleMonitoring()
        stopMouseMonitoring()
        stopKeyboardEventTap()
        
        print("[HotkeyManager] Monitoring stopped")
    }
    
    func resetState() {
        wasShiftPressed = false
        wasCtrlPressed = false
    }
    
    func requireReleaseBeforeNextShow() {
        requiresReleaseBeforeNextShow = true
        print("[HotkeyManager] Hold key must be released before next show")
    }
}
