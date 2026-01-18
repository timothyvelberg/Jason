//
//  FavoriteFoldersViews.swift
//  Jason
//
//  Created by Timothy Velberg on 24/11/2025.
//


import SwiftUI
import AppKit

// MARK: - Favorites Settings View

struct FavoritesSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var favorites: [(folder: FolderEntry, settings: FavoriteFolderSettings)] = []
    @State private var editingFavorite: FolderEntry?
    @State private var editingName: String = ""
    @State private var editingMaxItems: String = ""
    @State private var newFolderPath: String = ""
    
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
            
            if favorites.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No favorites yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        TextField("Paste folder path...", text: $newFolderPath)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 400)
                        
                        Button("Add") {
                            addFolder()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newFolderPath.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(favorites, id: \.folder.id) { item in
                        FavoriteRow(
                            folder: item.folder,
                            maxItems: item.settings.maxItems,
                            onEdit: {
                                editingFavorite = item.folder
                                editingName = item.folder.title
                                editingMaxItems = item.settings.maxItems.map { String($0) } ?? ""
                            },
                            onRemove: {
                                removeFavorite(item.folder)
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    .onMove(perform: moveFolder)
                }
                .listStyle(.inset)
            }
            
            Divider()
            
            HStack {
                TextField("Paste folder path...", text: $newFolderPath)
                    .textFieldStyle(.roundedBorder)
                
                Button("Add") {
                    addFolder()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newFolderPath.trimmingCharacters(in: .whitespaces).isEmpty)
                
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
        let path = newFolderPath.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return }
        
        let url = URL(fileURLWithPath: path)
        let title = url.lastPathComponent
        
        if DatabaseManager.shared.addFavoriteFolder(path: path, title: title, settings: nil) {
            print("✅ Added favorite: \(title)")
            newFolderPath = ""
            loadFavorites()
        } else {
            print("❌ Failed to add favorite")
        }
    }
    
    private func removeFavorite(_ folder: FolderEntry) {
        if DatabaseManager.shared.removeFavoriteFolder(path: folder.path) {
            print("🗑️ Removed favorite: \(folder.title)")
            loadFavorites()
        }
    }
    
    private func moveFolder(from source: IndexSet, to destination: Int) {
        // Update local state first for immediate UI feedback
        favorites.move(fromOffsets: source, toOffset: destination)
        
        // Get the index we're moving from
        guard let sourceIndex = source.first else { return }
        
        // Calculate actual destination (accounting for the removal)
        let actualDestination = sourceIndex < destination ? destination - 1 : destination
        
        print("🔄 Moving folder from index \(sourceIndex) to \(actualDestination)")
        
        // Update database order
        if DatabaseManager.shared.reorderFavoriteFolders(from: sourceIndex, to: actualDestination) {
            print("✅ Successfully reordered favorite folders in database")
        } else {
            print("❌ Failed to reorder favorites - reverting")
            // Revert local changes if database update failed
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
            // Drag indicator
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14))
                .foregroundColor(.secondary.opacity(0.5))
                .help("Drag to reorder")
            
            // Use layered folder icon with stored color
            let folderColor = folder.iconColor ?? NSColor(hex: "#55C2EE") ?? .systemBlue
            let icon: NSImage = {
                if let iconName = folder.iconName, !iconName.isEmpty {
                    return IconProvider.shared.createLayeredFolderIconWithSymbol(
                        color: folderColor,
                        symbolName: iconName,
                        symbolColor: .white,
                        size: 32,
                        symbolSize: 14,
                        cornerRadius: 4,
                        symbolOffset: -2
                    )
                } else {
                    return IconProvider.shared.createLayeredFolderIcon(
                        color: folderColor,
                        size: 32,
                        cornerRadius: 4
                    )
                }
            }()
            
            Image(nsImage: icon)
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
                    Image(systemName: "pencil.circle.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)
                .help("Edit folder settings")
                
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
    }
}

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
    @State private var useCustomAngle: Bool = false
    @State private var slicePositioning: String = "startClockwise"
    @State private var childRingThickness: String = "80"
    @State private var childIconSize: String = "32"
    
    // Icon customization
    @State private var iconName: String = ""
    @State private var folderColorHex: String = "#55C2EE"
    @State private var selectedSortOrder: FolderSortOrder = .modifiedNewest
    
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
                    
                    Picker("Sort By", selection: $selectedSortOrder) {
                        ForEach(FolderSortOrder.allCases, id: \.self) { sortOrder in
                            Label(sortOrder.displayName, systemImage: sortOrder.icon)
                                .tag(sortOrder)
                        }
                    }
                    .help("How items are sorted when you open this folder")
                    
                    // Icon Customization Section
                    Section("Icon Customization") {
                        HStack {
                            TextField("Folder Color (hex)", text: $folderColorHex)
                                .textFieldStyle(.roundedBorder)
                            
                            // Color preview swatch
                            if let color = NSColor(hex: folderColorHex) {
                                Circle()
                                    .fill(Color(nsColor: color))
                                    .frame(width: 20, height: 20)
                                    .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1))
                            } else {
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Image(systemName: "xmark")
                                            .font(.caption2)
                                            .foregroundColor(.red)
                                    )
                            }
                        }
                        .help("Enter a hex color like #55C2EE or #FF9500")
                        
                        TextField("SF Symbol Name (optional)", text: $iconName)
                            .help("e.g., star.fill, camera.fill, music.note")
                        
                        // Live Preview
                        HStack {
                            Text("Preview:")
                                .foregroundColor(.secondary)
                            
                            if let folderColor = NSColor(hex: folderColorHex) {
                                let previewIcon: NSImage = {
                                    let trimmedIcon = iconName.trimmingCharacters(in: .whitespaces)
                                    if trimmedIcon.isEmpty {
                                        return IconProvider.shared.createLayeredFolderIcon(
                                            color: folderColor,
                                            size: 48,
                                            cornerRadius: 4
                                        )
                                    } else {
                                        return IconProvider.shared.createLayeredFolderIconWithSymbol(
                                            color: folderColor,
                                            symbolName: trimmedIcon,
                                            symbolColor: .white,
                                            size: 48,
                                            symbolSize: 20,
                                            cornerRadius: 4,
                                            symbolOffset: -4
                                        )
                                    }
                                }()
                                
                                Image(nsImage: previewIcon)
                                    .frame(width: 48, height: 48)
                            } else {
                                Text("Invalid hex")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                            
                            // Symbol validation
                            if !iconName.trimmingCharacters(in: .whitespaces).isEmpty {
                                if NSImage(systemSymbolName: iconName.trimmingCharacters(in: .whitespaces), accessibilityDescription: nil) == nil {
                                    Text("Invalid symbol")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }
                            }
                            
                            Spacer()
                        }
                    }
                    
                    Section("Layout") {
                        Picker("Preferred Layout", selection: $selectedLayout) {
                            Text("Full Circle").tag("fullCircle")
                            Text("Partial Slice").tag("partialSlice")
                        }
                        
                        Toggle("Use Custom Angle", isOn: $useCustomAngle)
                            .help("When OFF, uses smart default angle calculation. When ON, uses custom angle below.")
                        
                        TextField("Item Angle (degrees)", text: $itemAngleSize)
                            .help("Angle per item: 15-60 degrees")
                            .disabled(!useCustomAngle)
                        
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
            .frame(height: 450)
            
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
            loadCurrentSettings()
        }
        .padding()
        .frame(width: 500, height: 600)
    }
    
    private func loadCurrentSettings() {
        // Load layout settings
        if let settings = currentSettings {
            selectedLayout = settings.preferredLayout ?? "fullCircle"
            itemAngleSize = settings.itemAngleSize.map { String($0) } ?? "30"
            slicePositioning = settings.slicePositioning ?? "startClockwise"
            childRingThickness = settings.childRingThickness.map { String($0) } ?? "80"
            childIconSize = settings.childIconSize.map { String($0) } ?? "32"
            useCustomAngle = settings.itemAngleSize != nil
            selectedSortOrder = settings.contentSortOrder ?? .modifiedNewest
        }
        
        // Load icon settings from folder entry
        if let existingIconName = folder.iconName {
            iconName = existingIconName
        }
        
        // Load folder color hex (or default to blue)
        if let existingColorHex = folder.iconColorHex, !existingColorHex.isEmpty {
            folderColorHex = existingColorHex
        } else {
            folderColorHex = "#55C2EE"
        }
    }
    
    private func saveChanges() {
        // Parse numeric values
        let maxItemsValue = Int(maxItems.trimmingCharacters(in: .whitespaces))
        let itemAngleValue = useCustomAngle ? Int(itemAngleSize.trimmingCharacters(in: .whitespaces)) : nil
        let thicknessValue = Int(childRingThickness.trimmingCharacters(in: .whitespaces))
        let iconSizeValue = Int(childIconSize.trimmingCharacters(in: .whitespaces))
        
        let settings = FavoriteFolderSettings(
            maxItems: maxItemsValue,
            preferredLayout: selectedLayout,
            itemAngleSize: itemAngleValue,
            slicePositioning: slicePositioning,
            childRingThickness: thicknessValue,
            childIconSize: iconSizeValue,
            contentSortOrder: selectedSortOrder
        )
        
        // Update layout settings in database
        if DatabaseManager.shared.updateFavoriteSettings(path: folder.path, title: name, settings: settings) {
            print("✅ Updated favorite settings for: \(folder.title)")
            
            // Update icon customization
            let trimmedIconName = iconName.trimmingCharacters(in: .whitespaces)
            let trimmedColorHex = folderColorHex.trimmingCharacters(in: .whitespaces)
            
            // Validate hex before saving
            let colorToSave = NSColor(hex: trimmedColorHex) != nil ? trimmedColorHex : "#55C2EE"
            
            DatabaseManager.shared.setFolderIcon(
                path: folder.path,
                iconName: trimmedIconName.isEmpty ? nil : trimmedIconName,
                iconColorHex: colorToSave,
                baseAsset: "folder-layered",
                symbolSize: 24,
                symbolOffset: -4
            )
            
            print("✅ Updated folder color: \(colorToSave)")
            
            onSave()
        } else {
            print("❌ Failed to update favorite settings")
        }
    }
}
