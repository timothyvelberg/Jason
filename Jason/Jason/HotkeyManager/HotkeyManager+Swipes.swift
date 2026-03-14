//
//  HotkeyManager+Swipes.swift
//  Jason
//
//  Created by Timothy Velberg on 14/03/2026.
//

import AppKit

extension HotkeyManager {
    
    // MARK: - Registration
    
    func registerSwipe(
        direction: String,
        fingerCount: Int,
        modifierFlags: UInt,
        forConfigId configId: Int,
        callback: @escaping () -> Void
    ) {
        for (existingId, existing) in registeredSwipes {
            if existing.direction == direction &&
               existing.fingerCount == fingerCount &&
               existing.modifierFlags == modifierFlags {
                unregisterSwipe(forConfigId: existingId)
                break
            }
        }
        registeredSwipes[configId] = (direction, fingerCount, modifierFlags, callback)
    }
    
    func unregisterSwipe(forConfigId configId: Int) {
        if let _ = registeredSwipes.removeValue(forKey: configId) {
            print("[HotkeyManager] Unregistered swipe for config \(configId)")
        }
    }
    
    func unregisterAllSwipes() {
        let count = registeredSwipes.count
        registeredSwipes.removeAll()
        print("[HotkeyManager] Unregistered all \(count) swipe gesture(s)")
    }
    
    // MARK: - Handler
    
    func handleSwipeEvent(_ event: NSEvent) {
        let isUIVisible = isUIVisible?() ?? false
        print("   isUIVisible: \(isUIVisible)")
        
        guard !isUIVisible else {
            print("   Ignoring swipe - UI is visible")
            return
        }
        
        let deltaX = event.deltaX
        let deltaY = event.deltaY
        print("   Delta values: X=\(deltaX), Y=\(deltaY)")
        
        let direction: String
        if abs(deltaX) > abs(deltaY) {
            direction = deltaX > 0 ? "right" : "left"
            print("   → Detected HORIZONTAL swipe: \(direction)")
        } else {
            direction = deltaY > 0 ? "down" : "up"
            print("   → Detected VERTICAL swipe: \(direction)")
        }
        
        let cgFlags = CGEventSource.flagsState(.combinedSessionState)
        var eventModifiers: UInt = 0
        if cgFlags.contains(.maskCommand) { eventModifiers |= NSEvent.ModifierFlags.command.rawValue }
        if cgFlags.contains(.maskControl) { eventModifiers |= NSEvent.ModifierFlags.control.rawValue }
        if cgFlags.contains(.maskAlternate) { eventModifiers |= NSEvent.ModifierFlags.option.rawValue }
        if cgFlags.contains(.maskShift) { eventModifiers |= NSEvent.ModifierFlags.shift.rawValue }
        
        print("[HotkeyManager] Swipe gesture detected (NSEvent - no finger count): direction=\(direction), modifiers=\(eventModifiers)")
        print("   NSEvent swipe handler called - finger count unknown, cannot match registered gestures")
        print("   Registered gestures require finger count from MultitouchGestureDetector")
    }
}
