//
//  DatabaseManager+Cache.swift
//  Jason
//
//  Created by Timothy Velberg on 15/10/2025.

import Foundation
import SQLite3

extension DatabaseManager {
    
    // MARK: - Folder Cache Methods
    
    /// Get cached folder contents
    func getFolderCache(for path: String) -> FolderCacheEntry? {
        guard let db = db else { return nil }
        
        var result: FolderCacheEntry?
        
        queue.sync {
            let sql = "SELECT path, last_scanned, items_json, item_count FROM folder_cache WHERE path = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (path as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    let path = String(cString: sqlite3_column_text(statement, 0))
                    let lastScanned = Int(sqlite3_column_int64(statement, 1))
                    let itemsJSON = String(cString: sqlite3_column_text(statement, 2))
                    let itemCount = Int(sqlite3_column_int(statement, 3))
                    
                    result = FolderCacheEntry(
                        path: path,
                        lastScanned: lastScanned,
                        itemsJSON: itemsJSON,
                        itemCount: itemCount
                    )
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare SELECT for folder cache '\(path)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return result
    }
    
    /// Save folder contents to cache
    func saveFolderCache(_ entry: FolderCacheEntry) {
        guard let db = db else { return }
        
        queue.async {
            let sql = "INSERT OR REPLACE INTO folder_cache (path, last_scanned, items_json, item_count) VALUES (?, ?, ?, ?);"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (entry.path as NSString).utf8String, -1, nil)
                sqlite3_bind_int64(statement, 2, Int64(entry.lastScanned))
                sqlite3_bind_text(statement, 3, (entry.itemsJSON as NSString).utf8String, -1, nil)
                sqlite3_bind_int(statement, 4, Int32(entry.itemCount))
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("💾 [DatabaseManager] Cached folder contents: \(entry.path) (\(entry.itemCount) items)")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to save folder cache for '\(entry.path)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare INSERT for folder cache '\(entry.path)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
    }
    
    /// Check if cache is stale (older than 1 hour)
    func isCacheStale(for path: String, maxAge: TimeInterval = 3600) -> Bool {
        guard let cache = getFolderCache(for: path) else {
            return true // No cache = stale
        }
        
        let now = Int(Date().timeIntervalSince1970)
        let age = now - cache.lastScanned
        
        return age > Int(maxAge)
    }
    
    /// Clear cache for specific folder
    func clearFolderCache(for path: String) {
        guard let db = db else { return }
        
        queue.async {
            let sql = "DELETE FROM folder_cache WHERE path = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (path as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("🗑️ [DatabaseManager] Cleared cache for: \(path)")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to clear cache for '\(path)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare DELETE for folder cache '\(path)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
    }
    
    /// Clear all folder cache
    func clearAllFolderCache() {
        guard let db = db else { return }
        
        queue.async {
            let sql = "DELETE FROM folder_cache;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("🗑️ [DatabaseManager] Cleared all folder cache")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to clear all folder cache: \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare DELETE for all folder cache: \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
    }
    
    // MARK: - Usage History Methods
    
    /// Record or update usage history for a file/folder
    func recordUsageHistory(itemPath: String, itemType: String) {
        guard let db = db else { return }
        
        queue.async {
            let now = Int(Date().timeIntervalSince1970)
            
            // Check if entry exists
            let checkSQL = "SELECT id, access_count FROM usage_history WHERE item_path = ?;"
            var checkStatement: OpaquePointer?
            var existingId: Int?
            var currentCount = 0
            
            if sqlite3_prepare_v2(db, checkSQL, -1, &checkStatement, nil) == SQLITE_OK {
                sqlite3_bind_text(checkStatement, 1, (itemPath as NSString).utf8String, -1, nil)
                
                if sqlite3_step(checkStatement) == SQLITE_ROW {
                    existingId = Int(sqlite3_column_int(checkStatement, 0))
                    currentCount = Int(sqlite3_column_int(checkStatement, 1))
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare CHECK for usage history '\(itemPath)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(checkStatement)
            
            if let id = existingId {
                // Update existing entry
                let updateSQL = "UPDATE usage_history SET access_count = ?, last_accessed = ? WHERE id = ?;"
                var updateStatement: OpaquePointer?
                
                if sqlite3_prepare_v2(db, updateSQL, -1, &updateStatement, nil) == SQLITE_OK {
                    sqlite3_bind_int(updateStatement, 1, Int32(currentCount + 1))
                    sqlite3_bind_int64(updateStatement, 2, Int64(now))
                    sqlite3_bind_int(updateStatement, 3, Int32(id))
                    
                    if sqlite3_step(updateStatement) == SQLITE_DONE {
                        print("📊 [DatabaseManager] Updated usage history: \(itemPath)")
                    } else {
                        if let error = sqlite3_errmsg(db) {
                            print("❌ [DatabaseManager] Failed to update usage history for '\(itemPath)': \(String(cString: error))")
                        }
                    }
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to prepare UPDATE for usage history '\(itemPath)': \(String(cString: error))")
                    }
                }
                sqlite3_finalize(updateStatement)
            } else {
                // Insert new entry
                let insertSQL = "INSERT INTO usage_history (item_path, item_type, access_count, last_accessed) VALUES (?, ?, 1, ?);"
                var insertStatement: OpaquePointer?
                
                if sqlite3_prepare_v2(db, insertSQL, -1, &insertStatement, nil) == SQLITE_OK {
                    sqlite3_bind_text(insertStatement, 1, (itemPath as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(insertStatement, 2, (itemType as NSString).utf8String, -1, nil)
                    sqlite3_bind_int64(insertStatement, 3, Int64(now))
                    
                    if sqlite3_step(insertStatement) == SQLITE_DONE {
                        print("📊 [DatabaseManager] Created usage history: \(itemPath)")
                    } else {
                        if let error = sqlite3_errmsg(db) {
                            print("❌ [DatabaseManager] Failed to insert usage history for '\(itemPath)': \(String(cString: error))")
                        }
                    }
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to prepare INSERT for usage history '\(itemPath)': \(String(cString: error))")
                    }
                }
                sqlite3_finalize(insertStatement)
            }
        }
    }
    
    /// Get usage history, optionally filtered by type
    func getUsageHistory(type: String? = nil, limit: Int = 50) -> [UsageHistoryEntry] {
        guard let db = db else { return [] }
        
        var results: [UsageHistoryEntry] = []
        
        queue.sync {
            var sql = "SELECT id, item_path, item_type, access_count, last_accessed FROM usage_history"
            if let type = type {
                sql += " WHERE item_type = '\(type)'"
            }
            sql += " ORDER BY access_count DESC, last_accessed DESC LIMIT \(limit);"
            
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(statement, 0))
                    let itemPath = String(cString: sqlite3_column_text(statement, 1))
                    let itemType = String(cString: sqlite3_column_text(statement, 2))
                    let accessCount = Int(sqlite3_column_int(statement, 3))
                    let lastAccessed = Int(sqlite3_column_int64(statement, 4))
                    
                    results.append(UsageHistoryEntry(
                        id: id,
                        itemPath: itemPath,
                        itemType: itemType,
                        accessCount: accessCount,
                        lastAccessed: lastAccessed
                    ))
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare SELECT for usage history: \(String(cString: error))")
                }
            }
            
            sqlite3_finalize(statement)
        }
        
        return results
    }
}
