//
//  DatabaseManager+FavoriteDynamicFiles.swift
//  Jason
//
//  Created by Timothy Velberg on 04/11/2025.
//

import Foundation
import SQLite3
import AppKit

extension DatabaseManager {
    
    // MARK: - Favorite Dynamic Files Methods
    
    /// Get all favorite dynamic files
    func getFavoriteDynamicFiles() -> [FavoriteDynamicFileEntry] {
        guard let db = db else { return [] }
        
        var results: [FavoriteDynamicFileEntry] = []
        
        queue.sync {
            let sql = """
            SELECT id, display_name, folder_path, query_type, file_extensions, name_pattern, 
                   sort_order, icon_data, last_accessed, access_count 
            FROM favorite_dynamic_files 
            ORDER BY sort_order;
            """
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(statement, 0))
                    let displayName = String(cString: sqlite3_column_text(statement, 1))
                    let folderPath = String(cString: sqlite3_column_text(statement, 2))
                    let queryType = String(cString: sqlite3_column_text(statement, 3))
                    let fileExtensions = sqlite3_column_text(statement, 4) != nil ? String(cString: sqlite3_column_text(statement, 4)) : nil
                    let namePattern = sqlite3_column_text(statement, 5) != nil ? String(cString: sqlite3_column_text(statement, 5)) : nil
                    let sortOrder = Int(sqlite3_column_int(statement, 6))
                    
                    var iconData: Data?
                    if let blob = sqlite3_column_blob(statement, 7) {
                        let size = sqlite3_column_bytes(statement, 7)
                        iconData = Data(bytes: blob, count: Int(size))
                    }
                    
                    let lastAccessed: Int? = sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 8))
                    let accessCount = Int(sqlite3_column_int(statement, 9))
                    
                    results.append(FavoriteDynamicFileEntry(
                        id: id,
                        displayName: displayName,
                        folderPath: folderPath,
                        queryType: queryType,
                        fileExtensions: fileExtensions,
                        namePattern: namePattern,
                        sortOrder: sortOrder,
                        iconData: iconData,
                        lastAccessed: lastAccessed,
                        accessCount: accessCount
                    ))
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare SELECT for favorite dynamic files: \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return results
    }
    
    /// Add dynamic file to favorites
    func addFavoriteDynamicFile(
        displayName: String,
        folderPath: String,
        queryType: String,
        fileExtensions: String? = nil,
        namePattern: String? = nil,
        iconData: Data? = nil
    ) -> Bool {
        guard let db = db else { return false }
        
        var success = false
        
        queue.sync {
            // Get next sort order
            var nextSortOrder = 0
            var countStatement: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM favorite_dynamic_files;", -1, &countStatement, nil) == SQLITE_OK {
                if sqlite3_step(countStatement) == SQLITE_ROW {
                    nextSortOrder = Int(sqlite3_column_int(countStatement, 0))
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare COUNT for favorite dynamic files: \(String(cString: error))")
                }
            }
            sqlite3_finalize(countStatement)
            
            // Insert new favorite dynamic file
            let sql = """
            INSERT INTO favorite_dynamic_files 
            (display_name, folder_path, query_type, file_extensions, name_pattern, sort_order, icon_data) 
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (displayName as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 2, (folderPath as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 3, (queryType as NSString).utf8String, -1, nil)
                
                if let fileExtensions = fileExtensions {
                    sqlite3_bind_text(statement, 4, (fileExtensions as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statement, 4)
                }
                
                if let namePattern = namePattern {
                    sqlite3_bind_text(statement, 5, (namePattern as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statement, 5)
                }
                
                sqlite3_bind_int(statement, 6, Int32(nextSortOrder))
                
                if let iconData = iconData {
                    iconData.withUnsafeBytes { buffer in
                        sqlite3_bind_blob(statement, 7, buffer.baseAddress, Int32(iconData.count), nil)
                    }
                } else {
                    sqlite3_bind_null(statement, 7)
                }
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("⭐ [DatabaseManager] Added favorite dynamic file: \(displayName)")
                    success = true
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to insert favorite dynamic file '\(displayName)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare INSERT for favorite dynamic file '\(displayName)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return success
    }
    
    /// Remove dynamic file from favorites
    func removeFavoriteDynamicFile(id: Int) -> Bool {
        guard let db = db else { return false }
        
        var success = false
        
        queue.sync {
            let sql = "DELETE FROM favorite_dynamic_files WHERE id = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(id))
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("🗑️ [DatabaseManager] Removed favorite dynamic file: \(id)")
                    success = true
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to delete favorite dynamic file '\(id)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare DELETE for favorite dynamic file '\(id)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return success
    }
    
    /// Update dynamic file access tracking
    func updateDynamicFileAccess(id: Int) {
        guard let db = db else { return }
        
        queue.async {
            let now = Int(Date().timeIntervalSince1970)
            
            let sql = """
            UPDATE favorite_dynamic_files 
            SET last_accessed = ?, access_count = access_count + 1
            WHERE id = ?;
            """
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int64(statement, 1, Int64(now))
                sqlite3_bind_int(statement, 2, Int32(id))
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("📊 [DatabaseManager] Updated access for dynamic file: \(id)")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to update access for dynamic file '\(id)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare UPDATE for dynamic file access '\(id)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
    }
    
    /// Get dynamic file by ID
    func getFavoriteDynamicFile(id: Int) -> FavoriteDynamicFileEntry? {
        guard let db = db else { return nil }
        
        var result: FavoriteDynamicFileEntry?
        
        queue.sync {
            let sql = """
            SELECT id, display_name, folder_path, query_type, file_extensions, name_pattern, 
                   sort_order, icon_data, last_accessed, access_count 
            FROM favorite_dynamic_files 
            WHERE id = ?;
            """
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(id))
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(statement, 0))
                    let displayName = String(cString: sqlite3_column_text(statement, 1))
                    let folderPath = String(cString: sqlite3_column_text(statement, 2))
                    let queryType = String(cString: sqlite3_column_text(statement, 3))
                    let fileExtensions = sqlite3_column_text(statement, 4) != nil ? String(cString: sqlite3_column_text(statement, 4)) : nil
                    let namePattern = sqlite3_column_text(statement, 5) != nil ? String(cString: sqlite3_column_text(statement, 5)) : nil
                    let sortOrder = Int(sqlite3_column_int(statement, 6))
                    
                    var iconData: Data?
                    if let blob = sqlite3_column_blob(statement, 7) {
                        let size = sqlite3_column_bytes(statement, 7)
                        iconData = Data(bytes: blob, count: Int(size))
                    }
                    
                    let lastAccessed: Int? = sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 8))
                    let accessCount = Int(sqlite3_column_int(statement, 9))
                    
                    result = FavoriteDynamicFileEntry(
                        id: id,
                        displayName: displayName,
                        folderPath: folderPath,
                        queryType: queryType,
                        fileExtensions: fileExtensions,
                        namePattern: namePattern,
                        sortOrder: sortOrder,
                        iconData: iconData,
                        lastAccessed: lastAccessed,
                        accessCount: accessCount
                    )
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare SELECT for dynamic file '\(id)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return result
    }
    
    /// Update favorite dynamic file details
    func updateFavoriteDynamicFile(
        id: Int,
        displayName: String,
        folderPath: String,
        queryType: String,
        fileExtensions: String?,
        namePattern: String?,
        iconData: Data?
    ) -> Bool {
        guard let db = db else { return false }
        
        var success = false
        
        queue.sync {
            let sql = """
            UPDATE favorite_dynamic_files
            SET display_name = ?, folder_path = ?, query_type = ?, 
                file_extensions = ?, name_pattern = ?, icon_data = ?
            WHERE id = ?;
            """
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (displayName as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 2, (folderPath as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 3, (queryType as NSString).utf8String, -1, nil)
                
                if let fileExtensions = fileExtensions {
                    sqlite3_bind_text(statement, 4, (fileExtensions as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statement, 4)
                }
                
                if let namePattern = namePattern {
                    sqlite3_bind_text(statement, 5, (namePattern as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statement, 5)
                }
                
                if let iconData = iconData {
                    iconData.withUnsafeBytes { buffer in
                        sqlite3_bind_blob(statement, 6, buffer.baseAddress, Int32(iconData.count), nil)
                    }
                } else {
                    sqlite3_bind_null(statement, 6)
                }
                
                sqlite3_bind_int(statement, 7, Int32(id))
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("✏️ [DatabaseManager] Updated favorite dynamic file: \(displayName)")
                    success = true
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to update favorite dynamic file '\(displayName)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare UPDATE for favorite dynamic file '\(displayName)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return success
    }
    
    /// Reorder favorite dynamic file
    func reorderFavoriteDynamicFile(id: Int, newSortOrder: Int) -> Bool {
        guard let db = db else { return false }
        
        var success = false
        
        queue.sync {
            let sql = "UPDATE favorite_dynamic_files SET sort_order = ? WHERE id = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(newSortOrder))
                sqlite3_bind_int(statement, 2, Int32(id))
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("🔄 [DatabaseManager] Reordered dynamic file: \(id) to position \(newSortOrder)")
                    success = true
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to reorder dynamic file '\(id)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare UPDATE for reordering dynamic file '\(id)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return success
    }
}
