//
//  AddContextShortcutSheet.swift
//  Jason
//
//  Created by Timothy Velberg on 18/04/2026.
//

import SwiftUI

struct AddContextShortcutSheet: View {
    @Environment(\.dismiss) var dismiss

    let app: ContextApp
    let existingShortcut: ContextShortcut?
    let onSave: () -> Void

    @State private var shortcutName: String = ""
    @State private var description: String = ""
    @State private var iconName: String = ""
    @State private var recordedKeyCode: UInt16?
    @State private var recordedModifierFlags: UInt?
    @State private var errorMessage: String?

    init(app: ContextApp, existingShortcut: ContextShortcut? = nil, onSave: @escaping () -> Void) {
        self.app = app
        self.existingShortcut = existingShortcut
        self.onSave = onSave
    }

    var isEditing: Bool { existingShortcut != nil }

    var isValid: Bool {
        !shortcutName.trimmingCharacters(in: .whitespaces).isEmpty && recordedKeyCode != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isEditing ? "Edit Shortcut" : "Add Shortcut")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(app.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.headline)
                        TextField("e.g. New Tab, Close Window", text: $shortcutName)
                            .textFieldStyle(.roundedBorder)
                        Text("This is what appears as the label in Jason.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.headline)
                        TextField("Optional", text: $description)
                            .textFieldStyle(.roundedBorder)
                    }

                    Divider()

                    // Icon
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Icon")
                            .font(.headline)
                        TextField("SF Symbol name, e.g. plus.square, xmark.circle", text: $iconName)
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 12) {
                            Text("Preview:")
                                .foregroundColor(.secondary)
                                .font(.caption)

                            let trimmed = iconName.trimmingCharacters(in: .whitespaces)
                            if trimmed.isEmpty {
                                Image(systemName: "command")
                                    .font(.system(size: 20))
                                    .foregroundColor(.secondary)
                                    .frame(width: 28, height: 28)
                            } else if NSImage(systemSymbolName: trimmed, accessibilityDescription: nil) != nil {
                                Image(systemName: trimmed)
                                    .font(.system(size: 20))
                                    .foregroundColor(.blue)
                                    .frame(width: 28, height: 28)
                            } else {
                                Image(systemName: "command")
                                    .font(.system(size: 20))
                                    .foregroundColor(.secondary)
                                    .frame(width: 28, height: 28)
                                Text("Invalid symbol")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }

                    Divider()

                    // Key recorder
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Keyboard Shortcut")
                            .font(.headline)
                        KeyboardShortcutRecorder(
                            keyCode: $recordedKeyCode,
                            modifierFlags: $recordedModifierFlags
                        )
                        Text("Click the button and press your desired key combination.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Error
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
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button(isEditing ? "Save Changes" : "Save Shortcut") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 480, height: 500)
        .onAppear { populateIfEditing() }
    }

    // MARK: - Populate

    private func populateIfEditing() {
        guard let shortcut = existingShortcut else { return }
        shortcutName = shortcut.shortcutName
        description = shortcut.description ?? ""
        iconName = shortcut.iconName ?? ""
        recordedKeyCode = shortcut.keyCode
        recordedModifierFlags = shortcut.modifierFlags
    }

    // MARK: - Save

    private func save() {
        guard let keyCode = recordedKeyCode,
              let modifierFlags = recordedModifierFlags else {
            errorMessage = "Please record a keyboard shortcut."
            return
        }

        let trimmedIcon = iconName.trimmingCharacters(in: .whitespaces)
        let validatedIcon: String? = trimmedIcon.isEmpty ? nil :
            (NSImage(systemSymbolName: trimmedIcon, accessibilityDescription: nil) != nil ? trimmedIcon : nil)

        if let existing = existingShortcut {
            // Update
            let updated = ContextShortcut(
                id: existing.id,
                bundleId: existing.bundleId,
                displayName: existing.displayName,
                shortcutName: shortcutName.trimmingCharacters(in: .whitespaces),
                description: description.trimmingCharacters(in: .whitespaces).isEmpty ? nil : description.trimmingCharacters(in: .whitespaces),
                iconName: validatedIcon,
                keyCode: keyCode,
                modifierFlags: modifierFlags,
                enabled: existing.enabled,
                sortOrder: existing.sortOrder
            )
            DatabaseManager.shared.updateContextShortcut(updated)
        } else {
            // Insert
            let existingShortcuts = DatabaseManager.shared.fetchContextShortcuts(for: app.bundleId)
            let shortcut = ContextShortcut(
                id: 0,
                bundleId: app.bundleId,
                displayName: app.displayName,
                shortcutName: shortcutName.trimmingCharacters(in: .whitespaces),
                description: description.trimmingCharacters(in: .whitespaces).isEmpty ? nil : description.trimmingCharacters(in: .whitespaces),
                iconName: validatedIcon,
                keyCode: keyCode,
                modifierFlags: modifierFlags,
                enabled: true,
                sortOrder: existingShortcuts.count
            )
            DatabaseManager.shared.insertContextShortcut(shortcut)
        }

        onSave()
        dismiss()
    }
}
