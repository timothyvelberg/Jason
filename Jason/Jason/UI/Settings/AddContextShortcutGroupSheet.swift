//
//  AddContextShortcutGroupSheet.swift
//  Jason
//
//  Created by Timothy Velberg on 29/04/2026.
//  Sheet for creating a new shortcut group within a context instance.
//

import SwiftUI
import AppKit

struct AddContextShortcutGroupSheet: View {
    @Environment(\.dismiss) var dismiss

    let ringId: Int
    let startingSortOrder: Int
    let onSave: (ContextShortcutGroup) -> Void

    @State private var name: String = ""
    @State private var iconName: String = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Group")
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
                Button("Add Group") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 380, height: 280)
    }

    private func save() {
        let trimmed = iconName.trimmingCharacters(in: .whitespaces)
        let validIcon: String? = trimmed.isEmpty ? nil :
            (NSImage(systemSymbolName: trimmed, accessibilityDescription: nil) != nil ? trimmed : nil)

        guard let newId = DatabaseManager.shared.insertContextShortcutGroup(
            ringId: ringId,
            name: name.trimmingCharacters(in: .whitespaces),
            iconName: validIcon,
            sortOrder: startingSortOrder
        ) else { return }

        let group = ContextShortcutGroup(
            id: newId,
            ringId: ringId,
            name: name.trimmingCharacters(in: .whitespaces),
            iconName: validIcon,
            sortOrder: startingSortOrder
        )
        onSave(group)
        dismiss()
    }
}
