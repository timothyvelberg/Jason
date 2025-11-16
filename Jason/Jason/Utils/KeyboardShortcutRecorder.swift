//
//  KeyboardShortcutRecorder.swift
//  Jason
//
//  Created by Timothy Velberg on 13/11/2025.


import SwiftUI
import AppKit

struct KeyboardShortcutRecorder: View {
    @Binding var keyCode: UInt16?
    @Binding var modifierFlags: UInt?
    @State private var isRecording = false
    @State private var localMonitor: Any?
    @State private var showConflictWarning = false
    
    var displayText: String {
        if isRecording {
            return "Press keys..."
        } else if let keyCode = keyCode, let modifiers = modifierFlags {
            return formatShortcut(keyCode: keyCode, modifiers: modifiers)
        } else {
            return "Click to record"
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }) {
                HStack {
                    Image(systemName: isRecording ? "record.circle.fill" : "keyboard")
                        .foregroundColor(isRecording ? .red : .blue)
                    
                    Text(displayText)
                        .frame(minWidth: 120, alignment: .leading)
                        .foregroundColor(isRecording ? .secondary : .primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Color.red.opacity(0.1) : Color.gray.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.red : Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            
            // Warning icon for potentially conflicting shortcuts
            if showConflictWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .help("Warning: This shortcut may conflict with typing or other apps")
            }
            
            if keyCode != nil {
                Button(action: clearShortcut) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear shortcut")
            }
        }
    }
    
    // MARK: - Recording
    
    private func startRecording() {
        isRecording = true
        
        // Add local event monitor to capture key presses
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [self] event in
            // Ignore just modifier keys
            if event.type == .flagsChanged {
                return event
            }
            
            // Capture the key code and modifiers
            let capturedKeyCode = event.keyCode
            let capturedModifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            
            // Block Escape key from being recorded (it's reserved for hiding UI)
            guard capturedKeyCode != 53 else {
                print("⚠️ [ShortcutRecorder] Escape key cannot be used as a shortcut (reserved for hiding UI)")
                return nil // Consume event but don't save
            }
            
            // Save the shortcut (modifiers are optional now!)
            self.keyCode = capturedKeyCode
            self.modifierFlags = capturedModifiers.rawValue
            
            // Check if this shortcut might conflict with normal typing
            self.showConflictWarning = isPotentiallyConflicting(keyCode: capturedKeyCode, modifiers: capturedModifiers)
            
            // Stop recording
            DispatchQueue.main.async {
                self.stopRecording()
            }
            
            return nil // Consume the event
        }
        
        print("🎹 [ShortcutRecorder] Recording started")
    }
    
    private func stopRecording() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        isRecording = false
        print("🎹 [ShortcutRecorder] Recording stopped")
    }
    
    private func clearShortcut() {
        keyCode = nil
        modifierFlags = nil
        showConflictWarning = false
        print("🎹 [ShortcutRecorder] Shortcut cleared")
    }
    
    // MARK: - Conflict Detection
    
    /// Check if a shortcut might conflict with normal typing or common usage
    private func isPotentiallyConflicting(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        // Function keys (F1-F19) are safe even without modifiers
        let functionKeys: Set<UInt16> = [
            122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,  // F1-F12
            105, 107, 113, 106, 64, 79, 80                           // F13-F19
        ]
        if functionKeys.contains(keyCode) {
            return false  // Function keys are safe
        }
        
        // Keys that are safe when used alone (non-alphanumeric)
        let safeStandaloneKeys: Set<UInt16> = [
            49,   // Space
            48,   // Tab
            123, 124, 125, 126  // Arrow keys
        ]
        
        // If no modifiers are pressed
        if modifiers.isEmpty {
            // Only safe standalone keys are okay without modifiers
            return !safeStandaloneKeys.contains(keyCode)
        }
        
        // With modifiers, most keys are safe
        return false
    }
    
    // MARK: - Formatting
    
    private func formatShortcut(keyCode: UInt16, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        parts.append(keyCodeToString(keyCode))
        
        return parts.joined()
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String {
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
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 33: return "["
        case 30: return "]"
        case 41: return ";"
        case 39: return "'"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 47: return "."
        case 49: return "Space"
        case 50: return "`"
        case 51: return "Delete"
        case 53: return "Esc"
        case 36: return "Return"
        case 48: return "Tab"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 106: return "F16"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 113: return "F15"
        case 118: return "F4"
        case 120: return "F2"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "[\(keyCode)]"
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        KeyboardShortcutRecorder(
            keyCode: .constant(2),
            modifierFlags: .constant(NSEvent.ModifierFlags([.control, .shift]).rawValue)
        )
        
        KeyboardShortcutRecorder(
            keyCode: .constant(nil),
            modifierFlags: .constant(nil)
        )
    }
    .padding()
    .frame(width: 300, height: 200)
}
