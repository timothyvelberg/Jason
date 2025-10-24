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
        
        // Create folders table (all folders - registry + usage tracking)
        let foldersSQL = """
        CREATE TABLE IF NOT EXISTS folders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT UNIQUE NOT NULL,
            title TEXT NOT NULL,
            icon TEXT,
            icon_name TEXT,
            icon_color_hex TEXT,
            base_asset TEXT DEFAULT '_folder-blue_',
            symbol_size REAL DEFAULT 24.0,
            symbol_offset REAL DEFAULT -8.0,
            last_accessed INTEGER NOT NULL,
            access_count INTEGER DEFAULT 0
        );
        """
        
        // Create favorite_folders table (which folders are favorites)
        let favoriteFoldersSQL = """
        CREATE TABLE IF NOT EXISTS favorite_folders (
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
        
        // Create favorite_apps table (favorite applications)
        let favoriteAppsSQL = """
        CREATE TABLE IF NOT EXISTS favorite_apps (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bundle_identifier TEXT UNIQUE NOT NULL,
            display_name TEXT NOT NULL,
            sort_order INTEGER NOT NULL,
            icon_override TEXT,
            last_accessed INTEGER,
            access_count INTEGER DEFAULT 0
        );
        """
        
        // Create folder_cache table (performance optimization)
        let folderCacheSQL = """
        CREATE TABLE IF NOT EXISTS folder_cache (
            path TEXT PRIMARY KEY,
            last_scanned INTEGER NOT NULL,
            items_json TEXT NOT NULL,
            item_count INTEGER NOT NULL
        );
        """
        
        // Create preferences table (general settings)
        let preferencesSQL = """
        CREATE TABLE IF NOT EXISTS preferences (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """
        
        // Execute all schema creation
        let tables = [foldersSQL, favoriteFoldersSQL, favoriteAppsSQL, folderCacheSQL, preferencesSQL]
        
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
        } else {
            if let error = sqlite3_errmsg(db) {
                print("❌ [DatabaseManager] Failed to prepare SELECT for folder '\(path)': \(String(cString: error))")
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
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to insert folder '\(folderName)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare INSERT for folder '\(folderName)': \(String(cString: error))")
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
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to update access for '\(path)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare UPDATE for folder access '\(path)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
    }

    /// Set custom icon for a folder
    func setFolderIcon(path: String, iconName: String?, iconColorHex: String?, baseAsset: String = "_folder-blue_", symbolSize: CGFloat = 24.0, symbolOffset: CGFloat = -8.0) {
        guard let db = db else { return }
        
        queue.async {
            // First ensure the folder exists
            let folderId = self._getOrCreateFolderUnsafe(path: path, title: nil)
            guard folderId != nil else {
                print("❌ [DatabaseManager] Failed to get/create folder for icon update: \(path)")
                return
            }
            
            let sql = """
            UPDATE folders 
            SET icon_name = ?, icon_color_hex = ?, base_asset = ?, symbol_size = ?, symbol_offset = ?
            WHERE path = ?;
            """
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                if let iconName = iconName {
                    sqlite3_bind_text(statement, 1, (iconName as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statement, 1)
                }
                
                if let iconColorHex = iconColorHex {
                    sqlite3_bind_text(statement, 2, (iconColorHex as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statement, 2)
                }
                
                sqlite3_bind_text(statement, 3, (baseAsset as NSString).utf8String, -1, nil)
                sqlite3_bind_double(statement, 4, Double(symbolSize))
                sqlite3_bind_double(statement, 5, Double(symbolOffset))
                sqlite3_bind_text(statement, 6, (path as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("🎨 [DatabaseManager] Set custom icon for folder: \(path)")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to set icon for folder '\(path)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare UPDATE for folder icon '\(path)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
    }

    /// Remove custom icon from a folder (reset to defaults)
    func removeFolderIcon(path: String) {
        guard let db = db else { return }
        
        queue.async {
            let sql = """
            UPDATE folders 
            SET icon_name = NULL, icon_color_hex = NULL, base_asset = '_folder-blue_', symbol_size = 24.0, symbol_offset = -8.0
            WHERE path = ?;
            """
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (path as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("🗑️ [DatabaseManager] Removed custom icon for folder: \(path)")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to remove icon for folder '\(path)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare UPDATE for removing icon '\(path)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
    }

    /// Get all folders with custom icons
    func getFoldersWithCustomIcons() -> [FolderEntry] {
        guard let db = db else { return [] }
        
        var results: [FolderEntry] = []
        
        queue.sync {
            let sql = """
            SELECT id, path, title, icon, icon_name, icon_color_hex, 
                   COALESCE(base_asset, '_folder-blue_'), 
                   COALESCE(symbol_size, 24.0), 
                   COALESCE(symbol_offset, -8.0),
                   last_accessed, access_count 
            FROM folders 
            WHERE icon_name IS NOT NULL
            ORDER BY title;
            """
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(statement, 0))
                    let path = String(cString: sqlite3_column_text(statement, 1))
                    let title = String(cString: sqlite3_column_text(statement, 2))
                    let icon = sqlite3_column_text(statement, 3) != nil ? String(cString: sqlite3_column_text(statement, 3)) : nil
                    let iconName = sqlite3_column_text(statement, 4) != nil ? String(cString: sqlite3_column_text(statement, 4)) : nil
                    let iconColorHex = sqlite3_column_text(statement, 5) != nil ? String(cString: sqlite3_column_text(statement, 5)) : nil
                    let baseAsset = String(cString: sqlite3_column_text(statement, 6))
                    let symbolSize = CGFloat(sqlite3_column_double(statement, 7))
                    let symbolOffset = CGFloat(sqlite3_column_double(statement, 8))
                    let lastAccessed = Int(sqlite3_column_int64(statement, 9))
                    let accessCount = Int(sqlite3_column_int(statement, 10))
                    
                    results.append(FolderEntry(
                        id: id,
                        path: path,
                        title: title,
                        icon: icon,
                        iconName: iconName,
                        iconColorHex: iconColorHex,
                        baseAsset: baseAsset,
                        symbolSize: symbolSize,
                        symbolOffset: symbolOffset,
                        lastAccessed: lastAccessed,
                        accessCount: accessCount
                    ))
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare SELECT for custom icons: \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return results
    }

    /// Get folder by path
    func getFolder(path: String) -> FolderEntry? {
        guard let db = db else { return nil }
        
        var result: FolderEntry?
        
        queue.sync {
            let sql = """
            SELECT id, path, title, icon, icon_name, icon_color_hex, 
                   COALESCE(base_asset, '_folder-blue_'), 
                   COALESCE(symbol_size, 24.0), 
                   COALESCE(symbol_offset, -8.0),
                   last_accessed, access_count 
            FROM folders WHERE path = ?;
            """
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (path as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(statement, 0))
                    let path = String(cString: sqlite3_column_text(statement, 1))
                    let title = String(cString: sqlite3_column_text(statement, 2))
                    let icon = sqlite3_column_text(statement, 3) != nil ? String(cString: sqlite3_column_text(statement, 3)) : nil
                    let iconName = sqlite3_column_text(statement, 4) != nil ? String(cString: sqlite3_column_text(statement, 4)) : nil
                    let iconColorHex = sqlite3_column_text(statement, 5) != nil ? String(cString: sqlite3_column_text(statement, 5)) : nil
                    let baseAsset = String(cString: sqlite3_column_text(statement, 6))
                    let symbolSize = CGFloat(sqlite3_column_double(statement, 7))
                    let symbolOffset = CGFloat(sqlite3_column_double(statement, 8))
                    let lastAccessed = Int(sqlite3_column_int64(statement, 9))
                    let accessCount = Int(sqlite3_column_int(statement, 10))
                    
                    result = FolderEntry(
                        id: id,
                        path: path,
                        title: title,
                        icon: icon,
                        iconName: iconName,
                        iconColorHex: iconColorHex,
                        baseAsset: baseAsset,
                        symbolSize: symbolSize,
                        symbolOffset: symbolOffset,
                        lastAccessed: lastAccessed,
                        accessCount: accessCount
                    )
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare SELECT for folder '\(path)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return result
    }

    /// Get all favorite folders with their settings
    func getFavoriteFolders() -> [(folder: FolderEntry, settings: FavoriteFolderSettings)] {
        guard let db = db else { return [] }
        
        var results: [(folder: FolderEntry, settings: FavoriteFolderSettings)] = []
        
        queue.sync {
            let sql = """
            SELECT f.id, f.path, f.title, f.icon, f.icon_name, f.icon_color_hex,
                   COALESCE(f.base_asset, '_folder-blue_'), 
                   COALESCE(f.symbol_size, 24.0), 
                   COALESCE(f.symbol_offset, -8.0),
                   f.last_accessed, f.access_count,
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
                    let iconName = sqlite3_column_text(statement, 4) != nil ? String(cString: sqlite3_column_text(statement, 4)) : nil
                    let iconColorHex = sqlite3_column_text(statement, 5) != nil ? String(cString: sqlite3_column_text(statement, 5)) : nil
                    let baseAsset = String(cString: sqlite3_column_text(statement, 6))
                    let symbolSize = CGFloat(sqlite3_column_double(statement, 7))
                    let symbolOffset = CGFloat(sqlite3_column_double(statement, 8))
                    let lastAccessed = Int(sqlite3_column_int64(statement, 9))
                    let accessCount = Int(sqlite3_column_int(statement, 10))
                    
                    let maxItems: Int? = sqlite3_column_type(statement, 11) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 11))
                    let preferredLayout = sqlite3_column_text(statement, 12) != nil ? String(cString: sqlite3_column_text(statement, 12)) : nil
                    let itemAngleSize: Int? = sqlite3_column_type(statement, 13) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 13))
                    let slicePositioning = sqlite3_column_text(statement, 14) != nil ? String(cString: sqlite3_column_text(statement, 14)) : nil
                    let childRingThickness: Int? = sqlite3_column_type(statement, 15) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 15))
                    let childIconSize: Int? = sqlite3_column_type(statement, 16) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 16))
                    
                    let folder = FolderEntry(
                        id: id,
                        path: path,
                        title: title,
                        icon: icon,
                        iconName: iconName,
                        iconColorHex: iconColorHex,
                        baseAsset: baseAsset,
                        symbolSize: symbolSize,
                        symbolOffset: symbolOffset,
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
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare SELECT for favorite folders: \(String(cString: error))")
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
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare COUNT for favorite folders: \(String(cString: error))")
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
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to insert favorite folder '\(path)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare INSERT for favorite folder '\(path)': \(String(cString: error))")
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
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to delete favorite folder '\(path)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare DELETE for favorite folder '\(path)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return success
    }

    /// Update settings for a favorite folder (including title and all settings)
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
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to update folder title '\(title)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare UPDATE for folder title '\(title)': \(String(cString: error))")
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
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to update favorite settings for '\(path)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare UPDATE for favorite settings '\(path)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(settingsStatement)
        }
        
        return success
    }
    
    // MARK: - Favorite Apps Methods
    
    /// Get all favorite apps
    func getFavoriteApps() -> [FavoriteAppEntry] {
        guard let db = db else { return [] }
        
        var results: [FavoriteAppEntry] = []
        
        queue.sync {
            let sql = "SELECT id, bundle_identifier, display_name, sort_order, icon_override, last_accessed, access_count FROM favorite_apps ORDER BY sort_order;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(statement, 0))
                    let bundleIdentifier = String(cString: sqlite3_column_text(statement, 1))
                    let displayName = String(cString: sqlite3_column_text(statement, 2))
                    let sortOrder = Int(sqlite3_column_int(statement, 3))
                    let iconOverride = sqlite3_column_text(statement, 4) != nil ? String(cString: sqlite3_column_text(statement, 4)) : nil
                    let lastAccessed: Int? = sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 5))
                    let accessCount = Int(sqlite3_column_int(statement, 6))
                    
                    results.append(FavoriteAppEntry(
                        id: id,
                        bundleIdentifier: bundleIdentifier,
                        displayName: displayName,
                        sortOrder: sortOrder,
                        iconOverride: iconOverride,
                        lastAccessed: lastAccessed,
                        accessCount: accessCount
                    ))
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare SELECT for favorite apps: \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return results
    }
    
    /// Add app to favorites
    func addFavoriteApp(bundleIdentifier: String, displayName: String, iconOverride: String? = nil) -> Bool {
        guard let db = db else { return false }
        
        var success = false
        
        queue.sync {
            // Check if already exists
            let checkSQL = "SELECT id FROM favorite_apps WHERE bundle_identifier = ?;"
            var checkStatement: OpaquePointer?
            var alreadyExists = false
            
            if sqlite3_prepare_v2(db, checkSQL, -1, &checkStatement, nil) == SQLITE_OK {
                sqlite3_bind_text(checkStatement, 1, (bundleIdentifier as NSString).utf8String, -1, nil)
                if sqlite3_step(checkStatement) == SQLITE_ROW {
                    alreadyExists = true
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare CHECK for app '\(bundleIdentifier)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(checkStatement)
            
            if alreadyExists {
                print("⚠️ [DatabaseManager] App '\(displayName)' already in favorites")
                return
            }
            
            // Get next sort order
            var nextSortOrder = 0
            var countStatement: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM favorite_apps;", -1, &countStatement, nil) == SQLITE_OK {
                if sqlite3_step(countStatement) == SQLITE_ROW {
                    nextSortOrder = Int(sqlite3_column_int(countStatement, 0))
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare COUNT for favorite apps: \(String(cString: error))")
                }
            }
            sqlite3_finalize(countStatement)
            
            // Insert new favorite app
            let sql = "INSERT INTO favorite_apps (bundle_identifier, display_name, sort_order, icon_override) VALUES (?, ?, ?, ?);"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (bundleIdentifier as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 2, (displayName as NSString).utf8String, -1, nil)
                sqlite3_bind_int(statement, 3, Int32(nextSortOrder))
                
                if let iconOverride = iconOverride {
                    sqlite3_bind_text(statement, 4, (iconOverride as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statement, 4)
                }
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("⭐ [DatabaseManager] Added favorite app: \(displayName)")
                    success = true
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to insert favorite app '\(displayName)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare INSERT for favorite app '\(displayName)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return success
    }
    
    /// Remove app from favorites
    func removeFavoriteApp(bundleIdentifier: String) -> Bool {
        guard let db = db else { return false }
        
        var success = false
        
        queue.sync {
            let sql = "DELETE FROM favorite_apps WHERE bundle_identifier = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (bundleIdentifier as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("🗑️ [DatabaseManager] Removed favorite app: \(bundleIdentifier)")
                    success = true
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to delete favorite app '\(bundleIdentifier)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare DELETE for favorite app '\(bundleIdentifier)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return success
    }
    
    /// Update app access tracking
    func updateAppAccess(bundleIdentifier: String) {
        guard let db = db else { return }
        
        queue.async {
            let now = Int(Date().timeIntervalSince1970)
            
            let sql = """
            UPDATE favorite_apps 
            SET last_accessed = ?, access_count = access_count + 1
            WHERE bundle_identifier = ?;
            """
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int64(statement, 1, Int64(now))
                sqlite3_bind_text(statement, 2, (bundleIdentifier as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("📊 [DatabaseManager] Updated access for app: \(bundleIdentifier)")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to update access for app '\(bundleIdentifier)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare UPDATE for app access '\(bundleIdentifier)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
    }
    
    /// Get app by bundle identifier
    func getFavoriteApp(bundleIdentifier: String) -> FavoriteAppEntry? {
        guard let db = db else { return nil }
        
        var result: FavoriteAppEntry?
        
        queue.sync {
            let sql = "SELECT id, bundle_identifier, display_name, sort_order, icon_override, last_accessed, access_count FROM favorite_apps WHERE bundle_identifier = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (bundleIdentifier as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(statement, 0))
                    let bundleIdentifier = String(cString: sqlite3_column_text(statement, 1))
                    let displayName = String(cString: sqlite3_column_text(statement, 2))
                    let sortOrder = Int(sqlite3_column_int(statement, 3))
                    let iconOverride = sqlite3_column_text(statement, 4) != nil ? String(cString: sqlite3_column_text(statement, 4)) : nil
                    let lastAccessed: Int? = sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 5))
                    let accessCount = Int(sqlite3_column_int(statement, 6))
                    
                    result = FavoriteAppEntry(
                        id: id,
                        bundleIdentifier: bundleIdentifier,
                        displayName: displayName,
                        sortOrder: sortOrder,
                        iconOverride: iconOverride,
                        lastAccessed: lastAccessed,
                        accessCount: accessCount
                    )
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare SELECT for app '\(bundleIdentifier)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return result
    }
    
    /// Update app sort order
    func updateAppSortOrder(bundleIdentifier: String, sortOrder: Int) {
        guard let db = db else { return }
        
        queue.async {
            let sql = "UPDATE favorite_apps SET sort_order = ? WHERE bundle_identifier = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(sortOrder))
                sqlite3_bind_text(statement, 2, (bundleIdentifier as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("📊 [DatabaseManager] Updated sort order for app: \(bundleIdentifier)")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to update sort order for app '\(bundleIdentifier)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare UPDATE for app sort order '\(bundleIdentifier)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
    }
    
    /// Update favorite app details (display name and icon override)
    func updateFavoriteApp(bundleIdentifier: String, displayName: String, iconOverride: String?) -> Bool {
        guard let db = db else { return false }
        
        var success = false
        
        queue.sync {
            let sql = """
            UPDATE favorite_apps
            SET display_name = ?, icon_override = ?
            WHERE bundle_identifier = ?;
            """
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (displayName as NSString).utf8String, -1, nil)
                
                if let iconOverride = iconOverride {
                    sqlite3_bind_text(statement, 2, (iconOverride as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statement, 2)
                }
                
                sqlite3_bind_text(statement, 3, (bundleIdentifier as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("✏️ [DatabaseManager] Updated favorite app: \(displayName)")
                    success = true
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to update favorite app '\(displayName)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare UPDATE for favorite app '\(displayName)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return success
    }
    
    /// Reorder favorite app
    func reorderFavoriteApps(bundleIdentifier: String, newSortOrder: Int) -> Bool {
        guard let db = db else { return false }
        
        var success = false
        
        queue.sync {
            let sql = "UPDATE favorite_apps SET sort_order = ? WHERE bundle_identifier = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(newSortOrder))
                sqlite3_bind_text(statement, 2, (bundleIdentifier as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("🔄 [DatabaseManager] Reordered app: \(bundleIdentifier) to position \(newSortOrder)")
                    success = true
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to reorder app '\(bundleIdentifier)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare UPDATE for reordering app '\(bundleIdentifier)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
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
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare SELECT for favorites: \(String(cString: error))")
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
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to add favorite '\(name)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare INSERT for favorite '\(name)': \(String(cString: error))")
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
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to remove favorite '\(path)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare DELETE for favorite '\(path)': \(String(cString: error))")
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
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare SELECT for preference '\(key)': \(String(cString: error))")
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
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("⚙️ [DatabaseManager] Set preference: \(key) = \(value)")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to set preference '\(key)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare INSERT for preference '\(key)': \(String(cString: error))")
                }
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
    let iconName: String?
    let iconColorHex: String?
    let baseAsset: String
    let symbolSize: CGFloat
    let symbolOffset: CGFloat
    let lastAccessed: Int
    let accessCount: Int
    
    var iconColor: NSColor? {
        guard let hex = iconColorHex else { return nil }
        return NSColor(hex: hex)
    }
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

struct FavoriteAppEntry: Identifiable {
    let id: Int
    let bundleIdentifier: String
    let displayName: String
    let sortOrder: Int
    let iconOverride: String?
    let lastAccessed: Int?
    let accessCount: Int
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
