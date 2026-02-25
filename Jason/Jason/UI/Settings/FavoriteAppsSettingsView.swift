//
//  FavoriteAppsSettingsView.swift
//  Jason
//
//  Created by Timothy Velberg on 17/10/2025.
//

import SwiftUI
import AppKit

struct FavoriteAppsSettingsView: View {
    @State private var favoriteApps: [FavoriteAppEntry] = []
    @State private var showingAppPicker = false
    @State private var editingApp: FavoriteAppEntry?
    
    var body: some View {
        SettingsListShell(
            title: "Apps",
            emptyIcon: "star.slash",
            emptyTitle: "No favourite apps yet",
            emptySubtitle: "Click the + button below to add your first favourite app",
            primaryLabel: "Add App",
            primaryAction: { showingAppPicker = true },
            secondaryLabel: nil,
            secondaryAction: nil,
            isEmpty: favoriteApps.isEmpty
        ) {
            ForEach(favoriteApps) { app in
                AppRow(app: app) {
                    editingApp = app
                } onDelete: {
                    removeApp(app)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            .onMove(perform: moveApp)
        }
        .onAppear { loadFavoriteApps() }
        .sheet(isPresented: $showingAppPicker) {
            AppPickerView { bundleId, appName in
                addApp(bundleId: bundleId, name: appName)
                showingAppPicker = false
            }
        }
        .sheet(item: $editingApp) { app in
            EditFavoriteAppView(
                app: app,
                onSave: { updatedName, iconOverride in
                    updateApp(app, name: updatedName, iconOverride: iconOverride)
                    editingApp = nil
                },
                onCancel: { editingApp = nil }
            )
        }
    }
    
    // MARK: - Actions
    
    private func loadFavoriteApps() {
        favoriteApps = DatabaseManager.shared.getFavoriteApps()
    }
    
    private func addApp(bundleId: String, name: String) {
        if DatabaseManager.shared.addFavoriteApp(bundleIdentifier: bundleId, displayName: name, iconOverride: nil) {
            loadFavoriteApps()
            notifyProvider()
        }
    }
    
    private func removeApp(_ app: FavoriteAppEntry) {
        if DatabaseManager.shared.removeFavoriteApp(bundleIdentifier: app.bundleIdentifier) {
            loadFavoriteApps()
            notifyProvider()
        }
    }
    
    private func updateApp(_ app: FavoriteAppEntry, name: String, iconOverride: String?) {
        if DatabaseManager.shared.updateFavoriteApp(
            bundleIdentifier: app.bundleIdentifier,
            displayName: name,
            iconOverride: iconOverride
        ) {
            loadFavoriteApps()
            notifyProvider()
        }
    }
    
    private func moveApp(from source: IndexSet, to destination: Int) {
        favoriteApps.move(fromOffsets: source, toOffset: destination)
        for (index, app) in favoriteApps.enumerated() {
            DatabaseManager.shared.reorderFavoriteApps(
                bundleIdentifier: app.bundleIdentifier,
                newSortOrder: index
            )
        }
        loadFavoriteApps()
        notifyProvider()
    }
    
    private func notifyProvider() {
        NotificationCenter.default.postProviderUpdate(providerId: "combined-apps")
    }
}

// MARK: - App Row

private struct AppRow: View {
    let app: FavoriteAppEntry
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var appIcon: NSImage?
    
    var body: some View {
        SettingsRow(
            icon: appIcon.map { .nsImage($0) } ?? .systemSymbol("app.fill", .secondary),
            title: app.displayName,
            showDragHandle: true,
            onEdit: onEdit,
            onDelete: onDelete,
            metadata: {
                if let lastAccessed = app.lastAccessed {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(app.accessCount) launches")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formatDate(lastAccessed))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        )
        .onAppear { loadIcon() }
    }
    
    private func loadIcon() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
            appIcon = NSWorkspace.shared.icon(forFile: url.path)
        }
    }
    
    private func formatDate(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - App Picker View

struct AppPickerView: View {
    let onAppSelected: (String, String) -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var searchText = ""
    @State private var allApps: [(name: String, bundleId: String, icon: NSImage)] = []
    @State private var isLoading = true
    
    var filteredApps: [(name: String, bundleId: String, icon: NSImage)] {
        if searchText.isEmpty { return allApps }
        return allApps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleId.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Choose an Application")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search applications...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            Divider()
            
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView().scaleEffect(1.5)
                    Text("Loading applications...").foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredApps.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "No applications found" : "No results for \"\(searchText)\"")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredApps, id: \.bundleId) { app in
                            Button(action: { onAppSelected(app.bundleId, app.name) }) {
                                HStack(spacing: 12) {
                                    Image(nsImage: app.icon)
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(app.name)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Text(app.bundleId)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                hovering ? NSCursor.pointingHand.push() : NSCursor.pop()
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            
            Divider()
            
            HStack {
                Text("\(filteredApps.count) application\(filteredApps.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
        }
        .frame(width: 600, height: 500)
        .onAppear { loadAllApplications() }
    }
    
    private func loadAllApplications() {
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            let applicationDirs = [
                "/Applications",
                "/System/Applications",
                "/System/Library/CoreServices/Applications",
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
            ]
            
            var apps: [(name: String, bundleId: String, icon: NSImage)] = []
            
            for dir in applicationDirs {
                guard let contents = try? fileManager.contentsOfDirectory(atPath: dir) else { continue }
                for item in contents where item.hasSuffix(".app") {
                    let appPath = (dir as NSString).appendingPathComponent(item)
                    let appURL = URL(fileURLWithPath: appPath)
                    guard let bundle = Bundle(url: appURL),
                          let bundleId = bundle.bundleIdentifier else { continue }
                    let appName = bundle.infoDictionary?["CFBundleName"] as? String
                        ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
                        ?? appURL.deletingPathExtension().lastPathComponent
                    apps.append((name: appName, bundleId: bundleId, icon: NSWorkspace.shared.icon(forFile: appPath)))
                }
            }
            
            apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            
            DispatchQueue.main.async {
                self.allApps = apps
                self.isLoading = false
            }
        }
    }
}

// MARK: - Edit Favourite App View

struct EditFavoriteAppView: View {
    let app: FavoriteAppEntry
    let onSave: (String, String?) -> Void
    let onCancel: () -> Void
    
    @State private var displayName: String
    @State private var iconOverride: String
    @State private var useCustomIcon: Bool
    
    init(app: FavoriteAppEntry, onSave: @escaping (String, String?) -> Void, onCancel: @escaping () -> Void) {
        self.app = app
        self.onSave = onSave
        self.onCancel = onCancel
        _displayName = State(initialValue: app.displayName)
        _iconOverride = State(initialValue: app.iconOverride ?? "")
        _useCustomIcon = State(initialValue: app.iconOverride != nil)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Edit \(app.displayName)")
                .font(.title2)
                .fontWeight(.semibold)
            
            Form {
                Section {
                    TextField("Display Name", text: $displayName)
                }
                
                Section {
                    Toggle("Use Custom Icon", isOn: $useCustomIcon)
                    
                    if useCustomIcon {
                        TextField("SF Symbol Name", text: $iconOverride)
                            .help("e.g., star.fill, app.badge, folder.fill")
                        
                        if !iconOverride.isEmpty {
                            HStack {
                                Text("Preview:").foregroundColor(.secondary)
                                if let image = NSImage(systemSymbolName: iconOverride, accessibilityDescription: nil) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                        .foregroundColor(.blue)
                                } else {
                                    Text("Invalid symbol")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            
            Spacer()
            
            HStack(spacing: 12) {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                
                Button("Save") {
                    let finalIconOverride = useCustomIcon && !iconOverride.isEmpty ? iconOverride : nil
                    onSave(displayName, finalIconOverride)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(displayName.isEmpty)
            }
        }
        .padding()
        .frame(width: 450, height: 350)
    }
}
