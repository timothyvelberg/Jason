//
//  HotkeyManager+TwoFingerTaps.swift
//  Jason
//
//  Created by Timothy Velberg on 14/03/2026.

import AppKit

extension HotkeyManager {
    
    func registerTwoFingerTap(
        side: TapSide,
        modifierFlags: UInt,
        forConfigId configId: Int,
        callback: @escaping (TapSide) -> Void
    ) {
        let display = formatTwoFingerTap(side: side, modifiers: modifierFlags)
        print("[HotkeyManager] Registering two-finger tap for config \(configId): \(display)")
        
        for (existingId, existing) in registeredTwoFingerTaps {
            if existing.side == side && existing.modifierFlags == modifierFlags {
                print("   [HotkeyManager] Two-finger tap conflict with config \(existingId) - unregistering old")
                unregisterTwoFingerTap(forConfigId: existingId)
                break
            }
        }
        
        registeredTwoFingerTaps[configId] = (side, modifierFlags, callback)
    }
    
    
    func unregisterTwoFingerTap(forConfigId configId: Int) {
        if let _ = registeredTwoFingerTaps.removeValue(forKey: configId) {
            print("[HotkeyManager] Unregistered two-finger tap for config \(configId)")
        }
    }
    
    func unregisterAllTwoFingerTaps() {
        let count = registeredTwoFingerTaps.count
        registeredTwoFingerTaps.removeAll()
        print("[HotkeyManager] Unregistered all \(count) two-finger tap(s)")
    }
}

