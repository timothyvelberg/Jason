//
//  HotkeyManager+GestureHandling.swift
//  Jason
//
//  Created by Timothy Velberg on 14/03/2026.

import AppKit

extension HotkeyManager {
    
    func handleGestureEvent(_ event: GestureEvent) {
        let isUIVisible = isUIVisible?() ?? false
        guard !isUIVisible else { return }

        let cgFlags = CGEventSource.flagsState(.combinedSessionState)
        var eventModifiers: UInt = 0
        if cgFlags.contains(.maskCommand) { eventModifiers |= NSEvent.ModifierFlags.command.rawValue }
        if cgFlags.contains(.maskControl) { eventModifiers |= NSEvent.ModifierFlags.control.rawValue }
        if cgFlags.contains(.maskAlternate) { eventModifiers |= NSEvent.ModifierFlags.option.rawValue }
        if cgFlags.contains(.maskShift) { eventModifiers |= NSEvent.ModifierFlags.shift.rawValue }

        // Shared app-scope gate helper
        func passesAppScopeGate(bundleId: String?) -> Bool {
            guard let requiredBundleId = bundleId else { return true }
            let frontmost = FrontmostAppMonitor.shared.frontmostApp?.bundleIdentifier
            if frontmost != requiredBundleId {
                print("[HotkeyManager] Gesture skipped — frontmost '\(frontmost ?? "nil")' != '\(requiredBundleId)'")
                return false
            }
            return true
        }

        switch event {
        case .circle(let direction, let fingerCount):
            for (configId, registration) in registeredCircles {
                if registration.direction == direction &&
                   registration.fingerCount == fingerCount &&
                   registration.modifierFlags == eventModifiers {
                    guard passesAppScopeGate(bundleId: registration.bundleId) else { continue }
                    let display = formatCircleGesture(direction: direction, fingerCount: fingerCount, modifiers: eventModifiers)
                    print("[HotkeyManager] Circle MATCHED for config \(configId): \(display)")
                    DispatchQueue.main.async { registration.callback(direction) }
                    return
                }
            }
            print("   No matching circle gesture found")

        case .twoFingerTap(let side):
            for (configId, registration) in registeredTwoFingerTaps {
                if registration.side == side && registration.modifierFlags == eventModifiers {
                    guard passesAppScopeGate(bundleId: registration.bundleId) else { continue }
                    let display = formatTwoFingerTap(side: side, modifiers: eventModifiers)
                    print("[HotkeyManager] Two-finger tap MATCHED for config \(configId): \(display)")
                    DispatchQueue.main.async { registration.callback(side) }
                    return
                }
            }
            print("   No matching two-finger tap found")

        case .swipe(let direction, let fingerCount):
            let directionString = direction.rawValue
            for (configId, registration) in registeredSwipes {
                if registration.direction == directionString &&
                   registration.fingerCount == fingerCount &&
                   registration.modifierFlags == eventModifiers {
                    guard passesAppScopeGate(bundleId: registration.bundleId) else { continue }
                    let display = formatTrackpadGesture(direction: registration.direction, fingerCount: registration.fingerCount, modifiers: registration.modifierFlags)
                    print("[HotkeyManager] Swipe MATCHED for config \(configId): \(display)")
                    DispatchQueue.main.async { registration.callback() }
                    return
                }
            }
            print("   No matching swipe gesture found")

        case .tap(let fingerCount):
            for (configId, registration) in registeredSwipes {
                if registration.direction == "tap" &&
                   registration.fingerCount == fingerCount &&
                   registration.modifierFlags == eventModifiers {
                    guard passesAppScopeGate(bundleId: registration.bundleId) else { continue }
                    let display = formatTrackpadGesture(direction: "tap", fingerCount: fingerCount, modifiers: eventModifiers)
                    print("[HotkeyManager] Tap MATCHED for config \(configId): \(display)")
                    DispatchQueue.main.async { registration.callback() }
                    return
                }
            }
            print("   No matching tap gesture found")

        case .fingerAdd(let fromCount, let toCount):
            for (configId, registration) in registeredSwipes {
                if registration.direction == "add" &&
                   registration.fingerCount == toCount &&
                   registration.modifierFlags == eventModifiers {
                    guard passesAppScopeGate(bundleId: registration.bundleId) else { continue }
                    let display = formatTrackpadGesture(direction: "add", fingerCount: toCount, modifiers: eventModifiers)
                    print("[HotkeyManager] Add MATCHED for config \(configId): \(display)")
                    DispatchQueue.main.async { registration.callback() }
                    return
                }
            }
            print("   No matching add gesture found")
        }
    }
}
