//
//  FavoriteFoldersViews.swift
//  Jason
//
//  Created by Timothy Velberg on 24/11/2025.
//

import SwiftUI
import AppKit

struct FavoriteFoldersViews: View {
    @State private var favorites: [(folder: FolderEntry, settings: FavoriteFolderSettings)] = []
    @State private var editingFavorite: FolderEntry?
    @State private var editingName: String = ""
    @State private var newFolderPath: String = ""
    
    var body: some View {
        SettingsListShell(
            title: "Folders",
            emptyIcon: "folder.badge.plus",
            emptyTitle: "No favourites yet",
            emptySubtitle: "Paste a folder path below and tap Add",
            primaryLabel: "Add Folder",
            primaryAction: addFolder,
            secondaryLabel: nil,
            secondaryAction: nil,
            isEmpty: favorites.isEmpty
        ) {
            ForEach(favorites, id: \.folder.id) { item in
                FolderRow(folder: item.folder) {
                    editingFavorite = item.folder
                    editingName = item.folder.title
                } onDelete: {
                    removeFavorite(item.folder)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            .onMove(perform: moveFolder)
        }
        .onAppear { loadFavorites() }
        .sheet(item: $editingFavorite) { folder in
            let currentSettings = favorites.first(where: { $0.folder.id == folder.id })?.settings
            EditFavoriteView(
                folder: folder,
                name: $editingName,
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
    }
    
    private func addFolder() {
        let path = newFolderPath.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return }
        let title = URL(fileURLWithPath: path).lastPathComponent
        if DatabaseManager.shared.addFavoriteFolder(path: path, title: title, settings: nil) {
            newFolderPath = ""
            loadFavorites()
        }
    }
    
    private func removeFavorite(_ folder: FolderEntry) {
        if DatabaseManager.shared.removeFavoriteFolder(path: folder.path) {
            FolderWatcherManager.shared.reconcileWatchers()
            DatabaseManager.shared.reconcileEnhancedCache()
            loadFavorites()
        }
    }
    
    private func moveFolder(from source: IndexSet, to destination: Int) {
        favorites.move(fromOffsets: source, toOffset: destination)
        guard let sourceIndex = source.first else { return }
        let actualDestination = sourceIndex < destination ? destination - 1 : destination
        if !DatabaseManager.shared.reorderFavoriteFolders(from: sourceIndex, to: actualDestination) {
            loadFavorites()
        }
    }
}

// MARK: - Edit Favourite View

struct EditFavoriteView: View {
    @Environment(\.dismiss) var dismiss
    let folder: FolderEntry
    @Binding var name: String
    let currentSettings: FavoriteFolderSettings?
    let onSave: () -> Void
    
    @State private var iconName: String = ""
    @State private var folderColorHex: String = "#55C2EE"
    @State private var selectedSortOrder: FolderSortOrder = .modifiedNewest
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Favourite: \(folder.title)")
                .font(.title2)
                .fontWeight(.semibold)
            
            Form {
                Section("Basic Settings") {
                    TextField("Name", text: $name)
                }
                
                Picker("Sort By", selection: $selectedSortOrder) {
                    ForEach(FolderSortOrder.allCases, id: \.self) { sortOrder in
                        Label(sortOrder.displayName, systemImage: sortOrder.icon)
                            .tag(sortOrder)
                    }
                }
                .help("How items are sorted when you open this folder")
                
                Section("Icon Customization") {
                    HStack {
                        TextField("Folder Color (hex)", text: $folderColorHex)
                            .textFieldStyle(.roundedBorder)
                        
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
                    
                    HStack {
                        Text("Preview:")
                            .foregroundColor(.secondary)
                        
                        if let folderColor = NSColor(hex: folderColorHex) {
                            let previewIcon: NSImage = {
                                let trimmed = iconName.trimmingCharacters(in: .whitespaces)
                                if trimmed.isEmpty {
                                    return IconProvider.shared.createLayeredFolderIcon(
                                        color: folderColor, size: 48, cornerRadius: 4)
                                } else {
                                    return IconProvider.shared.createLayeredFolderIconWithSymbol(
                                        color: folderColor, symbolName: trimmed,
                                        symbolColor: .white, size: 48, symbolSize: 20,
                                        cornerRadius: 4, symbolOffset: -4)
                                }
                            }()
                            Image(nsImage: previewIcon)
                                .frame(width: 48, height: 48)
                        } else {
                            Text("Invalid hex").foregroundColor(.red).font(.caption)
                        }
                        
                        if !iconName.trimmingCharacters(in: .whitespaces).isEmpty {
                            if NSImage(systemSymbolName: iconName.trimmingCharacters(in: .whitespaces), accessibilityDescription: nil) == nil {
                                Text("Invalid symbol").foregroundColor(.red).font(.caption)
                            }
                        }
                        
                        Spacer()
                    }
                }
            }
            
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                
                Button("Save") { saveChanges() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .onAppear { loadCurrentSettings() }
        .padding()
        .frame(width: 500, height: 420)
    }
    
    private func loadCurrentSettings() {
        if let settings = currentSettings {
            selectedSortOrder = settings.contentSortOrder ?? .modifiedNewest
        }
        if let existingIconName = folder.iconName {
            iconName = existingIconName
        }
        if let existingColorHex = folder.iconColorHex, !existingColorHex.isEmpty {
            folderColorHex = existingColorHex
        } else {
            folderColorHex = "#55C2EE"
        }
    }
    
    private func saveChanges() {
        let settings = FavoriteFolderSettings(
            maxItems: nil,
            preferredLayout: nil,
            itemAngleSize: nil,
            slicePositioning: nil,
            childRingThickness: nil,
            childIconSize: nil,
            contentSortOrder: selectedSortOrder
        )
        
        if DatabaseManager.shared.updateFavoriteSettings(path: folder.path, title: name, settings: settings) {
            let trimmedIconName = iconName.trimmingCharacters(in: .whitespaces)
            let trimmedColorHex = folderColorHex.trimmingCharacters(in: .whitespaces)
            let colorToSave = NSColor(hex: trimmedColorHex) != nil ? trimmedColorHex : "#55C2EE"
            
            DatabaseManager.shared.setFolderIcon(
                path: folder.path,
                iconName: trimmedIconName.isEmpty ? nil : trimmedIconName,
                iconColorHex: colorToSave,
                baseAsset: "folder-layered",
                symbolSize: 24,
                symbolOffset: -4
            )
            onSave()
        }
    }
}

// MARK: - Folder Row

private struct FolderRow: View {
    let folder: FolderEntry
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    private var folderIcon: NSImage {
        let color = folder.iconColor ?? NSColor(hex: "#55C2EE") ?? .systemBlue
        if let symbolName = folder.iconName, !symbolName.isEmpty {
            return IconProvider.shared.createLayeredFolderIconWithSymbol(
                color: color,
                symbolName: symbolName,
                symbolColor: .white,
                size: 32,
                symbolSize: 14,
                cornerRadius: 4,
                symbolOffset: -2
            )
        } else {
            return IconProvider.shared.createLayeredFolderIcon(color: color, size: 32, cornerRadius: 4)
        }
    }
    
    var body: some View {
        SettingsRow(
            icon: .nsImage(folderIcon),
            title: folder.title,
            subtitle: folder.path,
            showDragHandle: true,
            onEdit: onEdit,
            onDelete: onDelete
        )
    }
}
