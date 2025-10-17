//
//  ContentView.swift
//  Jason
//
//  Created by Timothy Velberg on 31/07/2025.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var appSwitcher = AppSwitcherManager()
    @StateObject private var circularUI = CircularUIManager()
    
    var body: some View {
        Group {
            MinimalView(circularUI: circularUI)
//            if !appSwitcher.hasAccessibilityPermission {
//                PermissionRequestView(appSwitcher: appSwitcher, circularUI: circularUI)
//            } else {
//                MinimalView(circularUI: circularUI)
//            }
        }
        .onAppear {
            print("🚀 ContentView appeared")
            circularUI.setup(with: appSwitcher)
        }
        .onDisappear {
            print("👋 ContentView disappeared - stopping services")
            appSwitcher.stopAutoRefresh()
        }
    }
}

// MARK: - Permission Request View

struct PermissionRequestView: View {
    let appSwitcher: AppSwitcherManager
    @ObservedObject var circularUI: CircularUIManager
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            
            Text("Accessibility Permission Required")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Jason needs Accessibility permission to detect global keyboard shortcuts and function as an app switcher.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(spacing: 10) {
                Text("To grant permission:")
                    .fontWeight(.medium)
                
                Text("1. Click 'Open System Preferences' below")
                Text("2. Find 'Jason' in the list")
                Text("3. Check the box next to 'Jason'")
                Text("4. Come back and click 'Check Again'")
            }
            .font(.system(size: 14))
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            HStack(spacing: 15) {
                Button("Open System Preferences") {
                    appSwitcher.openAccessibilityPreferences()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Check Again") {
                    appSwitcher.checkAccessibilityPermission()
                }
                .buttonStyle(.bordered)
            }
            
            // Development testing buttons
            Divider()
                .padding(.vertical, 10)
            
            Text("Development Testing")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 10) {
                Button("Test Circular UI") {
                    circularUI.show()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Hide") {
                    circularUI.hide()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(30)
        .frame(maxWidth: 500)
    }
}

// MARK: - Minimal Hidden View

// MARK: - Minimal Hidden View

struct MinimalView: View {
    @ObservedObject var circularUI: CircularUIManager
    @State private var showingFavoritesSettings = false  // 👈 NEW
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "circle.grid.3x3.fill")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            
            Text("Jason App Switcher")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Press your keyboard shortcut to show the circular UI")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Divider()
                .padding(.vertical, 10)
            
            Text("Development Testing")
                .font(.caption)
                .foregroundColor(.secondary)
            
            VStack(spacing: 10) {
                Button("Test Circular UI") {
                    circularUI.show()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Hide Circular UI") {
                    circularUI.hide()
                }
                .buttonStyle(.bordered)
                
                Button("Manage Favorites") {
                    showingFavoritesSettings = true
                }
                .buttonStyle(.bordered)
                Button("Show DB Path") {
                    if let path = try? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                        .appendingPathComponent("Jason") {
                        print("📍 Database folder: \(path.path)")
                        NSWorkspace.shared.selectFile(path.appendingPathComponent("Jason.db").path, inFileViewerRootedAtPath: path.path)
                    }
                }
            }
        }
        .padding(30)
        .frame(width: 300, height: 400)
        .sheet(isPresented: $showingFavoritesSettings) {
            FavoritesSettingsView(circularUI: circularUI)
        }
    }
}

// MARK: - Favorites Settings View

struct FavoritesSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var favorites: [(folder: FolderEntry, settings: FavoriteFolderSettings)] = []
    @State private var editingFavorite: FolderEntry?
    @State private var editingName: String = ""
    @State private var editingMaxItems: String = ""
    
    let circularUI: CircularUIManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Manage Favorite Folders")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            Divider()
            
            // Favorites List
            if favorites.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No favorites yet")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    
                    Text("Click 'Add Folder' to add your first favorite")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(favorites.enumerated()), id: \.element.folder.id) { index, item in
                        FavoriteRow(
                            folder: item.folder,
                            maxItems: item.settings.maxItems,  // Changed from item.maxItems
                            onEdit: {
                                editingFavorite = item.folder
                                editingName = item.folder.title
                                editingMaxItems = item.settings.maxItems.map { String($0) } ?? ""
                            },
                            onRemove: {
                                removeFavorite(item.folder)
                            }
                        )
                    }
                    .onMove { from, to in
                        // TODO: Handle reordering
                    }
                }
            }
            
            Divider()
            
            // Add Button
            HStack {
                Button(action: addFolder) {
                    Label("Add Folder", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
                
                Text("\(favorites.count) favorite(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .frame(width: 600, height: 500)
        .onAppear {
            loadFavorites()
        }
        .sheet(item: $editingFavorite) { folder in
            // Find the settings for this folder
            let currentSettings = favorites.first(where: { $0.folder.id == folder.id })?.settings
            
            EditFavoriteView(
                folder: folder,
                name: $editingName,
                maxItems: $editingMaxItems,
                currentSettings: currentSettings,
                onSave: {
                    editingFavorite = nil
                    loadFavorites()
                }
            )
        }
    }
    
    // MARK: - Actions
    
    private func loadFavorites() {
        favorites = DatabaseManager.shared.getFavoriteFolders()
        print("📋 Loaded \(favorites.count) favorites")
        circularUI.hide()
    }
    
    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to add to favorites"
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            let path = url.path
            let title = url.lastPathComponent
            
            if DatabaseManager.shared.addFavoriteFolder(path: path, title: title, settings: nil) {
                print("✅ Added favorite: \(title)")
                loadFavorites()
            } else {
                print("❌ Failed to add favorite")
            }
        }
    }
    
    private func removeFavorite(_ folder: FolderEntry) {
        if DatabaseManager.shared.removeFavoriteFolder(path: folder.path) {
            print("🗑️ Removed favorite: \(folder.title)")
            loadFavorites()
        }
    }
}

// MARK: - Favorite Row

struct FavoriteRow: View {
    let folder: FolderEntry
    let maxItems: Int?
    let onEdit: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path))
                .resizable()
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(folder.title)
                    .font(.body)
                    .fontWeight(.medium)
                
                HStack(spacing: 8) {
                    Text(folder.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if let maxItems = maxItems {
                        Text("• Max: \(maxItems)")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Edit Favorite View

// MARK: - Edit Favorite View

// MARK: - Edit Favorite View

struct EditFavoriteView: View {
    @Environment(\.dismiss) var dismiss
    let folder: FolderEntry
    @Binding var name: String
    @Binding var maxItems: String
    let currentSettings: FavoriteFolderSettings?
    let onSave: () -> Void
    
    @State private var selectedLayout: String = "fullCircle"
    @State private var itemAngleSize: String = "30"
    @State private var slicePositioning: String = "startClockwise"
    @State private var childRingThickness: String = "80"
    @State private var childIconSize: String = "32"
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Favorite: \(folder.title)")
                .font(.title2)
                .fontWeight(.semibold)
            
            ScrollView {
                Form {
                    Section("Basic Settings") {
                        TextField("Name", text: $name)
                        TextField("Max Items (optional)", text: $maxItems)
                            .help("Leave empty for no limit")
                    }
                    
                    Section("Layout") {
                        Picker("Preferred Layout", selection: $selectedLayout) {
                            Text("Full Circle").tag("fullCircle")
                            Text("Partial Slice").tag("partialSlice")
                        }
                        
                        TextField("Item Angle (degrees)", text: $itemAngleSize)
                            .help("Angle per item: 15-60 degrees")
                        
                        Picker("Slice Positioning", selection: $slicePositioning) {
                            Text("Start Clockwise").tag("startClockwise")
                            Text("Start Counter-Clockwise").tag("startCounterClockwise")
                            Text("Center").tag("center")
                        }
                    }
                    
                    Section("Child Ring Appearance") {
                        TextField("Child Ring Thickness (px)", text: $childRingThickness)
                            .help("Thickness in pixels: 40-120")
                        
                        TextField("Child Icon Size (px)", text: $childIconSize)
                            .help("Icon size in pixels: 16-48")
                    }
                }
            }
            .frame(height: 400)
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Save") {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear {
            // Load current settings
            if let settings = currentSettings {
                selectedLayout = settings.preferredLayout ?? "fullCircle"
                itemAngleSize = settings.itemAngleSize.map { String($0) } ?? "30"
                slicePositioning = settings.slicePositioning ?? "startClockwise"
                childRingThickness = settings.childRingThickness.map { String($0) } ?? "80"
                childIconSize = settings.childIconSize.map { String($0) } ?? "32"
            }
        }
        .padding()
        .frame(width: 500, height: 550)
    }
    
    private func saveChanges() {
        // Parse numeric values
        let maxItemsValue = Int(maxItems.trimmingCharacters(in: .whitespaces))
        let itemAngleValue = Int(itemAngleSize.trimmingCharacters(in: .whitespaces))
        let thicknessValue = Int(childRingThickness.trimmingCharacters(in: .whitespaces))
        let iconSizeValue = Int(childIconSize.trimmingCharacters(in: .whitespaces))
        
        let settings = FavoriteFolderSettings(
            maxItems: maxItemsValue,
            preferredLayout: selectedLayout,
            itemAngleSize: itemAngleValue,
            slicePositioning: slicePositioning,
            childRingThickness: thicknessValue,
            childIconSize: iconSizeValue
        )
        
        // Update in database
        if DatabaseManager.shared.updateFavoriteSettings(path: folder.path, title: name, settings: settings) {
            print("✅ Updated favorite settings for: \(folder.title)")
            onSave()
        } else {
            print("❌ Failed to update favorite settings")
        }
    }
}
