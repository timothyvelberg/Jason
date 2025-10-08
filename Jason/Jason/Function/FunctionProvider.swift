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

extension AppSwitcherManager: FunctionProvider {
    var providerId: String {
        return "app-switcher"
    }
    
    var providerName: String {
        return "Applications"
    }
    
    var providerIcon: NSImage {
        return NSImage(systemSymbolName: "iphone.app.switcher", accessibilityDescription: nil) ?? NSImage()
    }
    
    func provideFunctions() -> [FunctionNode] {
        // Convert running apps to FunctionNodes with context actions
        let appNodes = runningApps.map { app in
            // Create context actions for each app
            let contextActions = [
                FunctionNode(
                    id: "activate-\(app.processIdentifier)",
                    name: "Bring to Front",
                    icon: NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil) ?? NSImage(),
                    onSelect: { [weak self] in
                        self?.switchToApp(app)
                    }
                ),
                FunctionNode(
                    id: "hide-\(app.processIdentifier)",
                    name: "Hide",
                    icon: NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil) ?? NSImage(),
                    onSelect: { [weak self] in
                        self?.hideApp(app)
                    }
                ),
                FunctionNode(
                    id: "quit-\(app.processIdentifier)",
                    name: "Quit",
                    icon: NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil) ?? NSImage(),
                    onSelect: { [weak self] in
                        self?.quitApp(app)
                    }
                )
            ]
            
            return FunctionNode(
                id: "app-\(app.processIdentifier)",
                name: app.localizedName ?? "Unknown",
                icon: app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!,
                contextActions: contextActions,
                onSelect: { [weak self] in
                    // Primary action: switch to app
                    self?.switchToApp(app)
                },
                onHover: {
                    // Optional: Could preview app windows here
                    print("Hovering over \(app.localizedName ?? "Unknown")")
                },
                onHoverExit: {
                    // Optional: Clean up preview
                    print("Left \(app.localizedName ?? "Unknown")")
                }
            )
        }
        
        // Return as a single category node
        return [
            FunctionNode(
                id: providerId,
                name: providerName,
                icon: providerIcon,
                children: appNodes,
                maxDisplayedChildren: 12  // Limit to 12 apps in the pie slice
            )
        ]
    }
    
    func refresh() {
        // Force reload of running applications
        loadRunningApplications()
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
