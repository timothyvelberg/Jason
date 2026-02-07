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
    @State private var showingEditSheet = false
    
    var body: some View {
        VStack(spacing: 0) {
            if favoriteApps.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "star.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No favorite apps yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Click the + button below to add your first favorite app")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button {
                        showingAppPicker = true
                    } label: {
                        Label("Add App", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(favoriteApps) { app in
                        FavoriteAppRow(
                            app: app,
                            onEdit: {
                                editingApp = app
                                showingEditSheet = true
                            },
                            onRemove: {
                                removeApp(app)
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    .onMove(perform: moveApp)
                }
                .listStyle(.inset)
            }
            
            Divider()
            
            HStack {
                Button {
                    showingAppPicker = true
                } label: {
                    Label("Add App", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
                
                Text("\(favoriteApps.count) favorite app\(favoriteApps.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .onAppear {
            loadFavoriteApps()
        }
        .sheet(isPresented: $showingAppPicker) {
            AppPickerView(onAppSelected: { bundleId, appName in
                addApp(bundleId: bundleId, name: appName)
                showingAppPicker = false
            })
        }
        .sheet(isPresented: $showingEditSheet) {
            if let app = editingApp {
                EditFavoriteAppView(
                    app: app,
                    onSave: { updatedName, iconOverride in
                        updateApp(app, name: updatedName, iconOverride: iconOverride)
                        showingEditSheet = false
                    },
                    onCancel: {
                        showingEditSheet = false
                    }
                )
            }
        }
    }
    
    // MARK: - Actions
    
    private func loadFavoriteApps() {
        favoriteApps = DatabaseManager.shared.getFavoriteApps()
        print("📋 Loaded \(favoriteApps.count) favorite apps")
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

// MARK: - Favorite App Row

struct FavoriteAppRow: View {
    let app: FavoriteAppEntry
    let onEdit: () -> Void
    let onRemove: () -> Void
    
    @State private var appIcon: NSImage?
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14))
                .foregroundColor(.secondary.opacity(0.5))
                .help("Drag to reorder")
            
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(app.bundleIdentifier)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
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
            
            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)
                .help("Edit app settings")
                
                Button(action: onRemove) {
                    Image(systemName: "trash.circle.fill")
                        .font(.title3)
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("Remove from favorites")
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            loadAppIcon()
        }
    }
    
    private func loadAppIcon() {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
            appIcon = NSWorkspace.shared.icon(forFile: appURL.path)
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
        if searchText.isEmpty {
            return allApps
        }
        return allApps.filter { app in
            app.name.localizedCaseInsensitiveContains(searchText) ||
            app.bundleId.localizedCaseInsensitiveContains(searchText)
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
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading applications...")
                        .foregroundColor(.secondary)
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
                            Button(action: {
                                onAppSelected(app.bundleId, app.name)
                            }) {
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
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.01))
                            .onHover { hovering in
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
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
        .onAppear {
            loadAllApplications()
        }
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
                    
                    let appName = bundle.infoDictionary?["CFBundleName"] as? String ??
                                  bundle.infoDictionary?["CFBundleDisplayName"] as? String ??
                                  appURL.deletingPathExtension().lastPathComponent
                    
                    let icon = NSWorkspace.shared.icon(forFile: appPath)
                    
                    apps.append((name: appName, bundleId: bundleId, icon: icon))
                }
            }
            
            apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            
            DispatchQueue.main.async {
                self.allApps = apps
                self.isLoading = false
                print("📱 [AppPicker] Loaded \(apps.count) applications")
            }
        }
    }
}

struct ProviderConfig: Identifiable {
    let id = UUID()
    let type: String
    let name: String
    let description: String
    var isEnabled: Bool
    var displayMode: ProviderDisplayMode
}

// MARK: - Edit Favorite App View

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
                                Text("Preview:")
                                    .foregroundColor(.secondary)
                                
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
                Button("Cancel") {
                    onCancel()
                }
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


