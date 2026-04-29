//
//  ContextShortcutFormatting.swift
//  Jason
//
//  Created by Timothy Velberg on 29/04/2026.
//  Shared keyboard shortcut formatting for context shortcut display.
//  Separate from TriggerFormConfig formatting because shortcuts include
//  additional keys: arrows, return, backspace.
//

import AppKit

/// Format a keyboard shortcut for display (e.g. "⌘⇧K").
func formatShortcut(keyCode: UInt16, modifierFlags: UInt) -> String {
    let flags = NSEvent.ModifierFlags(rawValue: modifierFlags)
    var parts: [String] = []
    if flags.contains(.control) { parts.append("⌃") }
    if flags.contains(.option)  { parts.append("⌥") }
    if flags.contains(.shift)   { parts.append("⇧") }
    if flags.contains(.command) { parts.append("⌘") }
    parts.append(shortcutKeyCodeToString(keyCode))
    return parts.joined()
}

/// Convert a key code to its display string for shortcut contexts.
func shortcutKeyCodeToString(_ keyCode: UInt16) -> String {
    switch keyCode {
    case 0:   return "A";     case 1:   return "S";   case 2:   return "D";   case 3:   return "F"
    case 4:   return "H";     case 5:   return "G";   case 6:   return "Z";   case 7:   return "X"
    case 8:   return "C";     case 9:   return "V";   case 11:  return "B";   case 12:  return "Q"
    case 13:  return "W";     case 14:  return "E";   case 15:  return "R";   case 16:  return "Y"
    case 17:  return "T";     case 31:  return "O";   case 32:  return "U";   case 34:  return "I"
    case 35:  return "P";     case 37:  return "L";   case 38:  return "J";   case 40:  return "K"
    case 45:  return "N";     case 46:  return "M";   case 49:  return "Space"
    case 36:  return "↩";     case 51:  return "⌫";   case 53:  return "Esc"
    case 123: return "←";     case 124: return "→";   case 125: return "↓";   case 126: return "↑"
    default:  return "[\(keyCode)]"
    }
}
