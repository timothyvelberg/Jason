//
//  DatabaseManager+EnhancedCache.swift
//  Jason
//
//  Created by Timothy Velberg on 25/10/2025.
//


import Foundation
import AppKit
import SQLite3

// MARK: - Enhanced Cache Data Structures

/// Enhanced folder item with all data needed to create FunctionNode without disk access
struct EnhancedFolderItem {
    let name: String
    let path: String
    let isDirectory: Bool
    let modificationDate: Date
    
    // Enhanced fields for instant loading
    let fileExtension: String
    let fileSize: Int64
    let hasCustomIcon: Bool
    let isImageFile: Bool
    let thumbnailData: Data?
    let folderConfigJSON: String?
    
    init(
        name: String,
        path: String,
        isDirectory: Bool,
        modificationDate: Date,
        fileExtension: String = "",
        fileSize: Int64 = 0,
        hasCustomIcon: Bool = false,
        isImageFile: Bool = false,
        thumbnailData: Data? = nil,
        folderConfigJSON: String? = nil
    ) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.modificationDate = modificationDate
        self.fileExtension = fileExtension
        self.fileSize = fileSize
        self.hasCustomIcon = hasCustomIcon
        self.isImageFile = isImageFile
        self.thumbnailData = thumbnailData
        self.folderConfigJSON = folderConfigJSON
    }
}

// MARK: - Database Manager Enhanced Cache Extension

extension DatabaseManager {
    
    // MARK: - Table Creation
    
    /// Create enhanced cache tables with thumbnail support
    func createEnhancedCacheTables() {
        guard let db = db else {
            print("❌ [EnhancedCache] Database not initialized")
            return
        }
        
        print("✅ [EnhancedCache] Database pointer is valid: \(db)")
        
        // Enhanced folder contents table
        let createEnhancedContentsTable = """
        CREATE TABLE IF NOT EXISTS folder_contents_enhanced (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            folder_path TEXT NOT NULL,
            item_name TEXT NOT NULL,
            item_path TEXT NOT NULL,
            is_directory INTEGER NOT NULL,
            modification_date INTEGER NOT NULL,
            
            -- Enhanced fields
            file_extension TEXT,
            file_size INTEGER,
            has_custom_icon INTEGER DEFAULT 0,
            is_image_file INTEGER DEFAULT 0,
            thumbnail_data BLOB,
            folder_config_json TEXT,
            
            cached_at INTEGER NOT NULL,
            
            UNIQUE(folder_path, item_path)
        );
        """
        
        if sqlite3_exec(db, createEnhancedContentsTable, nil, nil, nil) == SQLITE_OK {
            print("[EnhancedCache] ✅ Created folder_contents_enhanced table")
        } else {
            let error = String(cString: sqlite3_errmsg(db))
            print("[EnhancedCache] ❌ Failed to create table: \(error)")
        }
        
        // Create indexes for fast lookups
        let createIndexes = """
        CREATE INDEX IF NOT EXISTS idx_enhanced_folder_path ON folder_contents_enhanced(folder_path);
        CREATE INDEX IF NOT EXISTS idx_enhanced_cached_at ON folder_contents_enhanced(cached_at);
        """
        
        if sqlite3_exec(db, createIndexes, nil, nil, nil) == SQLITE_OK {
            print("[EnhancedCache] ✅ Created indexes")
        } else {
            let error = String(cString: sqlite3_errmsg(db))
            print("[EnhancedCache] ❌ Failed to create indexes: \(error)")
        }
        
        print("[EnhancedCache] 🎉 Enhanced cache tables ready!")
    }
    
    // MARK: - Save Enhanced Cache
    
    /// Save folder contents with thumbnails to enhanced cache
    func saveEnhancedFolderContents(folderPath: String, items: [EnhancedFolderItem]) {
        guard let db = db else {
            print("❌ [EnhancedCache] Database not initialized")
            return
        }
        
        queue.sync {
            let now = Int(Date().timeIntervalSince1970)
            
            // First, delete existing cache for this folder
            let deleteSQL = "DELETE FROM folder_contents_enhanced WHERE folder_path = ?;"
            var deleteStmt: OpaquePointer?
            
            if sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(deleteStmt, 1, (folderPath as NSString).utf8String, -1, nil)
                
                if sqlite3_step(deleteStmt) == SQLITE_DONE {
                    print("[EnhancedCache] 🗑️ Cleared old cache for: \(folderPath)")
                } else {
                    let error = String(cString: sqlite3_errmsg(db))
                    print("[EnhancedCache] ⚠️ Failed to clear old cache: \(error)")
                }
            }
            sqlite3_finalize(deleteStmt)
            
            // Insert new items
            let insertSQL = """
            INSERT INTO folder_contents_enhanced (
                folder_path, item_name, item_path, is_directory, modification_date,
                file_extension, file_size, has_custom_icon, is_image_file,
                thumbnail_data, folder_config_json, cached_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            
            var insertStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) != SQLITE_OK {
                let error = String(cString: sqlite3_errmsg(db))
                print("[EnhancedCache] ❌ Failed to prepare insert: \(error)")
                return
            }
            
            var savedCount = 0
            var thumbnailCount = 0
            
            for item in items {
                sqlite3_reset(insertStmt)
                
                // Bind values
                sqlite3_bind_text(insertStmt, 1, (folderPath as NSString).utf8String, -1, nil)
                sqlite3_bind_text(insertStmt, 2, (item.name as NSString).utf8String, -1, nil)
                sqlite3_bind_text(insertStmt, 3, (item.path as NSString).utf8String, -1, nil)
                sqlite3_bind_int(insertStmt, 4, item.isDirectory ? 1 : 0)
                sqlite3_bind_int64(insertStmt, 5, Int64(item.modificationDate.timeIntervalSince1970))
                
                sqlite3_bind_text(insertStmt, 6, (item.fileExtension as NSString).utf8String, -1, nil)
                sqlite3_bind_int64(insertStmt, 7, item.fileSize)
                sqlite3_bind_int(insertStmt, 8, item.hasCustomIcon ? 1 : 0)
                sqlite3_bind_int(insertStmt, 9, item.isImageFile ? 1 : 0)
                
                // Bind thumbnail data (BLOB)
                if let thumbnailData = item.thumbnailData {
                    thumbnailData.withUnsafeBytes { bytes in
                        sqlite3_bind_blob(insertStmt, 10, bytes.baseAddress, Int32(thumbnailData.count), nil)
                    }
                    thumbnailCount += 1
                } else {
                    sqlite3_bind_null(insertStmt, 10)
                }
                
                // Bind folder config JSON
                if let configJSON = item.folderConfigJSON {
                    sqlite3_bind_text(insertStmt, 11, (configJSON as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(insertStmt, 11)
                }
                
                sqlite3_bind_int64(insertStmt, 12, Int64(now))
                
                if sqlite3_step(insertStmt) == SQLITE_DONE {
                    savedCount += 1
                } else {
                    let error = String(cString: sqlite3_errmsg(db))
                    print("[EnhancedCache] ⚠️ Failed to insert item '\(item.name)': \(error)")
                }
            }
            
            DispatchQueue.main.async {
                NotificationCenter.default.postProviderUpdate(
                    providerId: "finder-logic",
                    folderPath: folderPath
                )
            }
            
            sqlite3_finalize(insertStmt)
            
            print("[EnhancedCache] 💾 Cached \(savedCount) items (\(thumbnailCount) with thumbnails) for: \(folderPath)")
            DispatchQueue.main.async {
                NotificationCenter.default.postProviderUpdate(
                    providerId: "finder-logic",
                    folderPath: folderPath
                )
                print("📢 Posted update notification for folder: \(folderPath)")
            }
        }
    }
    // MARK: - Load Enhanced Cache
    
    /// Get cached folder contents with thumbnails
    func getEnhancedCachedFolderContents(folderPath: String) -> [EnhancedFolderItem]? {
        guard let db = db else {
            print("❌ [EnhancedCache] Database not initialized")
            return nil
        }
        
        return queue.sync {
            let sql = """
            SELECT item_name, item_path, is_directory, modification_date,
                   file_extension, file_size, has_custom_icon, is_image_file,
                   thumbnail_data, folder_config_json
            FROM folder_contents_enhanced
            WHERE folder_path = ?
            ORDER BY modification_date DESC;
            """
            
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                let error = String(cString: sqlite3_errmsg(db))
                print("[EnhancedCache] ❌ Failed to prepare query: \(error)")
                return nil
            }
            
            sqlite3_bind_text(statement, 1, (folderPath as NSString).utf8String, -1, nil)
            
            var items: [EnhancedFolderItem] = []
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let name = String(cString: sqlite3_column_text(statement, 0))
                let path = String(cString: sqlite3_column_text(statement, 1))
                let isDirectory = sqlite3_column_int(statement, 2) == 1
                let modDate = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 3)))
                
                let fileExtension = sqlite3_column_text(statement, 4) != nil ? String(cString: sqlite3_column_text(statement, 4)) : ""
                let fileSize = sqlite3_column_int64(statement, 5)
                let hasCustomIcon = sqlite3_column_int(statement, 6) == 1
                let isImageFile = sqlite3_column_int(statement, 7) == 1
                
                // Load thumbnail data (BLOB)
                var thumbnailData: Data?
                if let blob = sqlite3_column_blob(statement, 8) {
                    let blobSize = sqlite3_column_bytes(statement, 8)
                    thumbnailData = Data(bytes: blob, count: Int(blobSize))
                }
                
                // Load folder config JSON
                var folderConfigJSON: String?
                if sqlite3_column_text(statement, 9) != nil {
                    folderConfigJSON = String(cString: sqlite3_column_text(statement, 9))
                }
                
                let item = EnhancedFolderItem(
                    name: name,
                    path: path,
                    isDirectory: isDirectory,
                    modificationDate: modDate,
                    fileExtension: fileExtension,
                    fileSize: fileSize,
                    hasCustomIcon: hasCustomIcon,
                    isImageFile: isImageFile,
                    thumbnailData: thumbnailData,
                    folderConfigJSON: folderConfigJSON
                )
                
                items.append(item)
            }
            
            sqlite3_finalize(statement)
            
            if items.isEmpty {
                return nil
            }
            
            print("[EnhancedCache] ⚡ Loaded \(items.count) items from enhanced cache")
            return items
        }
    }
    // MARK: - Cache Management
    
    /// Check if enhanced cache exists for a folder
    func hasEnhancedCache(for folderPath: String) -> Bool {
        guard let db = db else { return false }
        
        let sql = "SELECT COUNT(*) FROM folder_contents_enhanced WHERE folder_path = ?;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        
        sqlite3_bind_text(statement, 1, (folderPath as NSString).utf8String, -1, nil)
        
        var count = 0
        if sqlite3_step(statement) == SQLITE_ROW {
            count = Int(sqlite3_column_int(statement, 0))
        }
        
        sqlite3_finalize(statement)
        return count > 0
    }
    
    func getEnhancedCacheTimestamp(folderPath: String) -> Date? {
        guard let db = db else { return nil }
        
        return queue.sync {
            let sql = "SELECT MAX(cached_at) FROM folder_contents_enhanced WHERE folder_path = ?;"
            var statement: OpaquePointer?
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                let error = String(cString: sqlite3_errmsg(db))
                print("[EnhancedCache] ❌ Failed to prepare timestamp query: \(error)")
                return nil
            }
            
            sqlite3_bind_text(statement, 1, (folderPath as NSString).utf8String, -1, nil)
            
            var timestamp: Date?
            if sqlite3_step(statement) == SQLITE_ROW {
                let cachedAt = sqlite3_column_int64(statement, 0)
                if cachedAt > 0 {
                    timestamp = Date(timeIntervalSince1970: TimeInterval(cachedAt))
                }
            }
            
            sqlite3_finalize(statement)
            return timestamp
        }
    }
    
    /// Invalidate enhanced cache for a specific folder
    func invalidateEnhancedCache(for folderPath: String) {
        guard let db = db else { return }
        
        queue.sync {
            // First, check how many rows exist BEFORE deletion
            let countSQL = "SELECT COUNT(*) FROM folder_contents_enhanced WHERE folder_path = ?;"
            var countStmt: OpaquePointer?
            var beforeCount = 0
            
            if sqlite3_prepare_v2(db, countSQL, -1, &countStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(countStmt, 1, (folderPath as NSString).utf8String, -1, nil)
                if sqlite3_step(countStmt) == SQLITE_ROW {
                    beforeCount = Int(sqlite3_column_int(countStmt, 0))
                }
            }
            sqlite3_finalize(countStmt)
            
            print("[EnhancedCache] 🔍 Before DELETE: \(beforeCount) rows for '\(folderPath)'")
            
            // Now delete
            let sql = "DELETE FROM folder_contents_enhanced WHERE folder_path = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (folderPath as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    let deletedRows = sqlite3_changes(db)
                    print("[EnhancedCache] 🗑️ Invalidated cache for: \(folderPath)")
                    print("[EnhancedCache] 🗑️ Deleted \(deletedRows) rows (expected \(beforeCount))")
                    
                    // Verify deletion
                    if deletedRows == 0 && beforeCount > 0 {
                        print("[EnhancedCache] ⚠️ WARNING: DELETE didn't remove any rows, but \(beforeCount) existed!")
                    }
                } else {
                    let error = String(cString: sqlite3_errmsg(db))
                    print("[EnhancedCache] ⚠️ Failed to invalidate: \(error)")
                }
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                print("[EnhancedCache] ⚠️ Failed to prepare DELETE: \(error)")
            }
            
            sqlite3_finalize(statement)
            
            // Verify after deletion
            var afterStmt: OpaquePointer?
            var afterCount = 0
            if sqlite3_prepare_v2(db, countSQL, -1, &afterStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(afterStmt, 1, (folderPath as NSString).utf8String, -1, nil)
                if sqlite3_step(afterStmt) == SQLITE_ROW {
                    afterCount = Int(sqlite3_column_int(afterStmt, 0))
                }
            }
            sqlite3_finalize(afterStmt)
            
            print("[EnhancedCache] ✅ After DELETE: \(afterCount) rows remaining")
        }
    }
    
    /// Clean up old enhanced cache entries (older than 7 days)
    func cleanupOldEnhancedCache() {
        guard let db = db else { return }
        
        let sevenDaysAgo = Int(Date().timeIntervalSince1970) - (7 * 24 * 60 * 60)
        let sql = "DELETE FROM folder_contents_enhanced WHERE cached_at < ?;"
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, Int64(sevenDaysAgo))
            
            if sqlite3_step(statement) == SQLITE_DONE {
                let deleted = sqlite3_changes(db)
                if deleted > 0 {
                    print("[EnhancedCache] 🧹 Cleaned up \(deleted) old cache entries")
                }
            }
        }
        
        sqlite3_finalize(statement)
    }
    
    /// Get cache size statistics
    func getEnhancedCacheStats() -> (folders: Int, items: Int, thumbnails: Int, totalSize: Int64) {
        guard let db = db else { return (0, 0, 0, 0) }
        
        let sql = """
        SELECT 
            COUNT(DISTINCT folder_path) as folder_count,
            COUNT(*) as item_count,
            SUM(CASE WHEN thumbnail_data IS NOT NULL THEN 1 ELSE 0 END) as thumbnail_count,
            SUM(LENGTH(thumbnail_data)) as total_size
        FROM folder_contents_enhanced;
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return (0, 0, 0, 0)
        }
        
        var stats = (folders: 0, items: 0, thumbnails: 0, totalSize: Int64(0))
        
        if sqlite3_step(statement) == SQLITE_ROW {
            stats.folders = Int(sqlite3_column_int(statement, 0))
            stats.items = Int(sqlite3_column_int(statement, 1))
            stats.thumbnails = Int(sqlite3_column_int(statement, 2))
            stats.totalSize = sqlite3_column_int64(statement, 3)
        }
        
        sqlite3_finalize(statement)
        return stats
    }
}
