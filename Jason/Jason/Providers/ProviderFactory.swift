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
            print("   [ProviderFactory] Using AppSwitcherManager: \(manager === AppSwitcherManager.shared ? "SHARED ✅" : "INSTANCE ⚠️")")
        }
    }
    
    // MARK: - Provider Creation
    
    /// Create a provider instance from configuration
    /// - Parameter config: The provider configuration from the database
    /// - Returns: A provider instance conforming to FunctionProvider, or nil if type is unknown
    func createProvider(from config: ProviderConfiguration) -> (any FunctionProvider)? {
        print("[ProviderFactory] Creating provider: \(config.providerType)")
        
        let provider: (any FunctionProvider)?
        
        switch config.providerType {
        case "CombinedAppsProvider":
            provider = createCombinedAppsProvider(config: config)
            
        case "FavoriteFilesProvider":
            provider = createFavoriteFilesProvider(config: config)
            
        case "SystemActionsProvider":
            provider = createSystemActionsProvider(config: config)
            
        case "FinderLogic":
            provider = createFinderLogic(config: config)
            
        case "WindowManagementProvider":
            provider = createWindowManagementProvider(config: config)
            
        default:
            print("⚠️ [ProviderFactory] Unknown provider type: \(config.providerType)")
            return nil
        }
        
        if provider != nil {
            print("   [ProviderFactory] created \(config.providerType)")
        } else {
            print("   ❌ Failed to create \(config.providerType)")
        }
        
        return provider
    }
    
    /// Create providers from an array of configurations
    /// - Parameter configs: Array of provider configurations
    /// - Returns: Array of successfully created providers
    func createProviders(from configs: [ProviderConfiguration]) -> [any FunctionProvider] {
        print("[ProviderFactory] Creating \(configs.count) provider(s)")
        
        let providers = configs.compactMap { config -> (any FunctionProvider)? in
            return createProvider(from: config)
        }
        
        print("   Successfully created \(providers.count)/\(configs.count) provider(s)")
        
        return providers
    }
    
    // MARK: - Individual Provider Factories
    
    private func createCombinedAppsProvider(config: ProviderConfiguration) -> CombinedAppsProvider? {
        let provider = CombinedAppsProvider()
        
        // Wire up dependencies
        provider.circularUIManager = circularUIManager
        provider.appSwitcherManager = appSwitcherManager  //This is now the shared instance
        
        // TODO: Apply parentItemAngle from config when provider supports it
        // if let angle = config.parentItemAngle {
        //     provider.parentItemAngle = angle
        // }
        
        // TODO: Apply additional config parameters if needed
        // if let customConfig = config.config {
        //     // Apply provider-specific configuration
        // }
        
        return provider
    }
    
    private func createFavoriteFilesProvider(config: ProviderConfiguration) -> FavoriteFilesProvider? {
        let provider = FavoriteFilesProvider()
        
        // Wire up dependencies
        provider.circularUIManager = circularUIManager
        
        // TODO: Apply parentItemAngle from config when provider supports it
        // TODO: Apply additional config parameters if needed
        
        return provider
    }
    
    private func createSystemActionsProvider(config: ProviderConfiguration) -> SystemActionsProvider? {
        let provider = SystemActionsProvider()
        
        // SystemActionsProvider typically doesn't need dependencies
        
        // TODO: Apply parentItemAngle from config when provider supports it
        // TODO: Apply additional config parameters if needed
        
        return provider
    }
    
    private func createFinderLogic(config: ProviderConfiguration) -> FinderLogic? {
        let provider = FinderLogic()
        
        // FinderLogic typically doesn't need dependencies
        
        // TODO: Apply parentItemAngle from config when provider supports it
        // TODO: Apply additional config parameters if needed
        
        return provider
    }
    
    private func createWindowManagementProvider(config: ProviderConfiguration) -> WindowManagementProvider? {
        let provider = WindowManagementProvider()
        
        // Wire up dependencies
        provider.circularUIManager = circularUIManager
        
        // TODO: Apply parentItemAngle from config when provider supports it
        // TODO: Apply additional config parameters if needed
        
        return provider
    }
    
    // MARK: - Provider Type Validation
    
    /// Check if a provider type is supported by the factory
    /// - Parameter type: The provider type string
    /// - Returns: True if the factory can create this provider type
    static func isProviderTypeSupported(_ type: String) -> Bool {
        let supportedTypes = [
            "CombinedAppsProvider",
            "FavoriteFilesProvider",
            "SystemActionsProvider",
            "FinderLogic",
            "WindowManagementProvider"
        ]
        
        return supportedTypes.contains(type)
    }
    
    /// Get all supported provider types
    /// - Returns: Array of supported provider type strings
    static func supportedProviderTypes() -> [String] {
        return [
            "CombinedAppsProvider",
            "FavoriteFilesProvider",
            "SystemActionsProvider",
            "FinderLogic",
            "WindowManagementProvider"
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
