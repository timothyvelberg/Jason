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
    
    /// Whether panels from this provider should default to search mode instead of type-ahead
    var defaultsToSearchMode: Bool { get }
    
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
}

// MARK: - Default Implementations

extension FunctionProvider {
    // Default refresh does nothing - providers can override if needed
    func refresh() {
        // No-op by default
    }
    
    // Default async implementation returns empty array
    func loadChildren(for node: FunctionNode) async -> [FunctionNode] {
        print("⚠️ Provider '\(providerName)' does not implement loadChildren(for:)")
        return []
    }
    
    // Default to type-ahead - providers can override to enable search-first behavior
    var defaultsToSearchMode: Bool { false }
}
