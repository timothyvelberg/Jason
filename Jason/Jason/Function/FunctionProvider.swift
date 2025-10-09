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
        
        // Example: Category with FEW items - use partial slice
        let fewLeaves = (1...9).map { index in
            FunctionNode(
                id: "mock-few-func-\(index)",
                name: "Quick \(index)",
                icon: NSImage(systemSymbolName: "heart.fill", accessibilityDescription: nil) ?? NSImage(),
                // EXPLICIT INTERACTION MODEL:
                onLeftClick: .execute {
                    print("Mock Few Function \(index) executed")
                },
                onMiddleClick: .executeKeepOpen {
                    print("Mock Few Function \(index) executed (UI stays open)")
                }
            )
        }
        
        // Nested category example
        let nestedLeaves = (1...2).map { index in
            FunctionNode(
                id: "mock-nested-func-\(index)",
                name: "Nested \(index)",
                icon: NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) ?? NSImage(),
                // EXPLICIT INTERACTION MODEL:
                onLeftClick: .execute {
                    print("Mock Nested Function \(index) executed")
                },
                onMiddleClick: .executeKeepOpen {
                    print("Mock Nested Function \(index) executed (UI stays open)")
                }
            )
        }
        
        let nestedCategory = FunctionNode(
            id: "mock-nested-category",
            name: "Nested Category",
            icon: NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: nil) ?? NSImage(),
            children: nestedLeaves,
            preferredLayout: .partialSlice,  // Nested categories as partial slice
            // EXPLICIT INTERACTION MODEL:
            onLeftClick: .expand,           // Click to expand
            onRightClick: .expand,          // Right-click to expand
            onMiddleClick: .expand,         // Middle-click to expand
            onBoundaryCross: .expand        // Auto-expand on boundary cross
        )
        
        return [
            // Example: Nested structure with mixed layouts
            FunctionNode(
                id: "mock-category-with-nested",
                name: "Mixed Layout",
                icon: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage(),
                children: [nestedCategory] + fewLeaves,
                preferredLayout: .partialSlice,  // This level uses partial
                // EXPLICIT INTERACTION MODEL:
                onLeftClick: .expand,           // Click to expand
                onRightClick: .expand,          // Right-click to expand
                onMiddleClick: .expand,         // Middle-click to expand
                onBoundaryCross: .expand        // Auto-expand on boundary cross
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
