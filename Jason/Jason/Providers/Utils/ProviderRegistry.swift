//
//  ProviderRegistry.swift
//  Jason
//
//  Created by Timothy Velberg on 05/03/2026.
//  Manages shared provider instances across all UI instances.
//  Providers are created on first demand and released when no longer referenced.
//

import Foundation

class ProviderRegistry {
    
    // MARK: - Singleton
    
    static let shared = ProviderRegistry()
    
    // MARK: - Private State
    
    private var providers: [String: any FunctionProvider] = [:]
    private var refCounts: [String: Int] = [:]
    
    private init() {}
    
    // MARK: - Public Interface
    
    /// Acquire a provider by type string.
    /// Returns an existing instance if one is alive, otherwise creates one via the factory.
    /// Increments the ref count.
    func acquire(providerType: String, factory: () -> (any FunctionProvider)?) -> (any FunctionProvider)? {
        if let existing = providers[providerType] {
            refCounts[providerType, default: 0] += 1
            print("[ProviderRegistry] Reusing '\(providerType)' (refs: \(refCounts[providerType]!))")
            return existing
        }
        
        guard let newProvider = factory() else {
            print("[ProviderRegistry] Failed to create '\(providerType)'")
            return nil
        }
        
        providers[providerType] = newProvider
        refCounts[providerType] = 1
        print("[ProviderRegistry] Created '\(providerType)' (refs: 1)")
        return newProvider
    }
    
    /// Release a provider by type string.
    /// Decrements the ref count. When it hits zero, teardown() is called and the instance is removed.
    func release(providerType: String) {
        guard let current = refCounts[providerType] else {
            print("[ProviderRegistry] Warning: release called for untracked '\(providerType)'")
            return
        }
        
        let newCount = current - 1
        
        if newCount <= 0 {
            print("[ProviderRegistry] '\(providerType)' ref count hit 0 - tearing down")
            providers[providerType]?.teardown()
            providers.removeValue(forKey: providerType)
            refCounts.removeValue(forKey: providerType)
        } else {
            refCounts[providerType] = newCount
            print("[ProviderRegistry] Released '\(providerType)' (refs: \(newCount))")
        }
    }
    
    /// Release all providers held for a given set of type strings.
    /// Called when an instance is torn down.
    func releaseAll(providerTypes: [String]) {
        for type in providerTypes {
            release(providerType: type)
        }
    }
    
    // MARK: - Debug
    
    func logState() {
        print("[ProviderRegistry] State: \(refCounts.map { "\($0.key): \($0.value)" }.joined(separator: ", "))")
    }
}
