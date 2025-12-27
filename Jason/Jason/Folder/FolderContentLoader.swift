//
//  FolderContentLoader.swift
//  Jason
//
//  Created by Timothy Velberg on 27/12/2025.
//
//
//  Shared utility for loading folder contents with smart caching.
//  Used by FavoriteFolderProvider and FavoriteFilesProvider.

import Foundation
import AppKit

class FolderContentLoader {
    
    // MARK: - Data Structures
    
    /// Represents a loaded content item (file or folder)
    struct ContentItem {
        let name: String
        let path: String
        let url: URL
        let isDirectory: Bool
        let modificationDate: Date
        let fileExtension: String
        let fileSize: Int64
        let cachedThumbnailData: Data?  // Present if loaded from cache
        
        init(
            name: String,
            path: String,
            isDirectory: Bool,
            modificationDate: Date,
            fileExtension: String = "",
            fileSize: Int64 = 0,
            cachedThumbnailData: Data? = nil
        ) {
            self.name = name
            self.path = path
            self.url = URL(fileURLWithPath: path)
            self.isDirectory = isDirectory
            self.modificationDate = modificationDate
            self.fileExtension = fileExtension
            self.fileSize = fileSize
            self.cachedThumbnailData = cachedThumbnailData
        }
    }
    
    /// Result of loading folder contents
    struct LoadResult {
        let items: [ContentItem]
        let actualItemCount: Int
        let wasFromCache: Bool
    }
    
    // MARK: - Configuration
    
    /// Default maximum items to load from a folder
    static let defaultMaxItems: Int = 40
    
    /// Threshold for marking a folder as "heavy" (enables caching)
    static let heavyFolderThreshold: Int = 100
    
    // MARK: - Main Loading Method
    
    /// Load folder contents with smart caching and freshness checks
    /// - Parameters:
    ///   - folderPath: Path to the folder to load
    ///   - sortOrder: How to sort the contents
    ///   - maxItems: Optional limit on number of items (nil = defaultMaxItems)
    /// - Returns: LoadResult containing items and metadata
    static func loadContents(
        folderPath: String,
        sortOrder: FolderSortOrder,
        maxItems: Int? = nil
    ) async -> LoadResult {
        let db = DatabaseManager.shared
        let folderURL = URL(fileURLWithPath: folderPath)
        
        print("📂 [FolderContentLoader] Loading: \(folderPath)")
        print("🎯 [FolderContentLoader] Sort order: \(sortOrder.displayName)")
        
        // Record folder access
        db.recordFolderAccess(folderPath: folderPath)
        
        // Try cache first for heavy folders
        if let cachedResult = loadFromCache(folderPath: folderPath, sortOrder: sortOrder, maxItems: maxItems) {
            return cachedResult
        }
        
        // Cache miss - load from filesystem
        return await loadFromFilesystem(
            folderPath: folderPath,
            folderURL: folderURL,
            sortOrder: sortOrder,
            maxItems: maxItems
        )
    }
    
    // MARK: - Cache Loading
    
    /// Attempt to load from enhanced cache
    private static func loadFromCache(
        folderPath: String,
        sortOrder: FolderSortOrder,
        maxItems: Int?
    ) -> LoadResult? {
        let db = DatabaseManager.shared
        
        // Only use cache if folder is marked as heavy
        guard db.isHeavyFolder(path: folderPath) else {
            return nil
        }
        
        print("📦 [FolderContentLoader] Heavy folder detected - checking cache")
        
        // Check cache freshness
        guard let cacheTimestamp = db.getEnhancedCacheTimestamp(folderPath: folderPath) else {
            print("⚠️ [FolderContentLoader] No cache timestamp found")
            return nil
        }
        
        // Compare folder modification date with cache timestamp
        if let folderModDate = getFolderModificationDate(path: folderPath) {
            if folderModDate > cacheTimestamp {
                print("⏰ [FolderContentLoader] Cache stale - folder modified after cache")
                return nil
            }
        }
        
        // Get cached contents
        guard let cachedItems = db.getEnhancedCachedFolderContents(folderPath: folderPath) else {
            print("⚠️ [FolderContentLoader] Cache miss for heavy folder")
            return nil
        }
        
        print("⚡ [FolderContentLoader] CACHE HIT! Loaded \(cachedItems.count) items instantly")
        
        // Convert to ContentItem array
        var items = cachedItems.map { cached in
            ContentItem(
                name: cached.name,
                path: cached.path,
                isDirectory: cached.isDirectory,
                modificationDate: cached.modificationDate,
                fileExtension: cached.fileExtension,
                fileSize: cached.fileSize,
                cachedThumbnailData: cached.thumbnailData
            )
        }
        
        // Sort items
        items = sortItems(items, by: sortOrder)
        
        // Apply limit
        let limit = maxItems ?? defaultMaxItems
        let limitedItems = Array(items.prefix(limit))
        
        return LoadResult(
            items: limitedItems,
            actualItemCount: cachedItems.count,
            wasFromCache: true
        )
    }
    
    // MARK: - Filesystem Loading
    
    /// Load folder contents from filesystem
    private static func loadFromFilesystem(
        folderPath: String,
        folderURL: URL,
        sortOrder: FolderSortOrder,
        maxItems: Int?
    ) async -> LoadResult {
        print("💿 [FolderContentLoader] Loading from filesystem: \(folderPath)")
        let startTime = Date()
        
        // Count actual items first
        let actualCount = countFolderItems(at: folderURL)
        print("📊 [FolderContentLoader] Folder contains: \(actualCount) items")
        
        // Load on background thread
        let items: [ContentItem] = await Task.detached(priority: .userInitiated) {
            do {
                let contents = try FileManager.default.contentsOfDirectory(
                    at: folderURL,
                    includingPropertiesForKeys: [
                        .isDirectoryKey,
                        .nameKey,
                        .contentModificationDateKey,
                        .creationDateKey,
                        .fileSizeKey
                    ],
                    options: [.skipsHiddenFiles]
                )
                
                // Sort using utility
                let sortedContents = FolderSortingUtility.sortURLs(contents, by: sortOrder)
                
                // Apply limit
                let limit = maxItems ?? defaultMaxItems
                let limitedContents = Array(sortedContents.prefix(limit))
                
                // Convert to ContentItem
                return limitedContents.compactMap { url -> ContentItem? in
                    var isDirectory: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                        return nil
                    }
                    
                    var modDate = Date()
                    var fileSize: Int64 = 0
                    
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
                        if let date = attrs[.modificationDate] as? Date {
                            modDate = date
                        }
                        if let size = attrs[.size] as? Int64 {
                            fileSize = size
                        }
                    }
                    
                    return ContentItem(
                        name: url.lastPathComponent,
                        path: url.path,
                        isDirectory: isDirectory.boolValue,
                        modificationDate: modDate,
                        fileExtension: url.pathExtension.lowercased(),
                        fileSize: fileSize,
                        cachedThumbnailData: nil
                    )
                }
                
            } catch {
                print("❌ [FolderContentLoader] Failed to load folder: \(error)")
                return []
            }
        }.value
        
        let elapsed = Date().timeIntervalSince(startTime)
        print("✅ [FolderContentLoader] Loaded \(items.count) items in \(String(format: "%.2f", elapsed))s")
        
        return LoadResult(
            items: items,
            actualItemCount: actualCount,
            wasFromCache: false
        )
    }
    
    // MARK: - Finalization (Caching & Watching)
    
    /// Finalize the load by setting up caching and watching for heavy folders
    /// Call this after creating FunctionNodes from the LoadResult
    /// - Parameters:
    ///   - folderPath: Path to the folder
    ///   - folderName: Display name for logging
    ///   - actualCount: Total item count in folder
    ///   - wasFromCache: Whether the load was from cache
    ///   - nodes: The FunctionNodes created from the load
    ///   - folderURL: URL to the folder
    static func finalizeLoad(
        folderPath: String,
        folderName: String,
        actualCount: Int,
        wasFromCache: Bool,
        nodes: [FunctionNode],
        folderURL: URL
    ) {
        let db = DatabaseManager.shared
        
        // Update folder access tracking
        db.updateFolderAccess(path: folderPath)
        
        // Handle heavy folder status
        handleHeavyFolderStatus(
            folderPath: folderPath,
            folderName: folderName,
            itemCount: actualCount
        )
        
        // Cache if heavy and wasn't already from cache
        if !wasFromCache && actualCount > heavyFolderThreshold {
            print("📊 [FolderContentLoader] Caching heavy folder: \(folderName) (\(actualCount) items)")
            
            let enhancedItems = convertToEnhancedFolderItems(nodes: nodes, folderURL: folderURL)
            db.saveEnhancedFolderContents(folderPath: folderPath, items: enhancedItems)
            
            print("💾 [FolderContentLoader] Cached \(enhancedItems.count) items for future instant loads")
        }
    }
    
    // MARK: - Heavy Folder Management
    
    /// Handle heavy folder watching and status
    private static func handleHeavyFolderStatus(
        folderPath: String,
        folderName: String,
        itemCount: Int
    ) {
        let db = DatabaseManager.shared
        let isCurrentlyHeavy = db.isHeavyFolder(path: folderPath)
        let shouldBeHeavy = itemCount > heavyFolderThreshold
        
        if shouldBeHeavy && !isCurrentlyHeavy {
            // Folder just became heavy
            print("📊 [FolderContentLoader] Folder crossed threshold: \(itemCount) items")
            
            db.markAsHeavyFolder(path: folderPath, itemCount: itemCount)
            FolderWatcherManager.shared.startWatching(path: folderPath, itemName: folderName)
            
            print("👀 [FolderContentLoader] Started watching heavy folder: \(folderName)")
            
        } else if !shouldBeHeavy && isCurrentlyHeavy {
            // Folder just became light
            print("📉 [FolderContentLoader] Folder dropped below threshold: \(itemCount) items")
            
            db.removeHeavyFolder(path: folderPath)
            FolderWatcherManager.shared.stopWatching(path: folderPath)
            db.invalidateEnhancedCache(for: folderPath)
            
            print("🛑 [FolderContentLoader] Stopped watching - folder is now light: \(folderName)")
            
        } else if shouldBeHeavy && isCurrentlyHeavy {
            // Still heavy - update count
            db.updateHeavyFolderItemCount(path: folderPath, itemCount: itemCount)
        }
    }
    
    // MARK: - Helpers
    
    /// Get folder modification date
    private static func getFolderModificationDate(path: String) -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let modDate = attrs[.modificationDate] as? Date else {
            return nil
        }
        return modDate
    }
    
    /// Count items in folder
    private static func countFolderItems(at url: URL) -> Int {
        do {
            let items = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            return items.count
        } catch {
            print("⚠️ [FolderContentLoader] Failed to count items: \(error)")
            return 0
        }
    }
    
    /// Sort content items by sort order
    private static func sortItems(_ items: [ContentItem], by sortOrder: FolderSortOrder) -> [ContentItem] {
        // Convert to URLs, sort, then reorder items
        let urls = items.map { $0.url }
        let sortedURLs = FolderSortingUtility.sortURLs(urls, by: sortOrder)
        
        var sortedItems: [ContentItem] = []
        for sortedURL in sortedURLs {
            if let item = items.first(where: { $0.path == sortedURL.path }) {
                sortedItems.append(item)
            }
        }
        
        return sortedItems
    }
    
    /// Convert FunctionNodes to EnhancedFolderItem for caching
    private static func convertToEnhancedFolderItems(
        nodes: [FunctionNode],
        folderURL: URL
    ) -> [EnhancedFolderItem] {
        return nodes.compactMap { node -> EnhancedFolderItem? in
            var path: String?
            var isDirectory = false
            var modDate = Date()
            var fileExtension = ""
            var fileSize: Int64 = 0
            var thumbnailData: Data?
            
            // Folder node
            if let metadata = node.metadata,
               let folderURLString = metadata["folderURL"] as? String {
                path = folderURLString
                isDirectory = true
            }
            // File node
            else if let previewURL = node.previewURL {
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
                
                // Extract thumbnail from icon
                let iconImage = node.icon
                if let tiffData = iconImage.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    thumbnailData = pngData
                }
            }
            
            guard let itemPath = path else { return nil }
            
            let hasCustomIcon = !fileExtension.isEmpty &&
                IconProvider.shared.hasCustomFileIcon(for: fileExtension)
            
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
}
