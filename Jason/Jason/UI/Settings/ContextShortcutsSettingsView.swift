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
    @State private var showingAppPicker = false

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
                ContextAppRow(app: app) {
                    deleteApp(app)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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
    }

    // MARK: - Actions

    private func loadApps() {
        apps = DatabaseManager.shared.fetchAllContextApps()
    }

    private func addApp(bundleId: String, displayName: String) {
        let sortOrder = apps.count
        if DatabaseManager.shared.insertContextApp(bundleId: bundleId, displayName: displayName, sortOrder: sortOrder) {
            loadApps()
        }
    }

    private func deleteApp(_ app: ContextApp) {
        DatabaseManager.shared.deleteContextApp(bundleId: app.bundleId)
        loadApps()
    }

    private func moveApp(from source: IndexSet, to destination: Int) {
        apps.move(fromOffsets: source, toOffset: destination)
        let updates = apps.enumerated().map { (index, app) in
            (id: app.id, sortOrder: index)
        }
        DatabaseManager.shared.updateContextAppSortOrders(updates)
    }
}

// MARK: - App Row

private struct ContextAppRow: View {

    let app: ContextApp
    let onDelete: () -> Void

    @State private var appIcon: NSImage?

    var body: some View {
        SettingsRow(
            icon: appIcon.map { .nsImage($0) } ?? .systemSymbol("app.fill", .secondary),
            title: app.displayName,
            subtitle: app.bundleId,
            showDragHandle: true,
            onEdit: {
                // TODO: drill into shortcuts
            },
            onDelete: onDelete
        )
        .onAppear {
            loadIcon()
        }
    }

    private func loadIcon() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId) {
            appIcon = NSWorkspace.shared.icon(forFile: url.path)
        }
    }
}
