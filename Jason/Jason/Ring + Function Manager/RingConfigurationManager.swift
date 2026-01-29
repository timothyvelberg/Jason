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
        print("[RingConfigManager] Initialized")
    }
    
    // MARK: - Loading Methods
    
    /// Load all ring configurations from the database
    /// Updates the in-memory cache with all configurations
    func loadConfigurations() {
        let dbConfigs = databaseManager.getAllRingConfigurations()
        
        // Transform database entries to domain models
        var domainConfigs: [StoredRingConfiguration] = []
        
        for dbConfig in dbConfigs {
            if let domainConfig = transformToDomain(dbConfig) {
                domainConfigs.append(domainConfig)
            }
        }
        
        configurations = domainConfigs
        print("[RingConfigManager] Loaded \(configurations.count) configuration(s)")
        
        // Log summary
        for config in configurations {
            let status = config.isActive ? "ACTIVE" : "INACTIVE"
            print("   \(status) - \(config.name) (\(config.triggersSummary)) - \(config.providers.count) provider(s), \(config.triggers.count) trigger(s)")
        }
    }
    
    /// Load only active ring configurations from the database
    /// Updates the in-memory cache with active configurations only
    func loadActiveConfigurations() {
        print("[RingConfigManager] Loading active configurations from database...")
        
        let dbConfigs = databaseManager.getAllRingConfigurations()
        
        // Filter for active and transform
        var domainConfigs: [StoredRingConfiguration] = []
        
        for dbConfig in dbConfigs where dbConfig.isActive {
            if let domainConfig = transformToDomain(dbConfig) {
                domainConfigs.append(domainConfig)
            }
        }
        
        configurations = domainConfigs
        print("[RingConfigManager] Loaded \(configurations.count) active configuration(s)")
        
        // Log summary
        for config in configurations {
            print("   \(config.name) (\(config.triggersSummary)) - \(config.providers.count) provider(s), \(config.triggers.count) trigger(s)")
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
    
    /// Get configuration by shortcut string (DEPRECATED - legacy support)
    func getConfiguration(forShortcut shortcut: String) -> StoredRingConfiguration? {
        return configurations.first { $0.shortcut == shortcut }
    }
    
    /// Get configuration by keyboard shortcut (keyCode + modifierFlags)
    func getConfiguration(keyCode: UInt16, modifierFlags: UInt) -> StoredRingConfiguration? {
        return configurations.first { config in
            config.triggers.contains { trigger in
                trigger.triggerType == "keyboard" &&
                trigger.keyCode == keyCode &&
                trigger.modifierFlags == modifierFlags
            }
        }
    }
    
    /// Get configuration by mouse button
    func getConfiguration(buttonNumber: Int32, modifierFlags: UInt) -> StoredRingConfiguration? {
        return configurations.first { config in
            config.triggers.contains { trigger in
                trigger.triggerType == "mouse" &&
                trigger.buttonNumber == buttonNumber &&
                trigger.modifierFlags == modifierFlags
            }
        }
    }
    
    /// Get configuration by trackpad gesture
    func getConfiguration(swipeDirection: String, fingerCount: Int, modifierFlags: UInt) -> StoredRingConfiguration? {
        return configurations.first { config in
            config.triggers.contains { trigger in
                trigger.triggerType == "trackpad" &&
                trigger.swipeDirection == swipeDirection &&
                trigger.fingerCount == fingerCount &&
                trigger.modifierFlags == modifierFlags
            }
        }
    }
    
    // MARK: - Configuration CRUD
    
    /// Create a new ring configuration
    /// - Parameters:
    ///   - name: Display name for the ring
    ///   - shortcut: DEPRECATED - for display only
    ///   - ringRadius: Radius (thickness) of the ring band in points
    ///   - centerHoleRadius: Radius of the center hole in points
    ///   - iconSize: Size of icons in the ring
    ///   - startAngle: Starting angle for first item
    ///   - triggers: Array of trigger specifications
    ///   - providers: Array of provider specifications
    /// - Returns: The newly created configuration
    /// - Throws: StoredRingConfigurationError if validation fails
    func createConfiguration(
        name: String,
        shortcut: String = "",
        ringRadius: Double,
        centerHoleRadius: Double = 56.0,
        iconSize: Double,
        startAngle: Double = 0.0,
        presentationMode: PresentationMode = .ring,
        triggers: [(type: String, keyCode: UInt16?, modifierFlags: UInt, buttonNumber: Int32?, swipeDirection: String?, fingerCount: Int?, isHoldMode: Bool, autoExecuteOnRelease: Bool)] = [],
        providers: [(type: String, order: Int, displayMode: String?, angle: Double?)] = []
    ) throws -> StoredRingConfiguration {
        print("[RingConfigManager] Creating configuration '\(name)'")
        
        // Validate inputs
        try validateConfigurationInputs(
            name: name,
            ringRadius: ringRadius,
            centerHoleRadius: centerHoleRadius,
            iconSize: iconSize
        )
        
        // Validate all triggers for uniqueness
        for trigger in triggers {
            guard validateTrigger(
                triggerType: trigger.type,
                keyCode: trigger.keyCode,
                modifierFlags: trigger.modifierFlags,
                buttonNumber: trigger.buttonNumber,
                swipeDirection: trigger.swipeDirection,
                fingerCount: trigger.fingerCount,
                excludingTriggerId: nil
            ) else {
                let description = formatTriggerDescription(
                    triggerType: trigger.type,
                    keyCode: trigger.keyCode,
                    modifierFlags: trigger.modifierFlags,
                    buttonNumber: trigger.buttonNumber,
                    swipeDirection: trigger.swipeDirection,
                    fingerCount: trigger.fingerCount
                )
                throw StoredRingConfigurationError.duplicateShortcut(description)
            }
        }
        
        // Create ring in database (legacy trigger fields ignored)
        guard let ringId = databaseManager.createRingConfiguration(
            name: name,
            shortcut: shortcut,
            ringRadius: CGFloat(ringRadius),
            centerHoleRadius: CGFloat(centerHoleRadius),
            iconSize: CGFloat(iconSize),
            startAngle: CGFloat(startAngle),
            triggerType: "keyboard",
            keyCode: nil,
            modifierFlags: nil,
            buttonNumber: nil,
            swipeDirection: nil,
            fingerCount: nil,
            isHoldMode: false,
            autoExecuteOnRelease: true,
            presentationMode: presentationMode.rawValue,
        ) else {
            throw StoredRingConfigurationError.databaseError("Failed to create ring configuration")
        }
        
        print("   Created ring configuration with ID: \(ringId)")
        
        // Add triggers
        var triggerConfigs: [TriggerConfiguration] = []
        for trigger in triggers {
            if let triggerId = databaseManager.createTrigger(
                ringId: ringId,
                triggerType: trigger.type,
                keyCode: trigger.keyCode,
                modifierFlags: trigger.modifierFlags,
                buttonNumber: trigger.buttonNumber,
                swipeDirection: trigger.swipeDirection,
                fingerCount: trigger.fingerCount,
                isHoldMode: trigger.isHoldMode,
                autoExecuteOnRelease: trigger.autoExecuteOnRelease
            ) {
                triggerConfigs.append(TriggerConfiguration(
                    id: triggerId,
                    triggerType: trigger.type,
                    keyCode: trigger.keyCode,
                    modifierFlags: trigger.modifierFlags,
                    buttonNumber: trigger.buttonNumber,
                    swipeDirection: trigger.swipeDirection,
                    fingerCount: trigger.fingerCount,
                    isHoldMode: trigger.isHoldMode,
                    autoExecuteOnRelease: trigger.autoExecuteOnRelease
                ))
                print("   Added trigger: \(trigger.type)")
            }
        }
        
        // Add providers
        var providerConfigs: [ProviderConfiguration] = []
        for (index, provider) in providers.enumerated() {
            var configJSON: String? = nil
            if let displayMode = provider.displayMode {
                let config = ["displayMode": displayMode]
                if let jsonData = try? JSONSerialization.data(withJSONObject: config),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    configJSON = jsonString
                }
            }
            
            guard let providerId = databaseManager.createProvider(
                ringId: ringId,
                providerType: provider.type,
                providerOrder: provider.order,
                parentItemAngle: provider.angle.map { CGFloat($0) },
                providerConfig: configJSON
            ) else {
                print("   Failed to add provider '\(provider.type)'")
                continue
            }
            
            var configDict: [String: Any]? = nil
            if let displayMode = provider.displayMode {
                configDict = ["displayMode": displayMode]
            }
            
            providerConfigs.append(ProviderConfiguration(
                id: providerId,
                providerType: provider.type,
                order: provider.order,
                parentItemAngle: provider.angle,
                config: configDict
            ))
            
            print("   Added provider \(index + 1)/\(providers.count): \(provider.type)")
        }
        
        // Create domain model
        let newConfig = StoredRingConfiguration(
            id: ringId,
            name: name,
            shortcut: shortcut,
            ringRadius: ringRadius,
            centerHoleRadius: centerHoleRadius,
            iconSize: iconSize,
            startAngle: startAngle,
            isActive: true,
            presentationMode: presentationMode,
            triggers: triggerConfigs,
            providers: providerConfigs
        )
        
        // Update in-memory cache
        configurations.append(newConfig)
        
        print("[RingConfigManager] Created configuration successfully")
        return newConfig
    }
    
    /// Update an existing ring configuration (non-trigger fields only)
    /// Use addTrigger/removeTrigger for trigger changes
    func updateConfiguration(
        id: Int,
        name: String? = nil,
        shortcut: String? = nil,
        ringRadius: Double? = nil,
        centerHoleRadius: Double? = nil,
        iconSize: Double? = nil,
        startAngle: Double? = nil
    ) throws {
        print("[RingConfigManager] Updating configuration \(id)")
        
        // Verify configuration exists
        guard let _ = getConfiguration(id: id) else {
            throw StoredRingConfigurationError.configurationNotFound(id)
        }
        
        // Validate inputs if provided
        if let radius = ringRadius, radius <= 0 {
            throw StoredRingConfigurationError.invalidRadius(radius)
        }
        if let holeRadius = centerHoleRadius, holeRadius <= 0 {
            throw StoredRingConfigurationError.invalidCenterHoleRadius(holeRadius)
        }
        if let size = iconSize, size <= 0 {
            throw StoredRingConfigurationError.invalidIconSize(size)
        }
        
        // Update in database
        databaseManager.updateRingConfiguration(
            id: id,
            name: name,
            shortcut: shortcut,
            ringRadius: ringRadius.map { CGFloat($0) },
            centerHoleRadius: centerHoleRadius.map { CGFloat($0) },
            iconSize: iconSize.map { CGFloat($0) },
            startAngle: startAngle.map { CGFloat($0) }
        )
        
        // Reload from database to ensure consistency
        reloadConfiguration(id: id)
        
        print("[RingConfigManager] Configuration updated successfully")
    }
    
    /// Delete a ring configuration
    func deleteConfiguration(id: Int) throws {
        print("🗑️ [RingConfigManager] Deleting configuration \(id)")
        
        // Verify configuration exists
        guard getConfiguration(id: id) != nil else {
            throw StoredRingConfigurationError.configurationNotFound(id)
        }
        
        // Delete from database (CASCADE will delete providers and triggers)
        databaseManager.deleteRingConfiguration(id: id)
        
        // Remove from in-memory cache
        configurations.removeAll { $0.id == id }
        
        print("[RingConfigManager] Configuration deleted")
        print("   Total configurations now: \(configurations.count)")
    }
    
    // MARK: - Trigger Management
    
    /// Add a trigger to an existing ring
    /// - Returns: The ID of the newly created trigger
    /// - Throws: StoredRingConfigurationError if ring not found or trigger is duplicate
    func addTrigger(
        toRing ringId: Int,
        triggerType: String,
        keyCode: UInt16? = nil,
        modifierFlags: UInt = 0,
        buttonNumber: Int32? = nil,
        swipeDirection: String? = nil,
        fingerCount: Int? = nil,
        isHoldMode: Bool = false,
        autoExecuteOnRelease: Bool = true
    ) throws -> Int {
        print("[RingConfigManager] Adding trigger to ring \(ringId)")
        
        // Verify ring exists
        guard let config = getConfiguration(id: ringId) else {
            throw StoredRingConfigurationError.configurationNotFound(ringId)
        }
        
        // Only validate uniqueness if ring is active
        if config.isActive {
            guard validateTrigger(
                triggerType: triggerType,
                keyCode: keyCode,
                modifierFlags: modifierFlags,
                buttonNumber: buttonNumber,
                swipeDirection: swipeDirection,
                fingerCount: fingerCount,
                excludingTriggerId: nil
            ) else {
                let description = formatTriggerDescription(
                    triggerType: triggerType,
                    keyCode: keyCode,
                    modifierFlags: modifierFlags,
                    buttonNumber: buttonNumber,
                    swipeDirection: swipeDirection,
                    fingerCount: fingerCount
                )
                throw StoredRingConfigurationError.duplicateShortcut(description)
            }
        }
        
        // Create in database
        guard let triggerId = databaseManager.createTrigger(
            ringId: ringId,
            triggerType: triggerType,
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            buttonNumber: buttonNumber,
            swipeDirection: swipeDirection,
            fingerCount: fingerCount,
            isHoldMode: isHoldMode,
            autoExecuteOnRelease: autoExecuteOnRelease
        ) else {
            throw StoredRingConfigurationError.databaseError("Failed to create trigger")
        }
        
        // Reload configuration to update in-memory cache
        reloadConfiguration(id: ringId)
        
        print("[RingConfigManager] Trigger added successfully (ID: \(triggerId))")
        return triggerId
    }
    
    /// Remove a trigger from a ring
    func removeTrigger(id triggerId: Int) throws {
        print("🗑️ [RingConfigManager] Removing trigger \(triggerId)")
        
        // Find which ring this trigger belongs to
        var ringId: Int?
        for config in configurations {
            if config.triggers.contains(where: { $0.id == triggerId }) {
                ringId = config.id
                break
            }
        }
        
        guard let ringId = ringId else {
            throw StoredRingConfigurationError.databaseError("Trigger \(triggerId) not found")
        }
        
        // Delete from database
        databaseManager.deleteTrigger(id: triggerId)
        
        // Reload configuration to update in-memory cache
        reloadConfiguration(id: ringId)
        
        print("[RingConfigManager] Trigger removed successfully")
    }
    
    // MARK: - Provider Management
    
    /// Add a provider to an existing ring
    func addProvider(
        toRing ringId: Int,
        providerType: String,
        order: Int,
        angle: Double? = nil,
        config: [String: Any]? = nil
    ) throws -> Int {
        print("[RingConfigManager] Adding provider '\(providerType)' to ring \(ringId)")
        
        // Verify ring exists
        guard getConfiguration(id: ringId) != nil else {
            throw StoredRingConfigurationError.invalidRingId(ringId)
        }
        
        // Validate provider order uniqueness
        guard validateProviderOrder(order, forRing: ringId, excludingProvider: nil) else {
            throw StoredRingConfigurationError.duplicateProviderOrder(order, ringId: ringId)
        }
        
        // Serialize config to JSON if provided
        let configJSON: String?
        if let config = config {
            if let jsonData = try? JSONSerialization.data(withJSONObject: config),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                configJSON = jsonString
            } else {
                configJSON = nil
            }
        } else {
            configJSON = nil
        }
        
        // Create provider in database
        guard let providerId = databaseManager.createProvider(
            ringId: ringId,
            providerType: providerType,
            providerOrder: order,
            parentItemAngle: angle.map { CGFloat($0) },
            providerConfig: configJSON
        ) else {
            throw StoredRingConfigurationError.databaseError("Failed to create provider")
        }
        
        // Reload configuration to update in-memory cache
        reloadConfiguration(id: ringId)
        
        print("[RingConfigManager] Provider added successfully (ID: \(providerId))")
        return providerId
    }
    
    /// Update a provider's settings
    func updateProvider(
        id providerId: Int,
        order: Int? = nil,
        angle: Double? = nil,
        config: [String: Any]? = nil,
        clearAngle: Bool = false,
        clearConfig: Bool = false
    ) throws {
        print("[RingConfigManager] Updating provider \(providerId)")
        
        // Find which ring this provider belongs to
        var ringId: Int?
        for config in configurations {
            if config.providers.contains(where: { $0.id == providerId }) {
                ringId = config.id
                break
            }
        }
        
        guard let ringId = ringId else {
            throw StoredRingConfigurationError.invalidProviderId(providerId)
        }
        
        // Validate order uniqueness if updating
        if let newOrder = order {
            guard validateProviderOrder(newOrder, forRing: ringId, excludingProvider: providerId) else {
                throw StoredRingConfigurationError.duplicateProviderOrder(newOrder, ringId: ringId)
            }
        }
        
        // Serialize config to JSON if provided
        let configJSON: String?
        if let config = config {
            if let jsonData = try? JSONSerialization.data(withJSONObject: config),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                configJSON = jsonString
            } else {
                configJSON = nil
            }
        } else {
            configJSON = nil
        }
        
        // Update in database
        databaseManager.updateProvider(
            id: providerId,
            providerOrder: order,
            parentItemAngle: angle.map { CGFloat($0) },
            providerConfig: configJSON,
            clearAngle: clearAngle,
            clearConfig: clearConfig
        )
        
        // Reload configuration to update in-memory cache
        reloadConfiguration(id: ringId)
        
        print("[RingConfigManager] Provider updated successfully")
    }
    
    /// Remove a provider from a ring
    func removeProvider(id providerId: Int) throws {
        print("🗑️ [RingConfigManager] Removing provider \(providerId)")
        
        // Find which ring this provider belongs to
        var ringId: Int?
        for config in configurations {
            if config.providers.contains(where: { $0.id == providerId }) {
                ringId = config.id
                break
            }
        }
        
        guard let ringId = ringId else {
            throw StoredRingConfigurationError.invalidProviderId(providerId)
        }
        
        // Delete from database
        databaseManager.removeProvider(id: providerId)
        
        // Reload configuration to update in-memory cache
        reloadConfiguration(id: ringId)
        
        print("[RingConfigManager] Provider removed successfully")
    }
    
    // MARK: - Active Status Management
    
    /// Set a configuration's active status
    func setConfigurationActive(_ id: Int, isActive: Bool) throws {
        print("[RingConfigManager] Setting configuration \(id) active: \(isActive)")
        
        // Verify configuration exists
        guard let existingConfig = getConfiguration(id: id) else {
            throw StoredRingConfigurationError.configurationNotFound(id)
        }
        
        // If activating, validate all triggers for uniqueness
        if isActive && !existingConfig.isActive {
            for trigger in existingConfig.triggers {
                guard validateTrigger(
                    triggerType: trigger.triggerType,
                    keyCode: trigger.keyCode,
                    modifierFlags: trigger.modifierFlags,
                    buttonNumber: trigger.buttonNumber,
                    swipeDirection: trigger.swipeDirection,
                    fingerCount: trigger.fingerCount,
                    excludingTriggerId: trigger.id
                ) else {
                    throw StoredRingConfigurationError.duplicateShortcut(trigger.displayDescription)
                }
            }
        }
        
        // Update in database
        databaseManager.setRingConfigurationActiveStatus(id: id, isActive: isActive)
        
        // Reload from database
        reloadConfiguration(id: id)
        
        let status = isActive ? "ACTIVE" : "INACTIVE"
        print("[RingConfigManager] Configuration now: \(status)")
    }
    
    // MARK: - Validation Methods
    
    /// Validate that a trigger is unique among active rings
    func validateTrigger(
        triggerType: String,
        keyCode: UInt16?,
        modifierFlags: UInt,
        buttonNumber: Int32?,
        swipeDirection: String?,
        fingerCount: Int?,
        excludingTriggerId: Int?
    ) -> Bool {
        let activeConfigs = getActiveConfigurations()
        
        for config in activeConfigs {
            for trigger in config.triggers {
                // Skip excluded trigger
                if let excludingId = excludingTriggerId, trigger.id == excludingId {
                    continue
                }
                
                // Check for match based on trigger type
                if trigger.triggerType == triggerType {
                    switch triggerType {
                    case "keyboard":
                        if trigger.keyCode == keyCode && trigger.modifierFlags == modifierFlags {
                            print("[RingConfigManager] Keyboard trigger already in use by '\(config.name)'")
                            return false
                        }
                    case "mouse":
                        if trigger.buttonNumber == buttonNumber && trigger.modifierFlags == modifierFlags {
                            print("[RingConfigManager] Mouse trigger already in use by '\(config.name)'")
                            return false
                        }
                    case "trackpad":
                        if trigger.swipeDirection == swipeDirection &&
                           trigger.fingerCount == fingerCount &&
                           trigger.modifierFlags == modifierFlags {
                            print("[RingConfigManager] Trackpad trigger already in use by '\(config.name)'")
                            return false
                        }
                    default:
                        break
                    }
                }
            }
        }
        
        return true
    }
    
    /// Validate that a provider order is unique within a ring
    func validateProviderOrder(_ order: Int, forRing ringId: Int, excludingProvider: Int?) -> Bool {
        guard let config = getConfiguration(id: ringId) else {
            return true
        }
        
        for provider in config.providers {
            if let excludingProvider = excludingProvider, provider.id == excludingProvider {
                continue
            }
            
            if provider.order == order {
                print("[RingConfigManager] Order \(order) already used by '\(provider.providerType)'")
                return false
            }
        }
        
        return true
    }
    
    // MARK: - Private Helpers
    
    /// Transform database entry to domain model
    private func transformToDomain(_ dbConfig: RingConfigurationEntry) -> StoredRingConfiguration? {
        // Get providers for this ring
        let dbProviders = databaseManager.getProviders(ringId: dbConfig.id)
        
        // Transform providers
        let providers = dbProviders.map { dbProvider in
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
        
        // Get triggers for this ring
        let dbTriggers = databaseManager.getTriggersForRing(ringId: dbConfig.id)
        
        // Transform triggers
        let triggers = dbTriggers.map { dbTrigger in
            TriggerConfiguration(
                id: dbTrigger.id,
                triggerType: dbTrigger.triggerType,
                keyCode: dbTrigger.keyCode,
                modifierFlags: dbTrigger.modifierFlags,
                buttonNumber: dbTrigger.buttonNumber,
                swipeDirection: dbTrigger.swipeDirection,
                fingerCount: dbTrigger.fingerCount,
                isHoldMode: dbTrigger.isHoldMode,
                autoExecuteOnRelease: dbTrigger.autoExecuteOnRelease
            )
        }
        
        let presentationMode = PresentationMode(rawValue: dbConfig.presentationMode) ?? .ring
        
        return StoredRingConfiguration(
            id: dbConfig.id,
            name: dbConfig.name,
            shortcut: dbConfig.shortcut,
            ringRadius: Double(dbConfig.ringRadius),
            centerHoleRadius: Double(dbConfig.centerHoleRadius),
            iconSize: Double(dbConfig.iconSize),
            startAngle: Double(dbConfig.startAngle),
            isActive: dbConfig.isActive,
            presentationMode: presentationMode,
            triggers: triggers,
            providers: providers
        )
    }
    
    /// Reload a single configuration from database
    private func reloadConfiguration(id: Int) {
        if let dbConfig = databaseManager.getRingConfiguration(id: id),
           let updatedConfig = transformToDomain(dbConfig) {
            if let index = configurations.firstIndex(where: { $0.id == id }) {
                configurations[index] = updatedConfig
            }
        }
    }
    
    /// Validate configuration inputs
    private func validateConfigurationInputs(
        name: String,
        ringRadius: Double,
        centerHoleRadius: Double,
        iconSize: Double
    ) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StoredRingConfigurationError.invalidShortcut("Name cannot be empty")
        }
        
        guard ringRadius > 0 else {
            throw StoredRingConfigurationError.invalidRadius(ringRadius)
        }
        
        guard centerHoleRadius > 0 else {
            throw StoredRingConfigurationError.invalidCenterHoleRadius(centerHoleRadius)
        }
        
        guard iconSize > 0 else {
            throw StoredRingConfigurationError.invalidIconSize(iconSize)
        }
    }
    
    /// Format a trigger description for error messages
    private func formatTriggerDescription(
        triggerType: String,
        keyCode: UInt16?,
        modifierFlags: UInt,
        buttonNumber: Int32?,
        swipeDirection: String?,
        fingerCount: Int?
    ) -> String {
        switch triggerType {
        case "keyboard":
            guard let keyCode = keyCode else { return "Unknown keyboard" }
            return formatShortcut(keyCode: keyCode, modifiers: modifierFlags)
        case "mouse":
            guard let buttonNumber = buttonNumber else { return "Unknown mouse" }
            return formatMouseButton(buttonNumber: buttonNumber, modifiers: modifierFlags)
        case "trackpad":
            guard let direction = swipeDirection else { return "Unknown trackpad" }
            return formatTrackpadGesture(direction: direction, fingerCount: fingerCount, modifiers: modifierFlags)
        default:
            return "Unknown trigger"
        }
    }
    
    /// Format a shortcut for display
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
    
    /// Convert key code to string
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
    
    /// Format a mouse button for display
    private func formatMouseButton(buttonNumber: Int32, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        let buttonName: String
        switch buttonNumber {
        case 2: buttonName = "Middle Click"
        case 3: buttonName = "Back Button"
        case 4: buttonName = "Forward Button"
        default: buttonName = "Button \(buttonNumber + 1)"
        }
        
        parts.append(buttonName)
        return parts.joined()
    }
    
    /// Format a trackpad gesture for display
    private func formatTrackpadGesture(direction: String, fingerCount: Int?, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        let fingerText = fingerCount.map { "\($0)-Finger " } ?? ""
        let gestureText: String
        switch direction.lowercased() {
        case "up": gestureText = "↑ \(fingerText)Swipe Up"
        case "down": gestureText = "↓ \(fingerText)Swipe Down"
        case "left": gestureText = "← \(fingerText)Swipe Left"
        case "right": gestureText = "→ \(fingerText)Swipe Right"
        case "circleclockwise": gestureText = "↻ \(fingerText)Circle"
        case "circlecounterclockwise": gestureText = "↺ \(fingerText)Circle"
        case "twofingertapleft": gestureText = "👆 Two-Finger Tap (Left)"
        case "twofingertapright": gestureText = "👆 Two-Finger Tap (Right)"
        default: gestureText = "\(fingerText)\(direction)"
        }
        
        parts.append(gestureText)
        return parts.joined()
    }
}
