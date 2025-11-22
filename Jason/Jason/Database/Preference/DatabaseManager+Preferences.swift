//
//  DatabaseManager+Preferences.swift
//  Jason
//
//  Created by Timothy Velberg on 15/10/2025.

import Foundation
import SQLite3

extension DatabaseManager {

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
