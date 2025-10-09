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

// MARK: - Mock Provider (for testing)

class MockFunctionProvider: FunctionProvider {
    var providerId: String = "mock"
    var providerName: String = "Mock Functions"
    var providerIcon: NSImage {
        return NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil) ?? NSImage()
    }
    
    func provideFunctions() -> [FunctionNode] {
        // Example: Category with MANY items - use full circle
        let manyLeaves = (1...20).map { index in
            FunctionNode(
                id: "mock-many-func-\(index)",
                name: "Item \(index)",
                icon: NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil) ?? NSImage(),
                onSelect: { print("Mock Many Function \(index) executed") }
            )
        }
        
        // Example: Category with FEW items - use partial slice
        let fewLeaves = (1...3).map { index in
            FunctionNode(
                id: "mock-few-func-\(index)",
                name: "Quick \(index)",
                icon: NSImage(systemSymbolName: "heart.fill", accessibilityDescription: nil) ?? NSImage(),
                onSelect: { print("Mock Few Function \(index) executed") }
            )
        }
        
        // Nested category example
        let nestedLeaves = (1...2).map { index in
            FunctionNode(
                id: "mock-nested-func-\(index)",
                name: "Nested \(index)",
                icon: NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) ?? NSImage(),
                onSelect: { print("Mock Nested Function \(index) executed") }
            )
        }
        
        let nestedCategory = FunctionNode(
            id: "mock-nested-category",
            name: "Nested Category",
            icon: NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: nil) ?? NSImage(),
            children: nestedLeaves,
            preferredLayout: .partialSlice  // Nested categories as partial slice
        )
        
        return [
            // Example 1: Many items → Full circle for easier access
            FunctionNode(
                id: "mock-category-many",
                name: "Many Items (Full ⭕)",
                icon: NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: nil) ?? NSImage(),
                children: manyLeaves,
                preferredLayout: .fullCircle  // ← Full circle with 20 items (18° each)
            ),
            
            // Example 2: Few items → Partial slice stays close to parent
            FunctionNode(
                id: "mock-category-few",
                name: "Few Items (Slice 🍕)",
                icon: NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: nil) ?? NSImage(),
                children: fewLeaves,
                preferredLayout: .partialSlice  // ← Partial slice (90° total)
            ),
            
            // Example 3: Direct function (no children)
            FunctionNode(
                id: "mock-direct-function-1",
                name: "Direct Action",
                icon: NSImage(systemSymbolName: "bolt.circle.fill", accessibilityDescription: nil) ?? NSImage(),
                onSelect: { print("Mock direct function executed!") }
            ),
            
            // Example 4: Nested structure with mixed layouts
            FunctionNode(
                id: "mock-category-with-nested",
                name: "Mixed Layout",
                icon: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage(),
                children: [nestedCategory] + fewLeaves,
                preferredLayout: .partialSlice  // This level uses partial
            )
        ]
    }
}

// MARK: - Usage Example for AppSwitcher
/*
 Example of how AppSwitcherManager would use preferredLayout:
 
 extension AppSwitcherManager: FunctionProvider {
     func provideFunctions() -> [FunctionNode] {
         let apps = runningApps.map { app in
             FunctionNode(
                 id: "app-\(app.processIdentifier)",
                 name: app.localizedName ?? "Unknown",
                 icon: app.icon ?? NSImage(),
                 contextActions: [
                     FunctionNode(name: "Quit", onSelect: { self.quitApp(app) }),
                     FunctionNode(name: "Hide", onSelect: { self.hideApp(app) })
                 ],
                 onSelect: { self.switchToApp(app) }
             )
         }
         
         return [
             FunctionNode(
                 id: "apps-category",
                 name: "Applications",
                 icon: NSImage(named: "apps") ?? NSImage(),
                 children: apps,
                 preferredLayout: .fullCircle  // ← 20+ apps fit better in full circle!
             )
         ]
     }
 }
 */
