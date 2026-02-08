//
//  FunctionProvider.swift
//  Jason
//
//  Protocol for any class that can provide functions to the FunctionManager
//

import Foundation
import AppKit

// MARK: - Function Provider Protocol

protocol FunctionProvider {
    /// Unique identifier for this provider
    var providerId: String { get }
    
    /// Display name for this provider (e.g., "Applications", "Files", "Bookmarks")
    var providerName: String { get }
    
    /// Icon to represent this provider in the UI
    var providerIcon: NSImage { get }

    /// The default typing mode for panels showing this provider's content
    var defaultTypingMode: TypingMode { get }
    
    /// Panel layout configuration (dimensions, line limit, etc.)
    var panelConfig: PanelConfig { get }
    
    /// Generate the function tree for this provider
    /// Returns an array of root-level FunctionNodes
    func provideFunctions() -> [FunctionNode]
    
    /// Optional: Refresh/reload data before providing functions
    /// Useful for providers that need to fetch fresh data
    func refresh()
    
    /// Load children dynamically for a node (ASYNC)
    /// Called when navigating into a node that needs dynamic content
    /// Returns fresh children based on node's metadata
    func loadChildren(for node: FunctionNode) async -> [FunctionNode]
    
    /// Clean up any cached data held by this provider.
    /// Called during instance teardown.
    func clearCache()
}



// MARK: - Mutable List Provider Protocol

/// Protocol for providers that support adding items and notify on changes.
/// Allows generic wiring of onAddItem/onItemsChanged without provider-specific code.
protocol MutableListProvider: FunctionProvider {
    func addItem(title: String)
    var onItemsChanged: (() -> Void)? { get set }
}

// MARK: - Default Implementations

extension FunctionProvider {
    // Default refresh does nothing - providers can override if needed
    func refresh() {
        // No-op by default
    }
    
    // Default async implementation returns empty array
    func loadChildren(for node: FunctionNode) async -> [FunctionNode] {
        print("Provider '\(providerName)' does not implement loadChildren(for:)")
        return []
    }
    
    
    // Default clearCache does nothing - providers override if they have caches
    func clearCache() {
        // No-op by default
    }
    
    // Default to type-ahead - providers can override
    var defaultTypingMode: TypingMode { .typeAhead }
    
    // Default panel config - providers can override for custom dimensions
    var panelConfig: PanelConfig { .default }
}
