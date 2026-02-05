//
//  ProviderFactory.swift
//  Jason
//
//  Factory for creating provider instances from ring configuration data.
//  Supports dynamic provider instantiation based on provider type strings.
//

import Foundation
import AppKit

class ProviderFactory {
    
    // MARK: - Dependencies
    
    /// Reference to CircularUIManager (needed by some providers)
    weak var circularUIManager: CircularUIManager?
    
    /// Reference to AppSwitcherManager (needed by CombinedAppsProvider)
    /// Now references the shared singleton instead of a per-instance manager
    weak var appSwitcherManager: AppSwitcherManager?
    
    // MARK: - Initialization
    
    init(circularUIManager: CircularUIManager? = nil, appSwitcherManager: AppSwitcherManager? = nil) {
        self.circularUIManager = circularUIManager
        self.appSwitcherManager = appSwitcherManager
        
        // Log which AppSwitcherManager we're using
        if let manager = appSwitcherManager {
            print("   [ProviderFactory] Using AppSwitcherManager: \(manager === AppSwitcherManager.shared ? "SHARED" : "INSTANCE")")
        }
    }
    
    // Add alongside the existing static methods
    static func normalizeProviderName(_ name: String) -> String {
        return name
            .replacingOccurrences(of: "Provider", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }
    
    // MARK: - Provider Creation
    
    /// Create a provider instance from configuration
    /// - Parameter config: The provider configuration from the database
    /// - Returns: A provider instance conforming to FunctionProvider, or nil if type is unknown
    func createProvider(from config: ProviderConfiguration) -> (any FunctionProvider)? {
        let provider: (any FunctionProvider)?
        
        switch config.providerType {
        case "CombinedAppsProvider":
            provider = createCombinedAppsProvider(config: config)
            
        case "FavoriteFilesProvider":
            provider = createFavoriteFilesProvider(config: config)
            
        case "SystemActionsProvider":
            provider = createSystemActionsProvider(config: config)
            
        case "FavoriteFolderProvider":
            provider = createFavoriteFolderProvider(config: config)
            
        case "WindowManagementProvider":
            provider = createWindowManagementProvider(config: config)
            
        case "ShortcutExecuteProvider":
            provider = createShortcutExecuteProvider(config: config)
            
        case "ClipboardHistoryProvider":
            provider = createClipboardHistoryProvider(config: config)
            
        case "TodoListProvider":
            provider = createTodoListProvider(config: config)
            
        default:
            return nil
        }
        
        if provider != nil {
            print("   [ProviderFactory] created \(config.providerType)")
        } else {
            print("   Failed to create \(config.providerType)")
        }
        
        return provider
    }
    
    /// Create providers from an array of configurations
    /// - Parameter configs: Array of provider configurations
    /// - Returns: Array of successfully created providers
    func createProviders(from configs: [ProviderConfiguration]) -> [any FunctionProvider] {
        let providers = configs.compactMap { config -> (any FunctionProvider)? in
            return createProvider(from: config)
        }
        return providers
    }
    
    // MARK: - Individual Provider Factories
    
    private func createCombinedAppsProvider(config: ProviderConfiguration) -> CombinedAppsProvider? {
        let provider = CombinedAppsProvider()
        
        // Wire up dependencies
        provider.circularUIManager = circularUIManager
        provider.appSwitcherManager = appSwitcherManager  //This is now the shared instance
    
        return provider
    }
    
    private func createClipboardHistoryProvider(config: ProviderConfiguration) -> ClipboardHistoryProvider? {
        let provider = ClipboardHistoryProvider()
        
        return provider
    }
    
    private func createFavoriteFilesProvider(config: ProviderConfiguration) -> FavoriteFilesProvider? {
        let provider = FavoriteFilesProvider()
        
        // Wire up dependencies
        provider.circularUIManager = circularUIManager
        
        return provider
    }
    
    private func createSystemActionsProvider(config: ProviderConfiguration) -> SystemActionsProvider? {
        let provider = SystemActionsProvider()
        
        return provider
    }
    
    private func createFavoriteFolderProvider(config: ProviderConfiguration) -> FavoriteFolderProvider? {
        let provider = FavoriteFolderProvider()
        
        return provider
    }
    
    private func createWindowManagementProvider(config: ProviderConfiguration) -> WindowManagementProvider? {
        let provider = WindowManagementProvider()
        
        // Wire up dependencies
        provider.circularUIManager = circularUIManager
        
        return provider
    }
    
    private func createShortcutExecuteProvider(config: ProviderConfiguration) -> ShortcutExecuteProvider? {
        let provider = ShortcutExecuteProvider()
        
        return provider
    }
    
    private func createTodoListProvider(config: ProviderConfiguration) -> TodoListProvider? {
        return TodoListProvider()
    }
    
    // MARK: - Provider Type Validation
    static func isProviderTypeSupported(_ type: String) -> Bool {
        return supportedProviderTypes().contains(type)
    }
    
    /// Get all supported provider types
    /// - Returns: Array of supported provider type strings
    static func supportedProviderTypes() -> [String] {
        return [
            "CombinedAppsProvider",
            "FavoriteFilesProvider",
            "SystemActionsProvider",
            "FavoriteFolderProvider",
            "WindowManagementProvider",
            "ShortcutExecuteProvider",
            "ClipboardHistoryProvider",
            "TodoListProvider"
        ]
    }
}

// MARK: - Convenience Extensions

extension ProviderFactory {
    
    /// Create providers from a StoredRingConfiguration
    /// - Parameter configuration: The ring configuration containing provider configs
    /// - Returns: Array of created providers in the correct order
    func createProviders(from configuration: StoredRingConfiguration) -> [any FunctionProvider] {
        print("[ProviderFactory] Creating providers for ring: \(configuration.name)")
        
        // Use sorted providers to maintain order
        let sortedConfigs = configuration.sortedProviders
        
        return createProviders(from: sortedConfigs)
    }
}

// MARK: - Future Enhancements Documentation

/*
 FUTURE ENHANCEMENTS:
 
 1. **ParentItemAngle Support**
    When providers are updated to accept parentItemAngle in their init or as a property:
    - Update provider init signatures
    - Apply config.parentItemAngle during creation
    - Example: provider.parentItemAngle = config.parentItemAngle
 
 2. **Provider-Specific Configuration**
    If providers need custom configuration beyond parentItemAngle:
    - Parse config.config dictionary
    - Apply provider-specific settings
    - Example:
      if let maxItems = config.intConfig(forKey: "maxItems") {
          provider.maxItems = maxItems
      }
 
 3. **Lazy Provider Creation**
    For performance optimization with many providers:
    - Create providers on-demand rather than all at once
    - Implement a provider cache/pool
 
 4. **Provider Validation**
    Add validation before creation:
    - Check if provider has required dependencies
    - Validate configuration parameters
    - Return detailed error messages
 
 5. **Dynamic Provider Registration**
    Allow plugins/extensions to register new provider types:
    - Registry pattern for provider factories
    - Dynamic type lookup
 */
