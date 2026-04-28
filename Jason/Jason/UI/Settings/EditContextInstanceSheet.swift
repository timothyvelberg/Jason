//
//  EditContextInstanceSheet.swift
//  Jason
//
//  Created by Timothy Velberg on 25/04/2026.
//

import SwiftUI

// MARK: - Top Level Item

enum ContextTopLevelItem: Identifiable {
    case group(ContextShortcutGroup)
    case ungroupedShortcut(ContextShortcut)

    var id: String {
        switch self {
        case .group(let g): return "group-\(g.id)"
        case .ungroupedShortcut(let s): return "shortcut-\(s.id)"
        }
    }

    var sortOrder: Int {
        switch self {
        case .group(let g): return g.sortOrder
        case .ungroupedShortcut(let s): return s.sortOrder
        }
    }
}

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
        _name = State(initialValue: config.name)
        _triggers = State(initialValue: config.triggers.map { TriggerFormConfig(from: $0) })
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !triggers.isEmpty &&
        triggers.allSatisfy { $0.isValid }
    }

    private var topLevelItems: [ContextTopLevelItem] {
        let groupItems = groups.map { ContextTopLevelItem.group($0) }
        let ungroupedItems = shortcuts.filter { $0.groupId == nil }.map { ContextTopLevelItem.ungroupedShortcut($0) }
        return (groupItems + ungroupedItems).sorted { $0.sortOrder < $1.sortOrder }
    }
    
    private var nextTopLevelSortOrder: Int { topLevelItems.count }

    private var shortcutsListHeight: CGFloat {
        var h: CGFloat = 0
        for item in topLevelItems {
            switch item {
            case .group(let g):
                let count = shortcuts.filter { $0.groupId == g.id }.count
                h += 36
                h += count == 0 ? 30 : CGFloat(count) * 44
            case .ungroupedShortcut:
                h += 44
            }
        }
        return max(h, 60)
    }

    var body: some View {
        VStack(spacing: 0) {

            // Header
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

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // MARK: Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.headline)
                        TextField("Instance name", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    Divider()

                    // MARK: Triggers
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Triggers")
                                .font(.headline)
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
                                        withAnimation {
                                            triggers.removeAll { $0.id == trigger.id }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .sheet(isPresented: $showAddTriggerSheet) {
                        AddTriggerSheet(existingTriggers: triggers) { newTrigger in
                            withAnimation { triggers.append(newTrigger) }
                        }
                    }

                    Divider()

                    // MARK: Shortcuts
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Shortcuts")
                                .font(.headline)
                            Spacer()
                            Button(action: { showAddGroupSheet = true }) {
                                Label("Add Group", systemImage: "folder.badge.plus")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Add a shortcut group")

                            Button(action: {
                                defaultGroupIdForNewShortcut = nil
                                ungroupedSortOrderForNewShortcut = nextTopLevelSortOrder
                                isAddingShortcut = true
                            }) {
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
                            List {
                                ForEach(topLevelItems) { item in
                                    switch item {
                                    case .group(let group):
                                        InstanceGroupSection(
                                            group: group,
                                            shortcuts: shortcuts.filter { $0.groupId == group.id },
                                            allGroups: groups,
                                            onAddShortcut: {
                                                defaultGroupIdForNewShortcut = group.id
                                                ungroupedSortOrderForNewShortcut = 0
                                                isAddingShortcut = true
                                            },
                                            onEditShortcut: { editingShortcut = $0 },
                                            onDeleteShortcut: deleteShortcut,
                                            onReassignShortcut: reassignShortcut,
                                            onDeleteGroup: { deleteGroup(group) },
                                            onMoveShortcut: { source, dest in moveShortcutWithinGroup(from: source, to: dest, groupId: group.id) }
                                        )
                                        .listRowInsets(EdgeInsets())
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                    case .ungroupedShortcut(let shortcut):
                                        InstanceShortcutRow(
                                            shortcut: shortcut,
                                            allGroups: groups,
                                            onEdit: { editingShortcut = shortcut },
                                            onDelete: { deleteShortcut(shortcut) },
                                            onReassign: { reassignShortcut(shortcut, to: $0) }
                                        )
                                        .listRowSeparator(.hidden)
                                    }
                                }
                                .onMove(perform: moveTopLevelItem)
                            }
                            .listStyle(.plain)
                            .scrollDisabled(true)
                            .frame(height: shortcutsListHeight)
                        }
                    }

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
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 560, height: 700)
        .onAppear { loadData() }
        .sheet(isPresented: $showAddGroupSheet) {
            AddContextShortcutGroupSheet(
                ringId: config.id,
                startingSortOrder: nextTopLevelSortOrder
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
    
    private func moveShortcutWithinGroup(from source: IndexSet, to dest: Int, groupId: Int64) {
        var scoped = shortcuts.filter { $0.groupId == groupId }
        scoped.move(fromOffsets: source, toOffset: dest)
        let updates = scoped.enumerated().map { (index, s) in (id: s.id, sortOrder: index) }
        DatabaseManager.shared.updateContextShortcutSortOrders(updates)
        // Update local state to match
        let rest = shortcuts.filter { $0.groupId != groupId }
        shortcuts = rest + scoped
    }

    // MARK: - Top Level Reorder

    private func moveTopLevelItem(from source: IndexSet, to destination: Int) {
        var items = topLevelItems
        items.move(fromOffsets: source, toOffset: destination)

        for (index, item) in items.enumerated() {
            switch item {
            case .group(let g):
                let updated = ContextShortcutGroup(id: g.id, ringId: g.ringId, name: g.name, iconName: g.iconName, sortOrder: index)
                DatabaseManager.shared.updateContextShortcutGroup(updated)
                if let idx = groups.firstIndex(where: { $0.id == g.id }) {
                    groups[idx] = updated
                }
            case .ungroupedShortcut(let s):
                var updated = s
                updated.sortOrder = index
                DatabaseManager.shared.updateContextShortcut(updated)
                if let idx = shortcuts.firstIndex(where: { $0.id == s.id }) {
                    shortcuts[idx] = updated
                }
            }
        }
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

    // MARK: - Save

    private func save() {
        errorMessage = nil

        let shortcutDisplay = triggers.first?.displayDescription ?? "No trigger"
        let configManager = RingConfigurationManager.shared

        do {
            try configManager.updateConfiguration(
                id: config.id,
                name: name.trimmingCharacters(in: .whitespaces),
                shortcut: shortcutDisplay,
                ringRadius: Double(config.ringRadius),
                centerHoleRadius: Double(config.centerHoleRadius),
                iconSize: Double(config.iconSize),
                startAngle: Double(config.startAngle),
                presentationMode: .ring
            )

            for trigger in config.triggers {
                try configManager.removeTrigger(id: trigger.id)
            }

            for trigger in triggers {
                _ = try configManager.addTrigger(
                    toRing: config.id,
                    triggerType: trigger.triggerType.rawValue,
                    keyCode: trigger.triggerType == .keyboard ? trigger.keyCode : nil,
                    modifierFlags: trigger.modifierFlags,
                    buttonNumber: trigger.triggerType == .mouse ? trigger.buttonNumber : nil,
                    swipeDirection: trigger.triggerType == .trackpad ? trigger.swipeDirection.rawValue : nil,
                    fingerCount: trigger.triggerType == .trackpad ? trigger.fingerCount : nil,
                    isHoldMode: trigger.isHoldMode,
                    isModifierHoldMode: trigger.isModifierHoldMode,
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

// MARK: - Group Section

private struct InstanceGroupSection: View {
    let group: ContextShortcutGroup
    let shortcuts: [ContextShortcut]
    let allGroups: [ContextShortcutGroup]
    let onAddShortcut: () -> Void
    let onEditShortcut: (ContextShortcut) -> Void
    let onDeleteShortcut: (ContextShortcut) -> Void
    let onReassignShortcut: (ContextShortcut, Int64?) -> Void
    let onDeleteGroup: () -> Void
    let onMoveShortcut: (IndexSet, Int) -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Group header
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

                    Button(action: onDeleteGroup) {
                        Image("context_actions_delete")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete group — shortcuts become ungrouped")
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(6)
            .onHover { isHovered = $0 }

            if shortcuts.isEmpty {
                Text("No shortcuts in this group")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.leading, 24)
                    .padding(.vertical, 6)
            } else {
                List {
                    ForEach(shortcuts) { shortcut in
                        InstanceShortcutRow(
                            shortcut: shortcut,
                            allGroups: allGroups,
                            onEdit: { onEditShortcut(shortcut) },
                            onDelete: { onDeleteShortcut(shortcut) },
                            onReassign: { onReassignShortcut(shortcut, $0) }
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                    }
                    .onMove(perform: onMoveShortcut)
                }
                .listStyle(.plain)
                .scrollDisabled(true)
                .frame(height: CGFloat(shortcuts.count) * 44)
            }
        }
    }
}

// MARK: - Shortcut Row

private struct InstanceShortcutRow: View {
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

    private func formatShortcut(keyCode: UInt16, modifierFlags: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifierFlags)
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option)  { parts.append("⌥") }
        if flags.contains(.shift)   { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"; case 1: return "S"; case 2: return "D"; case 3: return "F"
        case 4: return "H"; case 5: return "G"; case 6: return "Z"; case 7: return "X"
        case 8: return "C"; case 9: return "V"; case 11: return "B"; case 12: return "Q"
        case 13: return "W"; case 14: return "E"; case 15: return "R"; case 16: return "Y"
        case 17: return "T"; case 31: return "O"; case 32: return "U"; case 34: return "I"
        case 35: return "P"; case 37: return "L"; case 38: return "J"; case 40: return "K"
        case 45: return "N"; case 46: return "M"; case 49: return "Space"; case 51: return "⌫"
        case 53: return "Esc"; case 36: return "↩"; case 123: return "←"; case 124: return "→"
        case 125: return "↓"; case 126: return "↑"
        default: return "[\(keyCode)]"
        }
    }
}

// MARK: - Add Group Sheet

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
