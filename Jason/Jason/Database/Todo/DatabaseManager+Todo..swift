//
//  DatabaseManager+Todo..swift
//  Jason
//
//  Created by Timothy Velberg on 04/02/2026.

import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension DatabaseManager {
    
    /// Save a new todo to the database
    func saveTodo(id: String, title: String, createdAt: Date) {
        queue.sync {
            guard let db = db else {
                print("❌ [DatabaseManager] Database not initialized")
                return
            }
            
            let sql = "INSERT OR REPLACE INTO todos (id, title, is_completed, created_at) VALUES (?, ?, 0, ?);"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, title, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(statement, 3, createdAt.timeIntervalSince1970)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("✅ [DatabaseManager] Saved todo: \"\(title)\"")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to save todo: \(String(cString: error))")
                    }
                }
            }
            
            sqlite3_finalize(statement)
        }
    }
    
    /// Toggle a todo's completion status
    func toggleTodo(id: String) {
        queue.sync {
            guard let db = db else {
                print("❌ [DatabaseManager] Database not initialized")
                return
            }
            
            let sql = "UPDATE todos SET is_completed = CASE WHEN is_completed = 0 THEN 1 ELSE 0 END WHERE id = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("✅ [DatabaseManager] Toggled todo: \(id)")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to toggle todo: \(String(cString: error))")
                    }
                }
            }
            
            sqlite3_finalize(statement)
        }
    }
    
    /// Delete a todo from the database
    func deleteTodo(id: String) {
        queue.sync {
            guard let db = db else {
                print("❌ [DatabaseManager] Database not initialized")
                return
            }
            
            let sql = "DELETE FROM todos WHERE id = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("🗑️ [DatabaseManager] Deleted todo: \(id)")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to delete todo: \(String(cString: error))")
                    }
                }
            }
            
            sqlite3_finalize(statement)
        }
    }
    
    /// Get all todos, ordered by newest first
    func getAllTodos() -> [TodoListProvider.TodoItem] {
        var items: [TodoListProvider.TodoItem] = []
        
        queue.sync {
            guard let db = db else {
                print("❌ [DatabaseManager] Database not initialized")
                return
            }
            
            let sql = "SELECT id, title, is_completed, created_at FROM todos ORDER BY created_at DESC;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    guard let idCString = sqlite3_column_text(statement, 0),
                          let titleCString = sqlite3_column_text(statement, 1) else {
                        continue
                    }
                    
                    let id = String(cString: idCString)
                    let title = String(cString: titleCString)
                    let isCompleted = sqlite3_column_int(statement, 2) == 1
                    let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
                    
                    items.append(TodoListProvider.TodoItem(
                        id: id,
                        title: title,
                        isCompleted: isCompleted,
                        createdAt: createdAt
                    ))
                }
            }
            
            sqlite3_finalize(statement)
        }
        
        print("📋 [DatabaseManager] Loaded \(items.count) todos")
        return items
    }
}
