//
//  ContextShortcutsSettingsView.swift
//  Jason
//
//  Created by Timothy Velberg on 18/04/2026.

//  Read-only settings list for context-aware shortcuts.
//  Shows apps → instances → shortcuts in a collapsible hierarchy.
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
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
            }
        }
        .onAppear { loadApps() }
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
            EditContextShortcutsSheet(config: context.config, app: context.app) {
                loadInstances(for: context.app)
                loadData(for: context.config.id)
                CircularUIInstanceManager.shared.syncWithConfigurations()
            }
        }
    }

    // MARK: - Load

    private func loadApps() {
        apps = DatabaseManager.shared.fetchAllContextApps()
        for app in apps { loadInstances(for: app) }
    }

    private func loadInstances(for app: ContextApp) {
        let all = RingConfigurationManager.shared.getActiveConfigurations()
        instances[app.bundleId] = all.filter { $0.bundleId == app.bundleId }
    }

    private func loadData(for ringId: Int) {
        shortcuts[ringId] = DatabaseManager.shared.fetchContextShortcuts(for: ringId)
        groups[ringId]    = DatabaseManager.shared.fetchContextShortcutGroups(for: ringId)
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
                
                Text(app.displayName)
                    .font(.body)
                    .fontWeight(.medium)

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
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(.white)
                        .frame(width: 16, height: 16)
                        .background(Color.blue.opacity(0.8))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 16)
            .onHover { isHovered = $0 }
            
            // Instances list
            if isExpanded {
                if instances.isEmpty {
                    HStack {
                        Text("No instances yet — add one to get started.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                        Spacer()
                    }
                    .padding(.vertical, 10)
                } else {
                    VStack(spacing: 0) {
                        ForEach(instances) { config in
                            Divider()
                                .padding(.horizontal, -8)
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
//                    .padding(.vertical, 8)
                }
            }
            Divider()
                .padding(.horizontal, -8)
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
        let groupItems    = groups.map { ContextTopLevelItem.group($0) }
        let ungrouped     = shortcuts.filter { $0.groupId == nil }.map { ContextTopLevelItem.ungroupedShortcut($0) }
        return (groupItems + ungrouped).sorted { $0.sortOrder < $1.sortOrder }
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
                .padding(.vertical, 4)

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
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(.white)    
                        .frame(width: 16, height: 16)
                        .background(Color.blue.opacity(0.8))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .onHover { isHovered = $0 }

            // Read-only shortcut summary
            if isExpanded {
                Divider()
                    .padding(.horizontal, 8)
                if shortcuts.isEmpty && groups.isEmpty {
                    HStack {
                        Text("No shortcuts configured")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                } else {
                    VStack(spacing: 8){
                        VStack(alignment: .leading, spacing: 2) {
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

                                    ForEach(groupShortcuts) { shortcut in
                                        ReadOnlyShortcutRow(shortcut: shortcut)
                                            .padding(.leading, 40)
                                            .padding(.vertical, 16)
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
                        .padding(.horizontal, 8)
                        .padding(.vertical,16)
                    }
                }
            }
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

            switch shortcut.shortcutType {
            case .keyboard:
                if let keyCode = shortcut.keyCode, let modifierFlags = shortcut.modifierFlags {
                    badge(formatShortcut(keyCode: keyCode, modifierFlags: modifierFlags))
                }
            case .menu:
                if let menuPath = shortcut.menuPath {
                    badge(menuPath.replacingOccurrences(of: ";", with: " › "))
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.1))
            )
    }
} 
