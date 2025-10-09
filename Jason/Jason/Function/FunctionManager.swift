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
    private var providers: [FunctionProvider] = []
    
    // MARK: - Computed Properties for UI
    
    var ringConfigurations: [RingConfiguration] {
        var configs: [RingConfiguration] = []
        let centerHoleRadius: CGFloat = 50
        let ringThickness: CGFloat = 80
        let ringMargin: CGFloat = 2
        var currentRadius = centerHoleRadius
        
        for (index, ringState) in rings.enumerated() {
            // Calculate slice configuration
            let sliceConfig: PieSliceConfig
            
            if index == 0 {
                // Ring 0 is always a full circle (mixes different providers)
                sliceConfig = .fullCircle(itemCount: ringState.nodes.count)
            } else {
                // Ring 1+ - check parent node's layout preference
                guard index > 0, rings.indices.contains(index - 1) else {
                    sliceConfig = .fullCircle(itemCount: ringState.nodes.count)
                    continue
                }
                
                let parentRing = rings[index - 1]
                guard let parentSelectedIndex = parentRing.selectedIndex,
                      parentSelectedIndex < parentRing.nodes.count else {
                    sliceConfig = .fullCircle(itemCount: ringState.nodes.count)
                    continue
                }
                
                // Get the parent node to check its layout preference
                let parentNode = parentRing.nodes[parentSelectedIndex]
                let preferredLayout = parentNode.preferredLayout ?? .partialSlice  // Default to partial
                let itemCount = ringState.nodes.count
                
                // SMART FALLBACK: If partial slice has 12+ items, use full circle instead
                // Reason: 12 items × 30° = 360° (already a full circle)
                if preferredLayout == .partialSlice && itemCount >= 12 {
                    print("🔵 Ring \(index): Auto-converting to FULL CIRCLE (too many items: \(itemCount) >= 12)")
                    sliceConfig = .fullCircle(itemCount: itemCount)
                } else if preferredLayout == .fullCircle {
                    // Parent wants children as full circle
                    print("🔵 Ring \(index): Using FULL CIRCLE layout (parent '\(parentNode.name)' preference)")
                    sliceConfig = .fullCircle(itemCount: itemCount)
                } else {
                    // Parent wants children as partial slice (and itemCount < 12)
                    print("🔵 Ring \(index): Using PARTIAL SLICE layout (parent '\(parentNode.name)' preference, \(itemCount) items)")
                    
                    // Get the parent's slice config to calculate correct angle
                    let parentSliceConfig: PieSliceConfig
                    if index - 1 < configs.count {
                        parentSliceConfig = configs[index - 1].sliceConfig
                    } else {
                        // Fallback: parent is Ring 0 (full circle)
                        parentSliceConfig = .fullCircle(itemCount: parentRing.nodes.count)
                    }
                    
                    // Calculate parent's actual angle position
                    let parentAngle: Double
                    if parentSliceConfig.isFullCircle {
                        // Parent is full circle - use START of parent item slice
                        let parentItemAngle = 360.0 / Double(parentRing.nodes.count)
                        parentAngle = Double(parentSelectedIndex) * parentItemAngle
                    } else {
                        // Parent is partial slice - align to START of parent item
                        let baseAngle = parentSliceConfig.startAngle
                        let itemAngle = parentSliceConfig.itemAngle
                        parentAngle = baseAngle + (Double(parentSelectedIndex) * itemAngle)
                    }
                    
                    // If parent only has 1 child, use parent's angle width
                    if itemCount == 1 {
                        sliceConfig = .partialSlice(
                            itemCount: itemCount,
                            centeredAt: parentAngle,
                            defaultItemAngle: parentSliceConfig.itemAngle
                        )
                    } else {
                        sliceConfig = .partialSlice(
                            itemCount: itemCount,
                            centeredAt: parentAngle
                        )
                    }
                }
            }
            
            configs.append(RingConfiguration(
                level: index,
                startRadius: currentRadius,
                thickness: ringThickness,
                nodes: ringState.nodes,
                selectedIndex: ringState.hoveredIndex,
                sliceConfig: sliceConfig
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
                        node.onSelect?()
                    } else {
                        self.navigateInto(node)
                    }
                }
            )
        }
    }
    
    // MARK: - Initialization
    
    init(providers: [FunctionProvider] = []) {
        self.providers = providers
        print("FunctionManager initialized with \(providers.count) provider(s)")
    }
    
    // MARK: - Provider Management
    
    func registerProvider(_ provider: FunctionProvider) {
        providers.append(provider)
        print("Registered provider: \(provider.providerName)")
    }
    
    func removeProvider(withId id: String) {
        providers.removeAll { $0.providerId == id }
        print("Removed provider: \(id)")
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
        
        // Call onHoverExit on previously hovered node
        if let prevIndex = rings[ringLevel].hoveredIndex,
           prevIndex != index,
           rings[ringLevel].nodes.indices.contains(prevIndex) {
            let prevNode = rings[ringLevel].nodes[prevIndex]
            prevNode.onHoverExit?()
        }
        
        rings[ringLevel].hoveredIndex = index
        
        let node = rings[ringLevel].nodes[index]
        
        // Call onHover on newly hovered node
        node.onHover?()
        
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
        
        // Use displayedChildren which respects maxDisplayedChildren limit
        let displayedChildren = node.displayedChildren
        
        guard node.isBranch, !displayedChildren.isEmpty else {
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
        
        // Add new ring with displayed children (respects limit)
        rings.append(RingState(nodes: displayedChildren))
        activeRingLevel = ringLevel + 1
        
        print("Expanded category '\(node.name)' at ring \(ringLevel), created ring \(ringLevel + 1) with \(displayedChildren.count) nodes")
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
            node.onSelect?()
        } else {
            print("Navigating into category: \(node.name)")
            navigateInto(node)
        }
    }

    // MARK: - Data Loading
    
    func loadFunctions() {
        // Refresh all providers to get latest data
        for provider in providers {
            provider.refresh()
        }
        
        // Collect functions from all providers
        rootNodes = providers.flatMap { provider in
            let functions = provider.provideFunctions()
            print("Provider '\(provider.providerName)' provided \(functions.count) root node(s)")
            return functions
        }
        
        rebuildRings()
        print("Loaded \(rootNodes.count) total root nodes from \(providers.count) provider(s)")
    }
    
    // DEPRECATED: Use providers instead
    func loadMockFunctions() {
        print("⚠️ loadMockFunctions() is deprecated. Register MockFunctionProvider instead.")
        
        // For backward compatibility, create a mock provider
        let mockProvider = MockFunctionProvider()
        providers = [mockProvider]
        loadFunctions()
    }
}
