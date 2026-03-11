//
//  DatabaseManager+Legacy.swift
//  Jason
//
//  Created by Timothy Velberg on 15/10/2025.
//
//  Legacy favorites system - can be removed once fully migrated to new system

import Foundation
import SQLite3

extension DatabaseManager {
    
    // MARK: - Legacy Favorites Methods (Deprecated)
    
    /// Get all favorites (legacy system)
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
    
    /// Add favorite (legacy system)
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
    
    /// Remove favorite (legacy system)
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
}
