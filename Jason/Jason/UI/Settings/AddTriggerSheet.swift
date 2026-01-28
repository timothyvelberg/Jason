//
//  AddTriggerSheet.swift
//  Jason
//
//  Created by Timothy Velberg on 28/01/2026.
//


import SwiftUI
import AppKit

// MARK: - Add Trigger Sheet



struct AddTriggerSheet: View {
    @Environment(\.dismiss) var dismiss
    
    let existingTriggers: [TriggerFormConfig]
    let onAdd: (TriggerFormConfig) -> Void
    
    @State private var triggerType: TriggerType = .keyboard
    @State private var recordedKeyCode: UInt16?
    @State private var recordedModifierFlags: UInt?
    @State private var recordedButtonNumber: Int32?
    @State private var swipeDirection: SwipeDirection = .up
    @State private var fingerCount: Int = 3
    @State private var swipeModifierFlags: UInt = 0
    @State private var isHoldMode: Bool = false
    @State private var autoExecuteOnRelease: Bool = true
    
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Trigger")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Trigger type picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Trigger Type")
                            .font(.headline)
                        
                        Picker("", selection: $triggerType) {
                            Text("Keyboard").tag(TriggerType.keyboard)
                            Text("Mouse").tag(TriggerType.mouse)
                            Text("Trackpad").tag(TriggerType.trackpad)
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    Divider()
                    
                    // Trigger-specific recorder
                    if triggerType == .keyboard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Keyboard Shortcut")
                                .font(.headline)
                            
                            KeyboardShortcutRecorder(
                                keyCode: $recordedKeyCode,
                                modifierFlags: $recordedModifierFlags
                            )
                            
                            Text("Click the button and press your desired key combination")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if triggerType == .mouse {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Mouse Button")
                                .font(.headline)
                            
                            MouseButtonRecorder(
                                buttonNumber: $recordedButtonNumber,
                                modifierFlags: $recordedModifierFlags
                            )
                            
                            Text("Click the button and then click your mouse button")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Trackpad Gesture")
                                .font(.headline)
                            
                            TrackpadGesturePicker(
                                direction: $swipeDirection,
                                fingerCount: $fingerCount,
                                modifierFlags: $swipeModifierFlags
                            )
                        }
                    }
                    
                    Divider()
                    
                    // Behavior options
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Behavior")
                            .font(.headline)
                        
                        Toggle("Hold to show (release to hide)", isOn: $isHoldMode)
                            .help("When enabled, UI appears while held and disappears when released")
                        
                        if isHoldMode {
                            Toggle("Auto-execute on release", isOn: $autoExecuteOnRelease)
                                .padding(.leading, 20)
                                .help("Execute the hovered item when releasing")
                        }
                    }
                    
                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Add Trigger") {
                    addTrigger()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 500, height: 500)
    }
    
    private var isValid: Bool {
        switch triggerType {
        case .keyboard:
            return recordedKeyCode != nil
        case .mouse:
            return recordedButtonNumber != nil
        case .trackpad:
            return true
        }
    }
    
    private func addTrigger() {
        errorMessage = nil
        
        // Build the trigger config
        let newTrigger = TriggerFormConfig(
            triggerType: triggerType,
            keyCode: triggerType == .keyboard ? recordedKeyCode : nil,
            modifierFlags: triggerType == .trackpad ? swipeModifierFlags : (recordedModifierFlags ?? 0),
            buttonNumber: triggerType == .mouse ? recordedButtonNumber : nil,
            swipeDirection: swipeDirection,
            fingerCount: fingerCount,
            isHoldMode: isHoldMode,
            autoExecuteOnRelease: autoExecuteOnRelease
        )
        
        // Check for duplicates within the ring
        if isDuplicate(newTrigger) {
            errorMessage = "This trigger is already added to this ring"
            return
        }
        
        onAdd(newTrigger)
        dismiss()
    }
    
    private func isDuplicate(_ trigger: TriggerFormConfig) -> Bool {
        for existing in existingTriggers {
            if existing.triggerType == trigger.triggerType {
                switch trigger.triggerType {
                case .keyboard:
                    if existing.keyCode == trigger.keyCode && existing.modifierFlags == trigger.modifierFlags {
                        return true
                    }
                case .mouse:
                    if existing.buttonNumber == trigger.buttonNumber && existing.modifierFlags == trigger.modifierFlags {
                        return true
                    }
                case .trackpad:
                    if existing.swipeDirection == trigger.swipeDirection &&
                       existing.fingerCount == trigger.fingerCount &&
                       existing.modifierFlags == trigger.modifierFlags {
                        return true
                    }
                }
            }
        }
        return false
    }
}

// MARK: - Trigger Row View

struct TriggerRowView: View {
    let trigger: TriggerFormConfig
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundColor(.blue)
                .frame(width: 24)
            
            // Trigger description
            VStack(alignment: .leading, spacing: 2) {
                Text(trigger.displayDescription)
                    .font(.body)
                    .fontWeight(.medium)
                
                HStack(spacing: 8) {
                    Text(trigger.triggerType.rawValue.capitalized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if trigger.isHoldMode {
                        Text("• Hold")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
            
            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Remove trigger")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.05))
        )
    }
    
    private var iconName: String {
        switch trigger.triggerType {
        case .keyboard: return "keyboard"
        case .mouse: return "computermouse"
        case .trackpad: return "hand.draw"
        }
    }
}
