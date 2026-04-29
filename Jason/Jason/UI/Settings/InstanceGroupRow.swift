//
//  InstanceGroupRow.swift
//  Jason
//
//  Created by Timothy Velberg on 29/04/2026.
//  Collapsed group header row rendered in the root-level list of
//  InstanceShortcutListView. Tapping the chevron opens the group,
//  switching the list into group mode and locking drag-and-drop
//  to that group's shortcuts.
//

import SwiftUI

struct InstanceGroupRow: View {
    let group: ContextShortcutGroup
    let onExpand: () -> Void
    let onAddShortcut: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.4))

            Image(systemName: group.iconName ?? "folder")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Text(group.name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Spacer()

            if isHovered {
                Button(action: onAddShortcut) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Add shortcut to \(group.name)")

                Button(action: onDelete) {
                    Image("context_actions_delete")
                }
                .buttonStyle(.borderless)
                .help("Delete group — shortcuts become ungrouped")
            }

            Button(action: onExpand) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open group to reorder its shortcuts")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(6)
        .onHover { isHovered = $0 }
    }
}
