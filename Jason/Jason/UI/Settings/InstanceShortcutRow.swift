//
//  InstanceShortcutRow.swift
//  Jason
//
//  Created by Timothy Velberg on 29/04/2026.
//  Draggable shortcut row used in both root mode and group mode of
//  InstanceShortcutListView. Displays the shortcut name, key binding badge,
//  and a group picker for reassignment on hover.
//

import SwiftUI

struct InstanceShortcutRow: View {
    let shortcut: ContextShortcut
    let allGroups: [ContextShortcutGroup]
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onReassign: (Int64?) -> Void

    @State private var isHovered = false
    @State private var selectedGroupId: Int64? = nil

    private var groupPickerBinding: Binding<Int64?> {
        Binding(
            get: { selectedGroupId },
            set: { newValue in
                guard newValue != selectedGroupId else { return }
                selectedGroupId = newValue
                onReassign(newValue)
            }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.4))

            Image(systemName: shortcut.iconName ?? "command")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 16)

            Text(shortcut.shortcutName)
                .font(.subheadline)

            Spacer()

            shortcutBadge

            if isHovered {
                if !allGroups.isEmpty {
                    Picker("", selection: groupPickerBinding) {
                        Text("No Group").tag(Int64?.none)
                        ForEach(allGroups) { group in
                            Text(group.name).tag(Int64?.some(group.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }

                Button(action: onEdit) {
                    Image("context_actions_edit")
                }
                .buttonStyle(.borderless)
                .help("Edit shortcut")

                Button(action: onDelete) {
                    Image("context_actions_delete")
                }
                .buttonStyle(.borderless)
                .help("Delete shortcut")
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onAppear { selectedGroupId = shortcut.groupId }
    }

    @ViewBuilder
    private var shortcutBadge: some View {
        Group {
            switch shortcut.shortcutType {
            case .keyboard:
                if let keyCode = shortcut.keyCode, let modifierFlags = shortcut.modifierFlags {
                    Text(formatShortcut(keyCode: keyCode, modifierFlags: modifierFlags))
                }
            case .menu:
                if let menuPath = shortcut.menuPath {
                    Text(menuPath.replacingOccurrences(of: ";", with: " › "))
                }
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.1))
        )
    }
}
