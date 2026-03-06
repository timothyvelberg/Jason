//
//  DatabaseManager+HeavyFolderManagement.swift
//  Jason
//
//  Created by Timothy Velberg on 25/10/2025.
//

import Foundation
import SQLite3

extension DatabaseManager {
    
    // MARK: - Heavy Folder Management
    
    /// Remove a folder from heavy_folders table
    func removeHeavyFolder(path: String) {
        guard let db = db else {
            print("DatabaseManager] Database not initialized")
            return
        }
        
        let sql = "DELETE FROM heavy_folders WHERE path = ?;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (path as NSString).utf8String, -1, nil)
            
            if sqlite3_step(statement) == SQLITE_DONE {
                print("[DatabaseManager] Removed from heavy folders: \(path)")
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                print("[DatabaseManager] Failed to remove heavy folder: \(error)")
            }
        } else {
            let error = String(cString: sqlite3_errmsg(db))
            print("[DatabaseManager] Failed to prepare remove statement: \(error)")
        }
        
        sqlite3_finalize(statement)
    }
    
    /// Get heavy folder item count
    func getHeavyFolderItemCount(path: String) -> Int? {
        guard let db = db else { return nil }
        
        let sql = "SELECT item_count FROM heavy_folders WHERE path = ?;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        
        sqlite3_bind_text(statement, 1, (path as NSString).utf8String, -1, nil)
        
        var count: Int?
        if sqlite3_step(statement) == SQLITE_ROW {
            count = Int(sqlite3_column_int(statement, 0))
        }
        
        sqlite3_finalize(statement)
        return count
    }
    
    /// Update heavy folder item count
    func updateHeavyFolderItemCount(path: String, itemCount: Int) {
        guard let db = db else { return }
        
        let sql = "UPDATE heavy_folders SET item_count = ? WHERE path = ?;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(itemCount))
            sqlite3_bind_text(statement, 2, (path as NSString).utf8String, -1, nil)
            
            if sqlite3_step(statement) == SQLITE_DONE {
                print("[DatabaseManager] Updated item count for: \(path) to \(itemCount)")
            } else {
                let error = String(cString: sqlite3_errmsg(db))
                print("[DatabaseManager] Failed to update item count: \(error)")
            }
        }
        
        sqlite3_finalize(statement)
    }
}
