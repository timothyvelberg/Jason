//
//  DatabaseManager+RingTriggers..swift
//  Jason
//
//  Created by Timothy Velberg on 28/01/2026.
//  CRUD operations for ring triggers

import Foundation
import SQLite3

extension DatabaseManager {
    
    // MARK: - Create
    
    /// Create a new trigger for a ring
    /// - Returns: The new trigger ID, or nil if creation failed (e.g., duplicate trigger)
    func createTrigger(
        ringId: Int,
        triggerType: String,
        keyCode: UInt16? = nil,
        modifierFlags: UInt = 0,
        buttonNumber: Int32? = nil,
        swipeDirection: String? = nil,
        fingerCount: Int? = nil,
        isHoldMode: Bool = false,
        autoExecuteOnRelease: Bool = true
    ) -> Int? {
        guard let db = db else { return nil }
        
        var triggerId: Int?
        
        queue.sync {
            // Validate trigger is not already in use
            if _isTriggerInUseForTriggers(
                triggerType: triggerType,
                keyCode: keyCode,
                modifierFlags: modifierFlags,
                buttonNumber: buttonNumber,
                swipeDirection: swipeDirection,
                fingerCount: fingerCount,
                excludingTriggerId: nil
            ) {
                print("⚠️ [DatabaseManager] Trigger already in use by another ring")
                return
            }
            
            let sql = """
            INSERT INTO ring_triggers (ring_id, trigger_type, key_code, modifier_flags, button_number, swipe_direction, finger_count, is_hold_mode, auto_execute_on_release)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(ringId))
                sqlite3_bind_text(statement, 2, (triggerType as NSString).utf8String, -1, nil)
                
                if let keyCode = keyCode {
                    sqlite3_bind_int(statement, 3, Int32(keyCode))
                } else {
                    sqlite3_bind_null(statement, 3)
                }
                
                sqlite3_bind_int(statement, 4, Int32(modifierFlags))
                
                if let buttonNumber = buttonNumber {
                    sqlite3_bind_int(statement, 5, buttonNumber)
                } else {
                    sqlite3_bind_null(statement, 5)
                }
                
                if let swipeDirection = swipeDirection {
                    sqlite3_bind_text(statement, 6, (swipeDirection as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statement, 6)
                }
                
                if let fingerCount = fingerCount {
                    sqlite3_bind_int(statement, 7, Int32(fingerCount))
                } else {
                    sqlite3_bind_null(statement, 7)
                }
                
                sqlite3_bind_int(statement, 8, isHoldMode ? 1 : 0)
                sqlite3_bind_int(statement, 9, autoExecuteOnRelease ? 1 : 0)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    triggerId = Int(sqlite3_last_insert_rowid(db))
                    print("🎯 [DatabaseManager] Created trigger (id: \(triggerId!)) for ring \(ringId)")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to create trigger: \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare INSERT for trigger: \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return triggerId
    }
    
    // MARK: - Read
    
    /// Get all triggers for a specific ring
    func getTriggersForRing(ringId: Int) -> [RingTriggerEntry] {
        guard let db = db else { return [] }
        
        var results: [RingTriggerEntry] = []
        
        queue.sync {
            let sql = """
            SELECT id, ring_id, trigger_type, key_code, modifier_flags, button_number, swipe_direction, finger_count, is_hold_mode, auto_execute_on_release, created_at
            FROM ring_triggers
            WHERE ring_id = ?
            ORDER BY created_at;
            """
            
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(ringId))
                
                while sqlite3_step(statement) == SQLITE_ROW {
                    let entry = parseTriggerRow(statement)
                    results.append(entry)
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to fetch triggers for ring \(ringId): \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return results
    }
    
    /// Get a single trigger by ID
    func getTrigger(id: Int) -> RingTriggerEntry? {
        guard let db = db else { return nil }
        
        var result: RingTriggerEntry?
        
        queue.sync {
            let sql = """
            SELECT id, ring_id, trigger_type, key_code, modifier_flags, button_number, swipe_direction, finger_count, is_hold_mode, auto_execute_on_release, created_at
            FROM ring_triggers
            WHERE id = ?;
            """
            
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(id))
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    result = parseTriggerRow(statement)
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to fetch trigger \(id): \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return result
    }
    
    // MARK: - Delete
    
    /// Delete a trigger by ID
    func deleteTrigger(id: Int) {
        guard let db = db else { return }
        
        queue.async {
            let sql = "DELETE FROM ring_triggers WHERE id = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(id))
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    let changes = sqlite3_changes(db)
                    if changes > 0 {
                        print("🗑️ [DatabaseManager] Deleted trigger \(id)")
                    } else {
                        print("⚠️ [DatabaseManager] Trigger \(id) not found")
                    }
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to delete trigger \(id): \(String(cString: error))")
                    }
                }
            }
            sqlite3_finalize(statement)
        }
    }
    
    // MARK: - Validation
    
    /// Check if a trigger is already in use (queries ring_triggers table)
    /// - Parameter excludingTriggerId: Optional trigger ID to exclude (for updates)
    /// - Returns: true if trigger is in use, false otherwise
    func _isTriggerInUseForTriggers(
        triggerType: String,
        keyCode: UInt16?,
        modifierFlags: UInt,
        buttonNumber: Int32?,
        swipeDirection: String?,
        fingerCount: Int?,
        excludingTriggerId: Int?
    ) -> Bool {
        guard let db = db else { return false }
        
        var inUse = false
        
        // Build query based on trigger type
        let sql: String
        switch triggerType {
        case "keyboard":
            guard let keyCode = keyCode else { return false }
            sql = """
            SELECT t.id FROM ring_triggers t
            JOIN ring_configurations r ON t.ring_id = r.id
            WHERE t.trigger_type = 'keyboard' 
            AND t.key_code = \(keyCode) 
            AND t.modifier_flags = \(modifierFlags)
            AND r.is_active = 1
            \(excludingTriggerId.map { "AND t.id != \($0)" } ?? "");
            """
            
        case "mouse":
            guard let buttonNumber = buttonNumber else { return false }
            sql = """
            SELECT t.id FROM ring_triggers t
            JOIN ring_configurations r ON t.ring_id = r.id
            WHERE t.trigger_type = 'mouse' 
            AND t.button_number = \(buttonNumber) 
            AND t.modifier_flags = \(modifierFlags)
            AND r.is_active = 1
            \(excludingTriggerId.map { "AND t.id != \($0)" } ?? "");
            """
            
        case "trackpad":
            guard let swipeDirection = swipeDirection, let fingerCount = fingerCount else { return false }
            sql = """
            SELECT t.id FROM ring_triggers t
            JOIN ring_configurations r ON t.ring_id = r.id
            WHERE t.trigger_type = 'trackpad' 
            AND t.swipe_direction = '\(swipeDirection)' 
            AND t.finger_count = \(fingerCount) 
            AND t.modifier_flags = \(modifierFlags)
            AND r.is_active = 1
            \(excludingTriggerId.map { "AND t.id != \($0)" } ?? "");
            """
            
        default:
            return false
        }
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                inUse = true
            }
        }
        sqlite3_finalize(statement)
        
        return inUse
    }
    
    // MARK: - Private Helpers
    
    /// Parse a trigger row from a prepared statement
    private func parseTriggerRow(_ statement: OpaquePointer?) -> RingTriggerEntry {
        let id = Int(sqlite3_column_int(statement, 0))
        let ringId = Int(sqlite3_column_int(statement, 1))
        let triggerType = String(cString: sqlite3_column_text(statement, 2))
        
        let keyCode: UInt16? = {
            if sqlite3_column_type(statement, 3) == SQLITE_NULL { return nil }
            return UInt16(sqlite3_column_int(statement, 3))
        }()
        
        let modifierFlags = UInt(sqlite3_column_int(statement, 4))
        
        let buttonNumber: Int32? = {
            if sqlite3_column_type(statement, 5) == SQLITE_NULL { return nil }
            return sqlite3_column_int(statement, 5)
        }()
        
        let swipeDirection: String? = {
            if sqlite3_column_type(statement, 6) == SQLITE_NULL { return nil }
            return String(cString: sqlite3_column_text(statement, 6))
        }()
        
        let fingerCount: Int? = {
            if sqlite3_column_type(statement, 7) == SQLITE_NULL { return nil }
            return Int(sqlite3_column_int(statement, 7))
        }()
        
        let isHoldMode = sqlite3_column_int(statement, 8) == 1
        let autoExecuteOnRelease = sqlite3_column_int(statement, 9) == 1
        let createdAt = Int(sqlite3_column_int64(statement, 10))
        
        return RingTriggerEntry(
            id: id,
            ringId: ringId,
            triggerType: triggerType,
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            buttonNumber: buttonNumber,
            swipeDirection: swipeDirection,
            fingerCount: fingerCount,
            isHoldMode: isHoldMode,
            autoExecuteOnRelease: autoExecuteOnRelease,
            createdAt: createdAt
        )
    }
}
