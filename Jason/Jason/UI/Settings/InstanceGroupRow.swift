//
//  InstanceGroupRow.swift
//  Jason
//
//  Created by Timothy Velberg on 29/04/2026.

//  Group header row rendered inside the flat shortcut list.
//  The chevron toggles inline expansion of the group's shortcuts.
//  The drag handle is shown only when isDraggable — i.e. no group
//  is currently expanded and root-level reordering is active.

import SwiftUI

struct InstanceGroupRow: View {
    let group: ContextShortcutGroup
    let isExpanded: Bool
    let isDraggable: Bool
    let onToggleExpand: () -> Void
    let onAddShortcut: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {

            // Drag handle — removed entirely when root is frozen
            if isDraggable {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.4))
            }

            Image(systemName: group.iconName ?? "folder")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Text(group.name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
//                .padding(.vertical,4)

            Spacer()

            if isHovered {
                Button(action: onEdit) {
                    Image("context_actions_edit")
                }
                .buttonStyle(.borderless)
                .help("Edit group")

                Button(action: onDelete) {
                    Image("context_actions_delete")
                }
                .buttonStyle(.borderless)
                .help("Delete group — shortcuts become ungrouped")
            }

            Button(action: onToggleExpand) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(width: 16, height: 16)
                    .background(Color.blue .opacity(0.8))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse group" : "Expand group")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(6)
        .onHover { isHovered = $0 }
    }
}
