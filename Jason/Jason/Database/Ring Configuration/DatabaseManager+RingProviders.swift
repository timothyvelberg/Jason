//
//  DatabaseManager+RingProviders.swift
//  Jason
//
//  Created by Timothy Velberg on 22/11/2025.
//

import Foundation
import SQLite3
import AppKit

extension DatabaseManager {
    
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
    
    /// Reorder all providers in a ring based on array position
    /// - Parameters:
    ///   - ringId: The ring configuration ID
    ///   - providerIds: Array of provider IDs in desired order (index 0 = order 0, etc.)
    /// - Returns: true if reorder succeeded, false otherwise
    func reorderProviders(ringId: Int, providerIds: [Int]) -> Bool {
        guard let db = db else { return false }
        
        var success = false
        
        queue.sync {
            // Begin transaction - all or nothing
            if sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil) != SQLITE_OK {
                print("❌ [DatabaseManager] Failed to begin transaction for reorder")
                return
            }
            
            // Step 1: Set all to temporary negative values to avoid unique constraint
            for (index, providerId) in providerIds.enumerated() {
                let tempOrder = -(index + 1)  // -1, -2, -3, etc.
                let sql = "UPDATE ring_providers SET provider_order = ? WHERE id = ? AND ring_id = ?;"
                var statement: OpaquePointer?
                
                if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                    sqlite3_bind_int(statement, 1, Int32(tempOrder))
                    sqlite3_bind_int(statement, 2, Int32(providerId))
                    sqlite3_bind_int(statement, 3, Int32(ringId))
                    
                    if sqlite3_step(statement) != SQLITE_DONE {
                        if let error = sqlite3_errmsg(db) {
                            print("❌ [DatabaseManager] Failed to set temp order for provider \(providerId): \(String(cString: error))")
                        }
                        sqlite3_finalize(statement)
                        sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                        return
                    }
                }
                sqlite3_finalize(statement)
            }
            
            // Step 2: Set final positive values
            for (index, providerId) in providerIds.enumerated() {
                let sql = "UPDATE ring_providers SET provider_order = ? WHERE id = ? AND ring_id = ?;"
                var statement: OpaquePointer?
                
                if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                    sqlite3_bind_int(statement, 1, Int32(index))
                    sqlite3_bind_int(statement, 2, Int32(providerId))
                    sqlite3_bind_int(statement, 3, Int32(ringId))
                    
                    if sqlite3_step(statement) != SQLITE_DONE {
                        if let error = sqlite3_errmsg(db) {
                            print("❌ [DatabaseManager] Failed to set final order for provider \(providerId): \(String(cString: error))")
                        }
                        sqlite3_finalize(statement)
                        sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                        return
                    }
                }
                sqlite3_finalize(statement)
            }
            
            // Commit transaction
            if sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK {
                print("✅ [DatabaseManager] Reordered \(providerIds.count) providers in ring \(ringId)")
                success = true
            } else {
                print("❌ [DatabaseManager] Failed to commit reorder transaction")
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            }
        }
        
        return success
    }
    
}
