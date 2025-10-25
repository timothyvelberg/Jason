//
//  DatabaseManager+FavoriteApps.swift
//  Jason
//
//  Created by Timothy Velberg on 15/10/2025.

import Foundation
import SQLite3

extension DatabaseManager {
    
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
}
