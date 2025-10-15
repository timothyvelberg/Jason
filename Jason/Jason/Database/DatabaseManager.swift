//
//  DatabaseManager.swift
//  Jason
//
//  Created by Timothy Velberg on 15/10/2025.
//  Database manager for persistent caching and user data
//

import Foundation
import GRDB
import AppKit

class DatabaseManager {
    
    // MARK: - Singleton
    
    static let shared = DatabaseManager()
    
    // MARK: - Properties
    
    private var dbQueue: DatabaseQueue?
    private let databaseFileName = "Jason.db"
    
    // MARK: - Initialization
    
    private init() {
        do {
            let dbPath = try getDatabasePath()
            print("📦 [DatabaseManager] Database path: \(dbPath)")
            
            dbQueue = try DatabaseQueue(path: dbPath)
            try setupDatabase()
            
            print("✅ [DatabaseManager] Database initialized successfully")
        } catch {
            print("❌ [DatabaseManager] Failed to initialize database: \(error)")
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
        guard let dbQueue = dbQueue else {
            throw DatabaseError.notInitialized
        }
        
        try dbQueue.write { db in
            // Create folder_cache table
            try db.create(table: "folder_cache", ifNotExists: true) { table in
                table.column("path", .text).primaryKey()
                table.column("last_scanned", .integer).notNull()
                table.column("items_json", .text).notNull()
                table.column("item_count", .integer).notNull()
            }
            
            // Create usage_history table (for MRU tracking)
            try db.create(table: "usage_history", ifNotExists: true) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("item_path", .text).notNull()
                table.column("item_type", .text).notNull() // "folder", "file", "app"
                table.column("access_count", .integer).notNull().defaults(to: 1)
                table.column("last_accessed", .integer).notNull()
            }
            
            // Create favorites table
            try db.create(table: "favorites", ifNotExists: true) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("name", .text).notNull()
                table.column("path", .text).notNull().unique()
                table.column("icon_data", .blob)
                table.column("sort_order", .integer).notNull()
            }
            
            // Create preferences table
            try db.create(table: "preferences", ifNotExists: true) { table in
                table.column("key", .text).primaryKey()
                table.column("value", .text).notNull()
            }
            
            print("✅ [DatabaseManager] Database schema created/verified")
        }
    }
    
    // MARK: - Folder Cache Methods
    
    /// Get cached folder contents
    func getFolderCache(for path: String) -> FolderCacheEntry? {
        guard let dbQueue = dbQueue else { return nil }
        
        do {
            return try dbQueue.read { db in
                try FolderCacheEntry.fetchOne(db, key: path)
            }
        } catch {
            print("❌ [DatabaseManager] Failed to get folder cache for '\(path)': \(error)")
            return nil
        }
    }
    
    /// Save folder contents to cache
    func saveFolderCache(_ entry: FolderCacheEntry) {
        guard let dbQueue = dbQueue else { return }
        
        do {
            try dbQueue.write { db in
                try entry.save(db)
            }
            print("💾 [DatabaseManager] Saved folder cache for: \(entry.path) (\(entry.itemCount) items)")
        } catch {
            print("❌ [DatabaseManager] Failed to save folder cache: \(error)")
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
        guard let dbQueue = dbQueue else { return }
        
        do {
            try dbQueue.write { db in
                try db.execute(sql: "DELETE FROM folder_cache WHERE path = ?", arguments: [path])
            }
            print("🗑️ [DatabaseManager] Invalidated cache for: \(path)")
        } catch {
            print("❌ [DatabaseManager] Failed to invalidate cache: \(error)")
        }
    }
    
    /// Clear all folder cache
    func clearAllFolderCache() {
        guard let dbQueue = dbQueue else { return }
        
        do {
            try dbQueue.write { db in
                try db.execute(sql: "DELETE FROM folder_cache")
            }
            print("🗑️ [DatabaseManager] Cleared all folder cache")
        } catch {
            print("❌ [DatabaseManager] Failed to clear cache: \(error)")
        }
    }
    
    /// Get cache statistics
    func getCacheStats() -> (totalFolders: Int, totalItems: Int)? {
        guard let dbQueue = dbQueue else { return nil }
        
        do {
            return try dbQueue.read { db in
                let folderCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM folder_cache") ?? 0
                let itemCount = try Int.fetchOne(db, sql: "SELECT SUM(item_count) FROM folder_cache") ?? 0
                return (folderCount, itemCount)
            }
        } catch {
            print("❌ [DatabaseManager] Failed to get cache stats: \(error)")
            return nil
        }
    }
    
    // MARK: - Usage History Methods
    
    /// Record folder/file/app access
    func recordAccess(path: String, type: String) {
        guard let dbQueue = dbQueue else { return }
        
        let now = Int(Date().timeIntervalSince1970)
        
        do {
            try dbQueue.write { db in
                // Check if entry exists
                if let existing = try UsageHistoryEntry.filter(Column("item_path") == path).fetchOne(db) {
                    // Update existing entry
                    var updated = existing
                    updated.accessCount += 1
                    updated.lastAccessed = now
                    try updated.update(db)
                } else {
                    // Create new entry
                    var newEntry = UsageHistoryEntry(
                        id: nil,
                        itemPath: path,
                        itemType: type,
                        accessCount: 1,
                        lastAccessed: now
                    )
                    try newEntry.insert(db)
                }
            }
        } catch {
            print("❌ [DatabaseManager] Failed to record access: \(error)")
        }
    }
    
    /// Get most recently used items
    func getMRU(type: String? = nil, limit: Int = 10) -> [UsageHistoryEntry] {
        guard let dbQueue = dbQueue else { return [] }
        
        do {
            return try dbQueue.read { db in
                var query = UsageHistoryEntry.order(Column("last_accessed").desc)
                
                if let type = type {
                    query = query.filter(Column("item_type") == type)
                }
                
                return try query.limit(limit).fetchAll(db)
            }
        } catch {
            print("❌ [DatabaseManager] Failed to get MRU: \(error)")
            return []
        }
    }
    
    // MARK: - Favorites Methods
    
    /// Get all favorites
    func getFavorites() -> [FavoriteEntry] {
        guard let dbQueue = dbQueue else { return [] }
        
        do {
            return try dbQueue.read { db in
                try FavoriteEntry.order(Column("sort_order")).fetchAll(db)
            }
        } catch {
            print("❌ [DatabaseManager] Failed to get favorites: \(error)")
            return []
        }
    }
    
    /// Add favorite
    func addFavorite(name: String, path: String, iconData: Data?, sortOrder: Int) {
        guard let dbQueue = dbQueue else { return }
        
        do {
            try dbQueue.write { db in
                var favorite = FavoriteEntry(
                    id: nil,
                    name: name,
                    path: path,
                    iconData: iconData,
                    sortOrder: sortOrder
                )
                try favorite.insert(db)
            }
            print("⭐ [DatabaseManager] Added favorite: \(name)")
        } catch {
            print("❌ [DatabaseManager] Failed to add favorite: \(error)")
        }
    }
    
    /// Remove favorite
    func removeFavorite(path: String) {
        guard let dbQueue = dbQueue else { return }
        
        do {
            try dbQueue.write { db in
                try db.execute(sql: "DELETE FROM favorites WHERE path = ?", arguments: [path])
            }
            print("🗑️ [DatabaseManager] Removed favorite: \(path)")
        } catch {
            print("❌ [DatabaseManager] Failed to remove favorite: \(error)")
        }
    }
    
    // MARK: - Preferences Methods
    
    /// Get preference value
    func getPreference(key: String) -> String? {
        guard let dbQueue = dbQueue else { return nil }
        
        do {
            return try dbQueue.read { db in
                try String.fetchOne(db, sql: "SELECT value FROM preferences WHERE key = ?", arguments: [key])
            }
        } catch {
            print("❌ [DatabaseManager] Failed to get preference '\(key)': \(error)")
            return nil
        }
    }
    
    /// Set preference value
    func setPreference(key: String, value: String) {
        guard let dbQueue = dbQueue else { return }
        
        do {
            try dbQueue.write { db in
                try db.execute(
                    sql: "INSERT OR REPLACE INTO preferences (key, value) VALUES (?, ?)",
                    arguments: [key, value]
                )
            }
        } catch {
            print("❌ [DatabaseManager] Failed to set preference '\(key)': \(error)")
        }
    }
}

// MARK: - Models

struct FolderCacheEntry: Codable {
    let path: String
    let lastScanned: Int  // Unix timestamp
    let itemsJSON: String  // JSON-encoded array of file info
    let itemCount: Int
}

extension FolderCacheEntry: FetchableRecord, PersistableRecord {
    static let databaseTableName = "folder_cache"
}

struct UsageHistoryEntry: Codable {
    var id: Int?
    let itemPath: String
    let itemType: String
    var accessCount: Int
    var lastAccessed: Int
}

extension UsageHistoryEntry: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "usage_history"
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct FavoriteEntry: Codable {
    var id: Int?
    let name: String
    let path: String
    let iconData: Data?
    let sortOrder: Int
}

extension FavoriteEntry: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "favorites"
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Errors

enum DatabaseError: Error {
    case notInitialized
    case pathNotFound
    case saveFailed
    case fetchFailed
}
