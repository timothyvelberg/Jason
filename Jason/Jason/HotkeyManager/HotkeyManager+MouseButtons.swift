//
//  HotkeyManager+MouseButtons.swift
//  Jason
//
//  Created by Timothy Velberg on 14/03/2026.
//

import AppKit

extension HotkeyManager {
    
    // MARK: - Registration
    
    func registerMouseButton(
        buttonNumber: Int32,
        modifierFlags: UInt,
        forConfigId configId: Int,
        callback: @escaping () -> Void
    ) {
        let buttonDisplay = formatMouseButton(buttonNumber: buttonNumber, modifiers: modifierFlags)
        print("[HotkeyManager] Attempting to register mouse button for config \(configId): \(buttonDisplay)")
        
        for (existingId, existing) in registeredMouseButtons {
            if existing.buttonNumber == buttonNumber && existing.modifierFlags == modifierFlags {
                unregisterMouseButton(forConfigId: existingId)
                break
            }
        }
        
        registeredMouseButtons[configId] = (buttonNumber, modifierFlags, callback)
        
        if registeredMouseButtons.count == 1 && mouseEventTap == nil {
            startMouseMonitoring()
        }
    }
    
    func unregisterMouseButton(forConfigId configId: Int) {
        if let _ = registeredMouseButtons.removeValue(forKey: configId) {
            print("[HotkeyManager] Unregistered mouse button for config \(configId)")
            if registeredMouseButtons.isEmpty {
                stopMouseMonitoring()
            }
        }
    }
    
    func unregisterAllMouseButtons() {
        let count = registeredMouseButtons.count
        registeredMouseButtons.removeAll()
        print("[HotkeyManager] Unregistered all \(count) mouse button(s)")
        if count > 0 { stopMouseMonitoring() }
    }
    
    // MARK: - Monitoring
    
    func startMouseMonitoring() {
        guard mouseEventTap == nil else {
            print("[HotkeyManager] Mouse monitoring already active")
            return
        }
        
        print("[HotkeyManager] Starting mouse button monitoring...")
        
        let eventMask = (1 << CGEventType.otherMouseDown.rawValue)
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let mySelf = Unmanaged<HotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()
                mySelf.handleMouseEvent(event, type: type)
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[HotkeyManager] Failed to create mouse event tap")
            print("   NOTE: This requires Accessibility permissions!")
            return
        }
        
        mouseEventTap = eventTap
        mouseRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), mouseRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        print("[HotkeyManager] Mouse button monitoring started")
        
        if !registeredMouseButtons.isEmpty {
            print("   Registered mouse buttons:")
            for (configId, registration) in registeredMouseButtons {
                let display = formatMouseButton(buttonNumber: registration.buttonNumber, modifiers: registration.modifierFlags)
                print("      Config \(configId): \(display) (button=\(registration.buttonNumber), modifiers=\(registration.modifierFlags))")
            }
        }
    }
    
    func stopMouseMonitoring() {
        if let eventTap = mouseEventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), mouseRunLoopSource, .commonModes)
            mouseEventTap = nil
            mouseRunLoopSource = nil
            print("[HotkeyManager] Mouse button monitoring stopped")
        }
    }
    
    // MARK: - Handler
    
    func handleMouseEvent(_ event: CGEvent, type: CGEventType) {
        let isUIVisible = isUIVisible?() ?? false
        guard !isUIVisible else { return }
        
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        let cgFlags = event.flags
        var eventModifiers: UInt = 0
        
        if cgFlags.contains(.maskCommand) { eventModifiers |= NSEvent.ModifierFlags.command.rawValue }
        if cgFlags.contains(.maskControl) { eventModifiers |= NSEvent.ModifierFlags.control.rawValue }
        if cgFlags.contains(.maskAlternate) { eventModifiers |= NSEvent.ModifierFlags.option.rawValue }
        if cgFlags.contains(.maskShift) { eventModifiers |= NSEvent.ModifierFlags.shift.rawValue }
        
        print("[HotkeyManager] Mouse button \(buttonNumber) pressed, modifiers=\(eventModifiers)")
        
        for (configId, registration) in registeredMouseButtons {
            if buttonNumber == Int64(registration.buttonNumber) && eventModifiers == registration.modifierFlags {
                let display = formatMouseButton(buttonNumber: registration.buttonNumber, modifiers: registration.modifierFlags)
                print("[HotkeyManager] Mouse button MATCHED for config \(configId): \(display)")
                registration.callback()
                return
            }
        }
        
        print("[HotkeyManager] No matching mouse button found")
    }
}
