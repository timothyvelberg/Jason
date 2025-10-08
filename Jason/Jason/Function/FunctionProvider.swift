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
    
    /// Generate the function tree for this provider
    /// Returns an array of root-level FunctionNodes
    func provideFunctions() -> [FunctionNode]
    
    /// Optional: Refresh/reload data before providing functions
    /// Useful for providers that need to fetch fresh data
    func refresh()
}

// MARK: - Default Implementations

extension FunctionProvider {
    // Default refresh does nothing - providers can override if needed
    func refresh() {
        // No-op by default
    }
}

// MARK: - AppSwitcher Provider

// MARK: - Mock Provider (for testing)

class MockFunctionProvider: FunctionProvider {
    var providerId: String = "mock"
    var providerName: String = "Mock Functions"
    var providerIcon: NSImage {
        return NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil) ?? NSImage()
    }
    
    func provideFunctions() -> [FunctionNode] {
        let cat1Leaves = (1...6).map { index in
            FunctionNode(
                id: "mock-cat1-func-\(index)",
                name: "Cat1 Func \(index)",
                icon: NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil) ?? NSImage(),
                onSelect: { print("Mock Cat1 Function \(index) executed") }
            )
        }
        
        let cat2Leaves = (1...3).map { index in
            FunctionNode(
                id: "mock-cat2-func-\(index)",
                name: "Cat2 Func \(index)",
                icon: NSImage(systemSymbolName: "heart.fill", accessibilityDescription: nil) ?? NSImage(),
                onSelect: { print("Mock Cat2 Function \(index) executed") }
            )
        }
        
        let nestedLeaves = (1...2).map { index in
            FunctionNode(
                id: "mock-nested-func-\(index)",
                name: "Nested Func \(index)",
                icon: NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) ?? NSImage(),
                onSelect: { print("Mock Nested Function \(index) executed") }
            )
        }
        
        let nestedCategory = FunctionNode(
            id: "mock-nested-category",
            name: "Nested Category",
            icon: NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: nil) ?? NSImage(),
            children: nestedLeaves
        )
        
        return [
            FunctionNode(
                id: "mock-category-1",
                name: "Category 1",
                icon: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage(),
                children: cat1Leaves
            ),
            FunctionNode(
                id: "mock-category-2",
                name: "Category 2",
                icon: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage(),
                children: cat2Leaves
            ),
            FunctionNode(
                id: "mock-direct-function-1",
                name: "Direct Function",
                icon: NSImage(systemSymbolName: "bolt.circle.fill", accessibilityDescription: nil) ?? NSImage(),
                onSelect: { print("Mock direct function executed!") }
            ),
            FunctionNode(
                id: "mock-category-with-nested",
                name: "Has Nested Cat",
                icon: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage(),
                children: [nestedCategory] + cat1Leaves
            )
        ]
    }
}
