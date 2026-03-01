//
//  DatabaseManager+Snippets.swift
//  Jason
//
//  Created by Timothy Velberg on 07/02/2026.

import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension DatabaseManager {
    
    /// Save a new snippet to the database
    func saveSnippet(id: String, title: String, content: String, triggerText: String?, sortOrder: Int, createdAt: Date) {
        queue.sync {
            guard let db = db else {
                print("❌ [DatabaseManager] Database not initialized")
                return
            }
            
            let sql = "INSERT OR REPLACE INTO snippets (id, title, content, trigger_text, sort_order, created_at) VALUES (?, ?, ?, ?, ?, ?);"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, title, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 3, content, -1, SQLITE_TRANSIENT)
                if let triggerText = triggerText {
                    sqlite3_bind_text(statement, 4, triggerText, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(statement, 4)
                }
                sqlite3_bind_int(statement, 5, Int32(sortOrder))
                sqlite3_bind_double(statement, 6, createdAt.timeIntervalSince1970)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("✅ [DatabaseManager] Saved snippet: \"\(title)\"")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to save snippet: \(String(cString: error))")
                    }
                }
            }
            
            sqlite3_finalize(statement)
        }
    }
    
    /// Update an existing snippet
    func updateSnippet(id: String, title: String, content: String, triggerText: String?) {
        queue.sync {
            guard let db = db else {
                print("❌ [DatabaseManager] Database not initialized")
                return
            }
            
            let sql = "UPDATE snippets SET title = ?, content = ?, trigger_text = ? WHERE id = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, title, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, content, -1, SQLITE_TRANSIENT)
                if let triggerText = triggerText {
                    sqlite3_bind_text(statement, 3, triggerText, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(statement, 3)
                }
                sqlite3_bind_text(statement, 4, id, -1, SQLITE_TRANSIENT)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("[DatabaseManager] Updated snippet: \"\(title)\"")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("[DatabaseManager] Failed to update snippet: \(String(cString: error))")
                    }
                }
            }
            
            sqlite3_finalize(statement)
        }
    }
    
    /// Delete a snippet from the database
    func deleteSnippet(id: String) {
        queue.sync {
            guard let db = db else {
                print("[DatabaseManager] Database not initialized")
                return
            }
            
            let sql = "DELETE FROM snippets WHERE id = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("[DatabaseManager] Deleted snippet: \(id)")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("[DatabaseManager] Failed to delete snippet: \(String(cString: error))")
                    }
                }
            }
            
            sqlite3_finalize(statement)
        }
    }
    
    /// Get all snippets, ordered by sort_order
    func getAllSnippets() -> [SnippetsProvider.Snippet] {
        var items: [SnippetsProvider.Snippet] = []
        
        queue.sync {
            guard let db = db else {
                print("[DatabaseManager] Database not initialized")
                return
            }
            
            let sql = "SELECT id, title, content, trigger_text, sort_order, created_at FROM snippets ORDER BY sort_order ASC;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    guard let idCString = sqlite3_column_text(statement, 0),
                          let titleCString = sqlite3_column_text(statement, 1),
                          let contentCString = sqlite3_column_text(statement, 2) else {
                        continue
                    }
                    
                    let id = String(cString: idCString)
                    let title = String(cString: titleCString)
                    let content = String(cString: contentCString)
                    let triggerText: String? = sqlite3_column_text(statement, 3).map { String(cString: $0) }
                    let sortOrder = Int(sqlite3_column_int(statement, 4))
                    let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
                    
                    items.append(SnippetsProvider.Snippet(
                        id: id,
                        title: title,
                        content: content,
                        triggerText: triggerText,
                        sortOrder: sortOrder,
                        createdAt: createdAt
                    ))
                }
            }
            
            sqlite3_finalize(statement)
        }
        
        print("[DatabaseManager] Loaded \(items.count) snippets")
        return items
    }
    
    /// Reorder a snippet
    func reorderSnippet(id: String, newSortOrder: Int) {
        queue.sync {
            guard let db = db else {
                print("[DatabaseManager] Database not initialized")
                return
            }
            
            let sql = "UPDATE snippets SET sort_order = ? WHERE id = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(newSortOrder))
                sqlite3_bind_text(statement, 2, id, -1, SQLITE_TRANSIENT)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("[DatabaseManager] Reordered snippet \(id) to position \(newSortOrder)")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("[DatabaseManager] Failed to reorder snippet: \(String(cString: error))")
                    }
                }
            }
            
            sqlite3_finalize(statement)
        }
    }
    
    /// Get the next available sort order for a new snippet
    func getNextSnippetSortOrder() -> Int {
        var maxOrder = -1
        
        queue.sync {
            guard let db = db else { return }
            
            let sql = "SELECT MAX(sort_order) FROM snippets;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) == SQLITE_ROW {
                    if sqlite3_column_type(statement, 0) != SQLITE_NULL {
                        maxOrder = Int(sqlite3_column_int(statement, 0))
                    }
                }
            }
            
            sqlite3_finalize(statement)
        }
        
        return maxOrder + 1
    }
}
