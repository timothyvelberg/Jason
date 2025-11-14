//
//  RingConfiguration.swift
//  Jason
//
//  Domain models for ring configurations
//

import Foundation
import AppKit

// MARK: - Display Mode

/// Display mode for provider content in rings
enum DisplayMode: String {
    case parent  // Show category wrapper, children accessible via expansion
    case direct  // Skip category, show children directly in ring 0
}

// MARK: - Ring Configuration Models

/// Domain model representing a stored ring configuration from the database
/// This is distinct from:
/// - The database entry model (RingConfigurationEntry)
/// - FunctionManager's RingConfiguration (used for rendering/geometry)
struct StoredRingConfiguration: Identifiable, Equatable {
    let id: Int
    let name: String
    let shortcut: String           // DEPRECATED - display only, for now
    let ringRadius: Double
    let centerHoleRadius: Double
    let iconSize: Double
    let isActive: Bool
    let providers: [ProviderConfiguration]
    
    // Trigger data
    let triggerType: String        // "keyboard" or "mouse"
    let keyCode: UInt16?           // For keyboard triggers
    let modifierFlags: UInt?       // For both keyboard and mouse triggers
    let buttonNumber: Int32?       // For mouse triggers (2=middle, 3=back, 4=forward)
    
    // MARK: - Shortcut Properties
    
    /// Check if this configuration has a valid trigger (keyboard or mouse)
    var hasShortcut: Bool {
        if triggerType == "keyboard" {
            return keyCode != nil && modifierFlags != nil
        } else if triggerType == "mouse" {
            return buttonNumber != nil
        }
        return false
    }
    
    /// Get a human-readable shortcut description
    var shortcutDescription: String {
        if triggerType == "keyboard", let keyCode = keyCode, let modifiers = modifierFlags {
            return formatShortcut(keyCode: keyCode, modifiers: modifiers)
        } else if triggerType == "mouse", let buttonNumber = buttonNumber {
            return formatMouseButton(buttonNumber: buttonNumber, modifiers: modifierFlags ?? 0)
        }
        return "No trigger"
    }
    
    // MARK: - Computed Properties
    
    /// Total number of providers in this ring
    var providerCount: Int {
        return providers.count
    }
    
    /// Check if this ring has any providers
    var hasProviders: Bool {
        return !providers.isEmpty
    }
    
    /// Get providers sorted by their order
    var sortedProviders: [ProviderConfiguration] {
        return providers.sorted { $0.order < $1.order }
    }
    
    /// Calculate the outer radius of the ring
    var outerRadius: Double {
        return centerHoleRadius + ringRadius
    }
    
    /// Get the ring thickness (same as ringRadius, for semantic clarity)
    var thickness: Double {
        return ringRadius
    }
    
    /// Get provider by type
    func provider(ofType type: String) -> ProviderConfiguration? {
        return providers.first { $0.providerType == type }
    }
    
    /// Check if this ring contains a specific provider type
    func hasProvider(ofType type: String) -> Bool {
        return providers.contains { $0.providerType == type }
    }
    
    // MARK: - Shortcut Formatting Helpers
    
    /// Format shortcut for display
    private func formatShortcut(keyCode: UInt16, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        // Add key character
        parts.append(keyCodeToString(keyCode))
        
        return parts.joined()
    }
    
    /// Convert key code to string (for display purposes)
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
    
    // MARK: - Display Helpers
    
    /// Human-readable description for debugging
    var debugDescription: String {
        return """
        StoredRingConfiguration(
            id: \(id),
            name: "\(name)",
            shortcut: "\(shortcutDescription)",
            centerHole: \(centerHoleRadius),
            ringRadius: \(ringRadius),
            iconSize: \(iconSize),
            active: \(isActive),
            providers: \(providers.count)
        )
        """
    }
    
    // MARK: - Equatable
    
    static func == (lhs: StoredRingConfiguration, rhs: StoredRingConfiguration) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.shortcut == rhs.shortcut &&
               lhs.ringRadius == rhs.ringRadius &&
               lhs.centerHoleRadius == rhs.centerHoleRadius &&
               lhs.iconSize == rhs.iconSize &&
               lhs.isActive == rhs.isActive &&
               lhs.triggerType == rhs.triggerType &&
               lhs.keyCode == rhs.keyCode &&
               lhs.modifierFlags == rhs.modifierFlags &&
               lhs.buttonNumber == rhs.buttonNumber &&
               lhs.providers == rhs.providers
    }
}

/// Domain model representing a provider within a ring configuration
struct ProviderConfiguration: Identifiable, Equatable {
    let id: Int
    let providerType: String
    let order: Int
    let parentItemAngle: Double?
    let config: [String: Any]?
    
    // MARK: - Computed Properties
    
    /// Check if this provider has custom angle positioning
    var hasCustomAngle: Bool {
        return parentItemAngle != nil
    }
    
    /// Check if this provider has additional configuration
    var hasConfig: Bool {
        return config != nil && !(config?.isEmpty ?? true)
    }
    
    /// Get a specific config value by key
    func configValue<T>(forKey key: String) -> T? {
        return config?[key] as? T
    }
    
    /// Get a string config value
    func stringConfig(forKey key: String) -> String? {
        return configValue(forKey: key)
    }
    
    /// Get an integer config value
    func intConfig(forKey key: String) -> Int? {
        return configValue(forKey: key)
    }
    
    /// Get a boolean config value
    func boolConfig(forKey key: String) -> Bool? {
        return configValue(forKey: key)
    }
    
    /// Get a double config value
    func doubleConfig(forKey key: String) -> Double? {
        return configValue(forKey: key)
    }
    
    // MARK: - Display Mode
    
    /// Raw display mode string from config (if present)
    var displayMode: String? {
        return stringConfig(forKey: "displayMode")
    }
    
    /// Effective display mode with fallback to parent mode
    /// - Returns: DisplayMode enum value, defaulting to .parent if not specified or invalid
    var effectiveDisplayMode: DisplayMode {
        guard let mode = displayMode else { return .parent }
        return DisplayMode(rawValue: mode) ?? .parent
    }
    
    /// Check if this provider is using direct display mode
    var isDirectMode: Bool {
        return effectiveDisplayMode == .direct
    }
    
    /// Check if this provider is using parent display mode
    var isParentMode: Bool {
        return effectiveDisplayMode == .parent
    }
    
    // MARK: - Display Helpers
    
    /// Human-readable description for debugging
    var debugDescription: String {
        let angleStr = parentItemAngle.map { String(format: "%.1f°", $0) } ?? "dynamic"
        let configStr = hasConfig ? "\(config!.count) params" : "no config"
        let modeStr = displayMode ?? "default"
        return "\(providerType) [order: \(order), angle: \(angleStr), mode: \(modeStr), \(configStr)]"
    }
    
    // MARK: - Equatable
    
    static func == (lhs: ProviderConfiguration, rhs: ProviderConfiguration) -> Bool {
        // Compare all properties except config (since [String: Any] isn't Equatable)
        let basicMatch = lhs.id == rhs.id &&
                        lhs.providerType == rhs.providerType &&
                        lhs.order == rhs.order &&
                        lhs.parentItemAngle == rhs.parentItemAngle
        
        // Compare config dictionaries by converting to JSON
        let configMatch: Bool
        if lhs.config == nil && rhs.config == nil {
            configMatch = true
        } else if let lhsConfig = lhs.config, let rhsConfig = rhs.config {
            // Deep comparison via JSON serialization
            configMatch = NSDictionary(dictionary: lhsConfig).isEqual(to: rhsConfig)
        } else {
            configMatch = false
        }
        
        return basicMatch && configMatch
    }
}

// MARK: - Error Types

/// Errors that can occur when working with stored ring configurations
enum StoredRingConfigurationError: LocalizedError {
    case duplicateShortcut(String)
    case invalidShortcut(String)
    case invalidRingId(Int)
    case invalidProviderId(Int)
    case duplicateProviderOrder(Int, ringId: Int)
    case invalidProviderType(String)
    case databaseError(String)
    case configurationNotFound(Int)
    case noActiveConfigurations
    case invalidRadius(Double)
    case invalidCenterHoleRadius(Double)
    case invalidIconSize(Double)
    
    var errorDescription: String? {
        switch self {
        case .duplicateShortcut(let shortcut):
            return "Shortcut '\(shortcut)' is already in use by another active ring"
        case .invalidShortcut(let shortcut):
            return "Invalid shortcut: '\(shortcut)'"
        case .invalidRingId(let id):
            return "Ring configuration with ID \(id) not found"
        case .invalidProviderId(let id):
            return "Provider with ID \(id) not found"
        case .duplicateProviderOrder(let order, let ringId):
            return "Provider order \(order) is already used in ring \(ringId)"
        case .invalidProviderType(let type):
            return "Invalid provider type: '\(type)'"
        case .databaseError(let message):
            return "Database error: \(message)"
        case .configurationNotFound(let id):
            return "Configuration with ID \(id) not found"
        case .noActiveConfigurations:
            return "No active ring configurations found"
        case .invalidRadius(let radius):
            return "Invalid ring radius: \(radius). Must be greater than 0"
        case .invalidCenterHoleRadius(let radius):
            return "Invalid center hole radius: \(radius). Must be greater than 0"
        case .invalidIconSize(let size):
            return "Invalid icon size: \(size). Must be greater than 0"
        }
    }
}
