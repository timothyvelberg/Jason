//
//  RefreshOperation.swift
//  Jason
//

import Foundation
import AppKit

/// Operation that refreshes and caches a heavy folder's contents
class RefreshOperation: Operation, @unchecked Sendable {
    let path: String
    let folderName: String
    
    // Default cache limit for folders
    private static let defaultCacheLimit = 40
    
    init(path: String, folderName: String) {
        self.path = path
        self.folderName = folderName
        super.init()
    }
    
    override func main() {
        guard !isCancelled else {
            print("Refresh cancelled for \(folderName)")
            return
        }
        
        let start = Date()
        print("Starting refresh for \(folderName)")
        
        // Perform the actual refresh
        performRefresh()
        
        let duration = Date().timeIntervalSince1970 - start.timeIntervalSince1970
        print("Completed refresh for \(folderName) in \(String(format: "%.2f", duration))s")
    }
    
    private func performRefresh() {
        guard !isCancelled else { return }
        
        // Load folder contents (respecting maxItems limit)
        let items = loadFolderContents(at: path)
        
        guard !isCancelled else {
            print("Refresh cancelled during load for \(folderName)")
            return
        }
        
        // Cache to database using enhanced cache
        let cacheType = DatabaseManager.shared.getCacheType(for: path) ?? "heavy"

        DatabaseManager.shared.saveEnhancedFolderContents(
            folderPath: path,
            items: items,
            cacheType: cacheType
        )
        
        // Notify UI so nodeCache gets invalidated and any visible panel refreshes
        DispatchQueue.main.async {
            NotificationCenter.default.postProviderUpdate(
                providerId: "favorite-folder",
                folderPath: self.path
            )
        }
    }
    
    private func loadFolderContents(at path: String) -> [EnhancedFolderItem] {
        let fileManager = FileManager.default
        let folderURL = URL(fileURLWithPath: path)
        
        // Get folder settings - check favorite folders first, then dynamic files
        let (maxItems, sortOrder) = getFolderSettings(for: path)
        
        print("Refresh settings: max=\(maxItems), sort=\(sortOrder.displayName)")
        
        guard let itemURLs = try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            print("Failed to read contents of \(folderName)")
            return []
        }
        
        print("Found \(itemURLs.count) total items")
        
        // Sort URLs FIRST (so we get the RIGHT items before limiting)
        let sortedURLs = FolderSortingUtility.sortURLs(itemURLs, by: sortOrder)
        
        // Apply limit BEFORE converting to EnhancedFolderItems
        let limitedURLs = Array(sortedURLs.prefix(maxItems))
        
        print("Processing \(limitedURLs.count) items (after limit)")
        
        // Convert to EnhancedFolderItems
        var items: [EnhancedFolderItem] = []
        
        for itemURL in limitedURLs {
            guard !isCancelled else { break }
            
            guard let resourceValues = try? itemURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .creationDateKey,
                .addedToDirectoryDateKey

            ]) else {
                continue
            }
            
            let isDirectory = resourceValues.isDirectory ?? false
            let fileSize = Int64(resourceValues.fileSize ?? 0)
            let modificationDate = resourceValues.contentModificationDate ?? Date()
            let creationDate = resourceValues.creationDate ?? modificationDate
            let dateAdded = resourceValues.addedToDirectoryDate ?? modificationDate
            let fileExtension = itemURL.pathExtension.lowercased()
            
            // Check if it's an image file
            let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"]
            let isImageFile = imageExtensions.contains(fileExtension)
            
            // TODO: Add thumbnail generation here later with QLThumbnailGenerator
            // For now, skip thumbnails to keep it simple
            
            let item = EnhancedFolderItem(
                name: itemURL.lastPathComponent,
                path: itemURL.path,
                isDirectory: isDirectory,
                modificationDate: modificationDate,
                creationDate: creationDate,
                dateAdded: dateAdded,
                fileExtension: fileExtension,
                fileSize: fileSize,
                hasCustomIcon: false,
                isImageFile: isImageFile,
                thumbnailData: nil,  // Will add thumbnails later
                folderConfigJSON: nil
            )
            
            items.append(item)
        }
        
        print("Cached \(items.count) items")
        
        // Items are already sorted (we sorted the URLs before converting)
        return items
    }
    
    /// Get settings for a folder - checks favorite folders first, then dynamic files, then defaults
    private func getFolderSettings(for path: String) -> (maxItems: Int, sortOrder: FolderSortOrder) {
        let db = DatabaseManager.shared
        // 1. Check if it's a favorite folder
        let favoriteFolders = db.getFavoriteFolders()
        if let favoriteFolder = favoriteFolders.first(where: { $0.folder.path == path }) {
            let maxItems = favoriteFolder.settings.maxItems ?? Self.defaultCacheLimit
            let sortOrder = favoriteFolder.settings.contentSortOrder ?? .modifiedNewest
            return (maxItems, sortOrder)
        }
        
        // 2. Check if it's a dynamic file source folder - use FolderSortOrder directly
        let dynamicFiles = db.getFavoriteDynamicFiles()
        if let dynamicFile = dynamicFiles.first(where: { $0.folderPath == path }) {
            return (Self.defaultCacheLimit, dynamicFile.sortOrder)
        }
        
        // 3. Default settings
        print("⚠️ Folder '\(folderName)' not in favorites or dynamic files, using defaults")
        return (Self.defaultCacheLimit, .modifiedNewest)
    }
}
