//
//  ContextShortcutsSettingsView.swift
//  Jason
//
//  Created by Timothy Velberg on 18/04/2026.
//

import SwiftUI
import AppKit

struct ContextShortcutsSettingsView: View {

    @State private var apps: [ContextApp] = []
    @State private var shortcuts: [String: [ContextShortcut]] = [:]
    @State private var expandedApps: Set<String> = []
    @State private var showingAppPicker = false
    @State private var addingShortcutForApp: ContextApp? = nil
    @State private var editingContext: ShortcutEditContext? = nil

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
                    shortcuts: shortcuts[app.bundleId] ?? [],
                    isExpanded: expandedApps.contains(app.bundleId),
                    onToggleExpand: { toggleExpand(app) },
                    onDeleteApp: { deleteApp(app) },
                    onDeleteShortcut: { shortcut in
                        deleteShortcut(shortcut, for: app)
                    },
                    onEditShortcut: { shortcut in
                        editingContext = ShortcutEditContext(id: shortcut.id, shortcut: shortcut, app: app)
                    },
                    onAddShortcut: { addingShortcutForApp = app },
                    onMoveShortcut: { source, destination in
                        moveShortcut(from: source, to: destination, for: app)
                    }
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
            .onMove(perform: moveApp)
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
        .sheet(item: $addingShortcutForApp) { app in
            AddContextShortcutSheet(app: app) {
                loadShortcuts(for: app)
            }
        }
        .sheet(item: $editingContext) { context in
            AddContextShortcutSheet(app: context.app, existingShortcut: context.shortcut) {
                loadShortcuts(for: context.app)
            }
        }
    }

    // MARK: - Actions

    private func loadApps() {
        apps = DatabaseManager.shared.fetchAllContextApps()
    }

    private func loadShortcuts(for app: ContextApp) {
        shortcuts[app.bundleId] = DatabaseManager.shared.fetchContextShortcuts(for: app.bundleId)
    }

    private func addApp(bundleId: String, displayName: String) {
        if DatabaseManager.shared.insertContextApp(bundleId: bundleId, displayName: displayName, sortOrder: apps.count) {
            loadApps()
        }
    }

    private func deleteApp(_ app: ContextApp) {
        DatabaseManager.shared.deleteContextApp(bundleId: app.bundleId)
        shortcuts.removeValue(forKey: app.bundleId)
        expandedApps.remove(app.bundleId)
        loadApps()
    }

    private func deleteShortcut(_ shortcut: ContextShortcut, for app: ContextApp) {
        DatabaseManager.shared.deleteContextShortcut(id: shortcut.id)
        loadShortcuts(for: app)
    }

    private func toggleExpand(_ app: ContextApp) {
        if expandedApps.contains(app.bundleId) {
            expandedApps.remove(app.bundleId)
        } else {
            expandedApps.insert(app.bundleId)
            loadShortcuts(for: app)
        }
    }

    private func moveApp(from source: IndexSet, to destination: Int) {
        apps.move(fromOffsets: source, toOffset: destination)
        let updates = apps.enumerated().map { (index, app) in
            (id: app.id, sortOrder: index)
        }
        DatabaseManager.shared.updateContextAppSortOrders(updates)
    }

    private func moveShortcut(from source: IndexSet, to destination: Int, for app: ContextApp) {
        var appShortcuts = shortcuts[app.bundleId] ?? []
        appShortcuts.move(fromOffsets: source, toOffset: destination)
        shortcuts[app.bundleId] = appShortcuts
        let updates = appShortcuts.enumerated().map { (index, shortcut) in
            (id: shortcut.id, sortOrder: index)
        }
        DatabaseManager.shared.updateContextShortcutSortOrders(updates)
    }
}

// MARK: - Edit Context

struct ShortcutEditContext: Identifiable {
    let id: Int64
    let shortcut: ContextShortcut
    let app: ContextApp
}

// MARK: - App Row

private struct ContextAppRow: View {

    let app: ContextApp
    let shortcuts: [ContextShortcut]
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onDeleteApp: () -> Void
    let onDeleteShortcut: (ContextShortcut) -> Void
    let onEditShortcut: (ContextShortcut) -> Void
    let onAddShortcut: () -> Void
    let onMoveShortcut: (IndexSet, Int) -> Void

    @State private var appIcon: NSImage?
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // App row
            HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary.opacity(0.5))
                    .help("Drag to reorder")

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
                    Button(action: onAddShortcut) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Add shortcut")

                    Button(action: onDeleteApp) {
                        Image("context_actions_delete")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete app and all its shortcuts")
                }

                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse" : "Expand shortcuts")
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }

            // Shortcuts list
            if isExpanded {
                Divider()
                    .padding(.leading, 36)

                if shortcuts.isEmpty {
                    HStack {
                        Text("No shortcuts yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                        Spacer()
                    }
                    .padding(.leading, 36)
                    .padding(.vertical, 10)
                } else {
                    List {
                        ForEach(shortcuts) { shortcut in
                            ShortcutSubRow(
                                shortcut: shortcut,
                                onEdit: { onEditShortcut(shortcut) },
                                onDelete: { onDeleteShortcut(shortcut) }
                            )
                            .listRowInsets(EdgeInsets(top: 0, leading: 36, bottom: 0, trailing: 0))
                        }
                        .onMove(perform: onMoveShortcut)
                    }
                    .listStyle(.plain)
                    .frame(height: CGFloat(shortcuts.count) * 44)
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

// MARK: - Shortcut Sub Row

private struct ShortcutSubRow: View {

    let shortcut: ContextShortcut
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: shortcut.iconName ?? "command")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 16)

            Text(shortcut.shortcutName)
                .font(.subheadline)

            Spacer()

            Text(formatShortcut(keyCode: shortcut.keyCode, modifierFlags: shortcut.modifierFlags))
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.1))
                )

            if isHovered {
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
