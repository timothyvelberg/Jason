//
//  EditContextShortcutGroupSheet.swift
//  Jason
//
//  Created by Timothy Velberg on 30/04/2026.
//
//  Sheet for editing an existing shortcut group's name and icon.
//

import SwiftUI
import AppKit

struct EditContextShortcutGroupSheet: View {
    @Environment(\.dismiss) var dismiss

    let group: ContextShortcutGroup
    let onSave: (ContextShortcutGroup) -> Void

    @State private var name: String
    @State private var iconName: String

    init(group: ContextShortcutGroup, onSave: @escaping (ContextShortcutGroup) -> Void) {
        self.group = group
        self.onSave = onSave
        _name     = State(initialValue: group.name)
        _iconName = State(initialValue: group.iconName ?? "")
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Group")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name")
                        .font(.headline)
                    TextField("e.g. Layers, Boolean, Text", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Icon")
                        .font(.headline)
                    TextField("SF Symbol name (optional)", text: $iconName)
                        .textFieldStyle(.roundedBorder)

                    let trimmed = iconName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        if NSImage(systemSymbolName: trimmed, accessibilityDescription: nil) != nil {
                            Image(systemName: trimmed)
                                .font(.system(size: 20))
                                .foregroundColor(.blue)
                        } else {
                            Text("Invalid symbol")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .padding()

            Spacer()

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 380, height: 280)
    }

    private func save() {
        let trimmedIcon = iconName.trimmingCharacters(in: .whitespaces)
        let validIcon: String? = trimmedIcon.isEmpty ? nil :
            (NSImage(systemSymbolName: trimmedIcon, accessibilityDescription: nil) != nil ? trimmedIcon : nil)

        let updated = ContextShortcutGroup(
            id:       group.id,
            ringId:   group.ringId,
            name:     name.trimmingCharacters(in: .whitespaces),
            iconName: validIcon,
            sortOrder: group.sortOrder
        )

        DatabaseManager.shared.updateContextShortcutGroup(updated)
        onSave(updated)
        dismiss()
    }
}
