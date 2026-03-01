//
//  DatabaseManager+FavoriteFiles.swift
//  Jason
//
//  Created by Claude on 04/11/2025.

import Foundation
import SQLite3
import AppKit

extension DatabaseManager {
    
    // MARK: - Favorite Files Methods
    
    /// Get all favorite files
    func getFavoriteFiles() -> [FavoriteFileEntry] {
        guard let db = db else { return [] }
        
        var results: [FavoriteFileEntry] = []
        
        queue.sync {
            let sql = "SELECT id, path, display_name, sort_order, icon_data, last_accessed, access_count FROM favorite_files ORDER BY sort_order;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(statement, 0))
                    let path = String(cString: sqlite3_column_text(statement, 1))
                    let displayName = sqlite3_column_text(statement, 2) != nil ? String(cString: sqlite3_column_text(statement, 2)) : nil
                    let sortOrder = Int(sqlite3_column_int(statement, 3))
                    
                    var iconData: Data?
                    if let blob = sqlite3_column_blob(statement, 4) {
                        let size = sqlite3_column_bytes(statement, 4)
                        iconData = Data(bytes: blob, count: Int(size))
                    }
                    
                    let lastAccessed: Int? = sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 5))
                    let accessCount = Int(sqlite3_column_int(statement, 6))
                    
                    results.append(FavoriteFileEntry(
                        id: id,
                        path: path,
                        displayName: displayName,
                        sortOrder: sortOrder,
                        iconData: iconData,
                        lastAccessed: lastAccessed,
                        accessCount: accessCount
                    ))
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("[DatabaseManager] Failed to prepare SELECT for favorite files: \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return results
    }
    
    /// Add file to favorites
    func addFavoriteFile(path: String, displayName: String? = nil, iconData: Data? = nil) -> Bool {
        guard let db = db else { return false }
        
        var success = false
        
        queue.sync {
            // Check if already exists
            let checkSQL = "SELECT id FROM favorite_files WHERE path = ?;"
            var checkStatement: OpaquePointer?
            var alreadyExists = false
            
            if sqlite3_prepare_v2(db, checkSQL, -1, &checkStatement, nil) == SQLITE_OK {
                sqlite3_bind_text(checkStatement, 1, (path as NSString).utf8String, -1, nil)
                if sqlite3_step(checkStatement) == SQLITE_ROW {
                    alreadyExists = true
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("[DatabaseManager] Failed to prepare CHECK for file '\(path)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(checkStatement)
            
            if alreadyExists {
                print("[DatabaseManager] File '\(path)' already in favorites")
                return
            }
            
            // Get next sort order
            var nextSortOrder = 0
            var countStatement: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM favorite_files;", -1, &countStatement, nil) == SQLITE_OK {
                if sqlite3_step(countStatement) == SQLITE_ROW {
                    nextSortOrder = Int(sqlite3_column_int(countStatement, 0))
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("[DatabaseManager] Failed to prepare COUNT for favorite files: \(String(cString: error))")
                }
            }
            sqlite3_finalize(countStatement)
            
            // Insert new favorite file
            let sql = "INSERT INTO favorite_files (path, display_name, sort_order, icon_data) VALUES (?, ?, ?, ?);"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (path as NSString).utf8String, -1, nil)
                
                if let displayName = displayName {
                    sqlite3_bind_text(statement, 2, (displayName as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statement, 2)
                }
                
                sqlite3_bind_int(statement, 3, Int32(nextSortOrder))
                
                if let iconData = iconData {
                    iconData.withUnsafeBytes { buffer in
                        sqlite3_bind_blob(statement, 4, buffer.baseAddress, Int32(iconData.count), nil)
                    }
                } else {
                    sqlite3_bind_null(statement, 4)
                }
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    let fileName = URL(fileURLWithPath: path).lastPathComponent
                    print("[DatabaseManager] Added favorite file: \(displayName ?? fileName)")
                    success = true
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("[DatabaseManager] Failed to insert favorite file '\(path)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("[DatabaseManager] Failed to prepare INSERT for favorite file '\(path)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return success
    }
    
    /// Remove file from favorites
    func removeFavoriteFile(path: String) -> Bool {
        guard let db = db else { return false }
        
        var success = false
        
        queue.sync {
            let sql = "DELETE FROM favorite_files WHERE path = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (path as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("[DatabaseManager] Removed favorite file: \(path)")
                    success = true
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("[DatabaseManager] Failed to delete favorite file '\(path)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("[DatabaseManager] Failed to prepare DELETE for favorite file '\(path)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return success
    }
    
    /// Update file access tracking
    func updateFileAccess(path: String) {
        guard let db = db else { return }
        
        queue.async {
            let now = Int(Date().timeIntervalSince1970)
            
            let sql = """
            UPDATE favorite_files 
            SET last_accessed = ?, access_count = access_count + 1
            WHERE path = ?;
            """
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int64(statement, 1, Int64(now))
                sqlite3_bind_text(statement, 2, (path as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("[DatabaseManager] Updated access for file: \(path)")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("[DatabaseManager] Failed to update access for file '\(path)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("[DatabaseManager] Failed to prepare UPDATE for file access '\(path)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
    }
    
    /// Get file by path
    func getFavoriteFile(path: String) -> FavoriteFileEntry? {
        guard let db = db else { return nil }
        
        var result: FavoriteFileEntry?
        
        queue.sync {
            let sql = "SELECT id, path, display_name, sort_order, icon_data, last_accessed, access_count FROM favorite_files WHERE path = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (path as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(statement, 0))
                    let path = String(cString: sqlite3_column_text(statement, 1))
                    let displayName = sqlite3_column_text(statement, 2) != nil ? String(cString: sqlite3_column_text(statement, 2)) : nil
                    let sortOrder = Int(sqlite3_column_int(statement, 3))
                    
                    var iconData: Data?
                    if let blob = sqlite3_column_blob(statement, 4) {
                        let size = sqlite3_column_bytes(statement, 4)
                        iconData = Data(bytes: blob, count: Int(size))
                    }
                    
                    let lastAccessed: Int? = sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 5))
                    let accessCount = Int(sqlite3_column_int(statement, 6))
                    
                    result = FavoriteFileEntry(
                        id: id,
                        path: path,
                        displayName: displayName,
                        sortOrder: sortOrder,
                        iconData: iconData,
                        lastAccessed: lastAccessed,
                        accessCount: accessCount
                    )
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("[DatabaseManager] Failed to prepare SELECT for file '\(path)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return result
    }
    
    /// Update favorite file details (display name and icon)
    func updateFavoriteFile(path: String, displayName: String?, iconData: Data?) -> Bool {
        guard let db = db else { return false }
        
        var success = false
        
        queue.sync {
            let sql = """
            UPDATE favorite_files
            SET display_name = ?, icon_data = ?
            WHERE path = ?;
            """
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                if let displayName = displayName {
                    sqlite3_bind_text(statement, 1, (displayName as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statement, 1)
                }
                
                if let iconData = iconData {
                    iconData.withUnsafeBytes { buffer in
                        sqlite3_bind_blob(statement, 2, buffer.baseAddress, Int32(iconData.count), nil)
                    }
                } else {
                    sqlite3_bind_null(statement, 2)
                }
                
                sqlite3_bind_text(statement, 3, (path as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("[DatabaseManager] Updated favorite file: \(path)")
                    success = true
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("[DatabaseManager] Failed to update favorite file '\(path)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("[DatabaseManager] Failed to prepare UPDATE for favorite file '\(path)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return success
    }
    
    /// Reorder favorite file
    func reorderFavoriteFile(path: String, newSortOrder: Int) -> Bool {
        guard let db = db else { return false }
        
        var success = false
        
        queue.sync {
            let sql = "UPDATE favorite_files SET sort_order = ? WHERE path = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(newSortOrder))
                sqlite3_bind_text(statement, 2, (path as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("[DatabaseManager] Reordered file: \(path) to position \(newSortOrder)")
                    success = true
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("[DatabaseManager] Failed to reorder file '\(path)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("[DatabaseManager] Failed to prepare UPDATE for reordering file '\(path)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return success
    }
}
