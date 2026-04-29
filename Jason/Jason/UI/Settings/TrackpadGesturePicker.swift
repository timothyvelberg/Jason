//
//  TrackpadGesturePicker.swift
//  Jason
//
//  Created by Timothy Velberg on 29/04/2026.
//  Picker control for selecting a trackpad gesture (direction, finger count,
//  and optional modifier keys). Used inside AddTriggerSheet.
//

import SwiftUI
import AppKit

struct TrackpadGesturePicker: View {
    @Binding var direction: SwipeDirection
    @Binding var fingerCount: Int
    @Binding var modifierFlags: UInt

    @State private var useCommand = false
    @State private var useControl = false
    @State private var useOption = false
    @State private var useShift = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Finger count
            HStack {
                Text("Fingers:")
                    .frame(width: 80, alignment: .leading)

                Picker("", selection: $fingerCount) {
                    Text("1 Finger").tag(1)
                    Text("2 Fingers").tag(2)
                    Text("3 Fingers").tag(3)
                    Text("4 Fingers").tag(4)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                .onChange(of: fingerCount) { _, _ in
                    if !availableDirections().contains(direction) {
                        direction = availableDirections().first ?? .add
                    }
                }
            }

            // Direction
            HStack {
                Text("Direction:")
                    .frame(width: 80, alignment: .leading)

                Picker("", selection: $direction) {
                    ForEach(availableDirections(), id: \.self) { dir in
                        Text(dir.displayName).tag(dir)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)
            }

            // Modifier keys
            VStack(alignment: .leading, spacing: 6) {
                Text("Modifiers (optional):")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Toggle("⌘ Command", isOn: $useCommand)
                    Toggle("⌃ Control", isOn: $useControl)
                }
                HStack(spacing: 12) {
                    Toggle("⌥ Option", isOn: $useOption)
                    Toggle("⇧ Shift", isOn: $useShift)
                }
            }
            .padding(.leading, 20)

            // Live preview
            HStack {
                Text("Gesture:")
                    .frame(width: 80, alignment: .leading)
                Text(formatDisplay())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .onChange(of: useCommand) { _, _ in updateModifierFlags() }
        .onChange(of: useControl) { _, _ in updateModifierFlags() }
        .onChange(of: useOption)  { _, _ in updateModifierFlags() }
        .onChange(of: useShift)   { _, _ in updateModifierFlags() }
        .onAppear {
            let flags = NSEvent.ModifierFlags(rawValue: modifierFlags)
            useCommand = flags.contains(.command)
            useControl = flags.contains(.control)
            useOption  = flags.contains(.option)
            useShift   = flags.contains(.shift)
        }
    }

    // MARK: - Helpers

    private func availableDirections() -> [SwipeDirection] {
        switch fingerCount {
        case 1: return [.circleClockwise, .circleCounterClockwise]
        case 2: return [.twoFingerTapLeft, .twoFingerTapRight, .add]
        default: return [.up, .down, .left, .right, .tap, .add]
        }
    }

    private func updateModifierFlags() {
        var flags: UInt = 0
        if useCommand { flags |= NSEvent.ModifierFlags.command.rawValue }
        if useControl { flags |= NSEvent.ModifierFlags.control.rawValue }
        if useOption  { flags |= NSEvent.ModifierFlags.option.rawValue }
        if useShift   { flags |= NSEvent.ModifierFlags.shift.rawValue }
        modifierFlags = flags
    }

    private func formatDisplay() -> String {
        var parts: [String] = []
        if useControl { parts.append("⌃") }
        if useOption  { parts.append("⌥") }
        if useShift   { parts.append("⇧") }
        if useCommand { parts.append("⌘") }
        parts.append("\(fingerCount)-Finger \(direction.displayName)")
        return parts.joined()
    }
}
