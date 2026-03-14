//
//  HotkeyManager+Formatting.swift
//  Jason
//
//  Created by Timothy Velberg on 14/03/2026.
//

import AppKit

extension HotkeyManager {
    
    func formatShortcut(keyCode: UInt16, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }
    
    func keyCodeToString(_ keyCode: UInt16) -> String {
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
    
    func formatMouseButton(buttonNumber: Int32, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        let buttonName: String
        switch buttonNumber {
        case 2: buttonName = "Button 3 (Middle)"
        case 3: buttonName = "Button 4 (Back)"
        case 4: buttonName = "Button 5 (Forward)"
        default: buttonName = "Button \(buttonNumber + 1)"
        }
        
        parts.append(buttonName)
        return parts.joined()
    }
    
    func formatTrackpadGesture(direction: String, fingerCount: Int, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        let directionSymbol: String
        switch direction.lowercased() {
        case "up":    directionSymbol = "↑ \(fingerCount)-Finger Swipe Up"
        case "down":  directionSymbol = "↓ \(fingerCount)-Finger Swipe Down"
        case "left":  directionSymbol = "← \(fingerCount)-Finger Swipe Left"
        case "right": directionSymbol = "→ \(fingerCount)-Finger Swipe Right"
        case "tap":   directionSymbol = "\(fingerCount)-Finger Tap"
        default:      directionSymbol = "\(fingerCount)-Finger Swipe \(direction)"
        }
        
        parts.append(directionSymbol)
        return parts.joined()
    }
    
    func formatCircleGesture(direction: RotationDirection, fingerCount: Int, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        let dirSymbol = direction == .clockwise ? "↻" : "↺"
        let dirName = direction == .clockwise ? "Clockwise" : "Counter-Clockwise"
        parts.append("\(dirSymbol) \(fingerCount)-Finger \(dirName) Circle")
        return parts.joined()
    }
    
    func formatTwoFingerTap(side: TapSide, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        let sideSymbol = side == .left ? "←" : "→"
        parts.append("\(sideSymbol) Two-Finger Tap \(side.rawValue.capitalized)")
        return parts.joined()
    }
}
