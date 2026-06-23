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
        var didUpdate = false
        
        queue.sync {
            let sql = """
            UPDATE favorite_folders 
            SET content_sort_order = ? 
            WHERE folder_id = (SELECT id FROM folders WHERE path = ?);
            """
            
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (sortOrder.rawValue as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, (folderPath as NSString).utf8String, -1, SQLITE_TRANSIENT)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("✅ [DatabaseManager] Updated sort order for \(folderPath) to \(sortOrder.displayName)")
                    
                    didUpdate = true
                } else {
                    let error = String(cString: sqlite3_errmsg(db))
                    print("⚠️ [DatabaseManager] Failed to update sort order: \(error)")
                }
            }
            sqlite3_finalize(statement)
        }

        // Invalidate the cache OUTSIDE the serial queue: invalidateEnhancedCache runs
        // its own queue.sync, so calling it inside the block above would re-enter the
        // serial queue and deadlock.
        if didUpdate {
            invalidateEnhancedCache(for: folderPath)
        }
    }
    
    /// Get sort order for a favorite folder
    func getFavoriteFolderSortOrder(folderPath: String) -> FolderSortOrder {
        guard let db = db else { return .modifiedNewest }
        
        var sortOrder: FolderSortOrder = .modifiedNewest
        
        queue.sync {
            let sql = """
            SELECT ff.content_sort_order 
            FROM favorite_folders ff
            JOIN folders f ON ff.folder_id = f.id
            WHERE f.path = ?;
            """
            
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (folderPath as NSString).utf8String, -1, SQLITE_TRANSIENT)
                
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
