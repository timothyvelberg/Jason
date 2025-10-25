//
//  FinderLogic+FolderWatching.swift
//  Jason
//
//  Created by Timothy Velberg on 25/10/2025.
//

import Foundation

// MARK: - Folder Watching Helper Methods

extension FinderLogic {
    
    /// Check if a folder path is in the favorites list
    private func isFavoriteFolder(path: String) -> Bool {
        let favoriteFolders = DatabaseManager.shared.getFavoriteFolders()
        return favoriteFolders.contains { favoriteFolder in
            favoriteFolder.folder.path == path
        }
    }
    
    /// Handle dynamic folder watching when folder becomes heavy or light
    private func handleFolderWatchingStatus(folderPath: String, itemCount: Int, folderName: String) {
        let db = DatabaseManager.shared
        let isCurrentlyHeavy = db.isHeavyFolder(path: folderPath)
        let shouldBeHeavy = itemCount > 100
        let isFavorite = isFavoriteFolder(path: folderPath)
        
        if shouldBeHeavy && !isCurrentlyHeavy {
            // ⬆️ FOLDER JUST BECAME HEAVY
            print("📊 [FinderLogic] Folder crossed threshold: \(itemCount) items")
            
            // Mark as heavy
            db.markAsHeavyFolder(path: folderPath, itemCount: itemCount)
            
            // If it's a favorite, start watching it
            if isFavorite {
                FolderWatcherManager.shared.startWatching(path: folderPath, itemName: folderName)
                print("👀 [FSEvents] Started watching newly-heavy favorite folder: \(folderName)")
            }
            
        } else if !shouldBeHeavy && isCurrentlyHeavy {
            // ⬇️ FOLDER JUST BECAME LIGHT
            print("📉 [FinderLogic] Folder dropped below threshold: \(itemCount) items")
            
            // Remove from heavy folders
            db.removeHeavyFolder(path: folderPath)
            
            // Stop watching it
            FolderWatcherManager.shared.stopWatching(path: folderPath)
            print("🛑 [FSEvents] Stopped watching - folder is now light: \(folderName)")
            
            // Clear the cache
            db.invalidateEnhancedCache(for: folderPath)
            
        } else if shouldBeHeavy && isCurrentlyHeavy {
            // 📊 FOLDER IS STILL HEAVY - update count
            db.updateHeavyFolderItemCount(path: folderPath, itemCount: itemCount)
        }
    }
}

// MARK: - Updated loadChildren Method
// Replace the caching section (STEP 4) in your loadChildren() with this:

/*
    // 📊 STEP 4: Handle folder watching status dynamically
    handleFolderWatchingStatus(folderPath: folderPath, itemCount: actualItemCount, folderName: node.name)
    
    if actualItemCount > 100 {
        print("📊 [EnhancedCache] Folder has \(actualItemCount) items - caching with thumbnails")
        
        // Convert nodes to EnhancedFolderItem format WITH THUMBNAILS
        let enhancedItems = convertToEnhancedFolderItems(nodes: nodes, folderURL: folderURL)
        
        // Save to Enhanced Cache
        db.saveEnhancedFolderContents(folderPath: folderPath, items: enhancedItems)
        print("💾 [EnhancedCache] Cached \(nodes.count) items (with thumbnails) for future instant loads!")
        print("   (Folder actually has \(actualItemCount) items, but caching \(nodes.count) displayed items)")
    } else {
        print("ℹ️ [EnhancedCache] Folder has only \(actualItemCount) items - not caching (threshold: 100)")
    }
*/
