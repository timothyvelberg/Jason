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
    
    // MARK: - Ring State Structure
    
    struct RingState {
        var nodes: [FunctionNode]
        var hoveredIndex: Int?
        var selectedIndex: Int?
        
        init(nodes: [FunctionNode]) {
            self.nodes = nodes
            self.hoveredIndex = nil
            self.selectedIndex = nil
        }
    }
    
    // MARK: - Published State
    
    @Published var rings: [RingState] = []
    @Published var activeRingLevel: Int = 0
    @Published var ringResetTrigger: UUID = UUID()
    
    // MARK: - Private State
    
    private var rootNodes: [FunctionNode] = []
    private var navigationStack: [FunctionNode] = []
    private var appSwitcher: AppSwitcherManager?
    
    // MARK: - Computed Properties for UI
    
    var ringConfigurations: [RingConfiguration] {
        var configs: [RingConfiguration] = []
        let centerHoleRadius: CGFloat = 50
        let ringThickness: CGFloat = 80
        let ringMargin: CGFloat = 2
        var currentRadius = centerHoleRadius
        
        for (index, ringState) in rings.enumerated() {
            configs.append(RingConfiguration(
                level: index,
                startRadius: currentRadius,
                thickness: ringThickness,
                nodes: ringState.nodes,
                selectedIndex: ringState.hoveredIndex
            ))
            currentRadius += ringThickness + ringMargin
        }
        
        return configs
    }
    
    var currentFunctionList: [FunctionItem] {
        guard !rings.isEmpty else { return [] }
        return rings[0].nodes.map { node in
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
    
    // MARK: - Initialization
    
    init(appSwitcher: AppSwitcherManager) {
        self.appSwitcher = appSwitcher
        print("FunctionManager initialized")
    }
    
    // MARK: - State Management
    
    func reset() {
        navigationStack.removeAll()
        rings.removeAll()
        activeRingLevel = 0
        ringResetTrigger = UUID()
        print("FunctionManager state reset")
    }
    
    private func rebuildRings() {
        rings.removeAll()
        
        // Get current level nodes
        let currentNodes = navigationStack.isEmpty ? rootNodes : (navigationStack.last?.children ?? [])
        
        guard !currentNodes.isEmpty else { return }
        
        // Always have at least the base ring
        rings.append(RingState(nodes: currentNodes))
        
        // If there's a selected category in ring 0, show its children in ring 1
        if let ring0 = rings.first,
           let selectedIndex = ring0.selectedIndex,
           selectedIndex < ring0.nodes.count {
            let selectedNode = ring0.nodes[selectedIndex]
            if selectedNode.isBranch, let children = selectedNode.children, !children.isEmpty {
                rings.append(RingState(nodes: children))
            }
        }
        
        print("Rebuilt rings: \(rings.count) ring(s)")
    }
    
    // MARK: - Navigation
    
    func navigateInto(_ node: FunctionNode) {
        guard node.isBranch else {
            print("Cannot navigate into leaf node: \(node.name)")
            return
        }
        navigationStack.append(node)
        activeRingLevel = 0
        rebuildRings()
        print("Navigated into: \(node.name), depth: \(navigationStack.count)")
    }
    
    func navigateBack() {
        guard !navigationStack.isEmpty else {
            print("Already at root level")
            return
        }
        let previous = navigationStack.removeLast()
        activeRingLevel = 0
        rebuildRings()
        print("Navigated back from: \(previous.name), depth: \(navigationStack.count)")
    }
    
    // MARK: - Ring Interaction
    
    func hoverNode(ringLevel: Int, index: Int) {
        guard rings.indices.contains(ringLevel) else { return }
        guard rings[ringLevel].nodes.indices.contains(index) else { return }
        
        rings[ringLevel].hoveredIndex = index
        
        let node = rings[ringLevel].nodes[index]
        print("Hovering ring \(ringLevel), index \(index): \(node.name)")
    }
    
    func selectNode(ringLevel: Int, index: Int) {
        guard rings.indices.contains(ringLevel) else { return }
        guard rings[ringLevel].nodes.indices.contains(index) else { return }
        
        rings[ringLevel].selectedIndex = index
        rings[ringLevel].hoveredIndex = index
        
        let node = rings[ringLevel].nodes[index]
        print("Selected ring \(ringLevel), index \(index): \(node.name)")
    }
    
    func expandCategory(ringLevel: Int, index: Int) {
        print("⭐ expandCategory called: ringLevel=\(ringLevel), index=\(index)")
        
        guard rings.indices.contains(ringLevel) else {
            print("❌ Invalid ring level: \(ringLevel)")
            return
        }
        guard rings[ringLevel].nodes.indices.contains(index) else {
            print("❌ Invalid node index: \(index) for ring level: \(ringLevel)")
            return
        }
        
        let node = rings[ringLevel].nodes[index]
        
        guard node.isBranch, let children = node.children, !children.isEmpty else {
            print("Cannot expand non-category or empty category: \(node.name)")
            return
        }
        
        // Select the node at this level
        rings[ringLevel].selectedIndex = index
        rings[ringLevel].hoveredIndex = index
        
        // Remove any rings beyond this level
        if ringLevel + 1 < rings.count {
            rings.removeSubrange((ringLevel + 1)...)
        }
        
        // Add new ring with children
        rings.append(RingState(nodes: children))
        activeRingLevel = ringLevel + 1
        
        print("Expanded category '\(node.name)' at ring \(ringLevel), created ring \(ringLevel + 1) with \(children.count) nodes")
    }
    
    func collapseToRing(level: Int) {
        guard level >= 0, level < rings.count else { return }
        
        // Remove all rings after the specified level
        if level + 1 < rings.count {
            let removed = rings.count - (level + 1)
            rings.removeSubrange((level + 1)...)
            activeRingLevel = level
            print("Collapsed \(removed) ring(s), now at ring \(level)")
        }
    }
    
    // MARK: - Execution
    
    func executeSelected() {
        guard activeRingLevel < rings.count else { return }
        guard let selectedIndex = rings[activeRingLevel].selectedIndex else { return }
        guard rings[activeRingLevel].nodes.indices.contains(selectedIndex) else { return }
        
        let node = rings[activeRingLevel].nodes[selectedIndex]
        
        if node.isLeaf {
            print("Executing function: \(node.name)")
            node.action?()
        } else {
            print("Navigating into category: \(node.name)")
            navigateInto(node)
        }
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
        
        rebuildRings()
        print("Loaded \(rootNodes.count) root nodes with \(appNodes.count) app functions")
    }
    
    func loadMockFunctions() {
        let cat1Leaves = (1...6).map { index in
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
        
        let nestedLeaves = (1...6).map { index in
            FunctionNode(
                id: "nested-func-\(index)",
                name: "Nested Func \(index)",
                icon: NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) ?? NSImage(),
                children: nil,
                action: { print("Nested Function \(index) executed") }
            )
        }
        
        let nemo2Leaves = (1...8).map { index in
            FunctionNode(
                id: "nested-nemo-\(index)",
                name: "Nested Func \(index)",
                icon: NSImage(systemSymbolName: "doc.text.fill", accessibilityDescription: nil) ?? NSImage(),
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
                id: "direct-function-2",
                name: "Direct Function",
                icon: NSImage(systemSymbolName: "person.fill", accessibilityDescription: nil) ?? NSImage(),
                children: nil,
                action: { print("Direct function executed!") }
            ),
            FunctionNode(
                id: "direct-function-3",
                name: "Direct Function",
                icon: NSImage(systemSymbolName: "externaldrive.fill.badge.person.crop", accessibilityDescription: nil) ?? NSImage(),
                children: nil,
                action: { print("Direct function executed!") }
            ),
            FunctionNode(
                id: "category-nemo",
                name: "Category 1",
                icon: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage(),
                children: nemo2Leaves,
                action: nil
            ),
            FunctionNode(
                id: "direct-function-4",
                name: "Direct Function",
                icon: NSImage(systemSymbolName: "house.circle.fill", accessibilityDescription: nil) ?? NSImage(),
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
        
        rebuildRings()
        print("Loaded \(rootNodes.count) root nodes (tree structure)")
    }
}
