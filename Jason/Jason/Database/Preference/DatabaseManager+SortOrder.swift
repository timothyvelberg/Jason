//
//  DatabaseManager+SortOrder.swift
//  Jason
//
//  Created by Timothy Velberg on 26/10/2025.
//

import Foundation
import SQLite3

extension DatabaseManager {
    
    // MARK: - Update Sort Order
    
    /// Update sort order preference for a favorite folder
    func updateFavoriteFolderSortOrder(folderPath: String, sortOrder: FolderSortOrder) {
        guard let db = db else { return }
        
        queue.sync {
            let sql = """
            UPDATE favorite_folders 
            SET sort_order = ? 
            WHERE folder_id = (SELECT id FROM folders WHERE path = ?);
            """
            
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (sortOrder.rawValue as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 2, (folderPath as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("✅ [DatabaseManager] Updated sort order for \(folderPath) to \(sortOrder.displayName)")
                    
                    // Invalidate cache so next visit uses new sorting
                    invalidateEnhancedCache(for: folderPath)
                } else {
                    let error = String(cString: sqlite3_errmsg(db))
                    print("⚠️ [DatabaseManager] Failed to update sort order: \(error)")
                }
            }
            sqlite3_finalize(statement)
        }
    }
    
    /// Get sort order for a favorite folder
    func getFavoriteFolderSortOrder(folderPath: String) -> FolderSortOrder {
        guard let db = db else { return .modifiedNewest }
        
        var sortOrder: FolderSortOrder = .modifiedNewest
        
        queue.sync {
            let sql = """
            SELECT ff.sort_order 
            FROM favorite_folders ff
            JOIN folders f ON ff.folder_id = f.id
            WHERE f.path = ?;
            """
            
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (folderPath as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    if let sortOrderText = sqlite3_column_text(statement, 0) {
                        let sortOrderString = String(cString: sortOrderText)
                        sortOrder = FolderSortOrder(rawValue: sortOrderString) ?? .modifiedNewest
                    }
                }
            }
            sqlite3_finalize(statement)
        }
        
        return sortOrder
    }
}
