//
//  HotkeyManager+KeyboardEventTap.swift
//  Jason
//
//  Created by Timothy Velberg on 14/03/2026.
//

import AppKit

extension HotkeyManager {
    
    func startKeyboardEventTap() {
        guard keyboardEventTap == nil else {
            print("[HotkeyManager] Keyboard event tap already active")
            return
        }
        
        print("[HotkeyManager] Starting keyboard event tap...")
        
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let mySelf = Unmanaged<HotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()
                return mySelf.handleKeyboardEventTap(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[HotkeyManager] Failed to create keyboard event tap")
            print("   NOTE: This requires Accessibility permissions!")
            return
        }
        
        keyboardEventTap = eventTap
        keyboardRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), keyboardRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        print("[HotkeyManager] Keyboard event tap started (intercepts before other apps)")
    }
    
    func stopKeyboardEventTap() {
        if let eventTap = keyboardEventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), keyboardRunLoopSource, .commonModes)
            keyboardEventTap = nil
            keyboardRunLoopSource = nil
            print("[HotkeyManager] Keyboard event tap stopped")
        }
    }
    
    func handleKeyboardEventTap(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = keyboardEventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }
        
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let cgFlags = event.flags
        
        var eventModifiers: UInt = 0
        if cgFlags.contains(.maskCommand) { eventModifiers |= NSEvent.ModifierFlags.command.rawValue }
        if cgFlags.contains(.maskControl) { eventModifiers |= NSEvent.ModifierFlags.control.rawValue }
        if cgFlags.contains(.maskAlternate) { eventModifiers |= NSEvent.ModifierFlags.option.rawValue }
        if cgFlags.contains(.maskShift) { eventModifiers |= NSEvent.ModifierFlags.shift.rawValue }
        
        let normalizedModifiers = eventModifiers & (
            NSEvent.ModifierFlags.command.rawValue |
            NSEvent.ModifierFlags.control.rawValue |
            NSEvent.ModifierFlags.option.rawValue |
            NSEvent.ModifierFlags.shift.rawValue
        )
        
        if type == .keyDown {
            for (configId, registration) in registeredShortcuts {
                if registration.keyCode == keyCode && registration.modifierFlags == normalizedModifiers {
                    let display = formatShortcut(keyCode: keyCode, modifiers: normalizedModifiers)
                    
                    if registration.isHoldMode {
                        if activeHoldRegistration == configId { return nil }
                        if requiresReleaseBeforeNextShow && activeHoldRegistration != nil { return nil }
                        
                        print("[HotkeyManager] HOLD mode MATCHED for config \(configId): \(display) (intercepted)")
                        activeHoldRegistration = configId
                        DispatchQueue.main.async { registration.onPress() }
                    } else {
                        print("[HotkeyManager] TAP mode MATCHED for config \(configId): \(display) (intercepted)")
                        DispatchQueue.main.async { registration.onPress() }
                    }
                    
                    return nil
                }
            }
            
        } else if type == .keyUp {
            if let activeConfigId = activeHoldRegistration,
               let registration = registeredShortcuts[activeConfigId],
               registration.keyCode == keyCode {
                
                let display = formatShortcut(keyCode: registration.keyCode, modifiers: registration.modifierFlags)
                print("[HotkeyManager] HOLD key released for config \(activeConfigId): \(display)")
                
                activeHoldRegistration = nil
                
                if requiresReleaseBeforeNextShow {
                    requiresReleaseBeforeNextShow = false
                    print("   Ready for next show")
                }
                
                DispatchQueue.main.async { registration.onRelease?() }
                return nil
            }
        }
        
        return Unmanaged.passRetained(event)
    }
}
