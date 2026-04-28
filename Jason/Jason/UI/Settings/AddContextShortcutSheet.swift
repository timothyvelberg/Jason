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
    let ringId: Int
    let existingShortcut: ContextShortcut?
    let onSave: () -> Void
    let availableGroups: [ContextShortcutGroup]
    let defaultGroupId: Int64?
    let ungroupedSortOrder: Int?

    @State private var shortcutName: String = ""
    @State private var description: String = ""
    @State private var iconName: String = ""
    @State private var shortcutType: ShortcutType = .keyboard
    @State private var recordedKeyCode: UInt16?
    @State private var recordedModifierFlags: UInt?
    @State private var menuPath: String = ""
    @State private var errorMessage: String?
    @State private var selectedGroupId: Int64? = nil

    init(
        app: ContextApp,
        ringId: Int,
        availableGroups: [ContextShortcutGroup] = [],
        defaultGroupId: Int64? = nil,
        ungroupedSortOrder: Int? = nil,
        existingShortcut: ContextShortcut? = nil,
        onSave: @escaping () -> Void
    ) {
        self.app = app
        self.ringId = ringId
        self.availableGroups = availableGroups
        self.defaultGroupId = defaultGroupId
        self.ungroupedSortOrder = ungroupedSortOrder
        self.existingShortcut = existingShortcut
        self.onSave = onSave
    }

    var isEditing: Bool { existingShortcut != nil }

    var isValid: Bool {
        guard !shortcutName.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch shortcutType {
        case .keyboard:
            return recordedKeyCode != nil
        case .menu:
            return !menuPath.trimmingCharacters(in: .whitespaces).isEmpty
        }
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

                    // Group
                    if !availableGroups.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Group")
                                .font(.headline)
                            Picker("", selection: $selectedGroupId) {
                                Text("No Group").tag(Int64?.none)
                                ForEach(availableGroups) { group in
                                    Text(group.name).tag(Int64?.some(group.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 200)
                        }

                        Divider()
                    }

                    // Type toggle
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Action Type")
                            .font(.headline)
                        Picker("", selection: $shortcutType) {
                            Text("Keyboard Shortcut").tag(ShortcutType.keyboard)
                            Text("Menu Item").tag(ShortcutType.menu)
                        }
                        .pickerStyle(.segmented)
                    }

                    Divider()

                    // Keyboard or menu input
                    switch shortcutType {
                    case .keyboard:
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

                    case .menu:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Menu Path")
                                .font(.headline)
                            TextField("e.g. File;Export;Export as PNG", text: $menuPath)
                                .textFieldStyle(.roundedBorder)
                            Text("Separate each menu level with a semicolon.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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
        .frame(width: 480, height: 540)
        .onAppear { populateIfEditing() }
    }

    // MARK: - Populate

    private func populateIfEditing() {
        guard let shortcut = existingShortcut else {
            selectedGroupId = defaultGroupId
            return
        }
        shortcutName = shortcut.shortcutName
        description = shortcut.description ?? ""
        iconName = shortcut.iconName ?? ""
        shortcutType = shortcut.shortcutType
        recordedKeyCode = shortcut.keyCode
        recordedModifierFlags = shortcut.modifierFlags
        menuPath = shortcut.menuPath ?? ""
        selectedGroupId = shortcut.groupId
    }

    // MARK: - Save

    private func save() {
        let trimmedIcon = iconName.trimmingCharacters(in: .whitespaces)
        let validatedIcon: String? = trimmedIcon.isEmpty ? nil :
            (NSImage(systemSymbolName: trimmedIcon, accessibilityDescription: nil) != nil ? trimmedIcon : nil)

        switch shortcutType {
        case .keyboard:
            guard let keyCode = recordedKeyCode,
                  let modifierFlags = recordedModifierFlags else {
                errorMessage = "Please record a keyboard shortcut."
                return
            }
            saveShortcut(keyCode: keyCode, modifierFlags: modifierFlags, menuPath: nil, validatedIcon: validatedIcon)

        case .menu:
            let trimmedPath = menuPath.trimmingCharacters(in: .whitespaces)
            guard !trimmedPath.isEmpty else {
                errorMessage = "Please enter a menu path."
                return
            }
            saveShortcut(keyCode: nil, modifierFlags: nil, menuPath: trimmedPath, validatedIcon: validatedIcon)
        }
    }

    private func saveShortcut(keyCode: UInt16?, modifierFlags: UInt?, menuPath: String?, validatedIcon: String?) {
        if let existing = existingShortcut {
            let updated = ContextShortcut(
                id: existing.id,
                ringId: existing.ringId,
                shortcutName: shortcutName.trimmingCharacters(in: .whitespaces),
                description: description.trimmingCharacters(in: .whitespaces).isEmpty ? nil : description.trimmingCharacters(in: .whitespaces),
                iconName: validatedIcon,
                shortcutType: shortcutType,
                keyCode: keyCode,
                modifierFlags: modifierFlags,
                menuPath: menuPath,
                enabled: existing.enabled,
                sortOrder: existing.sortOrder,
                groupId: selectedGroupId
            )
            DatabaseManager.shared.updateContextShortcut(updated)
        } else {
            let existingShortcuts = DatabaseManager.shared.fetchContextShortcuts(for: ringId)
            let sortOrder: Int
            if let groupId = selectedGroupId {
                sortOrder = existingShortcuts.filter { $0.groupId == groupId }.count
            } else {
                sortOrder = ungroupedSortOrder ?? existingShortcuts.filter { $0.groupId == nil }.count
            }
            let shortcut = ContextShortcut(
                id: 0,
                ringId: ringId,
                shortcutName: shortcutName.trimmingCharacters(in: .whitespaces),
                description: description.trimmingCharacters(in: .whitespaces).isEmpty ? nil : description.trimmingCharacters(in: .whitespaces),
                iconName: validatedIcon,
                shortcutType: shortcutType,
                keyCode: keyCode,
                modifierFlags: modifierFlags,
                menuPath: menuPath,
                enabled: true,
                sortOrder: sortOrder,
                groupId: selectedGroupId
            )
            DatabaseManager.shared.insertContextShortcut(shortcut)
        }

        onSave()
        dismiss()
    }
}
