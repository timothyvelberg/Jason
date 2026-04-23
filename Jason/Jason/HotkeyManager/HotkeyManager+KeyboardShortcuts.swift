//
//  HotkeyManager+KeyboardShortcuts.swift
//  Jason
//
//  Created by Timothy Velberg on 14/03/2026.

import AppKit

extension HotkeyManager {
    
    // MARK: - Registration
    
    func registerShortcut(
        keyCode: UInt16,
        modifierFlags: UInt,
        isHoldMode: Bool = false,
        isModifierHoldMode: Bool = false,
        bundleId: String? = nil,        // NEW
        forConfigId configId: Int,
        onPress: @escaping () -> Void,
        onRelease: (() -> Void)? = nil
    ) {
        let shortcutDisplay = formatShortcut(keyCode: keyCode, modifiers: modifierFlags)
        let modeLabel = isModifierHoldMode ? "MODIFIER HOLD" : isHoldMode ? "HOLD" : "TAP"
        print("[HotkeyManager] Registering \(modeLabel) shortcut for config \(configId): \(shortcutDisplay)")

        // Conflict check: only unregister if same combo AND same scope
        for (existingId, existing) in registeredShortcuts {
            guard existing.keyCode == keyCode && existing.modifierFlags == modifierFlags else { continue }
            let sameScope: Bool
            switch (bundleId, existing.bundleId) {
            case (nil, nil):          sameScope = true
            case (let a?, let b?) where a == b: sameScope = true
            default:                  sameScope = false
            }
            if sameScope {
                print("   Conflict with config \(existingId) (same scope) - unregistering old")
                unregisterShortcut(forConfigId: existingId)
                break
            }
        }

        registeredShortcuts[configId] = KeyboardRegistration(
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            isHoldMode: isHoldMode,
            isModifierHoldMode: isModifierHoldMode,
            sustainModifierMask: modifierFlags,
            bundleId: bundleId,
            onPress: onPress,
            onRelease: onRelease
        )
    }
    
    func unregisterShortcut(forConfigId configId: Int) {
        if let _ = registeredShortcuts.removeValue(forKey: configId) {
            print("[HotkeyManager] Unregistered shortcut for config \(configId)")
        }
    }
    
    func unregisterAllShortcuts() {
        let count = registeredShortcuts.count
        registeredShortcuts.removeAll()
        print("[HotkeyManager] Unregistered all \(count) shortcut(s)")
    }
    
    // MARK: - Handlers
    
    @discardableResult
    func handleKeyEvent(_ event: NSEvent) -> Bool {
        let isUIVisible = isUIVisible?() ?? false
        let eventModifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        
        if event.keyCode == 53 && isUIVisible {
            print("[HotkeyManager] Escape pressed")
            if onEscapePressed?() == true {
                print("[HotkeyManager] Escape consumed by search")
                return true
            }
            onHide?()
            return true
        }
        
        if isUIVisible {
            switch event.keyCode {
            case 125:
                print("[HotkeyManager] Down arrow pressed")
                onArrowDown?()
                return true
            case 126:
                print("[HotkeyManager] Up arrow pressed")
                onArrowUp?()
                return true
            case 123:
                print("[HotkeyManager] Left arrow pressed")
                onArrowLeft?()
                return true
            case 124:
                print("[HotkeyManager] Right arrow pressed")
                onArrowRight?()
                return true
            case 36, 76:
                print("[HotkeyManager] Enter pressed")
                onEnter?()
                return true
            case 50:
                print("[HotkeyManager] Tilde pressed")
                onTildePressed?()
                return true
            case 51:
                if eventModifiers.contains(.command) {
                    print("[HotkeyManager] CMD+Backspace pressed")
                    onDeleteAll?()
                    return true
                } else if eventModifiers.contains(.option) {
                    print("[HotkeyManager] ALT+Backspace pressed")
                    onDeleteWord?()
                    return true
                } else {
                    print("[HotkeyManager] Backspace pressed")
                    onBackspace?()
                    return true
                }
            default:
                break
            }
            
            let hasBlockingModifiers = !event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            if !hasBlockingModifiers,
               let characters = event.charactersIgnoringModifiers,
               characters.count == 1,
               let char = characters.first,
               (char.isLetter || char.isNumber || char == " " || char.isPunctuation || char.isSymbol) {
                print("[HotkeyManager] Character input: '\(characters)'")
                onCharacterInput?(characters)
                return true
            }
        }
        
        let matchingRegistrations = registeredShortcuts.filter { $0.value.keyCode == event.keyCode }
        guard !matchingRegistrations.isEmpty else { return false }
        
        var bestMatch: (configId: Int, registration: KeyboardRegistration)? = nil
        var bestModifierCount = -1
        
        for (configId, registration) in matchingRegistrations {
            let registeredModifiers = NSEvent.ModifierFlags(rawValue: registration.modifierFlags)
                .intersection([.command, .control, .option, .shift])
            guard eventModifiers == registeredModifiers else { continue }
            let modifierCount = registeredModifiers.rawValue.nonzeroBitCount
            if modifierCount > bestModifierCount {
                bestModifierCount = modifierCount
                bestMatch = (configId, registration)
            }
        }
        
        guard let match = bestMatch else {
            print("[HotkeyManager] No exact modifier match for keyCode \(event.keyCode)")
            return false
        }
        // App-scope gate
        if let requiredBundleId = match.registration.bundleId {
            let frontmost = FrontmostAppMonitor.shared.frontmostApp?.bundleIdentifier
            guard frontmost == requiredBundleId else {
                print("[HotkeyManager] Trigger skipped — frontmost app '\(frontmost ?? "nil")' != '\(requiredBundleId)'")
                return false
            }
        }
        
        let display = formatShortcut(keyCode: match.registration.keyCode, modifiers: match.registration.modifierFlags)
        
        if match.registration.isHoldMode {
            if activeHoldRegistration == match.configId {
                print("[HotkeyManager] Hold key already active - ignoring repeat")
                return true
            }
            if requiresReleaseBeforeNextShow && activeHoldRegistration != nil {
                print("[HotkeyManager] Waiting for release before next show")
                return true
            }
            print("[HotkeyManager] HOLD mode MATCHED for config \(match.configId): \(display)")
            activeHoldRegistration = match.configId
            match.registration.onPress()
            return true
        } else {
            print("[HotkeyManager] TAP mode MATCHED for config \(match.configId): \(display)")
            match.registration.onPress()
            return true
        }
    }
    
    func handleKeyUpEvent(_ event: NSEvent) {
        guard let activeConfigId = activeHoldRegistration,
              let registration = registeredShortcuts[activeConfigId],
              registration.keyCode == event.keyCode else { return }
        
        let display = formatShortcut(keyCode: registration.keyCode, modifiers: registration.modifierFlags)
        print("[HotkeyManager] HOLD key released for config \(activeConfigId): \(display)")
        
        activeHoldRegistration = nil
        
        if requiresReleaseBeforeNextShow {
            requiresReleaseBeforeNextShow = false
            print("   Ready for next show")
        }
        
        registration.onRelease?()
    }
    
    func handleFlagsChanged(_ event: NSEvent) {
        // Modifier hold release detection — must run regardless of UI visibility
        if let activeConfigId = activeModifierHoldRegistration,
           let registration = registeredShortcuts[activeConfigId] {
            
            let currentFlags = event.modifierFlags.rawValue & (
                NSEvent.ModifierFlags.command.rawValue |
                NSEvent.ModifierFlags.control.rawValue |
                NSEvent.ModifierFlags.option.rawValue |
                NSEvent.ModifierFlags.shift.rawValue
            )
            
            let sustainStillHeld = (currentFlags & currentSustainMask) == currentSustainMask
            
            if !sustainStillHeld {
                print("[HotkeyManager] Sustain modifiers released for config \(activeConfigId)")
                activeModifierHoldRegistration = nil
                currentSustainMask = 0
                DispatchQueue.main.async { registration.onRelease?() }
            }
        }
        
        guard isUIVisible?() ?? false else { return }
        
        let isShiftPressed = event.modifierFlags.contains(.shift)
        let isCtrlPressed = event.modifierFlags.contains(.control)
        
        let inAppSwitcherMode = isInAppSwitcherMode?() ?? false
        if inAppSwitcherMode && wasCtrlPressed && !isCtrlPressed {
            print("[HotkeyManager] Ctrl released in app switcher mode")
            onCtrlReleasedInAppSwitcher?()
            wasCtrlPressed = false
            return
        }
        
        wasCtrlPressed = isCtrlPressed
    }
}
