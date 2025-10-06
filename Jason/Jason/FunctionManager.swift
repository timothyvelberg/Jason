//
//  FunctionManager.swift
//  Jason
//
//  Created by Timothy Velberg on 31/07/2025.
//

import Foundation
import AppKit
import SwiftUI

class FunctionManager: ObservableObject {
    @Published var rootNodes: [FunctionNode] = []
    @Published var navigationStack: [FunctionNode] = []
    @Published var selectedIndex: Int = 0
    @Published var selectedOuterIndex: Int = 0
    @Published var hoveredOuterIndex: Int = 0  // New: track outer ring hover
    @Published var isOuterRingExpanded: Bool = false
    @Published var hoveredIndex: Int = 0
    
    
    private var appSwitcher: AppSwitcherManager?
    
    var currentLevel: [FunctionNode] {
        if navigationStack.isEmpty {
            return rootNodes
        } else {
            return navigationStack.last?.children ?? []
        }
    }
    
    // MARK: - Ring Display Properties
    
    var innerRingNodes: [FunctionNode] {
        return currentLevel
    }
    
    var outerRingNodes: [FunctionNode] {
        guard selectedIndex >= 0, selectedIndex < currentLevel.count else { return [] }
        let selectedNode = currentLevel[selectedIndex]
        return selectedNode.children ?? []
    }
    
    var shouldShowOuterRing: Bool {
        return isOuterRingExpanded && !outerRingNodes.isEmpty
    }
    
    var currentFunctionList: [FunctionItem] {
        return currentLevel.map { node in
            FunctionItem(
                id: node.id,
                name: node.name,
                icon: node.icon,
                action: {
                    if node.isLeaf {
                        node.action?()
                    } else {
                        self.navigateInto(node)
                    }
                }
            )
        }
    }
    
    var currentSelectedIndex: Int {
        return hoveredIndex
    }
    
    init(appSwitcher: AppSwitcherManager) {
        self.appSwitcher = appSwitcher
        print("FunctionManager initialized")
    }
    
    // MARK: - Navigation
    
    func navigateInto(_ node: FunctionNode) {
        guard node.isBranch else {
            print("Cannot navigate into leaf node: \(node.name)")
            return
        }
        navigationStack.append(node)
        selectedIndex = 0
        selectedOuterIndex = 0
        hoveredOuterIndex = 0
        isOuterRingExpanded = false
        print("Navigated into: \(node.name), depth: \(navigationStack.count)")
    }
    
    func navigateBack() {
        guard !navigationStack.isEmpty else {
            print("Already at root level")
            return
        }
        let previous = navigationStack.removeLast()
        selectedIndex = 0
        selectedOuterIndex = 0
        hoveredOuterIndex = 0
        isOuterRingExpanded = false
        print("Navigated back from: \(previous.name), depth: \(navigationStack.count)")
    }
    
    // MARK: - Selection
    
    func selectInnerRing(at index: Int) {
        guard index >= 0, index < innerRingNodes.count else { return }
        
        let node = innerRingNodes[index]
        
        if selectedIndex == index {
            // Clicking same item - toggle expansion
            isOuterRingExpanded.toggle()
            print("Toggled outer ring for \(node.name): \(isOuterRingExpanded ? "shown" : "hidden")")
        } else {
            // Clicking different item - select it and expand if it has children
            selectedIndex = index
            hoveredIndex = index  // Keep hover in sync
            selectedOuterIndex = 0
            hoveredOuterIndex = 0
            isOuterRingExpanded = node.isBranch
            print("Selected inner ring \(index): \(node.name), outer ring: \(isOuterRingExpanded ? "shown" : "hidden")")
        }
    }
    
    func selectOuterRing(at index: Int) {
        guard index >= 0, index < outerRingNodes.count else { return }
        selectedOuterIndex = index
        hoveredOuterIndex = index
        
        let node = outerRingNodes[index]
        print("Selected outer ring \(index): \(node.name)")
    }
    
    func selectFunction(at index: Int) {
        guard index >= 0, index < innerRingNodes.count else { return }
        hoveredIndex = index
    }
    
    func selectOuterFunction(at index: Int) {
        guard index >= 0, index < outerRingNodes.count else { return }
        hoveredOuterIndex = index
    }
    
    // MARK: - Execution
    
    func executeInnerRing() {
        guard selectedIndex >= 0, selectedIndex < innerRingNodes.count else { return }
        let node = innerRingNodes[selectedIndex]
        
        if node.isLeaf {
            print("Executing inner ring function: \(node.name)")
            node.action?()
        } else {
            print("Navigating into category: \(node.name)")
            navigateInto(node)
        }
    }
    
    func executeOuterRing() {
        guard selectedOuterIndex >= 0, selectedOuterIndex < outerRingNodes.count else { return }
        let node = outerRingNodes[selectedOuterIndex]
        
        if node.isLeaf {
            print("Executing outer ring function: \(node.name)")
            node.action?()
        } else {
            print("Navigating into nested category: \(node.name)")
            navigateInto(node)
        }
    }
    
    func executeSelected() {
        executeInnerRing()
    }
    
    // MARK: - Data Loading
    
    func loadFunctions() {
        guard let appSwitcher = appSwitcher else { return }
        
        let appNodes = appSwitcher.runningApps.map { app in
            FunctionNode(
                id: "\(app.processIdentifier)",
                name: app.localizedName ?? "Unknown",
                icon: app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!,
                children: nil,
                action: {
                    appSwitcher.switchToApp(app)
                }
            )
        }
        
        rootNodes = [
            FunctionNode(
                id: "apps",
                name: "Applications",
                icon: NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage(),
                children: appNodes,
                action: nil
            )
        ]
        
        print("Loaded \(rootNodes.count) root nodes with \(appNodes.count) app functions")
    }
    
    func loadMockFunctions() {
        let cat1Leaves = (1...4).map { index in
            FunctionNode(
                id: "cat1-func-\(index)",
                name: "Cat1 Func \(index)",
                icon: NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil) ?? NSImage(),
                children: nil,
                action: { print("Cat1 Function \(index) executed") }
            )
        }
        
        let cat2Leaves = (1...3).map { index in
            FunctionNode(
                id: "cat2-func-\(index)",
                name: "Cat2 Func \(index)",
                icon: NSImage(systemSymbolName: "heart.fill", accessibilityDescription: nil) ?? NSImage(),
                children: nil,
                action: { print("Cat2 Function \(index) executed") }
            )
        }
        
        let nestedLeaves = (1...2).map { index in
            FunctionNode(
                id: "nested-func-\(index)",
                name: "Nested Func \(index)",
                icon: NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) ?? NSImage(),
                children: nil,
                action: { print("Nested Function \(index) executed") }
            )
        }
        
        let nestedCategory = FunctionNode(
            id: "nested-category",
            name: "Nested Category",
            icon: NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: nil) ?? NSImage(),
            children: nestedLeaves,
            action: nil
        )
        
        rootNodes = [
            FunctionNode(
                id: "category-1",
                name: "Category 1",
                icon: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage(),
                children: cat1Leaves,
                action: nil
            ),
            FunctionNode(
                id: "category-2",
                name: "Category 2",
                icon: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage(),
                children: cat2Leaves,
                action: nil
            ),
            FunctionNode(
                id: "direct-function-1",
                name: "Direct Function",
                icon: NSImage(systemSymbolName: "bolt.circle.fill", accessibilityDescription: nil) ?? NSImage(),
                children: nil,
                action: { print("Direct function executed!") }
            ),
            FunctionNode(
                id: "category-with-nested",
                name: "Has Nested Cat",
                icon: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage(),
                children: [nestedCategory] + cat1Leaves,
                action: nil
            )
        ]
        
        print("Loaded \(rootNodes.count) root nodes (tree structure)")
    }
}
