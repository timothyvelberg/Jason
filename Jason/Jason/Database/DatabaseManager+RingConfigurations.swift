//
//  DatabaseManager+RingConfigurations.swift
//  Jason
//
//  Created by Timothy Velberg on 06/11/2025.
//w

import Foundation
import SQLite3
import AppKit

extension DatabaseManager {
    
    // MARK: - Ring Configurations CRUD
    
    /// Create a new ring configuration
    func createRingConfiguration(
        name: String,
        shortcut: String,
        ringRadius: CGFloat,
        centerHoleRadius: CGFloat,  // NEW PARAMETER
        iconSize: CGFloat,
        displayOrder: Int = 0
    ) -> Int? {
        guard let db = db else { return nil }
        
        var ringId: Int?
        
        queue.sync {
            // Validate shortcut is unique among active rings
            if _isShortcutInUse(shortcut: shortcut) {
                print("⚠️ [DatabaseManager] Shortcut '\(shortcut)' is already in use by an active ring")
                return
            }
            
            let now = Int(Date().timeIntervalSince1970)
            
            let sql = """
            INSERT INTO ring_configurations (name, shortcut, ring_radius, center_hole_radius, icon_size, created_at, is_active, display_order)
            VALUES (?, ?, ?, ?, ?, ?, 1, ?);
            """
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (name as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 2, (shortcut as NSString).utf8String, -1, nil)
                sqlite3_bind_double(statement, 3, Double(ringRadius))
                sqlite3_bind_double(statement, 4, Double(centerHoleRadius))  // NEW
                sqlite3_bind_double(statement, 5, Double(iconSize))
                sqlite3_bind_int64(statement, 6, Int64(now))
                sqlite3_bind_int(statement, 7, Int32(displayOrder))
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    ringId = Int(sqlite3_last_insert_rowid(db))
                    print("🔵 [DatabaseManager] Created ring configuration: '\(name)' (id: \(ringId!))")
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
            SELECT id, name, shortcut, ring_radius, center_hole_radius, icon_size, created_at, is_active, display_order
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
                    let centerHoleRadius = CGFloat(sqlite3_column_double(statement, 4))  // NEW
                    let iconSize = CGFloat(sqlite3_column_double(statement, 5))
                    let createdAt = Int(sqlite3_column_int64(statement, 6))
                    let isActive = sqlite3_column_int(statement, 7) == 1
                    let displayOrder = Int(sqlite3_column_int(statement, 8))
                    
                    results.append(RingConfigurationEntry(
                        id: id,
                        name: name,
                        shortcut: shortcut,
                        ringRadius: ringRadius,
                        centerHoleRadius: centerHoleRadius,  // NEW
                        iconSize: iconSize,
                        createdAt: createdAt,
                        isActive: isActive,
                        displayOrder: displayOrder
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
            SELECT id, name, shortcut, ring_radius, center_hole_radius, icon_size, created_at, is_active, display_order
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
                    let centerHoleRadius = CGFloat(sqlite3_column_double(statement, 4))  // NEW
                    let iconSize = CGFloat(sqlite3_column_double(statement, 5))
                    let createdAt = Int(sqlite3_column_int64(statement, 6))
                    let isActive = sqlite3_column_int(statement, 7) == 1
                    let displayOrder = Int(sqlite3_column_int(statement, 8))
                    
                    results.append(RingConfigurationEntry(
                        id: id,
                        name: name,
                        shortcut: shortcut,
                        ringRadius: ringRadius,
                        centerHoleRadius: centerHoleRadius,  // NEW
                        iconSize: iconSize,
                        createdAt: createdAt,
                        isActive: isActive,
                        displayOrder: displayOrder
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
            SELECT id, name, shortcut, ring_radius, center_hole_radius, icon_size, created_at, is_active, display_order
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
                    let centerHoleRadius = CGFloat(sqlite3_column_double(statement, 4))  // NEW
                    let iconSize = CGFloat(sqlite3_column_double(statement, 5))
                    let createdAt = Int(sqlite3_column_int64(statement, 6))
                    let isActive = sqlite3_column_int(statement, 7) == 1
                    let displayOrder = Int(sqlite3_column_int(statement, 8))
                    
                    result = RingConfigurationEntry(
                        id: id,
                        name: name,
                        shortcut: shortcut,
                        ringRadius: ringRadius,
                        centerHoleRadius: centerHoleRadius,  // NEW
                        iconSize: iconSize,
                        createdAt: createdAt,
                        isActive: isActive,
                        displayOrder: displayOrder
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
        shortcut: String? = nil,
        ringRadius: CGFloat? = nil,
        centerHoleRadius: CGFloat? = nil,  // NEW PARAMETER
        iconSize: CGFloat? = nil,
        isActive: Bool? = nil,
        displayOrder: Int? = nil
    ) {
        guard let db = db else { return }
        
        queue.async {
            // If updating shortcut, validate it's not in use by another active ring
            if let newShortcut = shortcut {
                let checkSQL = """
                SELECT id FROM ring_configurations 
                WHERE shortcut = ? AND is_active = 1 AND id != ?;
                """
                var checkStatement: OpaquePointer?
                
                if sqlite3_prepare_v2(db, checkSQL, -1, &checkStatement, nil) == SQLITE_OK {
                    sqlite3_bind_text(checkStatement, 1, (newShortcut as NSString).utf8String, -1, nil)
                    sqlite3_bind_int(checkStatement, 2, Int32(id))
                    
                    if sqlite3_step(checkStatement) == SQLITE_ROW {
                        print("⚠️ [DatabaseManager] Cannot update: shortcut '\(newShortcut)' is already in use by another active ring")
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
            if centerHoleRadius != nil { updates.append("center_hole_radius = ?") }  // NEW
            if iconSize != nil { updates.append("icon_size = ?") }
            if isActive != nil { updates.append("is_active = ?") }
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
                if let centerHoleRadius = centerHoleRadius {  // NEW
                    sqlite3_bind_double(statement, paramIndex, Double(centerHoleRadius))
                    paramIndex += 1
                }
                if let iconSize = iconSize {
                    sqlite3_bind_double(statement, paramIndex, Double(iconSize))
                    paramIndex += 1
                }
                if let isActive = isActive {
                    sqlite3_bind_int(statement, paramIndex, isActive ? 1 : 0)
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
    
    /// Delete a ring configuration (cascade deletes providers)
    func deleteRingConfiguration(id: Int) {
        guard let db = db else { return }
        
        queue.async {
            let sql = "DELETE FROM ring_configurations WHERE id = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(id))
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    print("🗑️ [DatabaseManager] Deleted ring configuration id \(id)")
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
    
    /// Add a provider to a ring
    func addProviderToRing(
        ringId: Int,
        providerType: String,
        providerOrder: Int,
        parentItemAngle: CGFloat? = nil,
        providerConfig: String? = nil
    ) -> Int? {
        guard let db = db else { return nil }
        
        var providerId: Int?
        
        queue.sync {
            // Validate provider order is not already in use for this ring
            if _isProviderOrderInUse(ringId: ringId, providerOrder: providerOrder) {
                print("⚠️ [DatabaseManager] Provider order \(providerOrder) is already in use for ring id \(ringId)")
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
                    print("➕ [DatabaseManager] Added provider '\(providerType)' to ring id \(ringId) (provider id: \(providerId!))")
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
    
    /// Get all providers for a ring
    func getProvidersForRing(ringId: Int) -> [RingProviderEntry] {
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
                        } else {
                            return CGFloat(sqlite3_column_double(statement, 4))
                        }
                    }()
                    
                    let providerConfig: String? = {
                        if sqlite3_column_type(statement, 5) == SQLITE_NULL {
                            return nil
                        } else {
                            return String(cString: sqlite3_column_text(statement, 5))
                        }
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
    
    // MARK: - Validation Helpers
    
    /// Check if a shortcut is already in use by an active ring (UNSAFE - must be called within queue.sync)
    private func _isShortcutInUse(shortcut: String) -> Bool {
        guard let db = db else { return false }
        
        let sql = "SELECT id FROM ring_configurations WHERE shortcut = ? AND is_active = 1;"
        var statement: OpaquePointer?
        var inUse = false
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (shortcut as NSString).utf8String, -1, nil)
            if sqlite3_step(statement) == SQLITE_ROW {
                inUse = true
            }
        }
        sqlite3_finalize(statement)
        
        return inUse
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
}
