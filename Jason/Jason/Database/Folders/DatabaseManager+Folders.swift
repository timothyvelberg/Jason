//
//  DatabaseManager+Folders.swift
//  Jason
//
//  Created by Timothy Velberg on 15/10/2025.

import Foundation
import SQLite3

extension DatabaseManager {

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
    func _getOrCreateFolderUnsafe(path: String, title: String? = nil) -> Int? {
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
    func setFolderIcon(path: String, iconName: String?, iconColorHex: String?, baseAsset: String = "folder-blue", symbolSize: CGFloat = 24.0, symbolOffset: CGFloat = -8.0) {
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
            SET icon_name = NULL, icon_color_hex = NULL, base_asset = 'folder-blue', symbol_size = 24.0, symbol_offset = -8.0
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
                   COALESCE(base_asset, 'folder-blue'), 
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

}
