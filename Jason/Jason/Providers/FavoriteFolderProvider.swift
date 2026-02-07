//
//  FavoriteFolderProvider.swift
//  Jason
//
//  Provides favorite folder navigation with enhanced caching for heavy folders
//

import Foundation
import AppKit

class FavoriteFolderProvider: ObservableObject, FunctionProvider {
    
    // MARK: - Provider Info
    
    var providerId: String { "favorite-folder" }
    var providerName: String { "Favorite Folders" }
    var providerIcon: NSImage {
        return NSImage(named: "parent-folders") ?? NSImage()
    }
    
    private let maxItemsPerFolder: Int = 40
    private var nodeCache: [String: [FunctionNode]] = [:]
    
    // MARK: - FunctionProvider Protocol
    
    func provideFunctions() -> [FunctionNode] {
        print("📁 [FavoriteFolderProvider] provideFunctions() called")
        
        // Get favorites from database
        let favoritesFromDB = DatabaseManager.shared.getFavoriteFolders()
        
        // If no favorites in database, add defaults
        if favoritesFromDB.isEmpty {
            print("📁 [FavoriteFolderProvider] No favorites found - adding defaults")
            addDefaultFavorites()
            return provideFunctions() // Recurse once after adding defaults
        }
        
        let favoriteChildren = favoritesFromDB.map { (folder, settings) in
            createFavoriteFolderEntry(folderEntry: folder, settings: settings)
        }
        
        // Wrap in category node - applyDisplayMode will unwrap if displayMode == .direct
        return [FunctionNode(
            id: "favorite-folders-section",
            name: "Folders",
            type: .category,
            icon: NSImage(named: "parent-folders") ?? NSImage(),
            children: favoriteChildren,
            preferredLayout: .partialSlice,
            slicePositioning: .center,
            providerId: providerId,
            onLeftClick: ModifierAwareInteraction(base: .doNothing),
            onRightClick: ModifierAwareInteraction(base: .doNothing),
            onBoundaryCross: ModifierAwareInteraction(base: .expand)
        )]
    }
    
    func clearCache() {
        nodeCache.removeAll()
        print("🗑️ [FavoriteFolderProvider] Cache cleared")
    }
    
    func invalidateCache(for url: URL) {
        let cacheKey = url.path
        nodeCache.removeValue(forKey: cacheKey)
        print("🗑️ [FavoriteFolderProvider] Invalidated cache for: \(url.path)")
    }
    
    func refresh() {
        print("🔄 [FavoriteFolderProvider] refresh() called")
        nodeCache.removeAll()
    }
    
    // MARK: - Dynamic Loading
    
    func loadChildren(for node: FunctionNode) async -> [FunctionNode] {
        print("📂 [FavoriteFolderProvider] loadChildren called for: \(node.name)")
        
        guard let metadata = node.metadata,
              let urlString = metadata["folderURL"] as? String else {
            print("❌ No folderURL in metadata")
            return []
        }
        
        let folderURL = URL(fileURLWithPath: urlString)
        let folderPath = folderURL.path
        let db = DatabaseManager.shared
        
        // Get sort order
        let requestedSortOrder = getSortOrderForFolder(path: folderPath)
        print("🎯 [SORT] Folder: \(node.name) - Sort: \(requestedSortOrder.displayName)")
        
        // Early cancellation check — bail before any filesystem work
        try? Task.checkCancellation()
        if Task.isCancelled { return [] }
        
        // Record folder access
        db.recordFolderAccess(folderPath: folderPath)
        
        // Check actual folder size for heavy folder handling
        let actualItemCount = countFolderItems(at: folderURL)
        let folderExceedsLimit = actualItemCount > maxItemsPerFolder
        
        // Cancellation check — after counting but before heavy work
        try? Task.checkCancellation()
        if Task.isCancelled { return [] }
        
        // Check if this is a HEAVY folder and try ENHANCED CACHE
        if db.isHeavyFolder(path: folderPath) {
            print("📦 [FavoriteFolderProvider] Heavy folder detected: \(node.name)")
            
            if let cachedItems = db.getEnhancedCachedFolderContents(folderPath: folderPath) {
                print("⚡ [EnhancedCache] CACHE HIT! Loaded \(cachedItems.count) items instantly")
                
                // Convert to nodes
                var nodes = cachedItems.map { item in
                    if item.isDirectory {
                        return createFolderNodeFromCache(item: item)
                    } else {
                        return createFileNodeFromCache(item: item)
                    }
                }
                
                // Apply sort order
                nodes = sortNodes(nodes, by: requestedSortOrder)
                
                // Add "Open in Finder" if folder has more items than we're showing
                if folderExceedsLimit {
                    nodes.append(createOpenInFinderNode(for: folderURL))
                }
                
                return nodes
            } else {
                print("⚠️ [EnhancedCache] Cache miss for heavy folder - will reload and cache")
            }
        }
        
        // CACHE MISS OR NOT HEAVY - Load from disk
        print("💿 [START] Loading from disk: \(folderURL.path)")
        let startTime = Date()
        
        print("📊 [FavoriteFolderProvider] Actual folder contains: \(actualItemCount) items")
        
        // Cancellation check — before expensive disk + thumbnail work
        try? Task.checkCancellation()
        if Task.isCancelled {
            print("🚫 [FavoriteFolderProvider] Cancelled before disk load: \(node.name)")
            return []
        }
        
        let nodes: [FunctionNode] = await Task.detached(priority: .userInitiated) { [weak self] () -> [FunctionNode] in
            guard let self = self else {
                print("❌ [FavoriteFolderProvider] Self deallocated during load")
                return []
            }
            
            // Check cancellation inside detached task
            if Task.isCancelled {
                print("🚫 [FavoriteFolderProvider] Cancelled at start of background load")
                return []
            }
            
            print("🧵 [BACKGROUND] Started loading: \(folderURL.path)")
            
            let result = self.getFolderContents(at: folderURL, sortOrder: requestedSortOrder)
            
            // Check cancellation after loading but before returning
            if Task.isCancelled {
                print("🚫 [FavoriteFolderProvider] Cancelled after disk load: \(folderURL.lastPathComponent)")
                return []
            }
            
            print("🧵 [BACKGROUND] Finished loading: \(folderURL.path) - \(result.count) items")
            return result
        }.value
        
        // Cancellation check — before caching work
        if Task.isCancelled {
            print("🚫 [FavoriteFolderProvider] Cancelled before caching: \(node.name)")
            return []
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        print("✅ [END] Loaded \(nodes.count) nodes in \(String(format: "%.2f", elapsed))s")
        
        // Handle folder watching status dynamically
        handleFolderWatchingStatus(folderPath: folderPath, itemCount: actualItemCount, folderName: node.name)
        
        // Cache heavy folders
        if actualItemCount > 100 {
            // Final cancellation check — don't bother caching if we're about to be discarded
            if Task.isCancelled {
                print("🚫 [FavoriteFolderProvider] Cancelled before enhanced cache write: \(node.name)")
                return []
            }
            
            print("📊 [EnhancedCache] Folder has \(actualItemCount) items - caching with thumbnails")
            
            // Convert nodes to EnhancedFolderItem format WITH THUMBNAILS
            let enhancedItems = convertToEnhancedFolderItems(nodes: nodes, folderURL: folderURL)
            
            // Save to Enhanced Cache
            db.saveEnhancedFolderContents(folderPath: folderPath, items: enhancedItems)
            print("💾 [EnhancedCache] Cached \(nodes.count) items for future instant loads!")
        } else {
            print("ℹ️ [EnhancedCache] Folder has only \(actualItemCount) items - not caching (threshold: 100)")
        }
        
        // Add "Open in Finder" if folder has more items than we're showing
        var resultNodes = nodes
        if folderExceedsLimit {
            resultNodes.append(createOpenInFinderNode(for: folderURL))
        }
        
        return resultNodes
    }
    
    // MARK: - Sorting
    
    private func getSortOrderForFolder(path: String) -> FolderSortOrder {
        let favoriteFolders = DatabaseManager.shared.getFavoriteFolders()
        
        if let favoriteFolder = favoriteFolders.first(where: { $0.folder.path == path }),
           let sortOrder = favoriteFolder.settings.contentSortOrder {
            return sortOrder
        }
        
        return .alphabeticalAsc
    }
    
    private func sortNodes(_ nodes: [FunctionNode], by sortOrder: FolderSortOrder) -> [FunctionNode] {
        // Extract URLs from nodes for sorting
        var urlNodePairs: [(URL, FunctionNode)] = []
        
        for node in nodes {
            if let previewURL = node.previewURL {
                urlNodePairs.append((previewURL, node))
            } else if let metadata = node.metadata,
                      let urlString = metadata["folderURL"] as? String {
                urlNodePairs.append((URL(fileURLWithPath: urlString), node))
            }
        }
        
        // Sort URLs using FolderSortingUtility
        let urls = urlNodePairs.map { $0.0 }
        let sortedURLs = FolderSortingUtility.sortURLs(urls, by: sortOrder)
        
        // Reorder nodes to match sorted URLs
        var sortedNodes: [FunctionNode] = []
        for sortedURL in sortedURLs {
            if let pair = urlNodePairs.first(where: { $0.0 == sortedURL }) {
                sortedNodes.append(pair.1)
            }
        }
        
        return sortedNodes
    }
    
    // MARK: - Folder Watching
    
    private func isFavoriteFolder(path: String) -> Bool {
        let favoriteFolders = DatabaseManager.shared.getFavoriteFolders()
        return favoriteFolders.contains { $0.folder.path == path }
    }
    
    private func handleFolderWatchingStatus(folderPath: String, itemCount: Int, folderName: String) {
        let db = DatabaseManager.shared
        let isCurrentlyHeavy = db.isHeavyFolder(path: folderPath)
        let shouldBeHeavy = itemCount > 100
        let isFavorite = isFavoriteFolder(path: folderPath)
        
        if shouldBeHeavy && !isCurrentlyHeavy {
            // FOLDER JUST BECAME HEAVY
            print("📊 [FavoriteFolderProvider] Folder crossed threshold: \(itemCount) items")
            
            db.markAsHeavyFolder(path: folderPath, itemCount: itemCount)
            
            if isFavorite {
                FolderWatcherManager.shared.startWatching(path: folderPath, itemName: folderName)
                print("👀 [FSEvents] Started watching newly-heavy favorite folder: \(folderName)")
            }
            
        } else if !shouldBeHeavy && isCurrentlyHeavy {
            // FOLDER JUST BECAME LIGHT
            print("📉 [FavoriteFolderProvider] Folder dropped below threshold: \(itemCount) items")
            
            db.removeHeavyFolder(path: folderPath)
            FolderWatcherManager.shared.stopWatching(path: folderPath)
            print("🛑 [FSEvents] Stopped watching - folder is now light: \(folderName)")
            
            db.invalidateEnhancedCache(for: folderPath)
            
        } else if shouldBeHeavy && isCurrentlyHeavy {
            // FOLDER IS STILL HEAVY - update count
            db.updateHeavyFolderItemCount(path: folderPath, itemCount: itemCount)
        }
    }
    
    // MARK: - Folder Contents
    
    private func getFolderContents(at url: URL, sortOrder: FolderSortOrder) -> [FunctionNode] {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .nameKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            
            let sortedContents = FolderSortingUtility.sortURLs(contents, by: sortOrder)
            let limitedContents = Array(sortedContents.prefix(maxItemsPerFolder))
            
            return limitedContents.map { contentURL in
                if contentURL.isNavigableDirectory {
                    return createFolderNode(for: contentURL)
                } else {
                    return createFileNode(for: contentURL)
                }
            }
            
        } catch {
            print("❌ [FavoriteFolderProvider] Failed to get folder contents: \(error)")
            return []
        }
    }
    
    private func countFolderItems(at url: URL) -> Int {
        do {
            let items = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            return items.count
        } catch {
            print("⚠️ [FavoriteFolderProvider] Failed to count folder items: \(error)")
            return 0
        }
    }
    
    // MARK: - Node Creation
    
    private func createOpenInFinderNode(for folderURL: URL) -> FunctionNode {
        let finderIcon = NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")
        finderIcon.size = NSSize(width: 64, height: 64)
        
        return FunctionNode(
            id: "open-finder-\(folderURL.path)",
            name: "Open in Finder",
            type: .action,
            icon: finderIcon,
            preferredLayout: .partialSlice,
            showLabel: true,
            slicePositioning: .center,
            providerId: self.providerId,
            onLeftClick: ModifierAwareInteraction(base: .execute {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
            }),
            onRightClick: ModifierAwareInteraction(base: .doNothing),
            onBoundaryCross: ModifierAwareInteraction(base: .execute {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
            })
        )
    }
    
    private func createFileNode(for url: URL) -> FunctionNode {
        let fileName = url.lastPathComponent
        let dragImage = createThumbnail(for: url)
        let folderPath = url.deletingLastPathComponent().path
        let providerId = self.providerId
        
        return FunctionNode(
            id: "file-\(url.path)",
            name: fileName,
            type: .file,
            icon: dragImage,
            childDisplayMode: .panel,
            contextActions: [
                StandardContextActions.copyFile(url),
                StandardContextActions.showInFinder(url),
                StandardContextActions.deleteFile(url) { success in
                    if success {
                        NotificationCenter.default.postProviderUpdate(
                            providerId: providerId,
                            folderPath: folderPath
                        )
                    }
                }
            ],
            preferredLayout: .partialSlice,
            previewURL: url,
            showLabel: true,
            slicePositioning: .center,
            
            onLeftClick: ModifierAwareInteraction(base: .drag(DragProvider(
                fileURLs: [url],
                dragImage: dragImage,
                allowedOperations: .move,
                onClick: {
                    print("📂 Opening file: \(fileName)")
                    NSWorkspace.shared.openAndActivate(url)

                },
                onDragStarted: {
                    print("📦 Started dragging: \(fileName)")
                },
                onDragCompleted: { success in
                    if success {
                        print("✅ Successfully dragged: \(fileName)")
                    } else {
                        print("❌ Drag cancelled: \(fileName)")
                    }
                }
            ))),
            onRightClick: ModifierAwareInteraction(base: .expand),
            onMiddleClick: ModifierAwareInteraction(base: .executeKeepOpen {
                print("🖱️ Middle-click opening: \(fileName)")
                NSWorkspace.shared.openAndActivate(url)
            }),
            onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
        )
    }
    
    private func createFolderNode(for url: URL) -> FunctionNode {
        let folderName = url.lastPathComponent
        let icon = IconProvider.shared.getFolderIcon(for: url, size: 64, cornerRadius: 8)
        
        return FunctionNode(
            id: "folder-\(url.path)",
            name: folderName,
            type: .folder,
            icon: icon,
            children: nil,
            childDisplayMode: .panel,
            contextActions: [
                StandardContextActions.copyFile(url),
                StandardContextActions.showInFinder(url),
                StandardContextActions.deleteFile(url)
            ],
            preferredLayout: .partialSlice,
            previewURL: url,
            showLabel: true,
            slicePositioning: .center,
            metadata: ["folderURL": url.path],
            providerId: self.providerId,
            onLeftClick: ModifierAwareInteraction(base: .drag(DragProvider(
                fileURLs: [url],
                dragImage: icon,
                allowedOperations: [.move, .copy],
                clickBehavior: .navigate,
                onDragStarted: {
                    print("📦 Started dragging folder: \(folderName)")
                },
                onDragCompleted: { success in
                    if success {
                        print("✅ Successfully dragged folder: \(folderName)")
                    } else {
                        print("❌ Drag cancelled: \(folderName)")
                    }
                }
            ))),
            onRightClick: ModifierAwareInteraction(base: .expand),
            onMiddleClick: ModifierAwareInteraction(base: .executeKeepOpen {
                print("📂 Middle-click opening folder: \(folderName)")
                NSWorkspace.shared.openAndActivate(url)
            }),
            onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
        )
    }
    
    // MARK: - Cache Node Creation
    
    private func createFileNodeFromCache(item: EnhancedFolderItem) -> FunctionNode {
        let url = URL(fileURLWithPath: item.path)
        let fileName = item.name
        let folderPath = url.deletingLastPathComponent().path
        let providerId = self.providerId
        
        let icon: NSImage
        if let thumbnailData = item.thumbnailData, let cachedThumbnail = NSImage(data: thumbnailData) {
            icon = cachedThumbnail
        } else {
            icon = IconProvider.shared.getFileIcon(for: url, size: 64, cornerRadius: 8)
        }
        
        return FunctionNode(
            id: "file-\(item.path)",
            name: fileName,
            type: .file,
            icon: icon,
            childDisplayMode: .panel,
            contextActions: [
                StandardContextActions.copyFile(url),
                StandardContextActions.showInFinder(url),
                StandardContextActions.deleteFile(url) { success in
                    if success {
                        NotificationCenter.default.postProviderUpdate(
                            providerId: providerId,
                            folderPath: folderPath
                        )
                    }
                }
            ],
            preferredLayout: .partialSlice,
            previewURL: url,
            showLabel: true,
            slicePositioning: .center,
            
            onLeftClick: ModifierAwareInteraction(base: .drag(DragProvider(
                fileURLs: [url],
                dragImage: icon,
                allowedOperations: .move,
                onClick: {
                    print("📂 Opening file: \(fileName)")
                    NSWorkspace.shared.openAndActivate(url)
                },
                onDragStarted: {
                    print("📦 Started dragging: \(fileName)")
                },
                onDragCompleted: { success in
                    if success {
                        print("✅ Successfully dragged: \(fileName)")
                    } else {
                        print("❌ Drag cancelled: \(fileName)")
                    }
                }
            ))),
            onRightClick: ModifierAwareInteraction(base: .expand),
            onMiddleClick: ModifierAwareInteraction(base: .executeKeepOpen {
                print("🖱️ Middle-click opening: \(fileName)")
                NSWorkspace.shared.openAndActivate(url)
            }),
            onBoundaryCross: ModifierAwareInteraction(base: .navigateInto)
        )
    }
    
    private func createFolderNodeFromCache(item: EnhancedFolderItem) -> FunctionNode {
        let url = URL(fileURLWithPath: item.path)
        let folderName = item.name
        let icon = IconProvider.shared.getFolderIcon(for: url, size: 64, cornerRadius: 8)
        let parentPath = url.deletingLastPathComponent().path
        let providerId = self.providerId
        
        return FunctionNode(
            id: "folder-\(item.path)",
            name: folderName,
            type: .folder,
            icon: icon,
            children: nil,
            childDisplayMode: .panel,
            contextActions: [
                StandardContextActions.copyFile(url),
                StandardContextActions.showInFinder(url),
                StandardContextActions.deleteFile(url) { success in
                    if success {
                        NotificationCenter.default.postProviderUpdate(
                            providerId: providerId,
                            folderPath: parentPath
                        )
                    }
                }
            ],
            preferredLayout: .partialSlice,
            previewURL: url,
            showLabel: true,
            slicePositioning: .center,
            metadata: ["folderURL": item.path],
            providerId: self.providerId,
            onLeftClick: ModifierAwareInteraction(base: .drag(DragProvider(
                fileURLs: [url],
                dragImage: icon,
                allowedOperations: [.move, .copy],
                clickBehavior: .navigate,
                onDragStarted: {
                    print("📦 Started dragging folder: \(folderName)")
                },
                onDragCompleted: { success in
                    if success {
                        print("✅ Successfully dragged folder: \(folderName)")
                    } else {
                        print("❌ Drag cancelled: \(folderName)")
                    }
                }
            ))),
            onRightClick: ModifierAwareInteraction(base: .expand),
            onMiddleClick: ModifierAwareInteraction(base: .executeKeepOpen {
                print("📂 Middle-click opening folder: \(folderName)")
                NSWorkspace.shared.openAndActivate(url)
            }),
            onBoundaryCross: ModifierAwareInteraction(base: .navigateInto)
        )
    }
    
    // MARK: - Favorites Management
    
    private func createFavoriteFolderEntry(folderEntry: FolderEntry, settings: FavoriteFolderSettings) -> FunctionNode {
        let path = URL(fileURLWithPath: folderEntry.path)
        let metadata: [String: Any] = ["folderURL": folderEntry.path]
        
        let layout: LayoutStyle = {
            guard let layoutString = settings.preferredLayout else { return .fullCircle }
            return layoutString == "partialSlice" ? .partialSlice : .fullCircle
        }()
        
        let positioning: SlicePositioning = {
            guard let posString = settings.slicePositioning else { return .startClockwise }
            switch posString {
            case "startCounterClockwise": return .startCounterClockwise
            case "center": return .center
            default: return .startClockwise
            }
        }()
        
        let itemAngle = settings.itemAngleSize.map { CGFloat($0) }
        let childThickness = settings.childRingThickness.map { CGFloat($0) }
        let childIcon = settings.childIconSize.map { CGFloat($0) }
        
        let folderIcon: NSImage = {
            // Get color from hex stored in database, fallback to default blue
            let folderColor = folderEntry.iconColor ?? NSColor(hex: "#55C2EE") ?? .systemBlue
            
            if let iconName = folderEntry.iconName, !iconName.isEmpty {
                // Folder with symbol overlay
                return IconProvider.shared.createLayeredFolderIconWithSymbol(
                    color: folderColor,
                    symbolName: iconName,
                    symbolColor: .white,
                    size: 64,
                    symbolSize: folderEntry.symbolSize,
                    cornerRadius: 8,
                    symbolOffset: folderEntry.symbolOffset
                )
            } else {
                // Plain colored folder
                return IconProvider.shared.createLayeredFolderIcon(
                    color: folderColor,
                    size: 64,
                    cornerRadius: 8
                )
            }
        }()
        
        return FunctionNode(
            id: "favorite-\(path.path)",
            name: folderEntry.title,
            type: .folder,
            icon: folderIcon,
            children: nil,
            childDisplayMode: .panel,
            preferredLayout: layout,
            itemAngleSize: itemAngle,
            showLabel: true,
            childRingThickness: childThickness,
            childIconSize: childIcon,
            slicePositioning: positioning,
            metadata: metadata,
            providerId: self.providerId,
            onLeftClick: ModifierAwareInteraction(base: .drag(DragProvider(
                fileURLs: [path],
                dragImage: folderIcon,
                allowedOperations: [.move, .copy],
                onDragStarted: {
                    print("📦 Started dragging favorite folder: \(folderEntry.title)")
                },
                onDragCompleted: { success in
                    if success {
                        print("✅ Successfully dragged favorite folder: \(folderEntry.title)")
                    } else {
                        print("❌ Drag cancelled: \(folderEntry.title)")
                    }
                }
            ))),
            onRightClick: ModifierAwareInteraction(base: .expand),
            onMiddleClick: ModifierAwareInteraction(base: .executeKeepOpen {
                DatabaseManager.shared.updateFolderAccess(path: path.path)
                NSWorkspace.shared.openAndActivate(path)
            }),
            onBoundaryCross: ModifierAwareInteraction(base: .navigateInto)
        )
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
        }
        
        print("✅ [FavoriteFolderProvider] Added default favorites with smart sorting")
    }
    
    // MARK: - Enhanced Cache Helpers
    
    private func convertToEnhancedFolderItems(nodes: [FunctionNode], folderURL: URL) -> [EnhancedFolderItem] {
        return nodes.compactMap { node -> EnhancedFolderItem? in
            var path: String?
            var isDirectory = false
            var modDate = Date()
            var fileExtension = ""
            var fileSize: Int64 = 0
            var thumbnailData: Data?
            
            if let metadata = node.metadata,
               let folderURLString = metadata["folderURL"] as? String {
                path = folderURLString
                isDirectory = true
            } else if let previewURL = node.previewURL {
                path = previewURL.path
                isDirectory = false
                fileExtension = previewURL.pathExtension.lowercased()
                
                if let attrs = try? FileManager.default.attributesOfItem(atPath: previewURL.path) {
                    if let date = attrs[.modificationDate] as? Date {
                        modDate = date
                    }
                    if let size = attrs[.size] as? Int64 {
                        fileSize = size
                    }
                }
                
                // Extract thumbnail from the already-generated icon
                let iconImage = node.icon
                if let tiffData = iconImage.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    thumbnailData = pngData
                }
            }
            
            guard let itemPath = path else { return nil }
            
            let hasCustomIcon = !fileExtension.isEmpty && IconProvider.shared.hasCustomFileIcon(for: fileExtension)
            
            let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"]
            let isImageFile = imageExtensions.contains(fileExtension)
            
            return EnhancedFolderItem(
                name: node.name,
                path: itemPath,
                isDirectory: isDirectory,
                modificationDate: modDate,
                fileExtension: fileExtension,
                fileSize: fileSize,
                hasCustomIcon: hasCustomIcon,
                isImageFile: isImageFile,
                thumbnailData: thumbnailData,
                folderConfigJSON: nil
            )
        }
    }
    
    // MARK: - Thumbnail Creation
    
    private func createThumbnail(for url: URL) -> NSImage {
        let thumbnailSize = NSSize(width: 64, height: 64)
        let cornerRadius: CGFloat = 8
        
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"]
        let fileExtension = url.pathExtension.lowercased()
        
        if imageExtensions.contains(fileExtension) {
            if let image = NSImage(contentsOf: url) {
                let thumbnail = NSImage(size: thumbnailSize)
                
                thumbnail.lockFocus()
                
                let rect = NSRect(origin: .zero, size: thumbnailSize)
                let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
                path.addClip()
                
                image.draw(
                    in: rect,
                    from: NSRect(origin: .zero, size: image.size),
                    operation: .sourceOver,
                    fraction: 1.0
                )
                
                thumbnail.unlockFocus()
                
                return thumbnail
            }
        }
        
        return IconProvider.shared.getFileIcon(for: url, size: thumbnailSize.width, cornerRadius: cornerRadius)
    }
}
