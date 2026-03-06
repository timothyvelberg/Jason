//
//  DatabaseManager+RingValidation.swift
//  Jason
//
//  Validation helpers for checking trigger conflicts and provider order conflicts
//

import Foundation
import SQLite3
import AppKit

extension DatabaseManager {
    
    /// Check if a trigger (keyboard, mouse, or swipe) is already in use by an active ring (UNSAFE - must be called within queue.sync)
    func _isTriggerInUse(
        triggerType: String,
        keyCode: UInt16?,
        modifierFlags: UInt,
        buttonNumber: Int32?,
        swipeDirection: String?,
        fingerCount: Int?
    ) -> Bool {
        guard let db = db else { return false }
        
        if triggerType == "keyboard" {
            // Check keyboard shortcut conflicts
            guard let keyCode = keyCode else { return false }
            
            let sql = "SELECT id FROM ring_configurations WHERE trigger_type = 'keyboard' AND key_code = ? AND modifier_flags = ? AND is_active = 1;"
            var statement: OpaquePointer?
            var inUse = false
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(keyCode))
                sqlite3_bind_int(statement, 2, Int32(modifierFlags))
                if sqlite3_step(statement) == SQLITE_ROW {
                    inUse = true
                }
            }
            sqlite3_finalize(statement)
            
            return inUse
            
        } else if triggerType == "mouse" {
            // Check mouse button conflicts
            guard let buttonNumber = buttonNumber else { return false }
            
            let sql = "SELECT id FROM ring_configurations WHERE trigger_type = 'mouse' AND button_number = ? AND modifier_flags = ? AND is_active = 1;"
            var statement: OpaquePointer?
            var inUse = false
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, buttonNumber)
                sqlite3_bind_int(statement, 2, Int32(modifierFlags))
                if sqlite3_step(statement) == SQLITE_ROW {
                    inUse = true
                }
            }
            sqlite3_finalize(statement)
            
            return inUse
            
        } else if triggerType == "trackpad" {
            // Check trackpad gesture conflicts (direction + finger_count + modifiers)
            guard let swipeDirection = swipeDirection else { return false }
            guard let fingerCount = fingerCount else { return false }
            
            let sql = "SELECT id FROM ring_configurations WHERE trigger_type = 'trackpad' AND swipe_direction = ? AND finger_count = ? AND modifier_flags = ? AND is_active = 1;"
            var statement: OpaquePointer?
            var inUse = false
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (swipeDirection as NSString).utf8String, -1, nil)
                sqlite3_bind_int(statement, 2, Int32(fingerCount))
                sqlite3_bind_int(statement, 3, Int32(modifierFlags))
                if sqlite3_step(statement) == SQLITE_ROW {
                    inUse = true
                }
            }
            sqlite3_finalize(statement)
            
            return inUse
        } else if triggerType == "swipe" {
            // Legacy "swipe" support (treat as 3-finger trackpad gesture)
            guard let swipeDirection = swipeDirection else { return false }
            
            let sql = "SELECT id FROM ring_configurations WHERE trigger_type IN ('swipe', 'trackpad') AND swipe_direction = ? AND (finger_count = 3 OR finger_count IS NULL) AND modifier_flags = ? AND is_active = 1;"
            var statement: OpaquePointer?
            var inUse = false
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (swipeDirection as NSString).utf8String, -1, nil)
                sqlite3_bind_int(statement, 2, Int32(modifierFlags))
                if sqlite3_step(statement) == SQLITE_ROW {
                    inUse = true
                }
            }
            sqlite3_finalize(statement)
            
            return inUse
        }
        
        return false
    }
    
    /// Check if a provider order is already in use for a ring (UNSAFE - must be called within queue.sync)
    func _isProviderOrderInUse(ringId: Int, providerOrder: Int) -> Bool {
        guard let db = db else { return false }
        
        let sql = "SELECT id FROM ring_providers WHERE ring_id = ? AND provider_order = ?;"
        var statement: OpaquePointer?
        var inUse = false
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(ringId))
            sqlite3_bind_int(statement, 2, Int32(providerOrder))
            if sqlite3_step(statement) == SQLITE_ROW {
                inUse = true
            }
        }
        sqlite3_finalize(statement)
        
        return inUse
    }
    
}
