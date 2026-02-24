//
//  FavoriteFilesSettingsView.swift
//  Jason
//
//  Created by Timothy Velberg on 04/11/2025.
//

import SwiftUI
import AppKit

struct FavoriteFilesSettingsView: View {
    @State private var staticFiles: [FavoriteFileEntry] = []
    @State private var dynamicFiles: [FavoriteDynamicFileEntry] = []
    
    @State private var showingDynamicFileCreator = false
    @State private var editingStaticFile: FavoriteFileEntry?
    @State private var editingDynamicFile: FavoriteDynamicFileEntry?
    
    private var allEntries: [(id: String, entry: Any, listSortOrder: Int, isStatic: Bool)] {
        var combined: [(id: String, entry: Any, listSortOrder: Int, isStatic: Bool)] = []
        for file in staticFiles {
            combined.append((id: "static-\(file.path)", entry: file, listSortOrder: file.sortOrder, isStatic: true))
        }
        for file in dynamicFiles {
            combined.append((id: "dynamic-\(file.id ?? 0)", entry: file, listSortOrder: file.listSortOrder, isStatic: false))
        }
        return combined.sorted { $0.listSortOrder < $1.listSortOrder }
    }
    
    var body: some View {
        SettingsListShell(
            title: "Files",
            emptyIcon: "star.slash",
            emptyTitle: "No favourite files yet",
            emptySubtitle: "Add static files or create dynamic file rules",
            primaryLabel: "Add File",
            primaryAction: showFilePicker,
            secondaryLabel: "Add Rule",
            secondaryAction: { showingDynamicFileCreator = true },
            isEmpty: allEntries.isEmpty
        ) {
            ForEach(Array(allEntries.enumerated()), id: \.element.id) { _, item in
                if item.isStatic, let file = item.entry as? FavoriteFileEntry {
                    StaticFileRow(file: file) {
                        editingStaticFile = file
                    } onDelete: {
                        removeStaticFile(file)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                } else if !item.isStatic, let file = item.entry as? FavoriteDynamicFileEntry {
                    DynamicFileRow(file: file) {
                        editingDynamicFile = file
                    } onDelete: {
                        removeDynamicFile(file)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }
            .onMove(perform: moveFile)
        }
        .onAppear { loadFavoriteFiles() }
        .sheet(isPresented: $showingDynamicFileCreator) {
            AddDynamicFileView(
                onSave: { displayName, folderPath, sortOrder, extensions, pattern in
                    addDynamicFile(displayName: displayName, folderPath: folderPath, sortOrder: sortOrder, extensions: extensions, pattern: pattern)
                    showingDynamicFileCreator = false
                },
                onCancel: { showingDynamicFileCreator = false }
            )
        }
        .sheet(item: $editingStaticFile) { file in
            EditFavoriteFileView(
                file: file,
                onSave: { displayName, iconData in
                    updateStaticFile(file, displayName: displayName, iconData: iconData)
                    editingStaticFile = nil
                },
                onCancel: { editingStaticFile = nil }
            )
        }
        .sheet(item: $editingDynamicFile) { file in
            EditFavoriteDynamicFileView(
                file: file,
                onSave: { displayName, folderPath, sortOrder, extensions, pattern, iconData in
                    updateDynamicFile(file, displayName: displayName, folderPath: folderPath, sortOrder: sortOrder, extensions: extensions, pattern: pattern, iconData: iconData)
                    editingDynamicFile = nil
                },
                onCancel: { editingDynamicFile = nil }
            )
        }
    }
    
    // MARK: - Actions
    
    private func loadFavoriteFiles() {
        staticFiles = DatabaseManager.shared.getFavoriteFiles()
        dynamicFiles = DatabaseManager.shared.getFavoriteDynamicFiles()
    }
    
    private func showFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a file to add to favourites"
        if panel.runModal() == .OK, let url = panel.url {
            addStaticFile(path: url.path)
        }
    }
    
    private func addStaticFile(path: String) {
        if DatabaseManager.shared.addFavoriteFile(path: path, displayName: nil, iconData: nil) {
            loadFavoriteFiles()
            notifyProvider()
        }
    }
    
    private func addDynamicFile(displayName: String, folderPath: String, sortOrder: FolderSortOrder, extensions: String?, pattern: String?) {
        if DatabaseManager.shared.addFavoriteDynamicFile(displayName: displayName, folderPath: folderPath, sortOrder: sortOrder, fileExtensions: extensions, namePattern: pattern, iconData: nil) {
            loadFavoriteFiles()
            notifyProvider()
        }
    }
    
    private func removeStaticFile(_ file: FavoriteFileEntry) {
        if DatabaseManager.shared.removeFavoriteFile(path: file.path) {
            loadFavoriteFiles()
            notifyProvider()
        }
    }
    
    private func removeDynamicFile(_ file: FavoriteDynamicFileEntry) {
        guard let id = file.id else { return }
        if DatabaseManager.shared.removeFavoriteDynamicFile(id: id) {
            FolderWatcherManager.shared.reconcileWatchers()
            DatabaseManager.shared.reconcileEnhancedCache()
            loadFavoriteFiles()
            notifyProvider()
        }
    }
    
    private func updateStaticFile(_ file: FavoriteFileEntry, displayName: String?, iconData: Data?) {
        if DatabaseManager.shared.updateFavoriteFile(path: file.path, displayName: displayName, iconData: iconData) {
            loadFavoriteFiles()
            notifyProvider()
        }
    }
    
    private func updateDynamicFile(_ file: FavoriteDynamicFileEntry, displayName: String, folderPath: String, sortOrder: FolderSortOrder, extensions: String?, pattern: String?, iconData: Data?) {
        guard let id = file.id else { return }
        if DatabaseManager.shared.updateFavoriteDynamicFile(id: id, displayName: displayName, folderPath: folderPath, sortOrder: sortOrder, fileExtensions: extensions, namePattern: pattern, iconData: iconData) {
            loadFavoriteFiles()
            notifyProvider()
        }
    }
    
    private func moveFile(from source: IndexSet, to destination: Int) {
        guard let sourceIndex = source.first else { return }
        var entries = allEntries
        let movedEntry = entries.remove(at: sourceIndex)
        let actualDestination = sourceIndex < destination ? destination - 1 : destination
        entries.insert(movedEntry, at: actualDestination)
        for (index, entry) in entries.enumerated() {
            if entry.isStatic, let file = entry.entry as? FavoriteFileEntry {
                _ = DatabaseManager.shared.reorderFavoriteFile(path: file.path, newSortOrder: index)
            } else if !entry.isStatic, let file = entry.entry as? FavoriteDynamicFileEntry, let id = file.id {
                _ = DatabaseManager.shared.reorderFavoriteDynamicFile(id: id, newSortOrder: index)
            }
        }
        loadFavoriteFiles()
        notifyProvider()
    }
    
    private func notifyProvider() {
        NotificationCenter.default.postProviderUpdate(providerId: "favorite-files")
    }
}

// MARK: - Static File Row

private struct StaticFileRow: View {
    let file: FavoriteFileEntry
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var fileIcon: NSImage?
    @State private var fileExists = true
    
    var body: some View {
        SettingsRow(
            icon: fileIcon.map { .nsImage($0) } ?? .systemSymbol("doc.fill", .secondary),
            title: titleText,
            subtitle: file.path,
            showDragHandle: true,
            onEdit: onEdit,
            onDelete: onDelete,
            metadata: {
                HStack(spacing: 6) {
                    if !fileExists {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .help("File not found")
                    }
                    Text("Static")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .cornerRadius(4)
                    if let lastAccessed = file.lastAccessed {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(file.accessCount) opens")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(formatDate(lastAccessed))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 80)
                    }
                }
            }
        )
        .onAppear {
            fileIcon = NSWorkspace.shared.icon(forFile: file.path)
            fileExists = FileManager.default.fileExists(atPath: file.path)
        }
    }
    
    private var titleText: String {
        file.displayName ?? URL(fileURLWithPath: file.path).lastPathComponent
    }
    
    private func formatDate(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Dynamic File Row

private struct DynamicFileRow: View {
    let file: FavoriteDynamicFileEntry
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var fileIcon: NSImage?
    @State private var resolvedFileName: String?
    
    var body: some View {
        SettingsRow(
            icon: fileIcon.map { .nsImage($0) } ?? .systemSymbol("wand.and.stars", .purple),
            title: file.displayName,
            subtitle: subtitleText,
            showDragHandle: true,
            onEdit: onEdit,
            onDelete: onDelete,
            metadata: {
                HStack(spacing: 6) {
                    Text("Dynamic")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple)
                        .cornerRadius(4)
                    if let lastAccessed = file.lastAccessed {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(file.accessCount) opens")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(formatDate(lastAccessed))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 80)
                    }
                }
            }
        )
        .onAppear { resolveFile() }
    }
    
    private var subtitleText: String {
        let folderName = URL(fileURLWithPath: file.folderPath).lastPathComponent
        if let resolved = resolvedFileName {
            return "\(folderName) • \(file.sortOrder.displayName) → \(resolved)"
        } else {
            return "\(folderName) • \(file.sortOrder.displayName) • No file found"
        }
    }
    
    private func resolveFile() {
        DispatchQueue.global(qos: .userInitiated).async {
            let folderURL = URL(fileURLWithPath: file.folderPath)
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            ) else { return }
            
            var files = contents.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false
            }
            
            if let extensions = file.fileExtensions, !extensions.isEmpty {
                let extArray = extensions.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces).lowercased() }
                files = files.filter { extArray.contains($0.pathExtension.lowercased()) }
            }
            
            let sortedFiles = FolderSortingUtility.sortURLs(files, by: file.sortOrder)
            
            if let firstFile = sortedFiles.first {
                DispatchQueue.main.async {
                    self.resolvedFileName = firstFile.lastPathComponent
                    self.fileIcon = NSWorkspace.shared.icon(forFile: firstFile.path)
                }
            }
        }
    }
    
    private func formatDate(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Add Dynamic File View

struct AddDynamicFileView: View {
    let onSave: (String, String, FolderSortOrder, String?, String?) -> Void
    let onCancel: () -> Void
    
    @State private var displayName: String = ""
    @State private var folderPath: String = ""
    @State private var sortOrder: FolderSortOrder = .addedNewest
    @State private var fileExtensions: String = ""
    @State private var namePattern: String = ""
    @State private var useExtensionFilter = false
    @State private var useNamePattern = false
    
    private let sortOptions: [FolderSortOrder] = [
        .addedNewest, .addedOldest, .modifiedNewest, .modifiedOldest,
        .createdNewest, .createdOldest, .sizeDescending, .sizeAscending,
        .alphabeticalAsc, .alphabeticalDesc
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add Dynamic File Rule")
                .font(.title2)
                .fontWeight(.semibold)
            
            Form {
                Section {
                    TextField("Display Name", text: $displayName)
                        .help("e.g., 'Latest Screenshot', 'Newest Download'")
                }
                Section {
                    HStack {
                        TextField("Folder Path", text: $folderPath)
                        Button("Browse") { showFolderPicker() }
                    }
                    Picker("Sort Order", selection: $sortOrder) {
                        ForEach(sortOptions, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
                Section {
                    Toggle("Filter by File Extensions", isOn: $useExtensionFilter)
                    if useExtensionFilter {
                        TextField("Extensions (comma-separated)", text: $fileExtensions)
                            .help("e.g., png,jpg,pdf")
                    }
                    Toggle("Filter by Name Pattern", isOn: $useNamePattern)
                    if useNamePattern {
                        TextField("Name Pattern", text: $namePattern)
                            .help("Files containing this text")
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
                    onSave(displayName, folderPath, sortOrder,
                           useExtensionFilter && !fileExtensions.isEmpty ? fileExtensions : nil,
                           useNamePattern && !namePattern.isEmpty ? namePattern : nil)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(displayName.isEmpty || folderPath.isEmpty)
            }
        }
        .padding()
        .frame(width: 500, height: 500)
    }
    
    private func showFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select folder to monitor"
        if panel.runModal() == .OK, let url = panel.url {
            folderPath = url.path
        }
    }
}

// MARK: - Edit Favourite File View

struct EditFavoriteFileView: View {
    let file: FavoriteFileEntry
    let onSave: (String?, Data?) -> Void
    let onCancel: () -> Void
    
    @State private var displayName: String
    @State private var useCustomName: Bool
    
    init(file: FavoriteFileEntry, onSave: @escaping (String?, Data?) -> Void, onCancel: @escaping () -> Void) {
        self.file = file
        self.onSave = onSave
        self.onCancel = onCancel
        let fileName = URL(fileURLWithPath: file.path).lastPathComponent
        _displayName = State(initialValue: file.displayName ?? fileName)
        _useCustomName = State(initialValue: file.displayName != nil)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Favourite File")
                .font(.title2)
                .fontWeight(.semibold)
            
            Form {
                Section {
                    Text(file.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Section {
                    Toggle("Use Custom Name", isOn: $useCustomName)
                    if useCustomName {
                        TextField("Display Name", text: $displayName)
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
                    onSave(useCustomName && !displayName.isEmpty ? displayName : nil, nil)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(useCustomName && displayName.isEmpty)
            }
        }
        .padding()
        .frame(width: 450, height: 300)
    }
}

// MARK: - Edit Favourite Dynamic File View

struct EditFavoriteDynamicFileView: View {
    let file: FavoriteDynamicFileEntry
    let onSave: (String, String, FolderSortOrder, String?, String?, Data?) -> Void
    let onCancel: () -> Void
    
    @State private var displayName: String
    @State private var folderPath: String
    @State private var sortOrder: FolderSortOrder
    @State private var fileExtensions: String
    @State private var namePattern: String
    @State private var useExtensionFilter: Bool
    @State private var useNamePattern: Bool
    
    private let sortOptions: [FolderSortOrder] = [
        .addedNewest, .addedOldest, .modifiedNewest, .modifiedOldest,
        .createdNewest, .createdOldest, .sizeDescending, .sizeAscending,
        .alphabeticalAsc, .alphabeticalDesc
    ]
    
    init(file: FavoriteDynamicFileEntry, onSave: @escaping (String, String, FolderSortOrder, String?, String?, Data?) -> Void, onCancel: @escaping () -> Void) {
        self.file = file
        self.onSave = onSave
        self.onCancel = onCancel
        _displayName = State(initialValue: file.displayName)
        _folderPath = State(initialValue: file.folderPath)
        _sortOrder = State(initialValue: file.sortOrder)
        _fileExtensions = State(initialValue: file.fileExtensions ?? "")
        _namePattern = State(initialValue: file.namePattern ?? "")
        _useExtensionFilter = State(initialValue: file.fileExtensions != nil)
        _useNamePattern = State(initialValue: file.namePattern != nil)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Dynamic File Rule")
                .font(.title2)
                .fontWeight(.semibold)
            
            Form {
                Section {
                    TextField("Display Name", text: $displayName)
                }
                Section {
                    HStack {
                        TextField("Folder Path", text: $folderPath)
                        Button("Browse") { showFolderPicker() }
                    }
                    Picker("Sort Order", selection: $sortOrder) {
                        ForEach(sortOptions, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
                Section {
                    Toggle("Filter by File Extensions", isOn: $useExtensionFilter)
                    if useExtensionFilter {
                        TextField("Extensions (comma-separated)", text: $fileExtensions)
                            .help("e.g., png,jpg,pdf")
                    }
                    Toggle("Filter by Name Pattern", isOn: $useNamePattern)
                    if useNamePattern {
                        TextField("Name Pattern", text: $namePattern)
                            .help("Files containing this text")
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
                    onSave(displayName, folderPath, sortOrder,
                           useExtensionFilter && !fileExtensions.isEmpty ? fileExtensions : nil,
                           useNamePattern && !namePattern.isEmpty ? namePattern : nil,
                           nil)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(displayName.isEmpty || folderPath.isEmpty)
            }
        }
        .padding()
        .frame(width: 500, height: 500)
    }
    
    private func showFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select folder to monitor"
        if panel.runModal() == .OK, let url = panel.url {
            folderPath = url.path
        }
    }
}
