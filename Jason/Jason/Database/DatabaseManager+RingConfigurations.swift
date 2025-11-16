//
//  DatabaseManager+RingConfigurations.swift
//  Jason
//
//  Created by Timothy Velberg on 06/11/2025.
//

import Foundation
import SQLite3
import AppKit

extension DatabaseManager {
    
    // MARK: - Ring Configurations CRUD
    
    /// Create a new ring configuration
    func createRingConfiguration(
        name: String,
        shortcut: String,              // DEPRECATED - kept for display
        ringRadius: CGFloat,
        centerHoleRadius: CGFloat,
        iconSize: CGFloat,
        triggerType: String = "keyboard",  // "keyboard" or "mouse"
        keyCode: UInt16? = nil,
        modifierFlags: UInt? = nil,
        buttonNumber: Int32? = nil,        // For mouse triggers (2, 3, 4, etc.)
        isHoldMode: Bool = false,          // true = hold to show, false = tap to toggle
        autoExecuteOnRelease: Bool = true, // true = auto-execute on release (only when isHoldMode = true)
        displayOrder: Int = 0
    ) -> Int? {
        guard let db = db else { return nil }
        
        var ringId: Int?
        
        queue.sync {
            // Validate trigger is not already in use
            if _isTriggerInUse(
                triggerType: triggerType,
                keyCode: keyCode,
                modifierFlags: modifierFlags ?? 0,
                buttonNumber: buttonNumber
            ) {
                let triggerDisplay: String
                if triggerType == "keyboard", let keyCode = keyCode {
                    triggerDisplay = formatShortcut(keyCode: keyCode, modifiers: modifierFlags ?? 0)
                } else if triggerType == "mouse", let buttonNumber = buttonNumber {
                    triggerDisplay = formatMouseButton(buttonNumber: buttonNumber, modifiers: modifierFlags ?? 0)
                } else {
                    triggerDisplay = "Unknown"
                }
                print("⚠️ [DatabaseManager] Trigger '\(triggerDisplay)' is already in use by an active ring")
                return
            }
            
            let now = Int(Date().timeIntervalSince1970)
            
            let sql = """
            INSERT INTO ring_configurations (name, shortcut, ring_radius, center_hole_radius, icon_size, trigger_type, key_code, modifier_flags, button_number, is_hold_mode, auto_execute_on_release, created_at, is_active, display_order)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?);
            """
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (name as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 2, (shortcut as NSString).utf8String, -1, nil)
                sqlite3_bind_double(statement, 3, Double(ringRadius))
                sqlite3_bind_double(statement, 4, Double(centerHoleRadius))
                sqlite3_bind_double(statement, 5, Double(iconSize))
                sqlite3_bind_text(statement, 6, (triggerType as NSString).utf8String, -1, nil)
                
                // Bind keyCode (NULL if not provided)
                if let keyCode = keyCode {
                    sqlite3_bind_int(statement, 7, Int32(keyCode))
                } else {
                    sqlite3_bind_null(statement, 7)
                }
                
                // Bind modifierFlags (NULL if not provided)
                if let modifierFlags = modifierFlags {
                    sqlite3_bind_int(statement, 8, Int32(modifierFlags))
                } else {
                    sqlite3_bind_null(statement, 8)
                }
                
                // Bind buttonNumber (NULL if not provided)
                if let buttonNumber = buttonNumber {
                    sqlite3_bind_int(statement, 9, buttonNumber)
                } else {
                    sqlite3_bind_null(statement, 9)
                }
                
                // Bind isHoldMode
                sqlite3_bind_int(statement, 10, isHoldMode ? 1 : 0)
                
                // Bind autoExecuteOnRelease
                sqlite3_bind_int(statement, 11, autoExecuteOnRelease ? 1 : 0)
                
                sqlite3_bind_int64(statement, 12, Int64(now))
                sqlite3_bind_int(statement, 13, Int32(displayOrder))
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    ringId = Int(sqlite3_last_insert_rowid(db))
                    
                    let triggerDisplay: String
                    if triggerType == "keyboard", let keyCode = keyCode {
                        triggerDisplay = formatShortcut(keyCode: keyCode, modifiers: modifierFlags ?? 0)
                    } else if triggerType == "mouse", let buttonNumber = buttonNumber {
                        triggerDisplay = formatMouseButton(buttonNumber: buttonNumber, modifiers: modifierFlags ?? 0)
                    } else {
                        triggerDisplay = "No trigger"
                    }
                    
                    let modeDisplay = isHoldMode ? "hold" : "tap"
                    print("🔵 [DatabaseManager] Created ring configuration: '\(name)' (id: \(ringId!), trigger: \(triggerDisplay), mode: \(modeDisplay))")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to insert ring configuration '\(name)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare INSERT for ring configuration '\(name)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return ringId
    }
    
    /// Get all ring configurations
    func getAllRingConfigurations() -> [RingConfigurationEntry] {
        guard let db = db else { return [] }
        
        var results: [RingConfigurationEntry] = []
        
        queue.sync {
            let sql = """
            SELECT id, name, shortcut, ring_radius, center_hole_radius, icon_size, created_at, is_active, display_order, trigger_type, key_code, modifier_flags, button_number, is_hold_mode, auto_execute_on_release
            FROM ring_configurations
            ORDER BY display_order, name;
            """
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(statement, 0))
                    let name = String(cString: sqlite3_column_text(statement, 1))
                    let shortcut = String(cString: sqlite3_column_text(statement, 2))
                    let ringRadius = CGFloat(sqlite3_column_double(statement, 3))
                    let centerHoleRadius = CGFloat(sqlite3_column_double(statement, 4))
                    let iconSize = CGFloat(sqlite3_column_double(statement, 5))
                    let createdAt = Int(sqlite3_column_int64(statement, 6))
                    let isActive = sqlite3_column_int(statement, 7) == 1
                    let displayOrder = Int(sqlite3_column_int(statement, 8))
                    
                    // Read triggerType (default to "keyboard" for legacy rows)
                    let triggerType: String = {
                        let colType = sqlite3_column_type(statement, 9)
                        if colType == SQLITE_NULL {
                            return "keyboard"
                        }
                        return String(cString: sqlite3_column_text(statement, 9))
                    }()
                    
                    // Read keyCode (handle NULL)
                    let keyCode: UInt16? = {
                        let colType = sqlite3_column_type(statement, 10)
                        if colType == SQLITE_NULL {
                            return nil
                        }
                        return UInt16(sqlite3_column_int(statement, 10))
                    }()
                    
                    // Read modifierFlags (handle NULL)
                    let modifierFlags: UInt? = {
                        let colType = sqlite3_column_type(statement, 11)
                        if colType == SQLITE_NULL {
                            return nil
                        }
                        return UInt(sqlite3_column_int(statement, 11))
                    }()
                    
                    // Read buttonNumber (handle NULL)
                    let buttonNumber: Int32? = {
                        let colType = sqlite3_column_type(statement, 12)
                        if colType == SQLITE_NULL {
                            return nil
                        }
                        return sqlite3_column_int(statement, 12)
                    }()
                    
                    // Read isHoldMode (default to false for legacy rows)
                    let isHoldMode: Bool = {
                        let colType = sqlite3_column_type(statement, 13)
                        if colType == SQLITE_NULL {
                            return false
                        }
                        return sqlite3_column_int(statement, 13) == 1
                    }()
                    
                    // Read autoExecuteOnRelease (default to true for legacy rows)
                    let autoExecuteOnRelease: Bool = {
                        let colType = sqlite3_column_type(statement, 14)
                        if colType == SQLITE_NULL {
                            return true
                        }
                        return sqlite3_column_int(statement, 14) == 1
                    }()
                    
                    results.append(RingConfigurationEntry(
                        id: id,
                        name: name,
                        shortcut: shortcut,
                        ringRadius: ringRadius,
                        centerHoleRadius: centerHoleRadius,
                        iconSize: iconSize,
                        createdAt: createdAt,
                        isActive: isActive,
                        displayOrder: displayOrder,
                        triggerType: triggerType,
                        keyCode: keyCode,
                        modifierFlags: modifierFlags,
                        buttonNumber: buttonNumber,
                        isHoldMode: isHoldMode,
                        autoExecuteOnRelease: autoExecuteOnRelease
                    ))
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare SELECT for ring configurations: \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return results
    }

    /// Get active ring configurations only
    func getActiveRingConfigurations() -> [RingConfigurationEntry] {
        guard let db = db else { return [] }
        
        var results: [RingConfigurationEntry] = []
        
        queue.sync {
            let sql = """
            SELECT id, name, shortcut, ring_radius, center_hole_radius, icon_size, created_at, is_active, display_order, trigger_type, key_code, modifier_flags, button_number, is_hold_mode, auto_execute_on_release
            FROM ring_configurations
            WHERE is_active = 1
            ORDER BY display_order, name;
            """
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(statement, 0))
                    let name = String(cString: sqlite3_column_text(statement, 1))
                    let shortcut = String(cString: sqlite3_column_text(statement, 2))
                    let ringRadius = CGFloat(sqlite3_column_double(statement, 3))
                    let centerHoleRadius = CGFloat(sqlite3_column_double(statement, 4))
                    let iconSize = CGFloat(sqlite3_column_double(statement, 5))
                    let createdAt = Int(sqlite3_column_int64(statement, 6))
                    let isActive = sqlite3_column_int(statement, 7) == 1
                    let displayOrder = Int(sqlite3_column_int(statement, 8))
                    
                    // Read triggerType (default to "keyboard" for legacy rows)
                    let triggerType: String = {
                        let colType = sqlite3_column_type(statement, 9)
                        if colType == SQLITE_NULL {
                            return "keyboard"
                        }
                        return String(cString: sqlite3_column_text(statement, 9))
                    }()
                    
                    // Read keyCode (handle NULL)
                    let keyCode: UInt16? = {
                        let colType = sqlite3_column_type(statement, 10)
                        if colType == SQLITE_NULL {
                            return nil
                        }
                        return UInt16(sqlite3_column_int(statement, 10))
                    }()
                    
                    // Read modifierFlags (handle NULL)
                    let modifierFlags: UInt? = {
                        let colType = sqlite3_column_type(statement, 11)
                        if colType == SQLITE_NULL {
                            return nil
                        }
                        return UInt(sqlite3_column_int(statement, 11))
                    }()
                    
                    // Read buttonNumber (handle NULL)
                    let buttonNumber: Int32? = {
                        let colType = sqlite3_column_type(statement, 12)
                        if colType == SQLITE_NULL {
                            return nil
                        }
                        return sqlite3_column_int(statement, 12)
                    }()
                    
                    // Read isHoldMode (default to false for legacy rows)
                    let isHoldMode: Bool = {
                        let colType = sqlite3_column_type(statement, 13)
                        if colType == SQLITE_NULL {
                            return false
                        }
                        return sqlite3_column_int(statement, 13) == 1
                    }()
                    
                    // Read autoExecuteOnRelease (default to true for legacy rows)
                    let autoExecuteOnRelease: Bool = {
                        let colType = sqlite3_column_type(statement, 14)
                        if colType == SQLITE_NULL {
                            return true
                        }
                        return sqlite3_column_int(statement, 14) == 1
                    }()
                    
                    results.append(RingConfigurationEntry(
                        id: id,
                        name: name,
                        shortcut: shortcut,
                        ringRadius: ringRadius,
                        centerHoleRadius: centerHoleRadius,
                        iconSize: iconSize,
                        createdAt: createdAt,
                        isActive: isActive,
                        displayOrder: displayOrder,
                        triggerType: triggerType,
                        keyCode: keyCode,
                        modifierFlags: modifierFlags,
                        buttonNumber: buttonNumber,
                        isHoldMode: isHoldMode,
                        autoExecuteOnRelease: autoExecuteOnRelease
                    ))
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare SELECT for active ring configurations: \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return results
    }

    /// Get a single ring configuration by ID
    func getRingConfiguration(id: Int) -> RingConfigurationEntry? {
        guard let db = db else { return nil }
        
        var result: RingConfigurationEntry?
        
        queue.sync {
            let sql = """
            SELECT id, name, shortcut, ring_radius, center_hole_radius, icon_size, created_at, is_active, display_order, trigger_type, key_code, modifier_flags, button_number, is_hold_mode, auto_execute_on_release
            FROM ring_configurations
            WHERE id = ?;
            """
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(id))
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(statement, 0))
                    let name = String(cString: sqlite3_column_text(statement, 1))
                    let shortcut = String(cString: sqlite3_column_text(statement, 2))
                    let ringRadius = CGFloat(sqlite3_column_double(statement, 3))
                    let centerHoleRadius = CGFloat(sqlite3_column_double(statement, 4))
                    let iconSize = CGFloat(sqlite3_column_double(statement, 5))
                    let createdAt = Int(sqlite3_column_int64(statement, 6))
                    let isActive = sqlite3_column_int(statement, 7) == 1
                    let displayOrder = Int(sqlite3_column_int(statement, 8))
                    
                    // Read triggerType (default to "keyboard" for legacy rows)
                    let triggerType: String = {
                        let colType = sqlite3_column_type(statement, 9)
                        if colType == SQLITE_NULL {
                            return "keyboard"
                        }
                        return String(cString: sqlite3_column_text(statement, 9))
                    }()
                    
                    // Read keyCode (handle NULL)
                    let keyCode: UInt16? = {
                        let colType = sqlite3_column_type(statement, 10)
                        if colType == SQLITE_NULL {
                            return nil
                        }
                        return UInt16(sqlite3_column_int(statement, 10))
                    }()
                    
                    // Read modifierFlags (handle NULL)
                    let modifierFlags: UInt? = {
                        let colType = sqlite3_column_type(statement, 11)
                        if colType == SQLITE_NULL {
                            return nil
                        }
                        return UInt(sqlite3_column_int(statement, 11))
                    }()
                    
                    // Read buttonNumber (handle NULL)
                    let buttonNumber: Int32? = {
                        let colType = sqlite3_column_type(statement, 12)
                        if colType == SQLITE_NULL {
                            return nil
                        }
                        return sqlite3_column_int(statement, 12)
                    }()
                    
                    // Read isHoldMode (default to false for legacy rows)
                    let isHoldMode: Bool = {
                        let colType = sqlite3_column_type(statement, 13)
                        if colType == SQLITE_NULL {
                            return false
                        }
                        return sqlite3_column_int(statement, 13) == 1
                    }()
                    
                    // Read autoExecuteOnRelease (default to true for legacy rows)
                    let autoExecuteOnRelease: Bool = {
                        let colType = sqlite3_column_type(statement, 14)
                        if colType == SQLITE_NULL {
                            return true
                        }
                        return sqlite3_column_int(statement, 14) == 1
                    }()
                    
                    result = RingConfigurationEntry(
                        id: id,
                        name: name,
                        shortcut: shortcut,
                        ringRadius: ringRadius,
                        centerHoleRadius: centerHoleRadius,
                        iconSize: iconSize,
                        createdAt: createdAt,
                        isActive: isActive,
                        displayOrder: displayOrder,
                        triggerType: triggerType,
                        keyCode: keyCode,
                        modifierFlags: modifierFlags,
                        buttonNumber: buttonNumber,
                        isHoldMode: isHoldMode,
                        autoExecuteOnRelease: autoExecuteOnRelease
                    )
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare SELECT for ring configuration id \(id): \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return result
    }
    
    /// Update a ring configuration
    func updateRingConfiguration(
        id: Int,
        name: String? = nil,
        shortcut: String? = nil,       // DEPRECATED
        ringRadius: CGFloat? = nil,
        centerHoleRadius: CGFloat? = nil,
        iconSize: CGFloat? = nil,
        keyCode: UInt16? = nil,        // NEW
        modifierFlags: UInt? = nil,    // NEW
        displayOrder: Int? = nil
    ) {
        guard let db = db else { return }
        
        queue.async {
            // If updating keyCode/modifierFlags, validate uniqueness
            if let keyCode = keyCode, let modifierFlags = modifierFlags {
                let checkSQL = """
                SELECT id FROM ring_configurations 
                WHERE key_code = ? AND modifier_flags = ? AND is_active = 1 AND id != ?;
                """
                var checkStatement: OpaquePointer?
                
                if sqlite3_prepare_v2(db, checkSQL, -1, &checkStatement, nil) == SQLITE_OK {
                    sqlite3_bind_int(checkStatement, 1, Int32(keyCode))
                    sqlite3_bind_int(checkStatement, 2, Int32(modifierFlags))
                    sqlite3_bind_int(checkStatement, 3, Int32(id))
                    
                    if sqlite3_step(checkStatement) == SQLITE_ROW {
                        let shortcutDisplay = self.formatShortcut(keyCode: keyCode, modifiers: modifierFlags)
                        print("⚠️ [DatabaseManager] Cannot update: shortcut '\(shortcutDisplay)' is already in use by another active ring")
                        sqlite3_finalize(checkStatement)
                        return
                    }
                }
                sqlite3_finalize(checkStatement)
            }
            
            // Build dynamic UPDATE query
            var updates: [String] = []
            if name != nil { updates.append("name = ?") }
            if shortcut != nil { updates.append("shortcut = ?") }
            if ringRadius != nil { updates.append("ring_radius = ?") }
            if centerHoleRadius != nil { updates.append("center_hole_radius = ?") }
            if iconSize != nil { updates.append("icon_size = ?") }
            if keyCode != nil { updates.append("key_code = ?") }
            if modifierFlags != nil { updates.append("modifier_flags = ?") }
            if displayOrder != nil { updates.append("display_order = ?") }
            
            guard !updates.isEmpty else {
                print("⚠️ [DatabaseManager] No fields to update for ring configuration id \(id)")
                return
            }
            
            let sql = "UPDATE ring_configurations SET \(updates.joined(separator: ", ")) WHERE id = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                var paramIndex: Int32 = 1
                
                if let name = name {
                    sqlite3_bind_text(statement, paramIndex, (name as NSString).utf8String, -1, nil)
                    paramIndex += 1
                }
                if let shortcut = shortcut {
                    sqlite3_bind_text(statement, paramIndex, (shortcut as NSString).utf8String, -1, nil)
                    paramIndex += 1
                }
                if let ringRadius = ringRadius {
                    sqlite3_bind_double(statement, paramIndex, Double(ringRadius))
                    paramIndex += 1
                }
                if let centerHoleRadius = centerHoleRadius {
                    sqlite3_bind_double(statement, paramIndex, Double(centerHoleRadius))
                    paramIndex += 1
                }
                if let iconSize = iconSize {
                    sqlite3_bind_double(statement, paramIndex, Double(iconSize))
                    paramIndex += 1
                }
                if let keyCode = keyCode {
                    sqlite3_bind_int(statement, paramIndex, Int32(keyCode))
                    paramIndex += 1
                }
                if let modifierFlags = modifierFlags {
                    sqlite3_bind_int(statement, paramIndex, Int32(modifierFlags))
                    paramIndex += 1
                }
                if let displayOrder = displayOrder {
                    sqlite3_bind_int(statement, paramIndex, Int32(displayOrder))
                    paramIndex += 1
                }
                
                // Bind the WHERE id parameter
                sqlite3_bind_int(statement, paramIndex, Int32(id))
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("📊 [DatabaseManager] Updated ring configuration id \(id)")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to update ring configuration id \(id): \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare UPDATE for ring configuration id \(id): \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
    }
    
    /// Set a ring configuration's active status
    func setRingConfigurationActiveStatus(id: Int, isActive: Bool) {
        guard let db = db else { return }
        
        queue.async {
            let sql = "UPDATE ring_configurations SET is_active = ? WHERE id = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, isActive ? 1 : 0)
                sqlite3_bind_int(statement, 2, Int32(id))
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("📊 [DatabaseManager] Set ring configuration id \(id) active status to \(isActive)")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to update active status for ring configuration id \(id): \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare UPDATE for active status (id \(id)): \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
    }
    
    /// Get count of active ring configurations
    func getActiveRingCount() -> Int {
        guard let db = db else { return 0 }
        
        var count = 0
        
        queue.sync {
            let sql = "SELECT COUNT(*) FROM ring_configurations WHERE is_active = 1;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) == SQLITE_ROW {
                    count = Int(sqlite3_column_int(statement, 0))
                }
            }
            sqlite3_finalize(statement)
        }
        
        return count
    }
    
    /// Delete a ring configuration (also deletes associated providers via CASCADE)
    func deleteRingConfiguration(id: Int) {
        guard let db = db else { return }
        
        queue.async {
            let sql = "DELETE FROM ring_configurations WHERE id = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(id))
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    let changes = sqlite3_changes(db)
                    if changes > 0 {
                        print("🗑️ [DatabaseManager] Deleted ring configuration id \(id) (and associated providers)")
                    } else {
                        print("⚠️ [DatabaseManager] Ring configuration id \(id) not found")
                    }
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to delete ring configuration id \(id): \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare DELETE for ring configuration id \(id): \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
    }
    
    // MARK: - Ring Providers CRUD
    
    /// Create a provider for a ring configuration
    func createProvider(
        ringId: Int,
        providerType: String,
        providerOrder: Int,
        parentItemAngle: CGFloat? = nil,
        providerConfig: String? = nil
    ) -> Int? {
        guard let db = db else { return nil }
        
        var providerId: Int?
        
        queue.sync {
            // Validate provider order is unique within the ring
            if _isProviderOrderInUse(ringId: ringId, providerOrder: providerOrder) {
                print("⚠️ [DatabaseManager] Provider order \(providerOrder) is already in use in ring id \(ringId)")
                return
            }
            
            let sql = """
            INSERT INTO ring_providers (ring_id, provider_type, provider_order, parent_item_angle, provider_config)
            VALUES (?, ?, ?, ?, ?);
            """
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(ringId))
                sqlite3_bind_text(statement, 2, (providerType as NSString).utf8String, -1, nil)
                sqlite3_bind_int(statement, 3, Int32(providerOrder))
                
                if let parentItemAngle = parentItemAngle {
                    sqlite3_bind_double(statement, 4, Double(parentItemAngle))
                } else {
                    sqlite3_bind_null(statement, 4)
                }
                
                if let providerConfig = providerConfig {
                    sqlite3_bind_text(statement, 5, (providerConfig as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statement, 5)
                }
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    providerId = Int(sqlite3_last_insert_rowid(db))
                    print("🔵 [DatabaseManager] Created provider '\(providerType)' for ring id \(ringId) (provider id: \(providerId!))")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to insert provider '\(providerType)': \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare INSERT for provider '\(providerType)': \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return providerId
    }
    
    /// Get all providers for a ring configuration
    func getProviders(ringId: Int) -> [RingProviderEntry] {
        guard let db = db else { return [] }
        
        var results: [RingProviderEntry] = []
        
        queue.sync {
            let sql = """
            SELECT id, ring_id, provider_type, provider_order, parent_item_angle, provider_config
            FROM ring_providers
            WHERE ring_id = ?
            ORDER BY provider_order;
            """
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(ringId))
                
                while sqlite3_step(statement) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(statement, 0))
                    let ringId = Int(sqlite3_column_int(statement, 1))
                    let providerType = String(cString: sqlite3_column_text(statement, 2))
                    let providerOrder = Int(sqlite3_column_int(statement, 3))
                    
                    let parentItemAngle: CGFloat? = {
                        if sqlite3_column_type(statement, 4) == SQLITE_NULL {
                            return nil
                        }
                        return CGFloat(sqlite3_column_double(statement, 4))
                    }()
                    
                    let providerConfig: String? = {
                        if sqlite3_column_type(statement, 5) == SQLITE_NULL {
                            return nil
                        }
                        return String(cString: sqlite3_column_text(statement, 5))
                    }()
                    
                    results.append(RingProviderEntry(
                        id: id,
                        ringId: ringId,
                        providerType: providerType,
                        providerOrder: providerOrder,
                        parentItemAngle: parentItemAngle,
                        providerConfig: providerConfig
                    ))
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare SELECT for ring providers (ring id \(ringId)): \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
        
        return results
    }
    
    /// Update a provider's settings
    func updateProvider(
        id: Int,
        providerOrder: Int? = nil,
        parentItemAngle: CGFloat? = nil,
        providerConfig: String? = nil,
        clearAngle: Bool = false,
        clearConfig: Bool = false
    ) {
        guard let db = db else { return }
        
        queue.async {
            // If updating provider order, validate it's not in use by another provider in the same ring
            if let newOrder = providerOrder {
                // Get the ring_id for this provider
                let getRingSQL = "SELECT ring_id FROM ring_providers WHERE id = ?;"
                var getRingStatement: OpaquePointer?
                var currentRingId: Int?
                
                if sqlite3_prepare_v2(db, getRingSQL, -1, &getRingStatement, nil) == SQLITE_OK {
                    sqlite3_bind_int(getRingStatement, 1, Int32(id))
                    if sqlite3_step(getRingStatement) == SQLITE_ROW {
                        currentRingId = Int(sqlite3_column_int(getRingStatement, 0))
                    }
                }
                sqlite3_finalize(getRingStatement)
                
                if let ringId = currentRingId {
                    let checkSQL = """
                    SELECT id FROM ring_providers 
                    WHERE ring_id = ? AND provider_order = ? AND id != ?;
                    """
                    var checkStatement: OpaquePointer?
                    
                    if sqlite3_prepare_v2(db, checkSQL, -1, &checkStatement, nil) == SQLITE_OK {
                        sqlite3_bind_int(checkStatement, 1, Int32(ringId))
                        sqlite3_bind_int(checkStatement, 2, Int32(newOrder))
                        sqlite3_bind_int(checkStatement, 3, Int32(id))
                        
                        if sqlite3_step(checkStatement) == SQLITE_ROW {
                            print("⚠️ [DatabaseManager] Cannot update: provider order \(newOrder) is already in use in ring id \(ringId)")
                            sqlite3_finalize(checkStatement)
                            return
                        }
                    }
                    sqlite3_finalize(checkStatement)
                }
            }
            
            // Build dynamic UPDATE query
            var updates: [String] = []
            if providerOrder != nil { updates.append("provider_order = ?") }
            if clearAngle { updates.append("parent_item_angle = NULL") }
            else if parentItemAngle != nil { updates.append("parent_item_angle = ?") }
            if clearConfig { updates.append("provider_config = NULL") }
            else if providerConfig != nil { updates.append("provider_config = ?") }
            
            guard !updates.isEmpty else {
                print("⚠️ [DatabaseManager] No fields to update for provider id \(id)")
                return
            }
            
            let sql = "UPDATE ring_providers SET \(updates.joined(separator: ", ")) WHERE id = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                var paramIndex: Int32 = 1
                
                if let providerOrder = providerOrder {
                    sqlite3_bind_int(statement, paramIndex, Int32(providerOrder))
                    paramIndex += 1
                }
                if !clearAngle, let parentItemAngle = parentItemAngle {
                    sqlite3_bind_double(statement, paramIndex, Double(parentItemAngle))
                    paramIndex += 1
                }
                if !clearConfig, let providerConfig = providerConfig {
                    sqlite3_bind_text(statement, paramIndex, (providerConfig as NSString).utf8String, -1, nil)
                    paramIndex += 1
                }
                
                // Bind the WHERE id parameter
                sqlite3_bind_int(statement, paramIndex, Int32(id))
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("📊 [DatabaseManager] Updated provider id \(id)")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to update provider id \(id): \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare UPDATE for provider id \(id): \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
    }
    
    /// Remove a provider from a ring
    func removeProvider(id: Int) {
        guard let db = db else { return }
        
        queue.async {
            let sql = "DELETE FROM ring_providers WHERE id = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(id))
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("🗑️ [DatabaseManager] Removed provider id \(id)")
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to remove provider id \(id): \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare DELETE for provider id \(id): \(String(cString: error))")
                }
            }
            sqlite3_finalize(statement)
        }
    }
    
    // MARK: - Provider Configuration Helpers
    
    /// Update display mode for a specific provider in a ring configuration
    /// - Parameters:
    ///   - ringId: The ring configuration ID
    ///   - providerType: The provider type to update
    ///   - displayMode: The display mode ("parent" or "direct")
    /// - Returns: true if update succeeded, false otherwise
    func updateProviderDisplayMode(
        ringId: Int,
        providerType: String,
        displayMode: String
    ) -> Bool {
        guard let db = db else { return false }
        
        var success = false
        
        queue.sync {
            // Step 1: Get current provider_config JSON
            let selectSQL = "SELECT provider_config FROM ring_providers WHERE ring_id = ? AND provider_type = ?;"
            var selectStatement: OpaquePointer?
            var currentConfig: [String: Any] = [:]
            
            if sqlite3_prepare_v2(db, selectSQL, -1, &selectStatement, nil) == SQLITE_OK {
                sqlite3_bind_int(selectStatement, 1, Int32(ringId))
                sqlite3_bind_text(selectStatement, 2, (providerType as NSString).utf8String, -1, nil)
                
                if sqlite3_step(selectStatement) == SQLITE_ROW {
                    // Check if provider_config is NULL
                    if sqlite3_column_type(selectStatement, 0) != SQLITE_NULL {
                        if let configText = sqlite3_column_text(selectStatement, 0) {
                            let configString = String(cString: configText)
                            if let configData = configString.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: configData) as? [String: Any] {
                                currentConfig = json
                            }
                        }
                    }
                } else {
                    print("⚠️ [DatabaseManager] Provider '\(providerType)' not found in ring \(ringId)")
                    sqlite3_finalize(selectStatement)
                    return
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare SELECT for provider config: \(String(cString: error))")
                }
                sqlite3_finalize(selectStatement)
                return
            }
            sqlite3_finalize(selectStatement)
            
            // Step 2: Update displayMode in the JSON
            currentConfig["displayMode"] = displayMode
            
            // Step 3: Serialize back to JSON string
            guard let jsonData = try? JSONSerialization.data(withJSONObject: currentConfig),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                print("❌ [DatabaseManager] Failed to serialize provider config JSON")
                return
            }
            
            // Step 4: Update database
            let updateSQL = "UPDATE ring_providers SET provider_config = ? WHERE ring_id = ? AND provider_type = ?;"
            var updateStatement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, updateSQL, -1, &updateStatement, nil) == SQLITE_OK {
                sqlite3_bind_text(updateStatement, 1, (jsonString as NSString).utf8String, -1, nil)
                sqlite3_bind_int(updateStatement, 2, Int32(ringId))
                sqlite3_bind_text(updateStatement, 3, (providerType as NSString).utf8String, -1, nil)
                
                if sqlite3_step(updateStatement) == SQLITE_DONE {
                    print("✅ [DatabaseManager] Updated display mode for provider '\(providerType)' in ring \(ringId) to '\(displayMode)'")
                    success = true
                } else {
                    if let error = sqlite3_errmsg(db) {
                        print("❌ [DatabaseManager] Failed to update provider display mode: \(String(cString: error))")
                    }
                }
            } else {
                if let error = sqlite3_errmsg(db) {
                    print("❌ [DatabaseManager] Failed to prepare UPDATE for provider display mode: \(String(cString: error))")
                }
            }
            sqlite3_finalize(updateStatement)
        }
        
        return success
    }
    
    // MARK: - Validation Helpers
    
    /// Check if a trigger (keyboard or mouse) is already in use by an active ring (UNSAFE - must be called within queue.sync)
    private func _isTriggerInUse(
        triggerType: String,
        keyCode: UInt16?,
        modifierFlags: UInt,
        buttonNumber: Int32?
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
        }
        
        return false
    }
    
    /// Check if a provider order is already in use for a ring (UNSAFE - must be called within queue.sync)
    private func _isProviderOrderInUse(ringId: Int, providerOrder: Int) -> Bool {
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
    
    // MARK: - Helper Methods
    
    /// Format a keyboard shortcut for display (helper for logging)
    private func formatShortcut(keyCode: UInt16, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        parts.append(keyCodeToString(keyCode))
        
        return parts.joined()
    }
    
    /// Format a mouse button for display (helper for logging)
    private func formatMouseButton(buttonNumber: Int32, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        // Convert button number to readable name
        let buttonName: String
        switch buttonNumber {
        case 2:
            buttonName = "Button 3 (Middle)"
        case 3:
            buttonName = "Button 4 (Back)"
        case 4:
            buttonName = "Button 5 (Forward)"
        default:
            buttonName = "Button \(buttonNumber + 1)"
        }
        
        parts.append(buttonName)
        
        return parts.joined()
    }
    
    /// Convert key code to string (helper for display)
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
        case 49: return "Space"
        case 50: return "`"
        case 53: return "Esc"
        default: return "[\(keyCode)]"
        }
    }
}
