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
        print("[RingConfigManager] Loading all configurations from database...")
        
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
            let shortcutDisplay = config.hasShortcut ? config.shortcutDescription : config.shortcut
            print("   \(status) - \(config.name) (\(shortcutDisplay)) - \(config.providers.count) provider(s)")
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
            let shortcutDisplay = config.hasShortcut ? config.shortcutDescription : config.shortcut
            print("   \(config.name) (\(shortcutDisplay)) - \(config.providers.count) provider(s)")
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
    
    /// Get configuration by shortcut string (legacy)
    /// - Parameter shortcut: The keyboard shortcut to search for (e.g., "Cmd+Shift+A")
    /// - Returns: The configuration if found, nil otherwise
    func getConfiguration(forShortcut shortcut: String) -> StoredRingConfiguration? {
        return configurations.first { $0.shortcut == shortcut }
    }
    
    /// Get configuration by shortcut (keyCode + modifierFlags) - NEW
    /// - Parameters:
    ///   - keyCode: The key code
    ///   - modifierFlags: The modifier flags
    /// - Returns: The configuration if found, nil otherwise
    func getConfiguration(keyCode: UInt16, modifierFlags: UInt) -> StoredRingConfiguration? {
        return configurations.first { config in
            config.keyCode == keyCode && config.modifierFlags == modifierFlags
        }
    }
    
    // MARK: - Modification Methods
    
    /// Create a new ring configuration
    /// - Parameters:
    ///   - name: Display name for the ring
    ///   - shortcut: Keyboard shortcut string (for display, DEPRECATED)
    ///   - ringRadius: Radius (thickness) of the ring band in points
    ///   - centerHoleRadius: Radius of the center hole in points
    ///   - iconSize: Size of icons in the ring
    ///   - triggerType: Type of trigger - "keyboard" or "mouse" (default: "keyboard")
    ///   - keyCode: Raw key code for keyboard shortcut
    ///   - modifierFlags: Raw modifier flags for trigger
    ///   - buttonNumber: Mouse button number for mouse trigger (2=middle, 3=back, 4=forward)
    ///   - providers: Array of provider specifications (type, order, angle)
    /// - Returns: The newly created configuration
    /// - Throws: StoredRingConfigurationError if validation fails or database error occurs
    ///
    func createConfiguration(
        name: String,
        shortcut: String = "",             // DEPRECATED - for display only
        ringRadius: Double,
        centerHoleRadius: Double = 56.0,
        iconSize: Double,
        startAngle: Double = 0.0,
        triggerType: String = "keyboard",  // "keyboard", "mouse", or "trackpad"
        keyCode: UInt16? = nil,
        modifierFlags: UInt? = nil,
        buttonNumber: Int32? = nil,        // For mouse triggers
        swipeDirection: String? = nil,     // For trackpad triggers ("up", "down", "left", "right")
        fingerCount: Int? = nil,           // For trackpad triggers (3 or 4 fingers)
        isHoldMode: Bool = false,          // true = hold to show, false = tap to toggle
        autoExecuteOnRelease: Bool = true, // true = auto-execute on release (only when isHoldMode = true)
        providers: [(type: String, order: Int, displayMode: String?, angle: Double?)] = []
    ) throws -> StoredRingConfiguration {
        // Generate display string based on trigger type
        let shortcutDisplay: String
        if triggerType == "keyboard", let keyCode = keyCode {
            shortcutDisplay = formatShortcut(keyCode: keyCode, modifiers: modifierFlags ?? 0)
        } else if triggerType == "mouse", let buttonNumber = buttonNumber {
            shortcutDisplay = formatMouseButton(buttonNumber: buttonNumber, modifiers: modifierFlags ?? 0)
        } else if triggerType == "trackpad", let swipeDirection = swipeDirection {
            shortcutDisplay = formatTrackpadGesture(direction: swipeDirection, fingerCount: fingerCount, modifiers: modifierFlags ?? 0)
        } else {
            shortcutDisplay = shortcut
        }
        
        print("[RingConfigManager] Creating configuration '\(name)' with trigger '\(shortcutDisplay)'")
        
        // Validate inputs
        try validateConfigurationInputs(
            name: name,
            ringRadius: ringRadius,
            centerHoleRadius: centerHoleRadius,
            iconSize: iconSize
        )
        
        // Validate trigger based on type
        if triggerType == "keyboard" {
            // Validate keyboard shortcut uniqueness
            if let keyCode = keyCode, let modifierFlags = modifierFlags {
                guard validateShortcut(keyCode: keyCode, modifierFlags: modifierFlags, excludingRing: nil) else {
                    throw StoredRingConfigurationError.duplicateShortcut(shortcutDisplay)
                }
            }
        } else if triggerType == "mouse" {
            // Validate mouse button uniqueness
            if let buttonNumber = buttonNumber {
                guard validateMouseButton(buttonNumber, modifierFlags: modifierFlags ?? 0, excludingRing: nil) else {
                    throw StoredRingConfigurationError.duplicateShortcut(shortcutDisplay)
                }
            }
        } else if triggerType == "trackpad" {
            // Validate trackpad gesture uniqueness
            if let swipeDirection = swipeDirection, let fingerCount = fingerCount {
                guard validateTrackpadGesture(swipeDirection, fingerCount: fingerCount, modifierFlags: modifierFlags ?? 0, excludingRing: nil) else {
                    throw StoredRingConfigurationError.duplicateShortcut(shortcutDisplay)
                }
            }
        }
        
        // Create in database
        guard let ringId = databaseManager.createRingConfiguration(
            name: name,
            shortcut: shortcutDisplay,
            ringRadius: CGFloat(ringRadius),
            centerHoleRadius: CGFloat(centerHoleRadius),
            iconSize: CGFloat(iconSize),
            startAngle: CGFloat(startAngle),
            triggerType: triggerType,
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            buttonNumber: buttonNumber,
            swipeDirection: swipeDirection,
            fingerCount: fingerCount,
            isHoldMode: isHoldMode,
            autoExecuteOnRelease: autoExecuteOnRelease
        ) else {
            throw StoredRingConfigurationError.databaseError("Failed to create ring configuration")
        }
        
        print("   Created ring configuration with ID: \(ringId)")
        
        // Add providers if specified
        var providerConfigs: [ProviderConfiguration] = []
        for (index, provider) in providers.enumerated() {
            do {
                // Build provider config JSON if displayMode is specified
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
                    print("   Failed to add provider '\(provider.type)': database returned nil")
                    continue
                }
                
                // Build config dictionary for the domain model
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
                
                let modeInfo = provider.displayMode.map { " (mode: \($0))" } ?? ""
                print("   Added provider \(index + 1)/\(providers.count): \(provider.type)\(modeInfo)")
            }
        }
        
        // Create domain model
        let newConfig = StoredRingConfiguration(
            id: ringId,
            name: name,
            shortcut: shortcutDisplay,
            ringRadius: ringRadius,
            centerHoleRadius: centerHoleRadius,
            iconSize: iconSize,
            startAngle: startAngle,
            isActive: true,
            providers: providerConfigs,
            triggerType: triggerType,
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            buttonNumber: buttonNumber,
            swipeDirection: swipeDirection,
            fingerCount: fingerCount,
            isHoldMode: isHoldMode,
            autoExecuteOnRelease: autoExecuteOnRelease
        )
        
        // Update in-memory cache
        configurations.append(newConfig)
        
        print("[RingConfigManager] Created configuration successfully")
        print("   Total configurations now: \(configurations.count)")
        
        return newConfig
    }
    
    /// Update an existing ring configuration
    /// - Parameters:
    ///   - id: ID of the configuration to update
    ///   - name: New name (nil to keep current)
    ///   - shortcut: New shortcut string (nil to keep current, DEPRECATED)
    ///   - ringRadius: New ring radius/thickness (nil to keep current)
    ///   - centerHoleRadius: New center hole radius (nil to keep current)
    ///   - iconSize: New icon size (nil to keep current)
    ///   - triggerType: New trigger type (nil to keep current) - NEW
    ///   - keyCode: New key code (nil to keep current) - NEW
    ///   - modifierFlags: New modifier flags (nil to keep current) - NEW
    ///   - buttonNumber: New button number (nil to keep current) - NEW
    ///   - swipeDirection: New swipe direction (nil to keep current) - NEW
    ///   - fingerCount: New finger count (nil to keep current) - NEW
    ///   - isHoldMode: New hold mode setting (nil to keep current) - NEW
    ///   - autoExecuteOnRelease: New auto-execute setting (nil to keep current) - NEW
    /// - Throws: StoredRingConfigurationError if validation fails or configuration not found
    func updateConfiguration(
        id: Int,
        name: String? = nil,
        shortcut: String? = nil,           // DEPRECATED
        ringRadius: Double? = nil,
        centerHoleRadius: Double? = nil,
        iconSize: Double? = nil,
        startAngle: Double? = nil,
        triggerType: String? = nil,
        keyCode: UInt16? = nil,
        modifierFlags: UInt? = nil,
        buttonNumber: Int32? = nil,
        swipeDirection: String? = nil,
        fingerCount: Int? = nil,
        isHoldMode: Bool? = nil,
        autoExecuteOnRelease: Bool? = nil
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
        
        // Validate shortcut uniqueness if updating keyCode/modifierFlags
        if let keyCode = keyCode, let modifierFlags = modifierFlags {
            guard validateShortcut(keyCode: keyCode, modifierFlags: modifierFlags, excludingRing: id) else {
                let shortcutDisplay = formatShortcut(keyCode: keyCode, modifiers: modifierFlags)
                throw StoredRingConfigurationError.duplicateShortcut(shortcutDisplay)
            }
        }
        
        // Update in database (async operation)
        databaseManager.updateRingConfiguration(
            id: id,
            name: name,
            shortcut: shortcut,
            ringRadius: ringRadius.map { CGFloat($0) },
            centerHoleRadius: centerHoleRadius.map { CGFloat($0) },
            iconSize: iconSize.map { CGFloat($0) },
            startAngle: startAngle.map { CGFloat($0) },
            triggerType: triggerType,
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            buttonNumber: buttonNumber,
            swipeDirection: swipeDirection,
            fingerCount: fingerCount,
            isHoldMode: isHoldMode,
            autoExecuteOnRelease: autoExecuteOnRelease
        )
        
        // Reload from database to ensure consistency
        if let dbConfig = databaseManager.getRingConfiguration(id: id),
           let updatedConfig = transformToDomain(dbConfig) {
            if let index = configurations.firstIndex(where: { $0.id == id }) {
                configurations[index] = updatedConfig
            }
        }
        
        print("[RingConfigManager] Configuration updated successfully")
    }
    
    /// Delete a ring configuration
    /// - Parameter id: ID of the configuration to delete
    /// - Throws: StoredRingConfigurationError if configuration not found
    func deleteConfiguration(id: Int) throws {
        print("🗑️ [RingConfigManager] Deleting configuration \(id)")
        
        // Verify configuration exists
        guard getConfiguration(id: id) != nil else {
            throw StoredRingConfigurationError.configurationNotFound(id)
        }
        
        // Delete from database (CASCADE will delete providers)
        databaseManager.deleteRingConfiguration(id: id)
        
        // Remove from in-memory cache
        configurations.removeAll { $0.id == id }
        
        print("[RingConfigManager] Configuration deleted")
        print("   Total configurations now: \(configurations.count)")
    }
    
    // MARK: - Provider Management
    
    /// Add a provider to an existing ring
    /// - Parameters:
    ///   - ringId: ID of the ring to add provider to
    ///   - providerType: Type of provider (e.g., "RunningAppsProvider")
    ///   - order: Display order within the ring
    ///   - angle: Optional fixed angle for the provider's parent item
    ///   - config: Optional configuration dictionary
    /// - Returns: The ID of the newly created provider
    /// - Throws: StoredRingConfigurationError if ring not found or validation fails
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
        if let dbConfig = databaseManager.getRingConfiguration(id: ringId),
           let updatedConfig = transformToDomain(dbConfig) {
            if let index = configurations.firstIndex(where: { $0.id == ringId }) {
                configurations[index] = updatedConfig
            }
        }
        
        print("[RingConfigManager] Provider added successfully (ID: \(providerId))")
        
        return providerId
    }
    
    /// Update a provider's settings
    /// - Parameters:
    ///   - providerId: ID of the provider to update
    ///   - order: New order (nil to keep current)
    ///   - angle: New angle (nil to keep current)
    ///   - config: New config (nil to keep current)
    ///   - clearAngle: Set to true to clear the angle (set to nil)
    ///   - clearConfig: Set to true to clear the config (set to nil)
    /// - Throws: StoredRingConfigurationError if provider not found or validation fails
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
        if let dbConfig = databaseManager.getRingConfiguration(id: ringId),
           let updatedConfig = transformToDomain(dbConfig) {
            if let index = configurations.firstIndex(where: { $0.id == ringId }) {
                configurations[index] = updatedConfig
            }
        }
        
        print("[RingConfigManager] Provider updated successfully")
    }
    
    /// Remove a provider from a ring
    /// - Parameter providerId: ID of the provider to remove
    /// - Throws: StoredRingConfigurationError if provider not found
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
        if let dbConfig = databaseManager.getRingConfiguration(id: ringId),
           let updatedConfig = transformToDomain(dbConfig) {
            if let index = configurations.firstIndex(where: { $0.id == ringId }) {
                configurations[index] = updatedConfig
            }
        }
        
        print("[RingConfigManager] Provider removed successfully")
    }
    
    // MARK: - Active Status Management
    
    /// Set a configuration's active status
    /// - Parameters:
    ///   - id: ID of the configuration
    ///   - isActive: New active status
    /// - Throws: StoredRingConfigurationError if configuration not found
    func setConfigurationActive(_ id: Int, isActive: Bool) throws {
        print("[RingConfigManager] Setting configuration \(id) active: \(isActive)")
        
        // Verify configuration exists
        guard let existingConfig = getConfiguration(id: id) else {
            throw StoredRingConfigurationError.configurationNotFound(id)
        }
        
        // If activating, validate trigger uniqueness (if trigger exists)
        if isActive && !existingConfig.isActive && existingConfig.hasShortcut {
            if existingConfig.triggerType == "keyboard" {
                guard validateShortcut(keyCode: existingConfig.keyCode!, modifierFlags: existingConfig.modifierFlags!, excludingRing: id) else {
                    throw StoredRingConfigurationError.duplicateShortcut(existingConfig.shortcutDescription)
                }
            } else if existingConfig.triggerType == "mouse" {
                guard validateMouseButton(existingConfig.buttonNumber!, modifierFlags: existingConfig.modifierFlags!, excludingRing: id) else {
                    throw StoredRingConfigurationError.duplicateShortcut(existingConfig.shortcutDescription)
                }
            } else if existingConfig.triggerType == "trackpad" {
                guard validateTrackpadGesture(existingConfig.swipeDirection!, fingerCount: existingConfig.fingerCount!, modifierFlags: existingConfig.modifierFlags!, excludingRing: id) else {
                    throw StoredRingConfigurationError.duplicateShortcut(existingConfig.shortcutDescription)
                }
            }
        }
        
        // Update in database (async operation)
        databaseManager.setRingConfigurationActiveStatus(id: id, isActive: isActive)
        
        // Update in-memory cache
        if let index = configurations.firstIndex(where: { $0.id == id }) {
            let updatedConfig = StoredRingConfiguration(
                id: id,
                name: existingConfig.name,
                shortcut: existingConfig.shortcut,
                ringRadius: existingConfig.ringRadius,
                centerHoleRadius: existingConfig.centerHoleRadius,
                iconSize: existingConfig.iconSize,
                startAngle: existingConfig.startAngle,
                isActive: isActive,
                providers: existingConfig.providers,
                triggerType: existingConfig.triggerType,
                keyCode: existingConfig.keyCode,
                modifierFlags: existingConfig.modifierFlags,
                buttonNumber: existingConfig.buttonNumber,
                swipeDirection: existingConfig.swipeDirection,
                fingerCount: existingConfig.fingerCount,
                isHoldMode: existingConfig.isHoldMode,
                autoExecuteOnRelease: existingConfig.autoExecuteOnRelease
            )
            configurations[index] = updatedConfig
        }
        
        let status = isActive ? "ACTIVE" : "INACTIVE"
        print("[RingConfigManager] Configuration now: \(status)")
    }
    
    // MARK: - Validation Methods
    
    /// Validate that a shortcut (keyCode + modifierFlags) is unique among active rings - NEW
    /// - Parameters:
    ///   - keyCode: The key code to validate
    ///   - modifierFlags: The modifier flags to validate
    ///   - excludingRing: Optional ring ID to exclude from check (for updates)
    /// - Returns: true if shortcut is unique (or ring is excluded), false if duplicate exists
    func validateShortcut(keyCode: UInt16, modifierFlags: UInt, excludingRing: Int?) -> Bool {
        let activeRings = getActiveConfigurations()
        
        for config in activeRings {
            // Skip the excluded ring
            if let excludingRing = excludingRing, config.id == excludingRing {
                continue
            }
            
            // Check for duplicate
            if config.keyCode == keyCode && config.modifierFlags == modifierFlags {
                let shortcutDisplay = formatShortcut(keyCode: keyCode, modifiers: modifierFlags)
                print("[RingConfigManager] Shortcut '\(shortcutDisplay)' already used by '\(config.name)'")
                return false
            }
        }
        
        return true
    }
    
    /// Validate that a shortcut string is unique among active rings (DEPRECATED - legacy support)
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
                print("[RingConfigManager] Shortcut '\(shortcut)' already used by '\(config.name)'")
                return false
            }
        }
        
        return true
    }
    
    /// Validate that a mouse button is unique among active rings
    /// - Parameters:
    ///   - buttonNumber: The button number to validate (2=middle, 3=back, 4=forward)
    ///   - modifierFlags: The modifier flags
    ///   - excludingRing: Optional ring ID to exclude from check (for updates)
    /// - Returns: true if mouse button is unique (or ring is excluded), false if duplicate exists
    func validateMouseButton(_ buttonNumber: Int32, modifierFlags: UInt, excludingRing: Int?) -> Bool {
        let activeRings = getActiveConfigurations()
        
        for config in activeRings {
            // Skip the excluded ring
            if let excludingRing = excludingRing, config.id == excludingRing {
                continue
            }
            
            // Check for duplicate (must match both button and modifiers)
            if config.triggerType == "mouse",
               let configButton = config.buttonNumber,
               configButton == buttonNumber,
               config.modifierFlags == modifierFlags {
                let display = formatMouseButton(buttonNumber: buttonNumber, modifiers: modifierFlags)
                print("[RingConfigManager] Mouse button '\(display)' already used by '\(config.name)'")
                return false
            }
        }
        
        return true
    }
    
    /// Validate that a swipe gesture is unique among active rings
    /// - Parameters:
    ///   - swipeDirection: The swipe direction to validate ("up", "down", "left", "right")
    ///   - modifierFlags: The modifier flags
    ///   - excludingRing: Optional ring ID to exclude from check (for updates)
    /// - Returns: true if swipe gesture is unique (or ring is excluded), false if duplicate exists
    func validateTrackpadGesture(_ swipeDirection: String, fingerCount: Int, modifierFlags: UInt, excludingRing: Int?) -> Bool {
        let activeRings = getActiveConfigurations()
        
        for config in activeRings {
            // Skip the excluded ring
            if let excludingRing = excludingRing, config.id == excludingRing {
                continue
            }
            
            // Check for duplicate (must match direction, finger count, and modifiers)
            if config.triggerType == "trackpad",
               let configDirection = config.swipeDirection,
               let configFingerCount = config.fingerCount,
               configDirection == swipeDirection,
               configFingerCount == fingerCount,
               config.modifierFlags == modifierFlags {
                let display = formatTrackpadGesture(direction: swipeDirection, fingerCount: fingerCount, modifiers: modifierFlags)
                print("[RingConfigManager] Trackpad gesture '\(display)' already used by '\(config.name)'")
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
            startAngle: Double(dbConfig.startAngle),
            isActive: dbConfig.isActive,
            providers: providers,
            triggerType: dbConfig.triggerType,
            keyCode: dbConfig.keyCode,
            modifierFlags: dbConfig.modifierFlags,
            buttonNumber: dbConfig.buttonNumber,
            swipeDirection: dbConfig.swipeDirection,
            fingerCount: dbConfig.fingerCount,
            isHoldMode: dbConfig.isHoldMode,
            autoExecuteOnRelease: dbConfig.autoExecuteOnRelease
        )
    }
    
    /// Validate configuration inputs
    private func validateConfigurationInputs(
        name: String,
        ringRadius: Double,
        centerHoleRadius: Double,
        iconSize: Double
    ) throws {
        // Validate name
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StoredRingConfigurationError.invalidShortcut("Name cannot be empty")
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
    
    /// Format a shortcut for display (helper)
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
    
    /// Convert key code to string (helper)
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 40: return "K"
        case 49: return "Space"
        case 50: return "`"
        case 53: return "Esc"
        default: return "[\(keyCode)]"
        }
    }
    
    /// Format a mouse button for display (helper)
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
    
    /// Format a trackpad gesture for display (helper)
    private func formatTrackpadGesture(direction: String, fingerCount: Int?, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        // Convert direction to arrow emoji with finger count
        let directionSymbol: String
        let fingerText = fingerCount.map { "\($0)-Finger " } ?? ""
        switch direction.lowercased() {
        case "up":
            directionSymbol = "↑ \(fingerText)Swipe Up"
        case "down":
            directionSymbol = "↓ \(fingerText)Swipe Down"
        case "left":
            directionSymbol = "← \(fingerText)Swipe Left"
        case "right":
            directionSymbol = "→ \(fingerText)Swipe Right"
        case "tap":
            directionSymbol = "👆 \(fingerText)Tap"
        default:
            directionSymbol = "\(fingerText)Swipe \(direction)"
        }
        
        parts.append(directionSymbol)
        
        return parts.joined()
    }
}

// MARK: - Example Usage

// MARK: - Example Usage (Documentation)

/*
 Example usage of RingConfigurationManager:
 
 // On app launch
 let manager = RingConfigurationManager.shared
 await manager.loadActiveConfigurations()
 
 // Create a new ring with keyboard shortcut
 let newRing = try await manager.createConfiguration(
     name: "Quick Apps",
     shortcut: "Cmd+Shift+A",  // For display
     ringRadius: 80.0,
     centerHoleRadius: 56.0,
     iconSize: 64.0,
     keyCode: 0,  // "A"
     modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue,
     providers: [
         (type: "RunningAppsProvider", order: 1, displayMode: nil, angle: 180.0),
         (type: "FavoriteAppsProvider", order: 2, displayMode: "direct", angle: 180.0)
     ]
 )
 
 // Query by shortcut (new method)
 if let ring = manager.getConfiguration(keyCode: 0, modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue) {
     print("Found ring: \(ring.name)")
 }
 
 // Update configuration
 try await manager.updateConfiguration(
     id: ringId,
     name: "Quick Apps (Updated)",
     ringRadius: 400.0,
     keyCode: 3  // Change to "F"
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
