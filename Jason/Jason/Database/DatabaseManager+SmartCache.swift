//
//  DatabaseManager+SmartCache.swift
//  Jason
//
//  Created by Timothy Velberg on 15/10/2025.
//
//  Smart folder caching system with automatic optimization

import Foundation
import SQLite3

extension DatabaseManager {
    
    // MARK: - Smart Cache Schema Setup
    
    /// Create tables for smart caching system (call once on app launch)
    func setupSmartCacheTables() {
        guard let db = db else { return }
        
        queue.async {
            // Table 1: Track heavy folders (folders with >100 items)
            let heavyFoldersSQL = """
            CREATE TABLE IF NOT EXISTS heavy_folders (
                path TEXT PRIMARY KEY,
                item_count INTEGER NOT NULL,
                first_marked_at REAL NOT NULL,
                last_accessed_at REAL NOT NULL
            )
            """
            
            if sqlite3_exec(db, heavyFoldersSQL, nil, nil, nil) == SQLITE_OK {
//                print("[SmartCache] ✅ Created heavy_folders table")
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("[SmartCache] ❌ Error creating heavy_folders: \(String(cString: error))")
                }
            }
            
            // Table 2: Cache folder contents for heavy folders
            let folderContentsSQL = """
            CREATE TABLE IF NOT EXISTS folder_contents (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                folder_path TEXT NOT NULL,
                item_name TEXT NOT NULL,
                item_path TEXT NOT NULL,
                is_directory INTEGER NOT NULL,
                modification_date REAL NOT NULL,
                cached_at REAL NOT NULL,
                UNIQUE(folder_path, item_path)
            )
            """
            
            if sqlite3_exec(db, folderContentsSQL, nil, nil, nil) == SQLITE_OK {
//                print("[SmartCache] ✅ Created folder_contents table")
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("[SmartCache] ❌ Error creating folder_contents: \(String(cString: error))")
                }
            }
            
            // Table 3: Track folder access for cleanup
            let folderAccessSQL = """
            CREATE TABLE IF NOT EXISTS folder_access (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                folder_path TEXT NOT NULL,
                accessed_at REAL NOT NULL
            )
            """
            
            if sqlite3_exec(db, folderAccessSQL, nil, nil, nil) == SQLITE_OK {
//                print("[SmartCache] ✅ Created folder_access table")
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("[SmartCache] ❌ Error creating folder_access: \(String(cString: error))")
                }
            }
            
            // Indexes for performance
            let indexes = [
                "CREATE INDEX IF NOT EXISTS idx_heavy_folders_last_accessed ON heavy_folders(last_accessed_at)",
                "CREATE INDEX IF NOT EXISTS idx_folder_contents_folder_path ON folder_contents(folder_path)",
                "CREATE INDEX IF NOT EXISTS idx_folder_access_path_time ON folder_access(folder_path, accessed_at)"
            ]
            
            for indexSQL in indexes {
                sqlite3_exec(db, indexSQL, nil, nil, nil)
            }
            
//            print("[SmartCache] ✅ Created all indexes")
//            print("[SmartCache] 🎉 Smart cache tables ready!")
        }
    }
    
    // MARK: - Heavy Folder Management
    
    /// Mark a folder as heavy (>100 items)
    func markAsHeavyFolder(path: String, itemCount: Int) {
        guard let db = db else { return }
        
        queue.async {
            let now = Date().timeIntervalSince1970
            
            let sql = """
            INSERT INTO heavy_folders (path, item_count, first_marked_at, last_accessed_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(path) DO UPDATE SET
                item_count = excluded.item_count,
                last_accessed_at = excluded.last_accessed_at
            """
            
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (path as NSString).utf8String, -1, nil)
                sqlite3_bind_int(statement, 2, Int32(itemCount))
                sqlite3_bind_double(statement, 3, now)
                sqlite3_bind_double(statement, 4, now)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("[SmartCache] 📊 Marked as heavy folder: \(path) (\(itemCount) items)")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("[SmartCache] ❌ Error marking heavy folder: \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("[SmartCache] ❌ Error preparing statement: \(String(cString: error))")
                }
            }
            
            sqlite3_finalize(statement)
        }
    }
    
    /// Check if a folder is marked as heavy
    func isHeavyFolder(path: String) -> Bool {
        guard let db = db else { return false }
        
        var isHeavy = false
        
        queue.sync {
            let sql = "SELECT 1 FROM heavy_folders WHERE path = ? LIMIT 1"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (path as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    isHeavy = true
                }
            }
            
            sqlite3_finalize(statement)
        }
        
        return isHeavy
    }
    
    /// Get all heavy folders
    func getAllHeavyFolders() -> [HeavyFolderInfo] {
        guard let db = db else { return [] }
        
        var folders: [HeavyFolderInfo] = []
        
        queue.sync {
            let sql = """
            SELECT path, item_count, first_marked_at, last_accessed_at
            FROM heavy_folders
            ORDER BY last_accessed_at DESC
            """
            
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    let path = String(cString: sqlite3_column_text(statement, 0))
                    let itemCount = Int(sqlite3_column_int(statement, 1))
                    let firstMarkedAt = Double(sqlite3_column_double(statement, 2))
                    let lastAccessedAt = Double(sqlite3_column_double(statement, 3))
                    
                    folders.append(HeavyFolderInfo(
                        path: path,
                        itemCount: itemCount,
                        firstMarkedAt: Date(timeIntervalSince1970: firstMarkedAt),
                        lastAccessedAt: Date(timeIntervalSince1970: lastAccessedAt)
                    ))
                }
            }
            
            sqlite3_finalize(statement)
        }
        
        return folders
    }
    
    // MARK: - Folder Contents Caching
    
    /// Save folder contents to cache
    func saveFolderContents(folderPath: String, items: [FolderItem]) {
        guard let db = db else { return }
        
        queue.async {
            let now = Date().timeIntervalSince1970
            
            // Begin transaction
            sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
            
            // Delete existing cached items for this folder
            let deleteSQL = "DELETE FROM folder_contents WHERE folder_path = ?"
            var deleteStatement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStatement, nil) == SQLITE_OK {
                sqlite3_bind_text(deleteStatement, 1, (folderPath as NSString).utf8String, -1, nil)
                sqlite3_step(deleteStatement)
            }
            sqlite3_finalize(deleteStatement)
            
            // Insert all items
            let insertSQL = """
            INSERT INTO folder_contents 
            (folder_path, item_name, item_path, is_directory, modification_date, cached_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """
            
            for item in items {
                var statement: OpaquePointer?
                
                if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
                    sqlite3_bind_text(statement, 1, (folderPath as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(statement, 2, (item.name as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(statement, 3, (item.path as NSString).utf8String, -1, nil)
                    sqlite3_bind_int(statement, 4, item.isDirectory ? 1 : 0)
                    sqlite3_bind_double(statement, 5, item.modificationDate.timeIntervalSince1970)
                    sqlite3_bind_double(statement, 6, now)
                    
                    sqlite3_step(statement)
                }
                
                sqlite3_finalize(statement)
            }
            
            // Commit transaction
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
            
            print("[SmartCache] 💾 Cached \(items.count) items for: \(folderPath)")
        }
    }
    
    /// Get cached folder contents
    func getCachedFolderContents(folderPath: String) -> [FolderItem]? {
        guard let db = db else { return nil }
        
        var items: [FolderItem] = []
        
        queue.sync {
            let sql = """
            SELECT item_name, item_path, is_directory, modification_date
            FROM folder_contents
            WHERE folder_path = ?
            ORDER BY is_directory DESC, item_name COLLATE NOCASE ASC
            """
            
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (folderPath as NSString).utf8String, -1, nil)
                
                while sqlite3_step(statement) == SQLITE_ROW {
                    let name = String(cString: sqlite3_column_text(statement, 0))
                    let path = String(cString: sqlite3_column_text(statement, 1))
                    let isDirectory = sqlite3_column_int(statement, 2) == 1
                    let modDate = Double(sqlite3_column_double(statement, 3))
                    
                    items.append(FolderItem(
                        name: name,
                        path: path,
                        isDirectory: isDirectory,
                        modificationDate: Date(timeIntervalSince1970: modDate)
                    ))
                }
            }
            
            sqlite3_finalize(statement)
        }
        
        return items.isEmpty ? nil : items
    }
    
    /// Remove cached contents for a folder
    func removeFolderContentsCache(folderPath: String) {
        guard let db = db else { return }
        
        queue.async {
            let sql = "DELETE FROM folder_contents WHERE folder_path = ?"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (folderPath as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("[SmartCache] 🗑️ Removed cache for: \(folderPath)")
                }
            }
            
            sqlite3_finalize(statement)
        }
    }
    
    // MARK: - Access Tracking
    
    /// Record that a folder was accessed
    func recordFolderAccess(folderPath: String) {
        guard let db = db else { return }
        
        queue.async {
            let now = Date().timeIntervalSince1970
            
            // Update last_accessed_at in heavy_folders if it exists
            let updateSQL = "UPDATE heavy_folders SET last_accessed_at = ? WHERE path = ?"
            var updateStatement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, updateSQL, -1, &updateStatement, nil) == SQLITE_OK {
                sqlite3_bind_double(updateStatement, 1, now)
                sqlite3_bind_text(updateStatement, 2, (folderPath as NSString).utf8String, -1, nil)
                sqlite3_step(updateStatement)
            }
            sqlite3_finalize(updateStatement)
            
            // Also log in folder_access
            let insertSQL = "INSERT INTO folder_access (folder_path, accessed_at) VALUES (?, ?)"
            var insertStatement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, insertSQL, -1, &insertStatement, nil) == SQLITE_OK {
                sqlite3_bind_text(insertStatement, 1, (folderPath as NSString).utf8String, -1, nil)
                sqlite3_bind_double(insertStatement, 2, now)
                sqlite3_step(insertStatement)
            }
            sqlite3_finalize(insertStatement)
        }
    }
    
    // MARK: - Cleanup Operations
    
    /// Find and remove heavy folders not accessed in the last N days
    func cleanupInactiveHeavyFolders(inactiveDays: Int = 30) {
        guard let db = db else { return }
        
        queue.async {
            let cutoffTime = Date().addingTimeInterval(-Double(inactiveDays) * 24 * 60 * 60).timeIntervalSince1970
            
            // Get folders to remove
            var foldersToRemove: [String] = []
            let selectSQL = "SELECT path FROM heavy_folders WHERE last_accessed_at < ?"
            var selectStatement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, selectSQL, -1, &selectStatement, nil) == SQLITE_OK {
                sqlite3_bind_double(selectStatement, 1, cutoffTime)
                
                while sqlite3_step(selectStatement) == SQLITE_ROW {
                    let path = String(cString: sqlite3_column_text(selectStatement, 0))
                    foldersToRemove.append(path)
                }
            }
            sqlite3_finalize(selectStatement)
            
            // Remove each inactive folder
            for path in foldersToRemove {
                // Remove from heavy_folders
                let deleteHeavySQL = "DELETE FROM heavy_folders WHERE path = ?"
                var deleteHeavyStmt: OpaquePointer?
                
                if sqlite3_prepare_v2(db, deleteHeavySQL, -1, &deleteHeavyStmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(deleteHeavyStmt, 1, (path as NSString).utf8String, -1, nil)
                    sqlite3_step(deleteHeavyStmt)
                }
                sqlite3_finalize(deleteHeavyStmt)
                
                // Remove cached contents
                let deleteContentsSQL = "DELETE FROM folder_contents WHERE folder_path = ?"
                var deleteContentsStmt: OpaquePointer?
                
                if sqlite3_prepare_v2(db, deleteContentsSQL, -1, &deleteContentsStmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(deleteContentsStmt, 1, (path as NSString).utf8String, -1, nil)
                    sqlite3_step(deleteContentsStmt)
                }
                sqlite3_finalize(deleteContentsStmt)
                
                print("[SmartCache] 🧹 Removed inactive heavy folder: \(path)")
            }
            
            if foldersToRemove.count > 0 {
                print("[SmartCache] 🧹 Cleaned up \(foldersToRemove.count) inactive heavy folders")
            }
        }
    }
    
    /// Clean up old access records (keep last 90 days)
    func cleanupOldAccessRecords(keepDays: Int = 90) {
        guard let db = db else { return }
        
        queue.async {
            let cutoffTime = Date().addingTimeInterval(-Double(keepDays) * 24 * 60 * 60).timeIntervalSince1970
            
            let sql = "DELETE FROM folder_access WHERE accessed_at < ?"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_double(statement, 1, cutoffTime)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    let deleted = sqlite3_changes(db)
                    if deleted > 0 {
                        print("[SmartCache] 🧹 Cleaned up \(deleted) old access records")
                    }
                }
            }
            
            sqlite3_finalize(statement)
        }
    }
}

// MARK: - Supporting Types

/// Information about a heavy folder
struct HeavyFolderInfo {
    let path: String
    let itemCount: Int
    let firstMarkedAt: Date
    let lastAccessedAt: Date
    
    var daysSinceLastAccess: Int {
        let interval = Date().timeIntervalSince(lastAccessedAt)
        return Int(interval / (24 * 60 * 60))
    }
}

/// Represents a file or folder item
struct FolderItem {
    let name: String
    let path: String
    let isDirectory: Bool
    let modificationDate: Date
}
