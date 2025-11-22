//
//  DatabaseManager+FavoriteFolders.swift
//  Jason
//
//  Created by Timothy Velberg on 15/10/2025.

import Foundation
import SQLite3

extension DatabaseManager {
    
    /// Get all favorite folders with their settings
    func getFavoriteFolders() -> [(folder: FolderEntry, settings: FavoriteFolderSettings)] {
        guard let db = db else { return [] }
        
        var results: [(folder: FolderEntry, settings: FavoriteFolderSettings)] = []
        
        queue.sync {
            let sql = """
            SELECT f.id, f.path, f.title, f.icon, f.icon_name, f.icon_color_hex,
                   COALESCE(f.base_asset, 'folder-blue'), 
                   COALESCE(f.symbol_size, 24.0), 
                   COALESCE(f.symbol_offset, -8.0),
                   f.last_accessed, f.access_count,
                   ff.max_items, ff.preferred_layout, ff.item_angle_size, 
                   ff.slice_positioning, ff.child_ring_thickness, ff.child_icon_size,
                   COALESCE(ff.content_sort_order, 'modified_newest')
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
                    
                    // Read sort order
                    let contentSortOrderString = sqlite3_column_text(statement, 17) != nil
                        ? String(cString: sqlite3_column_text(statement, 17))
                        : "modified_newest"
                    let contentSortOrder = FolderSortOrder(rawValue: contentSortOrderString) ?? .modifiedNewest
                    
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
                        childIconSize: childIconSize,
                        contentSortOrder: contentSortOrder
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
             slice_positioning, child_ring_thickness, child_icon_size, content_sort_order) 
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
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
                    sqlite3_bind_text(statement, 4, ("partialSlice" as NSString).utf8String, -1, nil)
                }
                
                if let angleSize = settings?.itemAngleSize {
                    sqlite3_bind_int(statement, 5, Int32(angleSize))
                } else {
                    sqlite3_bind_int(statement, 5, 30)
                }
                
                if let positioning = settings?.slicePositioning {
                    sqlite3_bind_text(statement, 6, (positioning as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_text(statement, 6, ("center" as NSString).utf8String, -1, nil)
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
                
                // Bind content_sort_order
                if let sortOrder = settings?.contentSortOrder {
                    sqlite3_bind_text(statement, 9, (sortOrder.rawValue as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_text(statement, 9, ("modified_newest" as NSString).utf8String, -1, nil)
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
                child_icon_size = ?,
                content_sort_order = ?
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
                    sqlite3_bind_text(settingsStatement, 2, ("partialSlice" as NSString).utf8String, -1, nil)
                }
                
                if let angleSize = settings.itemAngleSize {
                    sqlite3_bind_int(settingsStatement, 3, Int32(angleSize))
                } else {
                    sqlite3_bind_null(settingsStatement, 3)  //Save NULL to use default calculation
                }
                
                if let positioning = settings.slicePositioning {
                    sqlite3_bind_text(settingsStatement, 4, (positioning as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_text(settingsStatement, 4, ("center" as NSString).utf8String, -1, nil)
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
                
                // Bind content_sort_order
                if let sortOrder = settings.contentSortOrder {
                    sqlite3_bind_text(settingsStatement, 7, (sortOrder.rawValue as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_text(settingsStatement, 7, ("modified_newest" as NSString).utf8String, -1, nil)
                }
                
                sqlite3_bind_text(settingsStatement, 8, (path as NSString).utf8String, -1, nil)
                
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
}
