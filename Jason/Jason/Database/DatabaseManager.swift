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
        
        // Drop old tables if they exist (fresh start)
        let dropTables = """
        DROP TABLE IF EXISTS folder_cache;
        DROP TABLE IF EXISTS usage_history;
        DROP TABLE IF EXISTS favorites;
        DROP TABLE IF EXISTS preferences;
        DROP TABLE IF EXISTS folders;
        DROP TABLE IF EXISTS favorite_folders;
        """
        
        if sqlite3_exec(db, dropTables, nil, nil, nil) != SQLITE_OK {
            if let error = sqlite3_errmsg(db) {
                print("⚠️ [DatabaseManager] Warning dropping tables: \(String(cString: error))")
            }
        }
        
        // Create folders table (all folders - registry + usage tracking)
        let foldersSQL = """
        CREATE TABLE folders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT UNIQUE NOT NULL,
            title TEXT NOT NULL,
            icon TEXT,
            last_accessed INTEGER NOT NULL,
            access_count INTEGER DEFAULT 0
        );
        """
        
        // Create favorite_folders table (which folders are favorites)
        let favoriteFoldersSQL = """
        CREATE TABLE favorite_folders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            folder_id INTEGER NOT NULL,
            sort_order INTEGER NOT NULL,
            max_items INTEGER,
            preferred_layout TEXT DEFAULT 'fullCircle',
            item_angle_size INTEGER DEFAULT 30,
            slice_positioning TEXT DEFAULT 'startClockwise',
            child_ring_thickness INTEGER DEFAULT 80,
            child_icon_size INTEGER DEFAULT 32,
            FOREIGN KEY (folder_id) REFERENCES folders(id) ON DELETE CASCADE
        );
        """
        
        // Create folder_cache table (performance optimization)
        let folderCacheSQL = """
        CREATE TABLE folder_cache (
            path TEXT PRIMARY KEY,
            last_scanned INTEGER NOT NULL,
            items_json TEXT NOT NULL,
            item_count INTEGER NOT NULL
        );
        """
        
        // Create preferences table (general settings)
        let preferencesSQL = """
        CREATE TABLE preferences (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """
        
        // Execute all schema creation
        let tables = [foldersSQL, favoriteFoldersSQL, folderCacheSQL, preferencesSQL]
        
        for sql in tables {
            if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to create table: \(String(cString: error))")
                }
                throw DatabaseError.schemaCreationFailed
            }
        }
        
        print("✅ [DatabaseManager] Database schema created successfully")
    }
    
    // MARK: - Folders Methods

    /// Get or create folder entry by path (thread-safe)
    func getOrCreateFolder(path: String, title: String? = nil) -> Int? {
        guard let db = db else { return nil }
        
        var folderId: Int?
        
        queue.sync {
            folderId = _getOrCreateFolderUnsafe(path: path, title: title)
        }
        
        return folderId
    }

    /// Get or create folder entry by path (UNSAFE - must be called within queue.sync)
    private func _getOrCreateFolderUnsafe(path: String, title: String? = nil) -> Int? {
        guard let db = db else { return nil }
        
        var folderId: Int?
        
        // Try to get existing folder
        let selectSQL = "SELECT id FROM folders WHERE path = ?;"
        var selectStatement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, selectSQL, -1, &selectStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(selectStatement, 1, (path as NSString).utf8String, -1, nil)
            
            if sqlite3_step(selectStatement) == SQLITE_ROW {
                folderId = Int(sqlite3_column_int(selectStatement, 0))
            }
        }
        sqlite3_finalize(selectStatement)
        
        // If doesn't exist, create it
        if folderId == nil {
            let folderName = title ?? URL(fileURLWithPath: path).lastPathComponent
            let now = Int(Date().timeIntervalSince1970)
            
            let insertSQL = """
            INSERT INTO folders (path, title, last_accessed, access_count)
            VALUES (?, ?, ?, 0);
            """
            var insertStatement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, insertSQL, -1, &insertStatement, nil) == SQLITE_OK {
                sqlite3_bind_text(insertStatement, 1, (path as NSString).utf8String, -1, nil)
                sqlite3_bind_text(insertStatement, 2, (folderName as NSString).utf8String, -1, nil)
                sqlite3_bind_int64(insertStatement, 3, Int64(now))
                
                if sqlite3_step(insertStatement) == SQLITE_DONE {
                    folderId = Int(sqlite3_last_insert_rowid(db))
                    print("📁 [DatabaseManager] Created folder entry: \(folderName) (id: \(folderId!))")
                }
            }
            sqlite3_finalize(insertStatement)
        }
        
        return folderId
    }

    /// Update folder access
    func updateFolderAccess(path: String) {
        guard let db = db else { return }
        
        queue.async {
            let now = Int(Date().timeIntervalSince1970)
            
            let sql = """
            UPDATE folders 
            SET last_accessed = ?, access_count = access_count + 1
            WHERE path = ?;
            """
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int64(statement, 1, Int64(now))
                sqlite3_bind_text(statement, 2, (path as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("📊 [DatabaseManager] Updated access for: \(path)")
                }
            }
            sqlite3_finalize(statement)
        }
    }

    /// Get folder by path
    func getFolder(path: String) -> FolderEntry? {
        guard let db = db else { return nil }
        
        var result: FolderEntry?
        
        queue.sync {
            let sql = "SELECT id, path, title, icon, last_accessed, access_count FROM folders WHERE path = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (path as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(statement, 0))
                    let path = String(cString: sqlite3_column_text(statement, 1))
                    let title = String(cString: sqlite3_column_text(statement, 2))
                    let icon = sqlite3_column_text(statement, 3) != nil ? String(cString: sqlite3_column_text(statement, 3)) : nil
                    let lastAccessed = Int(sqlite3_column_int64(statement, 4))
                    let accessCount = Int(sqlite3_column_int(statement, 5))
                    
                    result = FolderEntry(
                        id: id,
                        path: path,
                        title: title,
                        icon: icon,
                        lastAccessed: lastAccessed,
                        accessCount: accessCount
                    )
                }
            }
            sqlite3_finalize(statement)
        }
        
        return result
    }

    // MARK: - Favorite Folders Methods

    /// Get all favorite folders (sorted by sort_order)
    func getFavoriteFolders() -> [(folder: FolderEntry, settings: FavoriteFolderSettings)] {
        guard let db = db else { return [] }
        
        var results: [(FolderEntry, FavoriteFolderSettings)] = []
        
        queue.sync {
            let sql = """
            SELECT f.id, f.path, f.title, f.icon, f.last_accessed, f.access_count,
                   ff.max_items, ff.preferred_layout, ff.item_angle_size, 
                   ff.slice_positioning, ff.child_ring_thickness, ff.child_icon_size
            FROM favorite_folders ff
            JOIN folders f ON ff.folder_id = f.id
            ORDER BY ff.sort_order;
            """
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(statement, 0))
                    let path = String(cString: sqlite3_column_text(statement, 1))
                    let title = String(cString: sqlite3_column_text(statement, 2))
                    let icon = sqlite3_column_text(statement, 3) != nil ? String(cString: sqlite3_column_text(statement, 3)) : nil
                    let lastAccessed = Int(sqlite3_column_int64(statement, 4))
                    let accessCount = Int(sqlite3_column_int(statement, 5))
                    
                    let maxItems: Int? = sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 6))
                    let preferredLayout = sqlite3_column_text(statement, 7) != nil ? String(cString: sqlite3_column_text(statement, 7)) : nil
                    let itemAngleSize: Int? = sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 8))
                    let slicePositioning = sqlite3_column_text(statement, 9) != nil ? String(cString: sqlite3_column_text(statement, 9)) : nil
                    let childRingThickness: Int? = sqlite3_column_type(statement, 10) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 10))
                    let childIconSize: Int? = sqlite3_column_type(statement, 11) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 11))
                    
                    let folder = FolderEntry(
                        id: id,
                        path: path,
                        title: title,
                        icon: icon,
                        lastAccessed: lastAccessed,
                        accessCount: accessCount
                    )
                    
                    let settings = FavoriteFolderSettings(
                        maxItems: maxItems,
                        preferredLayout: preferredLayout,
                        itemAngleSize: itemAngleSize,
                        slicePositioning: slicePositioning,
                        childRingThickness: childRingThickness,
                        childIconSize: childIconSize
                    )
                    
                    results.append((folder, settings))
                }
            }
            sqlite3_finalize(statement)
        }
        
        return results
    }

    /// Add folder to favorites
    func addFavoriteFolder(path: String, title: String? = nil, settings: FavoriteFolderSettings? = nil) -> Bool {
        guard let db = db else { return false }
        
        var success = false
        
        queue.sync {
            // Get or create folder entry (using unsafe version since we're already in sync)
            guard let folderId = _getOrCreateFolderUnsafe(path: path, title: title) else {
                print("❌ [DatabaseManager] Failed to get/create folder for: \(path)")
                return
            }
            
            // Get next sort order
            var nextSortOrder = 0
            var countStatement: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM favorite_folders;", -1, &countStatement, nil) == SQLITE_OK {
                if sqlite3_step(countStatement) == SQLITE_ROW {
                    nextSortOrder = Int(sqlite3_column_int(countStatement, 0))
                }
            }
            sqlite3_finalize(countStatement)
            
            // Insert into favorite_folders with all settings
            let sql = """
            INSERT INTO favorite_folders 
            (folder_id, sort_order, max_items, preferred_layout, item_angle_size, 
             slice_positioning, child_ring_thickness, child_icon_size) 
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(folderId))
                sqlite3_bind_int(statement, 2, Int32(nextSortOrder))
                
                // Bind settings or use defaults
                if let maxItems = settings?.maxItems {
                    sqlite3_bind_int(statement, 3, Int32(maxItems))
                } else {
                    sqlite3_bind_null(statement, 3)
                }
                
                if let layout = settings?.preferredLayout {
                    sqlite3_bind_text(statement, 4, (layout as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_text(statement, 4, ("fullCircle" as NSString).utf8String, -1, nil)
                }
                
                if let angleSize = settings?.itemAngleSize {
                    sqlite3_bind_int(statement, 5, Int32(angleSize))
                } else {
                    sqlite3_bind_int(statement, 5, 30)
                }
                
                if let positioning = settings?.slicePositioning {
                    sqlite3_bind_text(statement, 6, (positioning as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_text(statement, 6, ("startClockwise" as NSString).utf8String, -1, nil)
                }
                
                if let thickness = settings?.childRingThickness {
                    sqlite3_bind_int(statement, 7, Int32(thickness))
                } else {
                    sqlite3_bind_int(statement, 7, 80)
                }
                
                if let iconSize = settings?.childIconSize {
                    sqlite3_bind_int(statement, 8, Int32(iconSize))
                } else {
                    sqlite3_bind_int(statement, 8, 32)
                }
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("⭐ [DatabaseManager] Added favorite folder: \(path)")
                    success = true
                }
            }
            sqlite3_finalize(statement)
        }
        
        return success
    }

    /// Remove folder from favorites
    func removeFavoriteFolder(path: String) -> Bool {
        guard let db = db else { return false }
        
        var success = false
        
        queue.sync {
            let sql = """
            DELETE FROM favorite_folders 
            WHERE folder_id = (SELECT id FROM folders WHERE path = ?);
            """
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (path as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("🗑️ [DatabaseManager] Removed favorite folder: \(path)")
                    success = true
                }
            }
            sqlite3_finalize(statement)
        }
        
        return success
    }
    
    /// Update favorite folder settings
    func updateFavoriteSettings(path: String, title: String, settings: FavoriteFolderSettings) -> Bool {
        guard let db = db else { return false }
        
        var success = false
        
        queue.sync {
            // First, update the folder title
            let updateFolderSQL = "UPDATE folders SET title = ? WHERE path = ?;"
            var folderStatement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, updateFolderSQL, -1, &folderStatement, nil) == SQLITE_OK {
                sqlite3_bind_text(folderStatement, 1, (title as NSString).utf8String, -1, nil)
                sqlite3_bind_text(folderStatement, 2, (path as NSString).utf8String, -1, nil)
                
                if sqlite3_step(folderStatement) == SQLITE_DONE {
                    print("✏️ [DatabaseManager] Updated folder title: \(title)")
                }
            }
            sqlite3_finalize(folderStatement)
            
            // Then, update the favorite settings
            let updateSettingsSQL = """
            UPDATE favorite_folders
            SET max_items = ?,
                preferred_layout = ?,
                item_angle_size = ?,
                slice_positioning = ?,
                child_ring_thickness = ?,
                child_icon_size = ?
            WHERE folder_id = (SELECT id FROM folders WHERE path = ?);
            """
            var settingsStatement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, updateSettingsSQL, -1, &settingsStatement, nil) == SQLITE_OK {
                // Bind all settings
                if let maxItems = settings.maxItems {
                    sqlite3_bind_int(settingsStatement, 1, Int32(maxItems))
                } else {
                    sqlite3_bind_null(settingsStatement, 1)
                }
                
                if let layout = settings.preferredLayout {
                    sqlite3_bind_text(settingsStatement, 2, (layout as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_text(settingsStatement, 2, ("fullCircle" as NSString).utf8String, -1, nil)
                }
                
                if let angleSize = settings.itemAngleSize {
                    sqlite3_bind_int(settingsStatement, 3, Int32(angleSize))
                } else {
                    sqlite3_bind_int(settingsStatement, 3, 30)
                }
                
                if let positioning = settings.slicePositioning {
                    sqlite3_bind_text(settingsStatement, 4, (positioning as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_text(settingsStatement, 4, ("startClockwise" as NSString).utf8String, -1, nil)
                }
                
                if let thickness = settings.childRingThickness {
                    sqlite3_bind_int(settingsStatement, 5, Int32(thickness))
                } else {
                    sqlite3_bind_int(settingsStatement, 5, 80)
                }
                
                if let iconSize = settings.childIconSize {
                    sqlite3_bind_int(settingsStatement, 6, Int32(iconSize))
                } else {
                    sqlite3_bind_int(settingsStatement, 6, 32)
                }
                
                sqlite3_bind_text(settingsStatement, 7, (path as NSString).utf8String, -1, nil)
                
                if sqlite3_step(settingsStatement) == SQLITE_DONE {
                    print("✅ [DatabaseManager] Updated favorite settings for: \(path)")
                    success = true
                }
            }
            sqlite3_finalize(settingsStatement)
        }
        
        return success
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

struct FolderEntry: Identifiable {
    let id: Int
    let path: String
    let title: String
    let icon: String?
    let lastAccessed: Int
    let accessCount: Int
}

struct FavoriteFolderEntry {
    let id: Int?
    let folderId: Int
    let sortOrder: Int
    let maxItems: Int?
    let preferredLayout: String?
    let itemAngleSize: Int?
    let slicePositioning: String?
    let childRingThickness: Int?
    let childIconSize: Int?
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

struct FavoriteFolderSettings {
    let maxItems: Int?
    let preferredLayout: String?
    let itemAngleSize: Int?
    let slicePositioning: String?
    let childRingThickness: Int?
    let childIconSize: Int?
}

// MARK: - Errors

enum DatabaseError: Error {
    case notInitialized
    case pathNotFound
    case schemaCreationFailed
    case saveFailed
    case fetchFailed
}
