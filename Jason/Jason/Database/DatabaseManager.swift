//
//  DatabaseManager.swift
//  Jason
//
//  Created by Timothy Velberg on 15/10/2025.

import Foundation
import SQLite3
import AppKit

class DatabaseManager {
    
    // MARK: - Singleton
    
    static let shared = DatabaseManager()
    
    // MARK: - Properties
    
    private var db: OpaquePointer?
    private let databaseFileName = "Jason.db"
    private let queue = DispatchQueue(label: "com.jason.database", qos: .userInitiated)
    
    // MARK: - Initialization
    
    private init() {
        do {
            let dbPath = try getDatabasePath()
            print("📦 [DatabaseManager] Database path: \(dbPath)")
            
            // Open database
            if sqlite3_open(dbPath, &db) == SQLITE_OK {
                print("✅ [DatabaseManager] Database opened successfully")
                try setupDatabase()
            } else {
                print("❌ [DatabaseManager] Failed to open database")
                if let error = sqlite3_errmsg(db) {
                    print("   Error: \(String(cString: error))")
                }
            }
        } catch {
            print("❌ [DatabaseManager] Failed to initialize database: \(error)")
        }
    }
    
    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }
    
    // MARK: - Database Path
    
    private func getDatabasePath() throws -> String {
        let fileManager = FileManager.default
        
        // Get Application Support directory
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw DatabaseError.pathNotFound
        }
        
        // Create Jason directory if it doesn't exist
        let jasonDir = appSupport.appendingPathComponent("Jason", isDirectory: true)
        
        if !fileManager.fileExists(atPath: jasonDir.path) {
            try fileManager.createDirectory(at: jasonDir, withIntermediateDirectories: true)
            print("📁 [DatabaseManager] Created Jason directory at: \(jasonDir.path)")
        }
        
        let dbPath = jasonDir.appendingPathComponent(databaseFileName).path
        return dbPath
    }
    
    // MARK: - Schema Setup
    
    private func setupDatabase() throws {
        guard let db = db else {
            throw DatabaseError.notInitialized
        }
        
        // Create folder_cache table
        let folderCacheSQL = """
        CREATE TABLE IF NOT EXISTS folder_cache (
            path TEXT PRIMARY KEY,
            last_scanned INTEGER NOT NULL,
            items_json TEXT NOT NULL,
            item_count INTEGER NOT NULL
        );
        """
        
        // Create usage_history table
        let usageHistorySQL = """
        CREATE TABLE IF NOT EXISTS usage_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            item_path TEXT NOT NULL,
            item_type TEXT NOT NULL,
            access_count INTEGER NOT NULL DEFAULT 1,
            last_accessed INTEGER NOT NULL
        );
        """
        
        // Create favorites table
        let favoritesSQL = """
        CREATE TABLE IF NOT EXISTS favorites (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            path TEXT NOT NULL UNIQUE,
            icon_data BLOB,
            sort_order INTEGER NOT NULL
        );
        """
        
        // Create preferences table
        let preferencesSQL = """
        CREATE TABLE IF NOT EXISTS preferences (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """
        
        // Execute all schema creation
        let tables = [folderCacheSQL, usageHistorySQL, favoritesSQL, preferencesSQL]
        
        for sql in tables {
            if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to create table: \(String(cString: error))")
                }
                throw DatabaseError.schemaCreationFailed
            }
        }
        
        print("✅ [DatabaseManager] Database schema created/verified")
    }
    
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
                    print("❌ [DatabaseManager] Failed to prepare statement: \(String(cString: error))")
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
            let sql = """
            INSERT OR REPLACE INTO folder_cache (path, last_scanned, items_json, item_count)
            VALUES (?, ?, ?, ?);
            """
            
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (entry.path as NSString).utf8String, -1, nil)
                sqlite3_bind_int64(statement, 2, Int64(entry.lastScanned))
                sqlite3_bind_text(statement, 3, (entry.itemsJSON as NSString).utf8String, -1, nil)
                sqlite3_bind_int(statement, 4, Int32(entry.itemCount))
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("💾 [DatabaseManager] Saved folder cache for: \(entry.path) (\(entry.itemCount) items)")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to save: \(String(cString: error))")
                    }
                }
            }
            
            sqlite3_finalize(statement)
        }
    }
    
    /// Check if cache is stale (older than timeout)
    func isCacheStale(for path: String, timeout: TimeInterval = 1800) -> Bool {
        guard let entry = getFolderCache(for: path) else {
            return true // No cache = stale
        }
        
        let now = Date().timeIntervalSince1970
        let age = now - Double(entry.lastScanned)
        
        return age > timeout
    }
    
    /// Clear cache for specific folder
    func invalidateFolderCache(for path: String) {
        guard let db = db else { return }
        
        queue.async {
            let sql = "DELETE FROM folder_cache WHERE path = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (path as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("🗑️ [DatabaseManager] Invalidated cache for: \(path)")
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
            
            if sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK {
                print("🗑️ [DatabaseManager] Cleared all folder cache")
            }
        }
    }
    
    /// Get cache statistics
    func getCacheStats() -> (totalFolders: Int, totalItems: Int)? {
        guard let db = db else { return nil }
        
        var stats: (Int, Int)?
        
        queue.sync {
            var folderCount = 0
            var itemCount = 0
            
            // Get folder count
            var statement1: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM folder_cache;", -1, &statement1, nil) == SQLITE_OK {
                if sqlite3_step(statement1) == SQLITE_ROW {
                    folderCount = Int(sqlite3_column_int(statement1, 0))
                }
            }
            sqlite3_finalize(statement1)
            
            // Get total item count
            var statement2: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT SUM(item_count) FROM folder_cache;", -1, &statement2, nil) == SQLITE_OK {
                if sqlite3_step(statement2) == SQLITE_ROW {
                    itemCount = Int(sqlite3_column_int(statement2, 0))
                }
            }
            sqlite3_finalize(statement2)
            
            stats = (folderCount, itemCount)
        }
        
        return stats
    }
    
    // MARK: - Usage History Methods
    
    /// Record folder/file/app access
    func recordAccess(path: String, type: String) {
        guard let db = db else { return }
        
        let now = Int(Date().timeIntervalSince1970)
        
        queue.async {
            // Check if entry exists
            let checkSQL = "SELECT id, access_count FROM usage_history WHERE item_path = ?;"
            var checkStatement: OpaquePointer?
            var existingId: Int?
            var existingCount = 0
            
            if sqlite3_prepare_v2(db, checkSQL, -1, &checkStatement, nil) == SQLITE_OK {
                sqlite3_bind_text(checkStatement, 1, (path as NSString).utf8String, -1, nil)
                
                if sqlite3_step(checkStatement) == SQLITE_ROW {
                    existingId = Int(sqlite3_column_int(checkStatement, 0))
                    existingCount = Int(sqlite3_column_int(checkStatement, 1))
                }
            }
            sqlite3_finalize(checkStatement)
            
            if let id = existingId {
                // Update existing
                let updateSQL = "UPDATE usage_history SET access_count = ?, last_accessed = ? WHERE id = ?;"
                var updateStatement: OpaquePointer?
                
                if sqlite3_prepare_v2(db, updateSQL, -1, &updateStatement, nil) == SQLITE_OK {
                    sqlite3_bind_int(updateStatement, 1, Int32(existingCount + 1))
                    sqlite3_bind_int64(updateStatement, 2, Int64(now))
                    sqlite3_bind_int(updateStatement, 3, Int32(id))
                    sqlite3_step(updateStatement)
                }
                sqlite3_finalize(updateStatement)
            } else {
                // Insert new
                let insertSQL = "INSERT INTO usage_history (item_path, item_type, access_count, last_accessed) VALUES (?, ?, 1, ?);"
                var insertStatement: OpaquePointer?
                
                if sqlite3_prepare_v2(db, insertSQL, -1, &insertStatement, nil) == SQLITE_OK {
                    sqlite3_bind_text(insertStatement, 1, (path as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(insertStatement, 2, (type as NSString).utf8String, -1, nil)
                    sqlite3_bind_int64(insertStatement, 3, Int64(now))
                    sqlite3_step(insertStatement)
                }
                sqlite3_finalize(insertStatement)
            }
        }
    }
    
    /// Get most recently used items
    func getMRU(type: String? = nil, limit: Int = 10) -> [UsageHistoryEntry] {
        guard let db = db else { return [] }
        
        var results: [UsageHistoryEntry] = []
        
        queue.sync {
            var sql = "SELECT id, item_path, item_type, access_count, last_accessed FROM usage_history"
            
            if let type = type {
                sql += " WHERE item_type = '\(type)'"
            }
            
            sql += " ORDER BY last_accessed DESC LIMIT \(limit);"
            
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
            }
            
            sqlite3_finalize(statement)
        }
        
        return results
    }
    
    // MARK: - Favorites Methods
    
    /// Get all favorites
    func getFavorites() -> [FavoriteEntry] {
        guard let db = db else { return [] }
        
        var results: [FavoriteEntry] = []
        
        queue.sync {
            let sql = "SELECT id, name, path, icon_data, sort_order FROM favorites ORDER BY sort_order;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(statement, 0))
                    let name = String(cString: sqlite3_column_text(statement, 1))
                    let path = String(cString: sqlite3_column_text(statement, 2))
                    
                    var iconData: Data?
                    if let blob = sqlite3_column_blob(statement, 3) {
                        let size = sqlite3_column_bytes(statement, 3)
                        iconData = Data(bytes: blob, count: Int(size))
                    }
                    
                    let sortOrder = Int(sqlite3_column_int(statement, 4))
                    
                    results.append(FavoriteEntry(
                        id: id,
                        name: name,
                        path: path,
                        iconData: iconData,
                        sortOrder: sortOrder
                    ))
                }
            }
            
            sqlite3_finalize(statement)
        }
        
        return results
    }
    
    /// Add favorite
    func addFavorite(name: String, path: String, iconData: Data?, sortOrder: Int) {
        guard let db = db else { return }
        
        queue.async {
            let sql = "INSERT INTO favorites (name, path, icon_data, sort_order) VALUES (?, ?, ?, ?);"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (name as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 2, (path as NSString).utf8String, -1, nil)
                
                if let iconData = iconData {
                    iconData.withUnsafeBytes { bytes in
                        sqlite3_bind_blob(statement, 3, bytes.baseAddress, Int32(iconData.count), nil)
                    }
                } else {
                    sqlite3_bind_null(statement, 3)
                }
                
                sqlite3_bind_int(statement, 4, Int32(sortOrder))
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("⭐ [DatabaseManager] Added favorite: \(name)")
                }
            }
            
            sqlite3_finalize(statement)
        }
    }
    
    /// Remove favorite
    func removeFavorite(path: String) {
        guard let db = db else { return }
        
        queue.async {
            let sql = "DELETE FROM favorites WHERE path = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (path as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("🗑️ [DatabaseManager] Removed favorite: \(path)")
                }
            }
            
            sqlite3_finalize(statement)
        }
    }
    
    // MARK: - Preferences Methods
    
    /// Get preference value
    func getPreference(key: String) -> String? {
        guard let db = db else { return nil }
        
        var result: String?
        
        queue.sync {
            let sql = "SELECT value FROM preferences WHERE key = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (key as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    result = String(cString: sqlite3_column_text(statement, 0))
                }
            }
            
            sqlite3_finalize(statement)
        }
        
        return result
    }
    
    /// Set preference value
    func setPreference(key: String, value: String) {
        guard let db = db else { return }
        
        queue.async {
            let sql = "INSERT OR REPLACE INTO preferences (key, value) VALUES (?, ?);"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (key as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 2, (value as NSString).utf8String, -1, nil)
                sqlite3_step(statement)
            }
            
            sqlite3_finalize(statement)
        }
    }
}

// MARK: - Models

struct FolderCacheEntry {
    let path: String
    let lastScanned: Int
    let itemsJSON: String
    let itemCount: Int
}

struct UsageHistoryEntry {
    let id: Int?
    let itemPath: String
    let itemType: String
    var accessCount: Int
    var lastAccessed: Int
}

struct FavoriteEntry {
    let id: Int?
    let name: String
    let path: String
    let iconData: Data?
    let sortOrder: Int
}

// MARK: - Errors

enum DatabaseError: Error {
    case notInitialized
    case pathNotFound
    case schemaCreationFailed
    case saveFailed
    case fetchFailed
}
