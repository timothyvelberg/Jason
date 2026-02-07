//
//  DatabaseManager+Clipboard.swift
//  Jason
//
//  Created by Timothy Velberg on 30/01/2026.
//

import Foundation
import SQLite3

// MARK: - SQLite Constants

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - Clipboard History

extension DatabaseManager {
    
    /// Save a clipboard entry to the database
    func saveClipboardEntry(_ entry: ClipboardEntry) {
        queue.sync {
            guard let db = db else {
                print("❌ [DatabaseManager] Database not initialized")
                return
            }
            
            let sql = """
            INSERT OR REPLACE INTO clipboard_history (id, content, rtf_data, html_data, copied_at)
            VALUES (?, ?, ?, ?, ?);
            """
            
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, entry.id.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, entry.content, -1, SQLITE_TRANSIENT)
                
                // Bind RTF data (BLOB) or NULL
                if let rtfData = entry.rtfData {
                    rtfData.withUnsafeBytes { bytes in
                        sqlite3_bind_blob(statement, 3, bytes.baseAddress, Int32(rtfData.count), SQLITE_TRANSIENT)
                    }
                } else {
                    sqlite3_bind_null(statement, 3)
                }
                
                // Bind HTML data (BLOB) or NULL
                if let htmlData = entry.htmlData {
                    htmlData.withUnsafeBytes { bytes in
                        sqlite3_bind_blob(statement, 4, bytes.baseAddress, Int32(htmlData.count), SQLITE_TRANSIENT)
                    }
                } else {
                    sqlite3_bind_null(statement, 4)
                }
                
                sqlite3_bind_double(statement, 5, entry.copiedAt.timeIntervalSince1970)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    let rtfInfo = entry.rtfData != nil ? " RTF:\(entry.rtfData!.count)" : ""
                    let htmlInfo = entry.htmlData != nil ? " HTML:\(entry.htmlData!.count)" : ""
                    print("📋 [DatabaseManager] Saved clipboard entry: \"\(entry.content.prefix(30))...\"\(rtfInfo)\(htmlInfo)")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to save clipboard entry: \(String(cString: error))")
                    }
                }
            }
            
            sqlite3_finalize(statement)
        }
    }
    
    /// Delete a clipboard entry from the database
    func deleteClipboardEntry(id: UUID) {
        queue.sync {
            guard let db = db else {
                print("❌ [DatabaseManager] Database not initialized")
                return
            }
            
            let sql = "DELETE FROM clipboard_history WHERE id = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, id.uuidString, -1, SQLITE_TRANSIENT)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("🗑️ [DatabaseManager] Deleted clipboard entry: \(id)")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to delete clipboard entry: \(String(cString: error))")
                    }
                }
            }
            
            sqlite3_finalize(statement)
        }
    }
    
    /// Get all clipboard entries, ordered by most recent first
    func getAllClipboardEntries() -> [ClipboardEntry] {
        var entries: [ClipboardEntry] = []
        
        queue.sync {
            guard let db = db else {
                print("❌ [DatabaseManager] Database not initialized")
                return
            }
            
            let sql = "SELECT id, content, rtf_data, html_data, copied_at FROM clipboard_history ORDER BY copied_at DESC;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    guard let idCString = sqlite3_column_text(statement, 0),
                          let contentCString = sqlite3_column_text(statement, 1) else {
                        continue
                    }
                    
                    let idString = String(cString: idCString)
                    let content = String(cString: contentCString)
                    
                    // Read RTF data (BLOB) - may be NULL
                    var rtfData: Data? = nil
                    if let blobPointer = sqlite3_column_blob(statement, 2) {
                        let blobSize = sqlite3_column_bytes(statement, 2)
                        if blobSize > 0 {
                            rtfData = Data(bytes: blobPointer, count: Int(blobSize))
                        }
                    }
                    
                    // Read HTML data (BLOB) - may be NULL
                    var htmlData: Data? = nil
                    if let blobPointer = sqlite3_column_blob(statement, 3) {
                        let blobSize = sqlite3_column_bytes(statement, 3)
                        if blobSize > 0 {
                            htmlData = Data(bytes: blobPointer, count: Int(blobSize))
                        }
                    }
                    
                    let copiedAt = sqlite3_column_double(statement, 4)
                    
                    if let uuid = UUID(uuidString: idString) {
                        let entry = ClipboardEntry(
                            id: uuid,
                            content: content,
                            rtfData: rtfData,
                            htmlData: htmlData,
                            copiedAt: Date(timeIntervalSince1970: copiedAt)
                        )
                        entries.append(entry)
                    }
                }
            }
            
            sqlite3_finalize(statement)
        }
        
        let rtfCount = entries.filter { $0.rtfData != nil }.count
        let htmlCount = entries.filter { $0.htmlData != nil }.count
        print("📋 [DatabaseManager] Loaded \(entries.count) clipboard entries (\(rtfCount) RTF, \(htmlCount) HTML)")
        return entries
    }
    
    /// Clear all clipboard history from database
    func clearClipboardHistory() {
        queue.sync {
            guard let db = db else {
                print("❌ [DatabaseManager] Database not initialized")
                return
            }
            
            let sql = "DELETE FROM clipboard_history;"
            
            if sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK {
                print("🗑️ [DatabaseManager] Cleared all clipboard history")
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to clear clipboard history: \(String(cString: error))")
                }
            }
        }
    }
    
    /// Prune clipboard history to keep only the most recent entries
    func pruneClipboardHistory(keepCount: Int = 200) {
        queue.sync {
            guard let db = db else {
                print("❌ [DatabaseManager] Database not initialized")
                return
            }
            
            let sql = """
            DELETE FROM clipboard_history
            WHERE id NOT IN (
                SELECT id FROM clipboard_history
                ORDER BY copied_at DESC
                LIMIT ?
            );
            """
            
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(keepCount))
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    let deletedCount = sqlite3_changes(db)
                    if deletedCount > 0 {
                        print("🧹 [DatabaseManager] Pruned \(deletedCount) old clipboard entries (keeping \(keepCount))")
                    }
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to prune clipboard history: \(String(cString: error))")
                    }
                }
            }
            
            sqlite3_finalize(statement)
        }
    }
}
