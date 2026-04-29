//
//  InstanceShortcutListView.swift
//  Jason
//
//  Created by Timothy Velberg on 29/04/2026.
//
//  Unified shortcut list for EditContextInstanceSheet.
//
//  There is always exactly one active List with one .onMove handler.
//  The drag context is determined by expansion state:
//
//  - Root mode (expandedGroup == nil):
//    All top-level items (groups + ungrouped shortcuts) are rendered
//    and draggable relative to each other.
//
//  - Group mode (expandedGroup == someId):
//    A fixed group header is shown above the list. The list renders
//    only that group's shortcuts. Drag is locked to those shortcuts.
//
//  Opening a group closes any previously open one, enforcing a single
//  active drag context at all times.
//

import SwiftUI

struct InstanceShortcutListView: View {

    let groups: [ContextShortcutGroup]
    let shortcuts: [ContextShortcut]

    let onMoveRootItems: (IndexSet, Int) -> Void
    let onMoveGroupShortcuts: (Int64, IndexSet, Int) -> Void
    let onAddShortcut: (Int64?) -> Void
    let onEditShortcut: (ContextShortcut) -> Void
    let onDeleteShortcut: (ContextShortcut) -> Void
    let onReassignShortcut: (ContextShortcut, Int64?) -> Void
    let onDeleteGroup: (ContextShortcutGroup) -> Void

    @State private var expandedGroup: Int64? = nil

    // MARK: - Top Level Items

    private var topLevelItems: [ContextTopLevelItem] {
        let groupItems = groups.map { ContextTopLevelItem.group($0) }
        let ungrouped  = shortcuts.filter { $0.groupId == nil }.map { ContextTopLevelItem.ungroupedShortcut($0) }
        return (groupItems + ungrouped).sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Body

    var body: some View {
        if let groupId = expandedGroup,
           let group = groups.first(where: { $0.id == groupId }) {
            groupModeView(group: group)
        } else {
            rootModeView
        }
    }

    // MARK: - Root Mode

    private var rootModeView: some View {
        let items = topLevelItems
        return List {
            ForEach(items) { item in
                switch item {
                case .group(let group):
                    InstanceGroupRow(
                        group: group,
                        onExpand: { expandedGroup = group.id },
                        onAddShortcut: { onAddShortcut(group.id) },
                        onDelete: { onDeleteGroup(group) }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                case .ungroupedShortcut(let shortcut):
                    InstanceShortcutRow(
                        shortcut: shortcut,
                        allGroups: groups,
                        onEdit: { onEditShortcut(shortcut) },
                        onDelete: { onDeleteShortcut(shortcut) },
                        onReassign: { onReassignShortcut(shortcut, $0) }
                    )
                    .listRowSeparator(.hidden)
                }
            }
            .onMove(perform: onMoveRootItems)
        }
        .listStyle(.plain)
        .scrollDisabled(true)
        .frame(height: max(60, CGFloat(items.count) * 44))
    }

    // MARK: - Group Mode

    private func groupModeView(group: ContextShortcutGroup) -> some View {
        let groupShortcuts = shortcuts.filter { $0.groupId == group.id }

        return VStack(alignment: .leading, spacing: 0) {

            groupModeHeader(group: group, count: groupShortcuts.count)

            if groupShortcuts.isEmpty {
                HStack {
                    Text("No shortcuts in this group")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else {
                List {
                    ForEach(groupShortcuts) { shortcut in
                        InstanceShortcutRow(
                            shortcut: shortcut,
                            allGroups: groups,
                            onEdit: { onEditShortcut(shortcut) },
                            onDelete: { onDeleteShortcut(shortcut) },
                            onReassign: { newGroupId in
                                onReassignShortcut(shortcut, newGroupId)
                                // Shortcut left this group — return to root
                                if newGroupId != group.id {
                                    expandedGroup = nil
                                }
                            }
                        )
                        .listRowSeparator(.hidden)
                    }
                    .onMove { source, dest in
                        onMoveGroupShortcuts(group.id, source, dest)
                    }
                }
                .listStyle(.plain)
                .scrollDisabled(true)
                .frame(height: max(60, CGFloat(groupShortcuts.count) * 44))
            }
        }
    }

    // MARK: - Group Mode Header

    private func groupModeHeader(group: ContextShortcutGroup, count: Int) -> some View {
        HStack(spacing: 8) {
            Button(action: { expandedGroup = nil }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Back to all shortcuts")

            Image(systemName: group.iconName ?? "folder")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Text(group.name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text("(\(count))")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))

            Spacer()

            Button(action: { onAddShortcut(group.id) }) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Add shortcut to \(group.name)")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(6)
    }
}
