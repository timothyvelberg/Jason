//
//  EditContextInstanceSheet.swift
//  Jason
//
//  Created by Timothy Velberg on 25/04/2026.
//  Edit sheet for a context-scoped ring instance. Manages name, triggers,
//  and shortcut/group data. Delegates all list rendering and drag-and-drop
//  to InstanceShortcutListView.
//

import SwiftUI

// MARK: - Edit Instance Sheet

struct EditContextInstanceSheet: View {
    @Environment(\.dismiss) var dismiss

    let config: StoredRingConfiguration
    let app: ContextApp
    let onSave: () -> Void

    @State private var name: String
    @State private var triggers: [TriggerFormConfig]
    @State private var groups: [ContextShortcutGroup] = []
    @State private var shortcuts: [ContextShortcut] = []

    @State private var showAddTriggerSheet = false
    @State private var showAddGroupSheet = false
    @State private var isAddingShortcut = false
    @State private var defaultGroupIdForNewShortcut: Int64? = nil
    @State private var ungroupedSortOrderForNewShortcut: Int = 0
    @State private var editingShortcut: ContextShortcut? = nil
    @State private var errorMessage: String?

    init(config: StoredRingConfiguration, app: ContextApp, onSave: @escaping () -> Void) {
        self.config = config
        self.app = app
        self.onSave = onSave
        _name     = State(initialValue: config.name)
        _triggers = State(initialValue: config.triggers.map { TriggerFormConfig(from: $0) })
    }

    // MARK: - Derived

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !triggers.isEmpty &&
        triggers.allSatisfy { $0.isValid }
    }

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
                    nameSection
                    Divider()
                    triggersSection
                    Divider()
                    shortcutsSection
                    if let error = errorMessage {
                        Text(error).font(.caption).foregroundColor(.red)
                    }
                }
                .padding()
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 700)
        .onAppear { loadData() }
        .sheet(isPresented: $showAddTriggerSheet) {
            AddTriggerSheet(existingTriggers: triggers) { newTrigger in
                withAnimation { triggers.append(newTrigger) }
            }
        }
        .sheet(isPresented: $showAddGroupSheet) {
            AddContextShortcutGroupSheet(
                ringId: config.id,
                startingSortOrder: topLevelItems.count
            ) { newGroup in
                groups.append(newGroup)
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
                Text("Edit Instance")
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
    }

    private var footer: some View {
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

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name").font(.headline)
            TextField("Instance name", text: $name)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var triggersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Triggers").font(.headline)
                Spacer()
                Button(action: { showAddTriggerSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("Add trigger")
            }

            if triggers.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "keyboard.badge.ellipsis")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No triggers configured")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(triggers) { trigger in
                        TriggerRowView(trigger: trigger) {
                            withAnimation { triggers.removeAll { $0.id == trigger.id } }
                        }
                    }
                }
            }
        }
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Shortcuts").font(.headline)
                Spacer()
                Button(action: { showAddGroupSheet = true }) {
                    Label("Add Group", systemImage: "folder.badge.plus")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Add a shortcut group")

                Button(action: { handleAddShortcut(groupId: nil) }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
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
        let updates = scoped.enumerated().map { (index, s) in (id: s.id, sortOrder: index) }
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

    // MARK: - Save

    private func save() {
        errorMessage = nil

        let shortcutDisplay = triggers.first?.displayDescription ?? "No trigger"
        let configManager   = RingConfigurationManager.shared

        do {
            try configManager.updateConfiguration(
                id:               config.id,
                name:             name.trimmingCharacters(in: .whitespaces),
                shortcut:         shortcutDisplay,
                ringRadius:       Double(config.ringRadius),
                centerHoleRadius: Double(config.centerHoleRadius),
                iconSize:         Double(config.iconSize),
                startAngle:       Double(config.startAngle),
                presentationMode: .ring
            )

            for trigger in config.triggers { try configManager.removeTrigger(id: trigger.id) }

            for trigger in triggers {
                _ = try configManager.addTrigger(
                    toRing:               config.id,
                    triggerType:          trigger.triggerType.rawValue,
                    keyCode:              trigger.triggerType == .keyboard ? trigger.keyCode : nil,
                    modifierFlags:        trigger.modifierFlags,
                    buttonNumber:         trigger.triggerType == .mouse    ? trigger.buttonNumber : nil,
                    swipeDirection:       trigger.triggerType == .trackpad ? trigger.swipeDirection.rawValue : nil,
                    fingerCount:          trigger.triggerType == .trackpad ? trigger.fingerCount : nil,
                    isHoldMode:           trigger.isHoldMode,
                    isModifierHoldMode:   trigger.isModifierHoldMode,
                    autoExecuteOnRelease: trigger.autoExecuteOnRelease
                )
            }

            print("✅ [EditContextInstanceSheet] Saved instance '\(name)' (id: \(config.id))")
            onSave()
            dismiss()
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
            print("❌ [EditContextInstanceSheet] \(error)")
        }
    }
}
