//
//  FavoriteFilesProvider.swift
//  Jason
//
//  Created by Timothy Velberg on 04/11/2025.
//  Provider for favorite files (static and dynamic/rule-based)

import Foundation
import AppKit

class FavoriteFilesProvider: ObservableObject, FunctionProvider {
    
    // MARK: - FunctionProvider Protocol
    
    var providerId: String {
        return "favorite-files"
    }
    
    var providerName: String {
        return "Favorite Files"
    }
    
    var providerIcon: NSImage {
        return NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil) ?? NSImage()
    }
    
    // MARK: - Properties
    
    weak var circularUIManager: CircularUIManager?
    
    private struct FileEntry {
        let id: String
        let displayName: String
        let filePath: String
        let icon: NSImage
        let isStatic: Bool
        let isDynamic: Bool
        let dynamicId: Int? // For dynamic files
        let sortOrder: Int
        let customIconData: Data?
    }
    
    private var fileEntries: [FileEntry] = []
    
    // MARK: - Initialization
    
    init() {
        print("📁 FavoriteFilesProvider initialized")
        loadFiles()
    }
    
    // MARK: - File Loading
    
    private func loadFiles() {
        var entries: [FileEntry] = []
        
        // 1. Load static favorite files
        let staticFiles = DatabaseManager.shared.getFavoriteFiles()
        print("📋 [FavoriteFiles] Loaded \(staticFiles.count) static favorite files")
        
        for file in staticFiles {
            // Check if file exists
            let fileURL = URL(fileURLWithPath: file.path)
            guard FileManager.default.fileExists(atPath: file.path) else {
                print("⚠️ [FavoriteFiles] Static file not found: \(file.path)")
                continue
            }
            
            // Get display name
            let displayName = file.displayName ?? fileURL.lastPathComponent
            
            // Get icon
            let icon: NSImage
            if let iconData = file.iconData, let customIcon = NSImage(data: iconData) {
                icon = customIcon
            } else {
                icon = NSWorkspace.shared.icon(forFile: file.path)
            }
            
            entries.append(FileEntry(
                id: "static-file-\(file.path)",
                displayName: displayName,
                filePath: file.path,
                icon: icon,
                isStatic: true,
                isDynamic: false,
                dynamicId: nil,
                sortOrder: file.sortOrder,
                customIconData: file.iconData
            ))
        }
        
        // 2. Load dynamic favorite files
        let dynamicFiles = DatabaseManager.shared.getFavoriteDynamicFiles()
        print("📋 [FavoriteFiles] Loaded \(dynamicFiles.count) dynamic favorite files")
        
        for dynamic in dynamicFiles {
            // Execute the query to find the matching file
            if let resolvedPath = resolveDynamicFile(dynamic) {
                // Get icon
                let icon: NSImage
                if let iconData = dynamic.iconData, let customIcon = NSImage(data: iconData) {
                    icon = customIcon
                } else {
                    icon = NSWorkspace.shared.icon(forFile: resolvedPath)
                }
                
                entries.append(FileEntry(
                    id: "dynamic-file-\(dynamic.id ?? 0)",
                    displayName: dynamic.displayName,
                    filePath: resolvedPath,
                    icon: icon,
                    isStatic: false,
                    isDynamic: true,
                    dynamicId: dynamic.id,
                    sortOrder: dynamic.sortOrder,
                    customIconData: dynamic.iconData
                ))
            } else {
                print("⚠️ [FavoriteFiles] No file found for dynamic rule: \(dynamic.displayName)")
                
                // Still add entry but with placeholder icon
                let icon = dynamic.iconData.flatMap { NSImage(data: $0) } ??
                          NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil) ?? NSImage()
                
                entries.append(FileEntry(
                    id: "dynamic-file-\(dynamic.id ?? 0)",
                    displayName: "\(dynamic.displayName) (not found)",
                    filePath: "", // Empty path indicates no file found
                    icon: icon,
                    isStatic: false,
                    isDynamic: true,
                    dynamicId: dynamic.id,
                    sortOrder: dynamic.sortOrder,
                    customIconData: dynamic.iconData
                ))
            }
        }
        
        // Sort by sortOrder
        entries.sort { $0.sortOrder < $1.sortOrder }
        
        fileEntries = entries
        
        print("✅ [FavoriteFiles] Total files: \(fileEntries.count)")
        print("   📄 Static: \(entries.filter { $0.isStatic }.count)")
        print("   🔄 Dynamic: \(entries.filter { $0.isDynamic }.count)")
    }
    
    // MARK: - Dynamic File Resolution
    
    private func resolveDynamicFile(_ dynamic: FavoriteDynamicFileEntry) -> String? {
        let folderURL = URL(fileURLWithPath: dynamic.folderPath)
        
        // Check if folder exists
        guard FileManager.default.fileExists(atPath: dynamic.folderPath) else {
            print("⚠️ [FavoriteFiles] Folder not found: \(dynamic.folderPath)")
            return nil
        }
        
        // Get folder contents
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            print("⚠️ [FavoriteFiles] Cannot read folder: \(dynamic.folderPath)")
            return nil
        }
        
        // Filter files (not directories)
        var files = contents.filter { url in
            guard let isDirectory = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory else {
                return false
            }
            return !isDirectory
        }
        
        // Apply file extension filter if specified
        if let extensions = dynamic.fileExtensions, !extensions.isEmpty {
            let extArray = extensions.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces).lowercased() }
            files = files.filter { url in
                let ext = url.pathExtension.lowercased()
                return extArray.contains(ext)
            }
        }
        
        // Apply name pattern filter if specified
        if let pattern = dynamic.namePattern, !pattern.isEmpty {
            files = files.filter { url in
                url.lastPathComponent.contains(pattern)
            }
        }
        
        // Apply query type sorting
        switch dynamic.queryType {
        case "most_recent", "modified_newest":
            // Sort by modification date (newest first)
            files.sort { url1, url2 in
                guard let date1 = try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      let date2 = try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
                    return false
                }
                return date1 > date2
            }
            
        case "newest_creation", "created_newest":
            // Sort by creation date (newest first)
            files.sort { url1, url2 in
                guard let date1 = try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate,
                      let date2 = try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate else {
                    return false
                }
                return date1 > date2
            }
            
        case "largest":
            // Sort by file size (largest first)
            files.sort { url1, url2 in
                guard let size1 = try? url1.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      let size2 = try? url2.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                    return false
                }
                return size1 > size2
            }
            
        case "smallest":
            // Sort by file size (smallest first)
            files.sort { url1, url2 in
                guard let size1 = try? url1.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      let size2 = try? url2.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                    return false
                }
                return size1 < size2
            }
            
        case "alphabetical":
            // Sort alphabetically
            files.sort { url1, url2 in
                url1.lastPathComponent.localizedCaseInsensitiveCompare(url2.lastPathComponent) == .orderedAscending
            }
            
        default:
            print("⚠️ [FavoriteFiles] Unknown query type: \(dynamic.queryType)")
        }
        
        // Return the first (best matching) file
        return files.first?.path
    }
    
    // MARK: - Provide Functions
    
    func provideFunctions() -> [FunctionNode] {
        loadFiles() // Refresh data
        
        // Create nodes for each file
        let fileNodes: [FunctionNode] = fileEntries.map { entry in
            createFileNode(from: entry)
        }
        
        if fileNodes.isEmpty {
            // Return empty state node
            return [
                FunctionNode(
                    id: "no-favorite-files",
                    name: "No Favorite Files",
                    icon: NSImage(systemSymbolName: "star.slash", accessibilityDescription: nil) ?? NSImage(),
                    preferredLayout: .partialSlice,
                    onLeftClick: ModifierAwareInteraction(base: .doNothing),
                    onRightClick: ModifierAwareInteraction(base: .doNothing),
                    onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                    onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
                )
            ]
        }
        
        return [
            FunctionNode(
                id: providerId,
                name: providerName,
                icon: providerIcon,
                children: fileNodes,
                preferredLayout: .partialSlice,
                slicePositioning: .center,
                providerId: providerId,
                onLeftClick: ModifierAwareInteraction(base: .expand),
                onRightClick: ModifierAwareInteraction(base: .doNothing),
                onMiddleClick: ModifierAwareInteraction(base: .expand),
                onBoundaryCross: ModifierAwareInteraction(base: .expand)
            )
        ]
    }
    
    private func createFileNode(from entry: FileEntry) -> FunctionNode {
        var contextActions: [FunctionNode] = []
        
        // Only add actions if file exists (path is not empty)
        if !entry.filePath.isEmpty {
            // Reveal in Finder
            contextActions.append(
                FunctionNode(
                    id: "\(entry.id)-reveal",
                    name: "Reveal in Finder",
                    icon: NSImage(systemSymbolName: "folder", accessibilityDescription: nil) ?? NSImage(),
                    onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                        self?.revealInFinder(path: entry.filePath)
                    }),
                    onMiddleClick: ModifierAwareInteraction(base: .executeKeepOpen { [weak self] in
                        self?.revealInFinder(path: entry.filePath)
                    })
                )
            )
            
            // Get Info
            contextActions.append(
                FunctionNode(
                    id: "\(entry.id)-info",
                    name: "Get Info",
                    icon: NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil) ?? NSImage(),
                    onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                        self?.showInfo(path: entry.filePath)
                    }),
                    onMiddleClick: ModifierAwareInteraction(base: .executeKeepOpen { [weak self] in
                        self?.showInfo(path: entry.filePath)
                    })
                )
            )
        }
        
        // Remove from favorites (always available)
        if entry.isStatic {
            contextActions.append(
                FunctionNode(
                    id: "\(entry.id)-remove",
                    name: "Remove from Favorites",
                    icon: NSImage(systemSymbolName: "star.slash", accessibilityDescription: nil) ?? NSImage(),
                    onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                        self?.removeFromFavorites(path: entry.filePath)
                    }),
                    onMiddleClick: ModifierAwareInteraction(base: .executeKeepOpen { [weak self] in
                        self?.removeFromFavorites(path: entry.filePath)
                    })
                )
            )
        } else if entry.isDynamic, let dynamicId = entry.dynamicId {
            contextActions.append(
                FunctionNode(
                    id: "\(entry.id)-remove",
                    name: "Remove from Favorites",
                    icon: NSImage(systemSymbolName: "star.slash", accessibilityDescription: nil) ?? NSImage(),
                    onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                        self?.removeDynamicFromFavorites(id: dynamicId)
                    }),
                    onMiddleClick: ModifierAwareInteraction(base: .executeKeepOpen { [weak self] in
                        self?.removeDynamicFromFavorites(id: dynamicId)
                    })
                )
            )
        }
        
        // Create the main node
        return FunctionNode(
            id: entry.id,
            name: entry.displayName,
            icon: entry.icon,
            contextActions: contextActions,
            preferredLayout: .partialSlice,
            previewURL: entry.filePath.isEmpty ? nil : URL(fileURLWithPath: entry.filePath),
            showLabel: true,
            metadata: [
                "filePath": entry.filePath,
                "isStatic": entry.isStatic,
                "isDynamic": entry.isDynamic,
                "sortOrder": entry.sortOrder
            ],
            onLeftClick: ModifierAwareInteraction(base: entry.filePath.isEmpty ? .doNothing : .execute { [weak self] in
                self?.openFile(path: entry.filePath, entry: entry)
            }),
            onRightClick: ModifierAwareInteraction(base: contextActions.isEmpty ? .doNothing : .expand),
            onMiddleClick: ModifierAwareInteraction(base: entry.filePath.isEmpty ? .doNothing : .executeKeepOpen { [weak self] in
                self?.openFile(path: entry.filePath, entry: entry)
            }),
            onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
        )
    }
    
    func refresh() {
        print("🔄 [FavoriteFiles] Refreshing files")
        loadFiles()
    }
    
    func loadChildren(for node: FunctionNode) async -> [FunctionNode] {
        // Favorite files don't have dynamic children
        return []
    }
    
    // MARK: - File Actions
    
    private func openFile(path: String, entry: FileEntry) {
        let fileURL = URL(fileURLWithPath: path)
        
        // Track access for static files
        if entry.isStatic {
            DatabaseManager.shared.updateFileAccess(path: path)
        } else if entry.isDynamic, let dynamicId = entry.dynamicId {
            DatabaseManager.shared.updateDynamicFileAccess(id: dynamicId)
        }
        
        // Open the file
        NSWorkspace.shared.open(fileURL)
        print("📂 [FavoriteFiles] Opened file: \(entry.displayName)")
    }
    
    private func revealInFinder(path: String) {
        let fileURL = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        print("👁️ [FavoriteFiles] Revealed in Finder: \(path)")
    }
    
    private func showInfo(path: String) {
        let fileURL = URL(fileURLWithPath: path)
        
        let script = """
        tell application "Finder"
            activate
            open information window of (POSIX file "\(path)" as alias)
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            
            if let error = error {
                print("❌ [FavoriteFiles] Failed to show info: \(error)")
            } else {
                print("ℹ️ [FavoriteFiles] Showed info for: \(path)")
            }
        }
    }
    
    // MARK: - Favorite Management
    
    private func removeFromFavorites(path: String) {
        let success = DatabaseManager.shared.removeFavoriteFile(path: path)
        if success {
            print("✅ [FavoriteFiles] Removed from favorites: \(path)")
            refresh()
            NotificationCenter.default.postProviderUpdate(providerId: providerId)
        }
    }
    
    private func removeDynamicFromFavorites(id: Int) {
        let success = DatabaseManager.shared.removeFavoriteDynamicFile(id: id)
        if success {
            print("✅ [FavoriteFiles] Removed dynamic file from favorites: \(id)")
            refresh()
            NotificationCenter.default.postProviderUpdate(providerId: providerId)
        }
    }
    
    // MARK: - Public Helper Methods
    
    /// Add a static file to favorites
    func addFavoriteFile(path: String, displayName: String? = nil, iconData: Data? = nil) -> Bool {
        let success = DatabaseManager.shared.addFavoriteFile(path: path, displayName: displayName, iconData: iconData)
        if success {
            refresh()
            NotificationCenter.default.postProviderUpdate(providerId: providerId)
        }
        return success
    }
    
    /// Add a dynamic file rule to favorites
    func addFavoriteDynamicFile(
        displayName: String,
        folderPath: String,
        queryType: String,
        fileExtensions: String? = nil,
        namePattern: String? = nil,
        iconData: Data? = nil
    ) -> Bool {
        let success = DatabaseManager.shared.addFavoriteDynamicFile(
            displayName: displayName,
            folderPath: folderPath,
            queryType: queryType,
            fileExtensions: fileExtensions,
            namePattern: namePattern,
            iconData: iconData
        )
        if success {
            refresh()
            NotificationCenter.default.postProviderUpdate(providerId: providerId)
        }
        return success
    }
    
    /// Update a static favorite file
    func updateFavoriteFile(path: String, displayName: String?, iconData: Data?) -> Bool {
        let success = DatabaseManager.shared.updateFavoriteFile(path: path, displayName: displayName, iconData: iconData)
        if success {
            refresh()
            NotificationCenter.default.postProviderUpdate(providerId: providerId)
        }
        return success
    }
    
    /// Update a dynamic favorite file
    func updateFavoriteDynamicFile(
        id: Int,
        displayName: String,
        folderPath: String,
        queryType: String,
        fileExtensions: String?,
        namePattern: String?,
        iconData: Data?
    ) -> Bool {
        let success = DatabaseManager.shared.updateFavoriteDynamicFile(
            id: id,
            displayName: displayName,
            folderPath: folderPath,
            queryType: queryType,
            fileExtensions: fileExtensions,
            namePattern: namePattern,
            iconData: iconData
        )
        if success {
            refresh()
            NotificationCenter.default.postProviderUpdate(providerId: providerId)
        }
        return success
    }
    
    /// Reorder favorite files
    func reorderFavorites(from sourceIndex: Int, to destinationIndex: Int) -> Bool {
        // Get all files sorted by current sort order
        var allFiles = fileEntries
        
        // Perform the move
        let movedFile = allFiles.remove(at: sourceIndex)
        allFiles.insert(movedFile, at: destinationIndex)
        
        // Update sort orders in database
        for (index, entry) in allFiles.enumerated() {
            if entry.isStatic {
                _ = DatabaseManager.shared.reorderFavoriteFile(path: entry.filePath, newSortOrder: index)
            } else if entry.isDynamic, let dynamicId = entry.dynamicId {
                _ = DatabaseManager.shared.reorderFavoriteDynamicFile(id: dynamicId, newSortOrder: index)
            }
        }
        
        refresh()
        NotificationCenter.default.postProviderUpdate(providerId: providerId)
        return true
    }
}
