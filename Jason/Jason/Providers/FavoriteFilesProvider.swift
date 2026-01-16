//
//  FavoriteFilesProvider.swift
//  Jason
//
//  Created by Timothy Velberg on 04/11/2025.
//  Provider for favorite files (static and dynamic/rule-based)
//
//  Updated: Now supports dynamic folders with navigation

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
        return NSImage(named: "parent-files") ?? NSImage()
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
        let listSortOrder: Int
        let customIconData: Data?
        let isDirectory: Bool
        let dynamicSortOrder: FolderSortOrder? // For navigating into dynamic folders
    }
    
    private var fileEntries: [FileEntry] = []
    
    // MARK: - Initialization
    
    init() {
        print("📁 FavoriteFilesProvider initialized")
//        loadFiles()
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
            
            // Check if it's a directory
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory)
            
            // Check if it's a package (.app, .bundle, etc.) - treat as file, not folder
            let isPackage = NSWorkspace.shared.isFilePackage(atPath: file.path)
            let treatAsDirectory = isDirectory.boolValue && !isPackage
            
            // Get display name
            let displayName = file.displayName ?? fileURL.lastPathComponent
            
            // Get icon
            let icon: NSImage
            if let iconData = file.iconData, let customIcon = NSImage(data: iconData) {
                icon = customIcon
            } else if treatAsDirectory {
                icon = IconProvider.shared.getFolderIcon(for: fileURL, size: 64, cornerRadius: 8)
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
                listSortOrder: file.sortOrder,
                customIconData: file.iconData,
                isDirectory: treatAsDirectory,
                dynamicSortOrder: nil
            ))
        }
        
        // 2. Load dynamic favorite files
        let dynamicFiles = DatabaseManager.shared.getFavoriteDynamicFiles()
        print("📋 [FavoriteFiles] Loaded \(dynamicFiles.count) dynamic favorite files")
        
        for dynamic in dynamicFiles {
            // Execute the query to find the matching file/folder
            if let resolvedPath = resolveDynamicFile(dynamic) {
                // Get the actual file name from resolved path
                let resolvedURL = URL(fileURLWithPath: resolvedPath)
                let fileName = resolvedURL.lastPathComponent
                
                // Check if it's a directory
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: resolvedPath, isDirectory: &isDirectory)
                
                // Check if it's a package (.app, .bundle, etc.) - treat as file, not folder
                let isPackage = NSWorkspace.shared.isFilePackage(atPath: resolvedPath)
                let treatAsDirectory = isDirectory.boolValue && !isPackage
                
                // Get icon
                let icon: NSImage
                if let iconData = dynamic.iconData, let customIcon = NSImage(data: iconData) {
                    icon = customIcon
                } else if treatAsDirectory {
                    icon = IconProvider.shared.getFolderIcon(for: resolvedURL, size: 64, cornerRadius: 8)
                } else {
                    icon = NSWorkspace.shared.icon(forFile: resolvedPath)
                }
                
                entries.append(FileEntry(
                    id: "dynamic-file-\(dynamic.id ?? 0)",
                    displayName: fileName,
                    filePath: resolvedPath,
                    icon: icon,
                    isStatic: false,
                    isDynamic: true,
                    dynamicId: dynamic.id,
                    listSortOrder: dynamic.listSortOrder,
                    customIconData: dynamic.iconData,
                    isDirectory: treatAsDirectory,
                    dynamicSortOrder: dynamic.sortOrder
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
                    listSortOrder: dynamic.listSortOrder,
                    customIconData: dynamic.iconData,
                    isDirectory: false,
                    dynamicSortOrder: dynamic.sortOrder
                ))
            }
        }
        
        // Sort by listSortOrder
        entries.sort { $0.listSortOrder < $1.listSortOrder }
        
        fileEntries = entries
        
        print("✅ [FavoriteFiles] Total files: \(fileEntries.count)")
    }
    
    // MARK: - Dynamic File Resolution
    
    private func resolveDynamicFile(_ dynamic: FavoriteDynamicFileEntry) -> String? {
        let folderPath = dynamic.folderPath
        
        // Check if folder exists
        guard FileManager.default.fileExists(atPath: folderPath) else {
            print("⚠️ [FavoriteFiles] Folder not found: \(folderPath)")
            return nil
        }
        
        // 🎯 TRY CACHE FIRST for heavy folders
        if let cachedResult = resolveDynamicFileFromCache(dynamic) {
            print("⚡ [FavoriteFiles] Cache hit for dynamic file: \(dynamic.displayName)")
            return cachedResult
        }
        
        // 📂 CACHE MISS - Fall back to filesystem scan
        print("💿 [FavoriteFiles] Cache miss for '\(dynamic.displayName)' - scanning filesystem")
        return resolveDynamicFileFromFilesystem(dynamic)
    }

    /// Try to resolve dynamic file from enhanced cache
    private func resolveDynamicFileFromCache(_ dynamic: FavoriteDynamicFileEntry) -> String? {
        let db = DatabaseManager.shared
        
        // Only use cache if folder is marked as heavy
        guard db.isHeavyFolder(path: dynamic.folderPath) else {
            return nil
        }
        
        // Check cache freshness before trusting it
        guard let cacheTimestamp = db.getEnhancedCacheTimestamp(folderPath: dynamic.folderPath) else {
            return nil
        }
        
        // Get folder's actual modification date
        let folderURL = URL(fileURLWithPath: dynamic.folderPath)
        if let folderModDate = try? FileManager.default.attributesOfItem(atPath: folderURL.path)[.modificationDate] as? Date {
            if folderModDate > cacheTimestamp {
                print("⏰ [FavoriteFiles] Cache stale for '\(dynamic.displayName)' - folder modified after cache")
                return nil
            }
        }
        
        // Get cached contents
        guard let cachedItems = db.getEnhancedCachedFolderContents(folderPath: dynamic.folderPath) else {
            return nil
        }
        
        // Start with all items (files AND folders now)
        var items = cachedItems
        
        // Apply file extension filter if specified (only applies to files)
        if let extensions = dynamic.fileExtensions, !extensions.isEmpty {
            let extArray = extensions.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces).lowercased() }
            items = items.filter { item in
                // Keep directories (they don't have extensions to filter)
                // Filter files by extension
                item.isDirectory || extArray.contains(item.fileExtension.lowercased())
            }
        }
        
        // Apply name pattern filter if specified
        if let pattern = dynamic.namePattern, !pattern.isEmpty {
            items = items.filter { item in
                item.name.contains(pattern)
            }
        }
        
        // Cache is already sorted by the folder's sort order
        // Return the first matching item
        guard let firstItem = items.first else {
            return nil
        }
        
        // Verify item still exists (cache might be slightly stale)
        guard FileManager.default.fileExists(atPath: firstItem.path) else {
            print("⚠️ [FavoriteFiles] Cached item no longer exists: \(firstItem.path)")
            return nil
        }
        
        return firstItem.path
    }
    
    /// Resolve dynamic file by scanning filesystem (fallback)
    private func resolveDynamicFileFromFilesystem(_ dynamic: FavoriteDynamicFileEntry) -> String? {
        let folderURL = URL(fileURLWithPath: dynamic.folderPath)
        
        // Get folder contents with all required properties for sorting
        guard var items = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            print("⚠️ [FavoriteFiles] Cannot read folder: \(dynamic.folderPath)")
            return nil
        }
        
        // Apply file extension filter if specified (only for files)
        if let extensions = dynamic.fileExtensions, !extensions.isEmpty {
            let extArray = extensions.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces).lowercased() }
            items = items.filter { url in
                // Check if directory - keep all directories
                if let isDir = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir {
                    return true
                }
                // Filter files by extension
                let ext = url.pathExtension.lowercased()
                return extArray.contains(ext)
            }
        }
        
        // Apply name pattern filter if specified
        if let pattern = dynamic.namePattern, !pattern.isEmpty {
            items = items.filter { url in
                url.lastPathComponent.contains(pattern)
            }
        }
        
        // 🎯 Use unified FolderSortingUtility
        let sortedItems = FolderSortingUtility.sortURLs(items, by: dynamic.sortOrder)
        
        // Check if this folder should be cached for future lookups
        if items.count > 100 {
            triggerCachePopulation(for: dynamic.folderPath)
        }
        
        // Return the first (best matching) item
        return sortedItems.first?.path
    }
    
    /// Trigger cache population for a heavy folder that isn't cached yet
    private func triggerCachePopulation(for folderPath: String) {
        let db = DatabaseManager.shared
        
        // Mark as heavy if not already
        if !db.isHeavyFolder(path: folderPath) {
            let itemCount = countFolderItems(at: folderPath)
            db.markAsHeavyFolder(path: folderPath, itemCount: itemCount)
            print("📊 [FavoriteFiles] Marked folder as heavy: \(folderPath) (\(itemCount) items)")
        }
        
        // Queue a refresh to populate the cache
        let folderName = URL(fileURLWithPath: folderPath).lastPathComponent
        FolderWatcherManager.shared.forceRefresh(path: folderPath, name: folderName)
        
        // Start watching for future changes
        FolderWatcherManager.shared.startWatching(path: folderPath, itemName: folderName)
    }
    
    private func countFolderItems(at path: String) -> Int {
        let folderURL = URL(fileURLWithPath: path)
        do {
            let items = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            return items.count
        } catch {
            return 0
        }
    }
    
    // MARK: - Provide Functions
    
    func provideFunctions() -> [FunctionNode] {
        let fileNodes: [FunctionNode] = fileEntries.map { entry in
            createFileNode(from: entry)
        }
        
        if fileNodes.isEmpty {
            return [
                FunctionNode(
                    id: "no-favorite-files",
                    name: "No Favorite Files",
                    type: .action,
                    icon: NSImage(systemSymbolName: "star.slash", accessibilityDescription: nil) ?? NSImage(),
                    preferredLayout: .partialSlice,
                    providerId: providerId,
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
                type: .category,
                icon: providerIcon,
                children: fileNodes,
//                childDisplayMode: .panel,
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
                    type: .action,
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
                    type: .action,
                    icon: NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil) ?? NSImage(),
                    onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                        self?.showInfo(path: entry.filePath)
                    }),
                    onMiddleClick: ModifierAwareInteraction(base: .executeKeepOpen { [weak self] in
                        self?.showInfo(path: entry.filePath)
                    })
                )
            )
            contextActions.append(
                FunctionNode(
                    id: "\(entry.id)-delete",
                    name: "Delete",
                    type: .action,
                    icon: NSImage(systemSymbolName: "trash", accessibilityDescription: nil) ?? NSImage(),
                    onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                        self?.deleteFile(path: entry.filePath)
                    }),
                    onMiddleClick: ModifierAwareInteraction(base: .executeKeepOpen { [weak self] in
                        self?.deleteFile(path: entry.filePath)
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
                    type: .action,
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
                    type: .action,
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
        
        // Build metadata
        var metadata: [String: Any] = [
            "filePath": entry.filePath,
            "isStatic": entry.isStatic,
            "isDynamic": entry.isDynamic,
            "listSortOrder": entry.listSortOrder
        ]
        
        // For directories, add folder navigation metadata
        if entry.isDirectory {
            metadata["folderURL"] = entry.filePath
            if let sortOrder = entry.dynamicSortOrder {
                metadata["sortOrder"] = sortOrder.rawValue
            }
        }
        
        // Create the main node - different behavior for files vs folders
        if entry.isDirectory {
            // FOLDER NODE - draggable + navigable
            let folderURL = URL(fileURLWithPath: entry.filePath)
            return FunctionNode(
                id: entry.id,
                name: entry.displayName,
                type: .folder,
                icon: entry.icon,
                children: nil,  // Will be loaded dynamically
//                childDisplayMode: .panel,
                contextActions: contextActions,
                preferredLayout: .partialSlice,
                previewURL: entry.filePath.isEmpty ? nil : folderURL,
                showLabel: true,
                slicePositioning: .center,
                metadata: metadata,
                providerId: providerId,
                onLeftClick: ModifierAwareInteraction(base: entry.filePath.isEmpty ? .doNothing : .drag(DragProvider(
                    fileURLs: [folderURL],
                    dragImage: entry.icon,
                    allowedOperations: [.move, .copy],
                    clickBehavior: .navigate,
                    onDragStarted: {
                        print("📦 Started dragging folder: \(entry.displayName)")
                    },
                    onDragCompleted: { success in
                        if success {
                            print("✅ Successfully dragged folder: \(entry.displayName)")
                        } else {
                            print("❌ Drag cancelled: \(entry.displayName)")
                        }
                    }
                ))),
                onRightClick: ModifierAwareInteraction(base: contextActions.isEmpty ? .doNothing : .expand),
                onMiddleClick: ModifierAwareInteraction(base: entry.filePath.isEmpty ? .doNothing : .executeKeepOpen { [weak self] in
                    self?.openFile(path: entry.filePath, entry: entry)
                }),
                onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
            )
        } else {
            // FILE NODE - draggable
            return FunctionNode(
                id: entry.id,
                name: entry.displayName,
                type: .file,
                icon: entry.icon,
                contextActions: contextActions,
                preferredLayout: .partialSlice,
                previewURL: entry.filePath.isEmpty ? nil : URL(fileURLWithPath: entry.filePath),
                showLabel: true,
                metadata: metadata,
                onLeftClick: ModifierAwareInteraction(base: entry.filePath.isEmpty ? .doNothing : .drag(DragProvider(
                    fileURLs: [URL(fileURLWithPath: entry.filePath)],
                    dragImage: entry.icon,
                    allowedOperations: [.move, .copy],
                    onClick: { [weak self] in
                        self?.openFile(path: entry.filePath, entry: entry)
                    },
                    onDragStarted: {
                        print("📦 Started dragging: \(entry.displayName)")
                    },
                    onDragCompleted: { success in
                        if success {
                            print("✅ Successfully dragged: \(entry.displayName)")
                        } else {
                            print("❌ Drag cancelled: \(entry.displayName)")
                        }
                    }
                ))),
                onRightClick: ModifierAwareInteraction(base: contextActions.isEmpty ? .doNothing : .expand),
                onMiddleClick: ModifierAwareInteraction(base: entry.filePath.isEmpty ? .doNothing : .executeKeepOpen { [weak self] in
                    self?.openFile(path: entry.filePath, entry: entry)
                }),
                onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
            )
        }
    }
    
    private func addDefaultFavorites() {
        // Downloads - Newest First
        if let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            let settings = FavoriteFolderSettings(
                maxItems: nil,
                preferredLayout: nil,
                itemAngleSize: nil,
                slicePositioning: nil,
                childRingThickness: nil,
                childIconSize: nil,
                contentSortOrder: .modifiedNewest
            )
            _ = DatabaseManager.shared.addFavoriteFolder(
                path: downloadsURL.path,
                title: "Downloads",
                settings: settings
            )
            
            // Also add dynamic file for latest download
            _ = DatabaseManager.shared.addFavoriteDynamicFile(
                displayName: "Latest Download",
                folderPath: downloadsURL.path,
                sortOrder: .modifiedNewest,
                fileExtensions: nil,
                namePattern: nil,
                iconData: nil
            )
        }
        
        // Git folder - Alphabetical
        let gitPath = "/Users/timothy/Files/Git/"
        if FileManager.default.fileExists(atPath: gitPath) {
            let settings = FavoriteFolderSettings(
                maxItems: nil,
                preferredLayout: nil,
                itemAngleSize: nil,
                slicePositioning: nil,
                childRingThickness: nil,
                childIconSize: nil,
                contentSortOrder: .alphabeticalAsc
            )
            _ = DatabaseManager.shared.addFavoriteFolder(
                path: gitPath,
                title: "Git",
                settings: settings
            )
        }
        
        // Screenshots - Newest First
        let screenshotsPath = "/Users/timothy/Library/CloudStorage/Dropbox/Screenshots"
        if FileManager.default.fileExists(atPath: screenshotsPath) {
            let settings = FavoriteFolderSettings(
                maxItems: nil,
                preferredLayout: nil,
                itemAngleSize: nil,
                slicePositioning: nil,
                childRingThickness: nil,
                childIconSize: nil,
                contentSortOrder: .modifiedNewest
            )
            _ = DatabaseManager.shared.addFavoriteFolder(
                path: screenshotsPath,
                title: "Screenshots",
                settings: settings
            )
            
            // Also add dynamic file for latest screenshot
            _ = DatabaseManager.shared.addFavoriteDynamicFile(
                displayName: "Latest Screenshot",
                folderPath: screenshotsPath,
                sortOrder: .modifiedNewest,
                fileExtensions: "png,jpg,jpeg,heic",
                namePattern: nil,
                iconData: nil
            )
        }
        
        print("✅ [FavoriteFolderProvider] Added default favorites with smart sorting")
    }
    
    func refresh() {
        print("🔄 [FavoriteFiles] Refreshing files")
        loadFiles()
    }
    
    // MARK: - Dynamic Children Loading (for folders)
    
    func loadChildren(for node: FunctionNode) async -> [FunctionNode] {
        print("📂 [FavoriteFilesProvider] loadChildren called for: \(node.name)")
        
        guard let metadata = node.metadata,
              let folderPath = metadata["folderURL"] as? String else {
            print("❌ [FavoriteFilesProvider] No folderURL in metadata")
            return []
        }
        
        let folderURL = URL(fileURLWithPath: folderPath)
        
        // Get sort order from metadata (carried from dynamic rule) or default
        let sortOrder: FolderSortOrder
        if let sortOrderRaw = metadata["sortOrder"] as? String,
           let order = FolderSortOrder(rawValue: sortOrderRaw) {
            sortOrder = order
        } else {
            sortOrder = .modifiedNewest
        }
        
        print("🎯 [FavoriteFilesProvider] Using sort order: \(sortOrder.displayName)")
        
        // Use FolderContentLoader for consistent heavy folder handling
        let result = await FolderContentLoader.loadContents(
            folderPath: folderPath,
            sortOrder: sortOrder,
            maxItems: nil
        )
        
        // Convert ContentItems to FunctionNodes
        let nodes = result.items.map { item in
            createChildNode(from: item, sortOrder: sortOrder)
        }
        
        // Finalize (cache population, watching setup)
        FolderContentLoader.finalizeLoad(
            folderPath: folderPath,
            folderName: node.name,
            actualCount: result.actualItemCount,
            wasFromCache: result.wasFromCache,
            nodes: nodes,
            folderURL: folderURL
        )
        
        return nodes
    }
    
    /// Create a child node from a ContentItem
    private func createChildNode(from item: FolderContentLoader.ContentItem, sortOrder: FolderSortOrder) -> FunctionNode {
        if item.isDirectory {
            return createChildFolderNode(from: item, sortOrder: sortOrder)
        } else {
            return createChildFileNode(from: item)
        }
    }
    
    /// Create a file node for folder contents
    private func createChildFileNode(from item: FolderContentLoader.ContentItem) -> FunctionNode {
        let icon: NSImage
        if let thumbnailData = item.cachedThumbnailData,
           let cachedIcon = NSImage(data: thumbnailData) {
            icon = cachedIcon
        } else {
            icon = IconProvider.shared.getFileIcon(for: item.url, size: 64, cornerRadius: 8)
        }
        
        return FunctionNode(
            id: "file-\(item.path)",
            name: item.name,
            type: .file,
            icon: icon,
            contextActions: [
                StandardContextActions.copyFile(item.url),
                StandardContextActions.deleteFile(item.url),
                StandardContextActions.showInFinder(item.url)
            ],
            preferredLayout: .partialSlice,
            previewURL: item.url,
            showLabel: true,
            slicePositioning: .center,
            onLeftClick: ModifierAwareInteraction(base: .drag(DragProvider(
                fileURLs: [item.url],
                dragImage: icon,
                allowedOperations: .move,
                onClick: {
                    print("📂 Opening file: \(item.name)")
                    NSWorkspace.shared.open(item.url)
                },
                onDragStarted: {
                    print("📦 Started dragging: \(item.name)")
                },
                onDragCompleted: { success in
                    if success {
                        print("✅ Successfully dragged: \(item.name)")
                    } else {
                        print("❌ Drag cancelled: \(item.name)")
                    }
                }
            ))),
            onRightClick: ModifierAwareInteraction(base: .expand),
            onMiddleClick: ModifierAwareInteraction(base: .executeKeepOpen {
                print("🖱️ Middle-click opening: \(item.name)")
                NSWorkspace.shared.open(item.url)
            }),
            onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
        )
    }
    
    /// Create a folder node for folder contents (supports further navigation)
    private func createChildFolderNode(from item: FolderContentLoader.ContentItem, sortOrder: FolderSortOrder) -> FunctionNode {
        let icon = IconProvider.shared.getFolderIcon(for: item.url, size: 64, cornerRadius: 8)
        
        return FunctionNode(
            id: "folder-\(item.path)",
            name: item.name,
            type: .folder,
            icon: icon,
            children: nil,
//            childDisplayMode: .panel,   
            contextActions: [
                StandardContextActions.showInFinder(item.url),
                StandardContextActions.deleteFile(item.url)
            ],
            preferredLayout: .partialSlice,
            previewURL: item.url,
            showLabel: true,
            slicePositioning: .center,
            metadata: [
                "folderURL": item.path,
                "sortOrder": sortOrder.rawValue  // Carry sort order down
            ],
            providerId: self.providerId,
            onLeftClick: ModifierAwareInteraction(base: .drag(DragProvider(
                fileURLs: [item.url],
                dragImage: icon,
                allowedOperations: [.move, .copy],
                clickBehavior: .navigate,
                onDragStarted: {
                    print("📦 Started dragging folder: \(item.name)")
                },
                onDragCompleted: { success in
                    if success {
                        print("✅ Successfully dragged folder: \(item.name)")
                    } else {
                        print("❌ Drag cancelled: \(item.name)")
                    }
                }
            ))),
            onRightClick: ModifierAwareInteraction(base: .expand),
            onMiddleClick: ModifierAwareInteraction(base: .executeKeepOpen {
                print("📂 Middle-click opening folder: \(item.name)")
                NSWorkspace.shared.open(item.url)
            }),
            onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
        )
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
    
    private func deleteFile(path: String) {
        let fileURL = URL(fileURLWithPath: path)
        
        do {
            try FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
            print("🗑️ [FavoriteFiles] Moved to trash: \(path)")
            
            // Refresh to resolve next matching item for dynamic rules
            refresh()
            NotificationCenter.default.postProviderUpdate(providerId: providerId)
            
        } catch {
            print("❌ [FavoriteFiles] Failed to delete: \(error)")
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
        sortOrder: FolderSortOrder,
        fileExtensions: String? = nil,
        namePattern: String? = nil,
        iconData: Data? = nil
    ) -> Bool {
        let success = DatabaseManager.shared.addFavoriteDynamicFile(
            displayName: displayName,
            folderPath: folderPath,
            sortOrder: sortOrder,
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
        sortOrder: FolderSortOrder,
        fileExtensions: String?,
        namePattern: String?,
        iconData: Data?
    ) -> Bool {
        let success = DatabaseManager.shared.updateFavoriteDynamicFile(
            id: id,
            displayName: displayName,
            folderPath: folderPath,
            sortOrder: sortOrder,
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
