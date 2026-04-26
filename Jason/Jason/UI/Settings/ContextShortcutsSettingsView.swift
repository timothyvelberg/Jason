//
//  ContextShortcutsSettingsView.swift
//  Jason
//
//  Created by Timothy Velberg on 18/04/2026.
//

import SwiftUI
import AppKit

// MARK: - Supporting Types

struct ShortcutEditContext: Identifiable {
    let id: Int64
    let shortcut: ContextShortcut
    let app: ContextApp
}

struct InstanceEditContext: Identifiable {
    let id: Int
    let config: StoredRingConfiguration
    let app: ContextApp
}

// MARK: - Main View

struct ContextShortcutsSettingsView: View {

    @State private var apps: [ContextApp] = []
    @State private var instances: [String: [StoredRingConfiguration]] = [:]
    @State private var shortcuts: [Int: [ContextShortcut]] = [:]
    @State private var groups: [Int: [ContextShortcutGroup]] = [:]
    @State private var expandedApps: Set<String> = []
    @State private var expandedInstances: Set<Int> = []
    @State private var showingAppPicker = false
    @State private var addingInstanceForApp: ContextApp? = nil
    @State private var editingInstanceContext: InstanceEditContext? = nil


    var body: some View {
        SettingsListShell(
            title: "Shortcuts",
            emptyIcon: "contextualmenu.and.cursorarrow",
            emptyTitle: "No Apps Configured",
            emptySubtitle: "Add an app to start configuring context-aware shortcuts.",
            primaryLabel: "Add App",
            primaryIcon: "plus.circle.fill",
            primaryAction: { showingAppPicker = true },
            isEmpty: apps.isEmpty
        ) {
            ForEach(apps) { app in
                ContextAppRow(
                    app: app,
                    instances: instances[app.bundleId] ?? [],
                    shortcuts: shortcuts,
                    groups: groups,
                    isExpanded: expandedApps.contains(app.bundleId),
                    expandedInstances: expandedInstances,
                    onToggleExpand: { toggleExpandApp(app) },
                    onToggleExpandInstance: { ringId in toggleExpandInstance(ringId, for: app) },
                    onDeleteApp: { deleteApp(app) },
                    onDeleteInstance: { config in deleteInstance(config, for: app) },
                    onAddInstance: { addingInstanceForApp = app },
                    onEditInstance: { config in
                        editingInstanceContext = InstanceEditContext(id: config.id, config: config, app: app)
                    }
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
        }
        .onAppear {
            loadApps()
        }
        .sheet(isPresented: $showingAppPicker) {
            AppPickerView { bundleId, appName in
                addApp(bundleId: bundleId, displayName: appName)
                showingAppPicker = false
            }
        }
        .sheet(item: $addingInstanceForApp) { app in
            AddContextInstanceSheet(bundleId: app.bundleId) {
                loadInstances(for: app)
                CircularUIInstanceManager.shared.syncWithConfigurations()
            }
        }
        .sheet(item: $editingInstanceContext) { context in
            EditContextInstanceSheet(config: context.config, app: context.app) {
                loadInstances(for: context.app)
                loadData(for: context.config.id)
                CircularUIInstanceManager.shared.syncWithConfigurations()
            }
        }
    }

    // MARK: - Load

    private func loadApps() {
        apps = DatabaseManager.shared.fetchAllContextApps()
        for app in apps {
            loadInstances(for: app)
        }
    }

    private func loadInstances(for app: ContextApp) {
        let all = RingConfigurationManager.shared.getActiveConfigurations()
        instances[app.bundleId] = all.filter { $0.bundleId == app.bundleId }
    }

    private func loadData(for ringId: Int) {
        shortcuts[ringId] = DatabaseManager.shared.fetchContextShortcuts(for: ringId)
        groups[ringId] = DatabaseManager.shared.fetchContextShortcutGroups(for: ringId)
    }

    // MARK: - Add

    private func addApp(bundleId: String, displayName: String) {
        if DatabaseManager.shared.insertContextApp(bundleId: bundleId, displayName: displayName, sortOrder: apps.count) {
            loadApps()
        }
    }

    // MARK: - Delete

    private func deleteApp(_ app: ContextApp) {
        let appInstances = instances[app.bundleId] ?? []
        for config in appInstances {
            CircularUIInstanceManager.shared.removeInstance(forConfigId: config.id)
            DatabaseManager.shared.deleteRingConfiguration(id: config.id)
            shortcuts.removeValue(forKey: config.id)
            groups.removeValue(forKey: config.id)
            expandedInstances.remove(config.id)
        }
        DatabaseManager.shared.deleteContextApp(bundleId: app.bundleId)
        instances.removeValue(forKey: app.bundleId)
        expandedApps.remove(app.bundleId)
        loadApps()
    }

    private func deleteInstance(_ config: StoredRingConfiguration, for app: ContextApp) {
        CircularUIInstanceManager.shared.removeInstance(forConfigId: config.id)
        DatabaseManager.shared.deleteRingConfiguration(id: config.id)
        shortcuts.removeValue(forKey: config.id)
        groups.removeValue(forKey: config.id)
        expandedInstances.remove(config.id)
        loadInstances(for: app)
        CircularUIInstanceManager.shared.syncWithConfigurations()
    }

    // MARK: - Expand / Collapse

    private func toggleExpandApp(_ app: ContextApp) {
        if expandedApps.contains(app.bundleId) {
            expandedApps.remove(app.bundleId)
        } else {
            expandedApps.insert(app.bundleId)
            loadInstances(for: app)
        }
    }

    private func toggleExpandInstance(_ ringId: Int, for app: ContextApp) {
        if expandedInstances.contains(ringId) {
            expandedInstances.remove(ringId)
        } else {
            expandedInstances.insert(ringId)
            loadData(for: ringId)
        }
    }
}

// MARK: - App Row

private struct ContextAppRow: View {

    let app: ContextApp
    let instances: [StoredRingConfiguration]
    let shortcuts: [Int: [ContextShortcut]]
    let groups: [Int: [ContextShortcutGroup]]
    let isExpanded: Bool
    let expandedInstances: Set<Int>
    let onToggleExpand: () -> Void
    let onToggleExpandInstance: (Int) -> Void
    let onDeleteApp: () -> Void
    let onDeleteInstance: (StoredRingConfiguration) -> Void
    let onAddInstance: () -> Void
    let onEditInstance: (StoredRingConfiguration) -> Void

    @State private var appIcon: NSImage?
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {

            // App header row
            HStack(spacing: 12) {
                if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                    Text(app.bundleId)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isHovered {
                    Button(action: onAddInstance) {
                        Label("Add Instance", systemImage: "plus.rectangle.on.rectangle")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Add an app-scoped instance")

                    Button(action: onDeleteApp) {
                        Image("context_actions_delete")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete app and all its instances")
                }

                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }

            // Instances list
            if isExpanded {
                Divider().padding(.leading, 36)

                if instances.isEmpty {
                    HStack {
                        Text("No instances yet — add one to get started.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                        Spacer()
                    }
                    .padding(.leading, 36)
                    .padding(.vertical, 10)
                } else {
                    VStack(spacing: 0) {
                        ForEach(instances) { config in
                            InstanceSubRow(
                                config: config,
                                shortcuts: shortcuts[config.id] ?? [],
                                groups: groups[config.id] ?? [],
                                isExpanded: expandedInstances.contains(config.id),
                                onToggleExpand: { onToggleExpandInstance(config.id) },
                                onDelete: { onDeleteInstance(config) },
                                onEdit: { onEditInstance(config) }
                            )
                        }
                    }
                    .padding(.leading, 36)
                }
            }

            Divider()
        }
        .onAppear { loadIcon() }
    }

    private func loadIcon() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId) {
            appIcon = NSWorkspace.shared.icon(forFile: url.path)
        }
    }
}

// MARK: - Instance Sub Row

private struct InstanceSubRow: View {

    let config: StoredRingConfiguration
    let shortcuts: [ContextShortcut]
    let groups: [ContextShortcutGroup]
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void

    @State private var isHovered = false
    
    private var topLevelItems: [ContextTopLevelItem] {
        let groupItems = groups.map { ContextTopLevelItem.group($0) }
        let ungroupedItems = shortcuts.filter { $0.groupId == nil }.map { ContextTopLevelItem.ungroupedShortcut($0) }
        return (groupItems + ungroupedItems).sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        VStack(spacing: 0) {

            // Instance header
            HStack(spacing: 10) {
                Image(systemName: "circle.grid.cross")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(config.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(config.triggersSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isHovered {
                    Button(action: onEdit) {
                        Image("context_actions_edit")
                    }
                    .buttonStyle(.borderless)
                    .help("Edit instance")

                    Button(action: onDelete) {
                        Image("context_actions_delete")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete instance and its shortcuts")
                }

                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }

            // Read-only shortcut summary
            if isExpanded {
                Divider().padding(.leading, 26)

                if shortcuts.isEmpty && groups.isEmpty {
                    HStack {
                        Text("No shortcuts configured")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                        Spacer()
                    }
                    .padding(.leading, 26)
                    .padding(.vertical, 8)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(topLevelItems) { item in
                            switch item {
                            case .group(let group):
                                let groupShortcuts = shortcuts.filter { $0.groupId == group.id }

                                HStack(spacing: 6) {
                                    Image(systemName: group.iconName ?? "folder")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    Text(group.name)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.leading, 26)
                                .padding(.top, 8)
                                .padding(.bottom, 2)

                                ForEach(groupShortcuts) { shortcut in
                                    ReadOnlyShortcutRow(shortcut: shortcut)
                                        .padding(.leading, 40)
                                }

                                if groupShortcuts.isEmpty {
                                    Text("Empty group")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .italic()
                                        .padding(.leading, 40)
                                        .padding(.bottom, 4)
                                }

                            case .ungroupedShortcut(let shortcut):
                                ReadOnlyShortcutRow(shortcut: shortcut)
                                    .padding(.leading, groups.isEmpty ? 26 : 40)
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }

            Divider().padding(.leading, 16).opacity(0.5)
        }
    }
}

// MARK: - Read Only Shortcut Row

private struct ReadOnlyShortcutRow: View {
    let shortcut: ContextShortcut

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: shortcut.iconName ?? "command")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 14)

            Text(shortcut.shortcutName)
                .font(.caption)

            Spacer()

            Text(formatShortcut(keyCode: shortcut.keyCode, modifierFlags: shortcut.modifierFlags))
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.1))
                )
        }
        .padding(.vertical, 3)
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
