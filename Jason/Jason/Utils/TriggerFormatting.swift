//
//  TriggerFormatting.swift
//  Jason
//
//  Created by Timothy Velberg on 22/11/2025.
//
//  Shared utility for formatting keyboard shortcuts, mouse buttons, and trackpad gestures
//  Used by: DatabaseManager, RingConfiguration, RingConfigurationManager, HotkeyManager
//

import Foundation
import AppKit

/// Utility for formatting trigger descriptions (keyboard, mouse, trackpad)
struct TriggerFormatting {
    
    // MARK: - Keyboard Shortcuts
    
    /// Format a keyboard shortcut for display
    /// - Parameters:
    ///   - keyCode: The key code (e.g., 0 for "A")
    ///   - modifiers: The modifier flags raw value
    /// - Returns: A formatted string like "⌘⇧K"
    static func formatShortcut(keyCode: UInt16, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        parts.append(keyCodeToString(keyCode))
        
        return parts.joined()
    }
    
    /// Convert key code to readable string
    /// - Parameter keyCode: The key code
    /// - Returns: A readable key name like "K" or "Space"
    static func keyCodeToString(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
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
    
    // MARK: - Mouse Buttons
    
    /// Format a mouse button for display
    /// - Parameters:
    ///   - buttonNumber: The mouse button number (2=middle, 3=back, 4=forward)
    ///   - modifiers: The modifier flags raw value
    /// - Returns: A formatted string like "⌘Button 3 (Middle)"
    static func formatMouseButton(buttonNumber: Int32, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        // Convert button number to readable name
        let buttonName: String
        switch buttonNumber {
        case 2:
            buttonName = "Button 3 (Middle)"
        case 3:
            buttonName = "Button 4 (Back)"
        case 4:
            buttonName = "Button 5 (Forward)"
        default:
            buttonName = "Button \(buttonNumber + 1)"
        }
        
        parts.append(buttonName)
        
        return parts.joined()
    }
    
    // MARK: - Trackpad Gestures
    
    /// Format a trackpad gesture for display
    /// - Parameters:
    ///   - direction: Swipe direction ("up", "down", "left", "right", "tap")
    ///   - fingerCount: Number of fingers (3 or 4, optional)
    ///   - modifiers: The modifier flags raw value
    /// - Returns: A formatted string like "⌘↑ 3-Finger Swipe Up"
    static func formatTrackpadGesture(direction: String, fingerCount: Int?, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        // Convert direction to arrow emoji with finger count
        let directionSymbol: String
        let fingerText = fingerCount.map { "\($0)-Finger " } ?? ""
        switch direction.lowercased() {
        case "up":
            directionSymbol = "↑ \(fingerText)Swipe Up"
        case "down":
            directionSymbol = "↓ \(fingerText)Swipe Down"
        case "left":
            directionSymbol = "← \(fingerText)Swipe Left"
        case "right":
            directionSymbol = "→ \(fingerText)Swipe Right"
        case "tap":
            directionSymbol = "👆 \(fingerText)Tap"
        default:
            directionSymbol = "\(fingerText)Swipe \(direction)"
        }
        
        parts.append(directionSymbol)
        
        return parts.joined()
    }
}
