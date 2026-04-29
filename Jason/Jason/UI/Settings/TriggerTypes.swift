//
//  TriggerTypes.swift
//  Jason
//
//  Created by Timothy Velberg on 29/04/2026.
//  Trigger type enums and form state model shared between
//  EditRingView and AddTriggerSheet.
//

import AppKit

// MARK: - Trigger Type

enum TriggerType: String {
    case keyboard
    case mouse
    case trackpad
}

// MARK: - Swipe Direction

enum SwipeDirection: String, CaseIterable {
    case up
    case down
    case left
    case right
    case tap
    case add
    case circleClockwise
    case circleCounterClockwise
    case twoFingerTapLeft
    case twoFingerTapRight

    var displayName: String {
        switch self {
        case .up:                     return "Swipe Up"
        case .down:                   return "Swipe Down"
        case .left:                   return "Swipe Left"
        case .right:                  return "Swipe Right"
        case .tap:                    return "Tap"
        case .add:                    return "Add Finger"
        case .circleClockwise:        return "Circle ↻ (Clockwise)"
        case .circleCounterClockwise: return "Circle ↺ (Counter-Clockwise)"
        case .twoFingerTapLeft:       return "Two-Finger Tap (←Left)"
        case .twoFingerTapRight:      return "Two-Finger Tap (Right→)"
        }
    }

    var isCircle: Bool {
        return self == .circleClockwise || self == .circleCounterClockwise
    }
}

// MARK: - Trigger Form Config

/// Form-layer representation of a trigger, used while editing a ring.
/// Converts to/from `TriggerConfiguration` (the DB model).
struct TriggerFormConfig: Identifiable, Equatable {
    let id: UUID
    var triggerType: TriggerType
    var keyCode: UInt16?
    var modifierFlags: UInt
    var buttonNumber: Int32?
    var swipeDirection: SwipeDirection
    var fingerCount: Int
    var isHoldMode: Bool
    var isModifierHoldMode: Bool
    var autoExecuteOnRelease: Bool

    /// Non-nil only for triggers that already exist in the database.
    var databaseId: Int?

    init(
        id: UUID = UUID(),
        triggerType: TriggerType = .keyboard,
        keyCode: UInt16? = nil,
        modifierFlags: UInt = 0,
        buttonNumber: Int32? = nil,
        swipeDirection: SwipeDirection = .up,
        fingerCount: Int = 3,
        isHoldMode: Bool = false,
        isModifierHoldMode: Bool = false,
        autoExecuteOnRelease: Bool = true,
        databaseId: Int? = nil
    ) {
        self.id = id
        self.triggerType = triggerType
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.buttonNumber = buttonNumber
        self.swipeDirection = swipeDirection
        self.fingerCount = fingerCount
        self.isHoldMode = isHoldMode
        self.isModifierHoldMode = isModifierHoldMode
        self.autoExecuteOnRelease = autoExecuteOnRelease
        self.databaseId = databaseId
    }

    /// Create from a `TriggerConfiguration` loaded from the database.
    init(from config: TriggerConfiguration) {
        self.id = UUID()
        self.databaseId = config.id
        self.modifierFlags = config.modifierFlags
        self.isHoldMode = config.isHoldMode
        self.isModifierHoldMode = config.isModifierHoldMode
        self.autoExecuteOnRelease = config.autoExecuteOnRelease

        if config.triggerType == "keyboard" {
            self.triggerType = .keyboard
            self.keyCode = config.keyCode
            self.buttonNumber = nil
            self.swipeDirection = .up
            self.fingerCount = 3
        } else if config.triggerType == "mouse" {
            self.triggerType = .mouse
            self.keyCode = nil
            self.buttonNumber = config.buttonNumber
            self.swipeDirection = .up
            self.fingerCount = 3
        } else {
            self.triggerType = .trackpad
            self.keyCode = nil
            self.buttonNumber = nil
            self.swipeDirection = SwipeDirection(rawValue: config.swipeDirection ?? "up") ?? .up
            self.fingerCount = config.fingerCount ?? 3
        }
    }

    // MARK: - Derived properties

    var displayDescription: String {
        switch triggerType {
        case .keyboard:
            guard let keyCode else { return "No key set" }
            return formatKeyboard(keyCode: keyCode, modifiers: modifierFlags)
        case .mouse:
            guard let buttonNumber else { return "No button set" }
            return formatMouse(buttonNumber: buttonNumber, modifiers: modifierFlags)
        case .trackpad:
            return formatTrackpad(direction: swipeDirection, fingerCount: fingerCount, modifiers: modifierFlags)
        }
    }

    var isValid: Bool {
        switch triggerType {
        case .keyboard:  return keyCode != nil
        case .mouse:     return buttonNumber != nil
        case .trackpad:  return true
        }
    }

    // MARK: - Formatting

    private func formatKeyboard(keyCode: UInt16, modifiers: UInt) -> String {
        modifierPrefix(modifiers) + keyCodeToString(keyCode)
    }

    private func formatMouse(buttonNumber: Int32, modifiers: UInt) -> String {
        let name: String
        switch buttonNumber {
        case 2:  name = "Middle Click"
        case 3:  name = "Back Button"
        case 4:  name = "Forward Button"
        default: name = "Button \(buttonNumber + 1)"
        }
        return modifierPrefix(modifiers) + name
    }

    private func formatTrackpad(direction: SwipeDirection, fingerCount: Int, modifiers: UInt) -> String {
        modifierPrefix(modifiers) + "\(fingerCount)-Finger \(direction.displayName)"
    }

    private func modifierPrefix(_ modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option)  { parts.append("⌥") }
        if flags.contains(.shift)   { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        return parts.joined()
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 0:  return "A"
        case 1:  return "S"
        case 2:  return "D"
        case 3:  return "F"
        case 4:  return "H"
        case 5:  return "G"
        case 6:  return "Z"
        case 7:  return "X"
        case 8:  return "C"
        case 9:  return "V"
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
        default: return "[\(keyCode)]"
        }
    }
}
