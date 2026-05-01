//
//  EditContextShortcutsSheet.swift
//  Jason
//
//  Created by Timothy Velberg on 30/04/2026.

//  Sheet for managing shortcuts and groups within a context instance.
//  Name and trigger editing is handled separately via EditContextInstanceSheet
//  in the instances overview.
//

import SwiftUI

struct EditContextShortcutsSheet: View {
    @Environment(\.dismiss) var dismiss

    let config: StoredRingConfiguration
    let app: ContextApp
    let onDone: () -> Void

    @State private var groups: [ContextShortcutGroup] = []
    @State private var shortcuts: [ContextShortcut] = []

    @State private var showAddGroupSheet = false
    @State private var editingGroup: ContextShortcutGroup? = nil
    @State private var isAddingShortcut = false
    @State private var defaultGroupIdForNewShortcut: Int64? = nil
    @State private var ungroupedSortOrderForNewShortcut: Int = 0
    @State private var editingShortcut: ContextShortcut? = nil

    // MARK: - Derived

    private var topLevelItems: [ContextTopLevelItem] {
        let groupItems = groups.map { ContextTopLevelItem.group($0) }
        let ungrouped  = shortcuts.filter { $0.groupId == nil }.map { ContextTopLevelItem.ungroupedShortcut($0) }
        return (groupItems + ungrouped).sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    shortcutsSection
                }
                .padding()
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 700)
        .onAppear { loadData() }
        .sheet(isPresented: $showAddGroupSheet) {
            AddContextShortcutGroupSheet(
                ringId: config.id,
                startingSortOrder: topLevelItems.count
            ) { newGroup in
                groups.append(newGroup)
            }
        }
        .sheet(item: $editingGroup) { group in
            EditContextShortcutGroupSheet(group: group) { updated in
                if let idx = groups.firstIndex(where: { $0.id == updated.id }) {
                    groups[idx] = updated
                }
            }
        }
        .sheet(isPresented: $isAddingShortcut) {
            AddContextShortcutSheet(
                app: app,
                ringId: config.id,
                availableGroups: groups,
                defaultGroupId: defaultGroupIdForNewShortcut,
                ungroupedSortOrder: defaultGroupIdForNewShortcut == nil ? ungroupedSortOrderForNewShortcut : nil
            ) {
                loadShortcuts()
            }
        }
        .sheet(item: $editingShortcut) { shortcut in
            AddContextShortcutSheet(
                app: app,
                ringId: config.id,
                availableGroups: groups,
                existingShortcut: shortcut
            ) {
                loadShortcuts()
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Shortcuts")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(app.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") {
                onDone()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Shortcuts Section

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Shortcuts").font(.headline)
                Spacer()
                Button(action: { showAddGroupSheet = true }) {
                    Text("Add Group")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Add a shortcut group")
                
                Text("/")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Button(action: { handleAddShortcut(groupId: nil) }) {
                    Text("Add Shortcut")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Add shortcut")
            }

            if topLevelItems.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "command")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No shortcuts yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Add a shortcut or create a group first")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
            } else {
                InstanceShortcutListView(
                    groups: groups,
                    shortcuts: shortcuts,
                    onMoveRootItems: moveTopLevelItem,
                    onMoveGroupShortcuts: moveShortcutsWithinGroup,
                    onAddShortcut: handleAddShortcut,
                    onEditShortcut: { editingShortcut = $0 },
                    onDeleteShortcut: deleteShortcut,
                    onReassignShortcut: reassignShortcut,
                    onEditGroup: { editingGroup = $0 },
                    onDeleteGroup: deleteGroup
                )
            }
        }
    }

    // MARK: - Add Shortcut

    private func handleAddShortcut(groupId: Int64?) {
        defaultGroupIdForNewShortcut = groupId
        if let groupId {
            ungroupedSortOrderForNewShortcut = shortcuts.filter { $0.groupId == groupId }.count
        } else {
            ungroupedSortOrderForNewShortcut = topLevelItems.count
        }
        isAddingShortcut = true
    }

    // MARK: - Reorder

    private func moveTopLevelItem(from source: IndexSet, to destination: Int) {
        var items = topLevelItems
        items.move(fromOffsets: source, toOffset: destination)

        for (index, item) in items.enumerated() {
            switch item {
            case .group(let g):
                let updated = ContextShortcutGroup(id: g.id, ringId: g.ringId, name: g.name, iconName: g.iconName, sortOrder: index)
                DatabaseManager.shared.updateContextShortcutGroup(updated)
                if let idx = groups.firstIndex(where: { $0.id == g.id }) { groups[idx] = updated }

            case .ungroupedShortcut(let s):
                var updated = s
                updated.sortOrder = index
                DatabaseManager.shared.updateContextShortcut(updated)
                if let idx = shortcuts.firstIndex(where: { $0.id == s.id }) { shortcuts[idx] = updated }
            }
        }
    }

    private func moveShortcutsWithinGroup(groupId: Int64, from source: IndexSet, to dest: Int) {
        var scoped = shortcuts.filter { $0.groupId == groupId }
        scoped.move(fromOffsets: source, toOffset: dest)
        // Update sortOrder on local copies so flatItems re-sorts correctly
        for index in scoped.indices {
            scoped[index].sortOrder = index
        }
        let updates = scoped.map { (id: $0.id, sortOrder: $0.sortOrder) }
        DatabaseManager.shared.updateContextShortcutSortOrders(updates)
        let rest = shortcuts.filter { $0.groupId != groupId }
        shortcuts = rest + scoped
    }

    // MARK: - Groups

    private func deleteGroup(_ group: ContextShortcutGroup) {
        DatabaseManager.shared.deleteContextShortcutGroup(id: group.id)
        groups.removeAll { $0.id == group.id }
        loadShortcuts()
    }

    // MARK: - Shortcuts

    private func deleteShortcut(_ shortcut: ContextShortcut) {
        DatabaseManager.shared.deleteContextShortcut(id: shortcut.id)
        shortcuts.removeAll { $0.id == shortcut.id }
    }

    private func reassignShortcut(_ shortcut: ContextShortcut, to newGroupId: Int64?) {
        var updated = shortcut
        updated.groupId = newGroupId
        DatabaseManager.shared.updateContextShortcut(updated)
        loadShortcuts()
    }

    // MARK: - Load

    private func loadData() {
        loadGroups()
        loadShortcuts()
    }

    private func loadGroups() {
        groups = DatabaseManager.shared.fetchContextShortcutGroups(for: config.id)
    }

    private func loadShortcuts() {
        shortcuts = DatabaseManager.shared.fetchContextShortcuts(for: config.id)
    }
}
