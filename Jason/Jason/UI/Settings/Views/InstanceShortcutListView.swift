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

// MARK: - Flat List Item

private enum FlatListItem: Identifiable {
    case groupHeader(ContextShortcutGroup, isExpanded: Bool)
    case groupShortcut(ContextShortcut, groupId: Int64)
    case ungroupedShortcut(ContextShortcut)

    var id: String {
        switch self {
        case .groupHeader(let g, _):      return "header-\(g.id)"
        case .groupShortcut(let s, _):    return "child-\(s.id)"
        case .ungroupedShortcut(let s):   return "root-\(s.id)"
        }
    }
}

// MARK: - View

struct InstanceShortcutListView: View {

    let groups: [ContextShortcutGroup]
    let shortcuts: [ContextShortcut]

    let onMoveRootItems: (IndexSet, Int) -> Void
    let onMoveGroupShortcuts: (Int64, IndexSet, Int) -> Void
    let onAddShortcut: (Int64?) -> Void
    let onEditShortcut: (ContextShortcut) -> Void
    let onDeleteShortcut: (ContextShortcut) -> Void
    let onReassignShortcut: (ContextShortcut, Int64?) -> Void
    let onEditGroup: (ContextShortcutGroup) -> Void
    let onDeleteGroup: (ContextShortcutGroup) -> Void

    @State private var expandedGroup: Int64? = nil

    // MARK: - Flat Array

    private var topLevelItems: [ContextTopLevelItem] {
        let groupItems = groups.map { ContextTopLevelItem.group($0) }
        let ungrouped  = shortcuts
            .filter { $0.groupId == nil }
            .map { ContextTopLevelItem.ungroupedShortcut($0) }
        return (groupItems + ungrouped).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var flatItems: [FlatListItem] {
        var result: [FlatListItem] = []
        for item in topLevelItems {
            switch item {
            case .group(let g):
                let isExpanded = expandedGroup == g.id
                result.append(.groupHeader(g, isExpanded: isExpanded))
                if isExpanded {
                    let groupShortcuts = shortcuts
                        .filter { $0.groupId == g.id }
                        .sorted { $0.sortOrder < $1.sortOrder }
                    for s in groupShortcuts {
                        result.append(.groupShortcut(s, groupId: g.id))
                    }
                }
            case .ungroupedShortcut(let s):
                result.append(.ungroupedShortcut(s))
            }
        }
        return result
    }

    // MARK: - Drag State

    /// Whether a given flat item is draggable given the current expandedGroup.
    private func isDraggable(_ item: FlatListItem) -> Bool {
        switch item {
        case .groupHeader:
            // Group headers are only draggable at root level (no group expanded)
            return expandedGroup == nil
        case .groupShortcut(_, let groupId):
            // Group shortcuts are draggable only when their group is the expanded one
            return expandedGroup == groupId
        case .ungroupedShortcut:
            // Ungrouped shortcuts are only draggable at root level
            return expandedGroup == nil
        }
    }

    // MARK: - Body

    var body: some View {
        let items = flatItems
        List {
            ForEach(items) { item in
                rowView(for: item)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .moveDisabled(!isDraggable(item))
            }
            .onMove { source, destination in
                handleMove(from: source, to: destination, in: items)
            }
            .padding(.vertical, 4)
        }
        .listStyle(.plain)
        .scrollDisabled(true)
        .padding(.horizontal, -16) 
        .frame(height: max(60, CGFloat(items.count) * 44))
    }

    // MARK: - Row Views

    @ViewBuilder
    private func rowView(for item: FlatListItem) -> some View {
        switch item {
        case .groupHeader(let group, let isExpanded):
            InstanceGroupRow(
                group: group,
                isExpanded: isExpanded,
                isDraggable: expandedGroup == nil,
                onToggleExpand: { toggleGroup(group.id) },
                onAddShortcut: { onAddShortcut(group.id) },
                onEdit: { onEditGroup(group) },
                onDelete: { onDeleteGroup(group) }
            )

        case .groupShortcut(let shortcut, let groupId):
            InstanceShortcutRow(
                shortcut: shortcut,
                allGroups: groups,
                isDraggable: expandedGroup == groupId,
                onEdit: { onEditShortcut(shortcut) },
                onDelete: { onDeleteShortcut(shortcut) },
                onReassign: { newGroupId in
                    onReassignShortcut(shortcut, newGroupId)
                    // Shortcut left this group — collapse back to root
                    if newGroupId != groupId { expandedGroup = nil }
                }
            )

        case .ungroupedShortcut(let shortcut):
            InstanceShortcutRow(
                shortcut: shortcut,
                allGroups: groups,
                isDraggable: expandedGroup == nil,
                onEdit: { onEditShortcut(shortcut) },
                onDelete: { onDeleteShortcut(shortcut) },
                onReassign: { onReassignShortcut(shortcut, $0) }
            )
        }
    }

    // MARK: - Toggle Expand

    private func toggleGroup(_ groupId: Int64) {
        expandedGroup = (expandedGroup == groupId) ? nil : groupId
    }

    // MARK: - Move Handler

    private func handleMove(from source: IndexSet, to destination: Int, in items: [FlatListItem]) {
        if let groupId = expandedGroup {
            handleGroupMove(groupId: groupId, from: source, to: destination, in: items)
        } else {
            handleRootMove(from: source, to: destination)
        }
    }

    /// Root mode: translate flat indices directly to topLevelItems indices and delegate up.
    private func handleRootMove(from source: IndexSet, to destination: Int) {
        // In root mode flatItems == topLevelItems (no expansion inserts extra rows),
        // so flat indices map 1:1 to topLevelItems indices.
        onMoveRootItems(source, destination)
    }

    /// Group mode: extract group shortcut indices from the flat array, translate
    /// source/destination to group-local indices, and delegate up.
    private func handleGroupMove(groupId: Int64, from source: IndexSet, to destination: Int, in items: [FlatListItem]) {
        // Find the flat indices occupied by this group's shortcuts
        let groupFlatIndices: [Int] = items.indices.filter {
            if case .groupShortcut(_, let gid) = items[$0], gid == groupId { return true }
            return false
        }
        guard let firstFlatIndex = groupFlatIndices.first else { return }
        let count = groupFlatIndices.count

        // Translate flat source indices to group-local indices
        let localSource = IndexSet(source.compactMap { flatIdx in
            groupFlatIndices.firstIndex(of: flatIdx)
        })
        guard !localSource.isEmpty else { return }

        // Clamp destination to the valid group-local range
        let localDest = max(0, min(destination - firstFlatIndex, count))

        onMoveGroupShortcuts(groupId, localSource, localDest)
    }
}
