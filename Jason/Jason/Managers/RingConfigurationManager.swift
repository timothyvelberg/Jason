//
//  RingConfigurationManager.swift
//  Jason
//
//  Orchestration layer that loads ring configurations from the database,
//  maintains them in memory, and provides them to CircularUIManager instances.
//

import Foundation
import SwiftUI

@MainActor
class RingConfigurationManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = RingConfigurationManager()
    
    // MARK: - Published State
    
    /// All loaded ring configurations
    @Published private(set) var configurations: [StoredRingConfiguration] = []
    
    // MARK: - Dependencies
    
    private let databaseManager: DatabaseManager
    
    // MARK: - Initialization
    
    private init() {
        self.databaseManager = DatabaseManager.shared
        print("🎛️ [RingConfigManager] Initialized")
    }
    
    // MARK: - Loading Methods
    
    /// Load all ring configurations from the database
    /// Updates the in-memory cache with all configurations
    func loadConfigurations() {
        print("📥 [RingConfigManager] Loading all configurations from database...")
        
        let dbConfigs = databaseManager.getAllRingConfigurations()
        
        // Transform database entries to domain models
        var domainConfigs: [StoredRingConfiguration] = []
        
        for dbConfig in dbConfigs {
            if let domainConfig = transformToDomain(dbConfig) {
                domainConfigs.append(domainConfig)
            }
        }
        
        configurations = domainConfigs
        print("✅ [RingConfigManager] Loaded \(configurations.count) configuration(s)")
        
        // Log summary
        for config in configurations {
            let status = config.isActive ? "🟢 ACTIVE" : "⚫️ inactive"
            print("   \(status) - \(config.name) (\(config.shortcut)) - \(config.providers.count) provider(s)")
        }
    }
    
    /// Load only active ring configurations from the database
    /// Updates the in-memory cache with active configurations only
    func loadActiveConfigurations() {
        print("📥 [RingConfigManager] Loading active configurations from database...")
        
        let dbConfigs = databaseManager.getAllRingConfigurations()
        
        // Filter for active and transform
        var domainConfigs: [StoredRingConfiguration] = []
        
        for dbConfig in dbConfigs where dbConfig.isActive {
            if let domainConfig = transformToDomain(dbConfig) {
                domainConfigs.append(domainConfig)
            }
        }
        
        configurations = domainConfigs
        print("✅ [RingConfigManager] Loaded \(configurations.count) active configuration(s)")
        
        // Log summary
        for config in configurations {
            print("   🟢 \(config.name) (\(config.shortcut)) - \(config.providers.count) provider(s)")
        }
    }
    
    // MARK: - Query Methods
    
    /// Get all configurations (from in-memory cache)
    func getAllConfigurations() -> [StoredRingConfiguration] {
        return configurations
    }
    
    /// Get configuration by ID
    func getConfiguration(id: Int) -> StoredRingConfiguration? {
        return configurations.first { $0.id == id }
    }
    
    /// Get all active configurations
    func getActiveConfigurations() -> [StoredRingConfiguration] {
        return configurations.filter { $0.isActive }
    }
    
    /// Get configuration by shortcut
    /// - Parameter shortcut: The keyboard shortcut to search for (e.g., "Cmd+Shift+A")
    /// - Returns: The configuration if found, nil otherwise
    func getConfiguration(forShortcut shortcut: String) -> StoredRingConfiguration? {
        return configurations.first { $0.shortcut == shortcut }
    }
    
    // MARK: - Modification Methods
    
    /// Create a new ring configuration
    /// - Parameters:
    ///   - name: Display name for the ring
    ///   - shortcut: Keyboard shortcut (e.g., "Cmd+Shift+A")
    ///   - ringRadius: Radius (thickness) of the ring band in points
    ///   - centerHoleRadius: Radius of the center hole in points
    ///   - iconSize: Size of icons in the ring
    ///   - providers: Array of provider specifications (type, order, angle)
    /// - Returns: The newly created configuration
    /// - Throws: StoredRingConfigurationError if validation fails or database error occurs
    func createConfiguration(
        name: String,
        shortcut: String,
        ringRadius: Double,
        centerHoleRadius: Double = 56.0,
        iconSize: Double,
        providers: [(type: String, order: Int, angle: Double?)] = []
    ) throws -> StoredRingConfiguration {
        print("➕ [RingConfigManager] Creating configuration '\(name)' with shortcut '\(shortcut)'")
        
        // Validate inputs
        try validateConfigurationInputs(
            name: name,
            shortcut: shortcut,
            ringRadius: ringRadius,
            centerHoleRadius: centerHoleRadius,
            iconSize: iconSize
        )
        
        // Validate shortcut uniqueness (for active rings)
        guard validateShortcut(shortcut, excludingRing: nil) else {
            throw StoredRingConfigurationError.duplicateShortcut(shortcut)
        }
        
        // Create in database
        guard let ringId = databaseManager.createRingConfiguration(
            name: name,
            shortcut: shortcut,
            ringRadius: CGFloat(ringRadius),
            centerHoleRadius: CGFloat(centerHoleRadius),
            iconSize: CGFloat(iconSize)
        ) else {
            throw StoredRingConfigurationError.databaseError("Failed to create ring configuration")
        }
        
        print("   ✅ Created ring configuration with ID: \(ringId)")
        
        // Add providers if specified
        var providerConfigs: [ProviderConfiguration] = []
        for (index, provider) in providers.enumerated() {
            do {
                guard let providerId = databaseManager.addProviderToRing(
                    ringId: ringId,
                    providerType: provider.type,
                    providerOrder: provider.order,
                    parentItemAngle: provider.angle.map { CGFloat($0) }
                ) else {
                    print("   ⚠️ Failed to add provider '\(provider.type)': database returned nil")
                    continue
                }
                
                providerConfigs.append(ProviderConfiguration(
                    id: providerId,
                    providerType: provider.type,
                    order: provider.order,
                    parentItemAngle: provider.angle,
                    config: nil
                ))
                
                print("   ✅ Added provider \(index + 1)/\(providers.count): \(provider.type)")
            }
        }
        
        // Create domain model
        let newConfig = StoredRingConfiguration(
            id: ringId,
            name: name,
            shortcut: shortcut,
            ringRadius: ringRadius,
            centerHoleRadius: centerHoleRadius,
            iconSize: iconSize,
            isActive: true,
            providers: providerConfigs
        )
        
        // Update in-memory cache
        configurations.append(newConfig)
        
        print("✅ [RingConfigManager] Created configuration successfully")
        print("   Total configurations now: \(configurations.count)")
        
        return newConfig
    }
    
    /// Update an existing ring configuration
    /// - Parameters:
    ///   - id: ID of the configuration to update
    ///   - name: New name (nil to keep current)
    ///   - shortcut: New shortcut (nil to keep current)
    ///   - ringRadius: New ring radius/thickness (nil to keep current)
    ///   - centerHoleRadius: New center hole radius (nil to keep current)
    ///   - iconSize: New icon size (nil to keep current)
    /// - Throws: StoredRingConfigurationError if validation fails or configuration not found
    func updateConfiguration(
        id: Int,
        name: String? = nil,
        shortcut: String? = nil,
        ringRadius: Double? = nil,
        centerHoleRadius: Double? = nil,
        iconSize: Double? = nil
    ) throws {
        print("✏️ [RingConfigManager] Updating configuration \(id)")
        
        // Find existing configuration
        guard let existingConfig = getConfiguration(id: id) else {
            throw StoredRingConfigurationError.configurationNotFound(id)
        }
        
        // Determine final values (use new if provided, otherwise keep existing)
        let finalName = name ?? existingConfig.name
        let finalShortcut = shortcut ?? existingConfig.shortcut
        let finalRadius = ringRadius ?? existingConfig.ringRadius
        let finalCenterHoleRadius = centerHoleRadius ?? existingConfig.centerHoleRadius
        let finalIconSize = iconSize ?? existingConfig.iconSize
        
        // Validate inputs
        try validateConfigurationInputs(
            name: finalName,
            shortcut: finalShortcut,
            ringRadius: finalRadius,
            centerHoleRadius: finalCenterHoleRadius,
            iconSize: finalIconSize
        )
        
        // If shortcut is changing, validate uniqueness
        if let newShortcut = shortcut, newShortcut != existingConfig.shortcut {
            guard validateShortcut(newShortcut, excludingRing: id) else {
                throw StoredRingConfigurationError.duplicateShortcut(newShortcut)
            }
        }
        
        // Update in database (async operation, no error thrown)
        databaseManager.updateRingConfiguration(
            id: id,
            name: name,
            shortcut: shortcut,
            ringRadius: ringRadius.map { CGFloat($0) },
            centerHoleRadius: centerHoleRadius.map { CGFloat($0) },
            iconSize: iconSize.map { CGFloat($0) }
        )
        
        // Update in-memory cache
        if let index = configurations.firstIndex(where: { $0.id == id }) {
            let updatedConfig = StoredRingConfiguration(
                id: id,
                name: finalName,
                shortcut: finalShortcut,
                ringRadius: finalRadius,
                centerHoleRadius: finalCenterHoleRadius,
                iconSize: finalIconSize,
                isActive: existingConfig.isActive,
                providers: existingConfig.providers
            )
            configurations[index] = updatedConfig
        }
        
        print("✅ [RingConfigManager] Updated configuration successfully")
    }
    
    /// Delete a ring configuration
    /// - Parameter id: ID of the configuration to delete
    /// - Throws: StoredRingConfigurationError if configuration not found or database error
    func deleteConfiguration(id: Int) throws {
        print("🗑️ [RingConfigManager] Deleting configuration \(id)")
        
        // Verify configuration exists
        guard getConfiguration(id: id) != nil else {
            throw StoredRingConfigurationError.configurationNotFound(id)
        }
        
        // Delete from database (async operation)
        databaseManager.deleteRingConfiguration(id: id)
        
        // Remove from in-memory cache
        configurations.removeAll { $0.id == id }
        
        print("✅ [RingConfigManager] Deleted configuration successfully")
        print("   Total configurations now: \(configurations.count)")
    }
    
    /// Add a provider to an existing ring configuration
    /// - Parameters:
    ///   - ringId: ID of the ring configuration
    ///   - providerType: Type of provider (e.g., "CombinedAppProvider")
    ///   - order: Display order of the provider
    ///   - angle: Optional fixed angle for the provider
    ///   - config: Optional configuration dictionary
    /// - Throws: StoredRingConfigurationError if validation fails
    func addProvider(
        toRing ringId: Int,
        providerType: String,
        order: Int,
        angle: Double? = nil,
        config: [String: Any]? = nil
    ) throws {
        print("➕ [RingConfigManager] Adding provider '\(providerType)' to ring \(ringId)")
        
        // Verify ring exists
        guard getConfiguration(id: ringId) != nil else {
            throw StoredRingConfigurationError.invalidRingId(ringId)
        }
        
        // Validate provider order is unique
        guard validateProviderOrder(order, forRing: ringId, excludingProvider: nil) else {
            throw StoredRingConfigurationError.duplicateProviderOrder(order, ringId: ringId)
        }
        
        // Add to database
        guard let providerId = databaseManager.addProviderToRing(
            ringId: ringId,
            providerType: providerType,
            providerOrder: order,
            parentItemAngle: angle.map { CGFloat($0) }
        ) else {
            throw StoredRingConfigurationError.databaseError("Failed to add provider to ring")
        }
        
        // Update in-memory cache
        if let index = configurations.firstIndex(where: { $0.id == ringId }) {
            let newProvider = ProviderConfiguration(
                id: providerId,
                providerType: providerType,
                order: order,
                parentItemAngle: angle,
                config: config
            )
            
            var updatedProviders = configurations[index].providers
            updatedProviders.append(newProvider)
            
            let updatedConfig = StoredRingConfiguration(
                id: configurations[index].id,
                name: configurations[index].name,
                shortcut: configurations[index].shortcut,
                ringRadius: configurations[index].ringRadius,
                centerHoleRadius: configurations[index].centerHoleRadius,
                iconSize: configurations[index].iconSize,
                isActive: configurations[index].isActive,
                providers: updatedProviders
            )
            
            configurations[index] = updatedConfig
        }
        
        print("✅ [RingConfigManager] Added provider successfully (ID: \(providerId))")
    }
    
    /// Remove a provider from a ring configuration
    /// - Parameters:
    ///   - providerId: ID of the provider to remove
    ///   - ringId: ID of the ring configuration
    /// - Throws: StoredRingConfigurationError if provider or ring not found
    func removeProvider(providerId: Int, fromRing ringId: Int) throws {
        print("🗑️ [RingConfigManager] Removing provider \(providerId) from ring \(ringId)")
        
        // Verify ring exists
        guard let config = getConfiguration(id: ringId) else {
            throw StoredRingConfigurationError.invalidRingId(ringId)
        }
        
        // Verify provider exists in this ring
        guard config.providers.contains(where: { $0.id == providerId }) else {
            throw StoredRingConfigurationError.invalidProviderId(providerId)
        }
        
        // Remove from database (async operation)
        databaseManager.removeProvider(id: providerId)
        
        // Update in-memory cache
        if let index = configurations.firstIndex(where: { $0.id == ringId }) {
            let updatedProviders = configurations[index].providers.filter { $0.id != providerId }
            
            let updatedConfig = StoredRingConfiguration(
                id: configurations[index].id,
                name: configurations[index].name,
                shortcut: configurations[index].shortcut,
                ringRadius: configurations[index].ringRadius,
                centerHoleRadius: configurations[index].centerHoleRadius,
                iconSize: configurations[index].iconSize,
                isActive: configurations[index].isActive,
                providers: updatedProviders
            )
            
            configurations[index] = updatedConfig
        }
        
        print("✅ [RingConfigManager] Removed provider successfully")
    }
    
    /// Toggle the active state of a ring configuration
    /// - Parameters:
    ///   - id: ID of the configuration
    ///   - isActive: New active state
    /// - Throws: StoredRingConfigurationError if configuration not found
    func setConfigurationActive(_ id: Int, isActive: Bool) throws {
        print("🔄 [RingConfigManager] Setting configuration \(id) active: \(isActive)")
        
        // Verify configuration exists
        guard let existingConfig = getConfiguration(id: id) else {
            throw StoredRingConfigurationError.configurationNotFound(id)
        }
        
        // If activating, validate shortcut uniqueness
        if isActive && !existingConfig.isActive {
            guard validateShortcut(existingConfig.shortcut, excludingRing: id) else {
                throw StoredRingConfigurationError.duplicateShortcut(existingConfig.shortcut)
            }
        }
        
        // Update in database (async operation)
        databaseManager.updateRingConfiguration(
            id: id,
            name: nil,
            shortcut: nil,
            ringRadius: nil,
            iconSize: nil,
            isActive: isActive
        )
        
        // Update in-memory cache
        if let index = configurations.firstIndex(where: { $0.id == id }) {
            let updatedConfig = StoredRingConfiguration(
                id: id,
                name: existingConfig.name,
                shortcut: existingConfig.shortcut,
                ringRadius: existingConfig.ringRadius,
                centerHoleRadius: existingConfig.centerHoleRadius,
                iconSize: existingConfig.iconSize,
                isActive: isActive,
                providers: existingConfig.providers
            )
            configurations[index] = updatedConfig
        }
        
        let status = isActive ? "🟢 ACTIVE" : "⚫️ INACTIVE"
        print("✅ [RingConfigManager] Configuration now: \(status)")
    }
    
    // MARK: - Validation Methods
    
    /// Validate that a shortcut is unique among active rings
    /// - Parameters:
    ///   - shortcut: The shortcut to validate
    ///   - excludingRing: Optional ring ID to exclude from check (for updates)
    /// - Returns: true if shortcut is unique (or ring is excluded), false if duplicate exists
    func validateShortcut(_ shortcut: String, excludingRing: Int?) -> Bool {
        let activeRings = getActiveConfigurations()
        
        for config in activeRings {
            // Skip the excluded ring
            if let excludingRing = excludingRing, config.id == excludingRing {
                continue
            }
            
            // Check for duplicate
            if config.shortcut == shortcut {
                print("⚠️ [RingConfigManager] Shortcut '\(shortcut)' already used by '\(config.name)'")
                return false
            }
        }
        
        return true
    }
    
    /// Validate that a provider order is unique within a ring
    /// - Parameters:
    ///   - order: The order value to validate
    ///   - ringId: ID of the ring to check
    ///   - excludingProvider: Optional provider ID to exclude from check (for updates)
    /// - Returns: true if order is unique (or provider is excluded), false if duplicate exists
    func validateProviderOrder(_ order: Int, forRing ringId: Int, excludingProvider: Int?) -> Bool {
        guard let config = getConfiguration(id: ringId) else {
            return true // Ring doesn't exist, so order is "valid" by default
        }
        
        for provider in config.providers {
            // Skip the excluded provider
            if let excludingProvider = excludingProvider, provider.id == excludingProvider {
                continue
            }
            
            // Check for duplicate order
            if provider.order == order {
                print("⚠️ [RingConfigManager] Order \(order) already used by '\(provider.providerType)'")
                return false
            }
        }
        
        return true
    }
    
    // MARK: - Private Helpers
    
    /// Transform database entry to domain model
    private func transformToDomain(_ dbConfig: RingConfigurationEntry) -> StoredRingConfiguration? {
        // Get providers for this ring
        let dbProviders = databaseManager.getProvidersForRing(ringId: dbConfig.id)
        
        // Transform providers
        let providers = dbProviders.map { dbProvider in
            // Parse config JSON if present
            let parsedConfig: [String: Any]?
            if let configJSON = dbProvider.providerConfig {
                parsedConfig = try? JSONSerialization.jsonObject(with: Data(configJSON.utf8)) as? [String: Any]
            } else {
                parsedConfig = nil
            }
            
            return ProviderConfiguration(
                id: dbProvider.id,
                providerType: dbProvider.providerType,
                order: dbProvider.providerOrder,
                parentItemAngle: dbProvider.parentItemAngle.map { Double($0) },
                config: parsedConfig
            )
        }
        
        return StoredRingConfiguration(
            id: dbConfig.id,
            name: dbConfig.name,
            shortcut: dbConfig.shortcut,
            ringRadius: Double(dbConfig.ringRadius),
            centerHoleRadius: Double(dbConfig.centerHoleRadius),
            iconSize: Double(dbConfig.iconSize),
            isActive: dbConfig.isActive,
            providers: providers
        )
    }
    
    /// Validate configuration inputs
    private func validateConfigurationInputs(
        name: String,
        shortcut: String,
        ringRadius: Double,
        centerHoleRadius: Double,
        iconSize: Double
    ) throws {
        // Validate name
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StoredRingConfigurationError.invalidShortcut("Name cannot be empty")
        }
        
        // Validate shortcut
        guard !shortcut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StoredRingConfigurationError.invalidShortcut("Shortcut cannot be empty")
        }
        
        // Validate ring radius
        guard ringRadius > 0 else {
            throw StoredRingConfigurationError.invalidRadius(ringRadius)
        }
        
        // Validate center hole radius
        guard centerHoleRadius > 0 else {
            throw StoredRingConfigurationError.invalidCenterHoleRadius(centerHoleRadius)
        }
        
        // Validate icon size
        guard iconSize > 0 else {
            throw StoredRingConfigurationError.invalidIconSize(iconSize)
        }
    }
}

// MARK: - Example Usage (Documentation)

/*
 Example usage of RingConfigurationManager:
 
 // On app launch
 let manager = RingConfigurationManager.shared
 await manager.loadActiveConfigurations()
 
 // Create a new ring
 let newRing = try await manager.createConfiguration(
     name: "Quick Apps",
     shortcut: "Cmd+Shift+A",
     ringRadius: 80.0,
     centerHoleRadius: 56.0,
     iconSize: 64.0,
     providers: [
         ("RunningAppsProvider", 1, 180.0),
         ("FavoriteAppsProvider", 2, 180.0)
     ]
 )
 
 // Query by shortcut
 if let ring = manager.getConfiguration(forShortcut: "Cmd+Shift+A") {
     // Pass to CircularUIManager to create UI instance
     print("Found ring: \(ring.name)")
 }
 
 // Update configuration
 try await manager.updateConfiguration(
     id: ringId,
     name: "Quick Apps (Updated)",
     ringRadius: 400.0
 )
 
 // Add a provider
 try await manager.addProvider(
     toRing: ringId,
     providerType: "SystemActionsProvider",
     order: 3,
     angle: nil
 )
 
 // Disable a ring
 try await manager.setConfigurationActive(ringId, isActive: false)
 
 // Get all active rings
 let activeRings = manager.getActiveConfigurations()
 for ring in activeRings {
     print("Active ring: \(ring.name) - \(ring.providers.count) providers")
 }
 */
