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
    
    @Published var rings: [RingState] = [] {
        didSet {
            // Invalidate cache when rings change
            lastRingsHash = 0
        }
    }
    @Published var activeRingLevel: Int = 0
    @Published var ringResetTrigger: UUID = UUID()
    
    // MARK: - Private State
    
    private var rootNodes: [FunctionNode] = []
    private var navigationStack: [FunctionNode] = []
    private var providers: [FunctionProvider] = []
    
    // MARK: - Cache for Ring Configurations
    
    private var cachedConfigurations: [RingConfiguration] = []
    private var lastRingsHash: Int = 0
    
    // MARK: - Helper Types
    
    private struct ParentInfo {
        let angle: Double
        let node: FunctionNode
        let parentItemAngle: Double
    }
    
    // MARK: - Computed Properties for UI
    
    var ringConfigurations: [RingConfiguration] {
        // Create a hash of current state to detect changes
        let currentHash = rings.map { $0.nodes.count }.reduce(0, ^) ^
                         activeRingLevel ^
                         rings.compactMap { $0.selectedIndex }.reduce(0, ^)
        
        // Only recalculate if state changed
        if currentHash != lastRingsHash || cachedConfigurations.isEmpty {
            cachedConfigurations = calculateRingConfigurations()
            lastRingsHash = currentHash
        }
        
        return cachedConfigurations
    }
    
    private func calculateRingConfigurations() -> [RingConfiguration] {
        var configs: [RingConfiguration] = []
        let centerHoleRadius: CGFloat = 50
        let defaultRingThickness: CGFloat = 80
        let defaultIconSize: CGFloat = 32
        let ringMargin: CGFloat = 2
        var currentRadius = centerHoleRadius
        
        for (index, ringState) in rings.enumerated() {
            let sliceConfig: PieSliceConfig
            
            // Determine thickness and icon size
            let ringThickness: CGFloat
            let iconSize: CGFloat
            
            if index == 0 {
                // Ring 0 is always a full circle starting at 0° with default sizes
                ringThickness = defaultRingThickness
                iconSize = defaultIconSize
                sliceConfig = .fullCircle(itemCount: ringState.nodes.count)
            } else {
                // Ring 1+ - get parent info
                guard let parentInfo = getParentInfo(for: index, configs: configs) else {
                    ringThickness = defaultRingThickness
                    iconSize = defaultIconSize
                    sliceConfig = .fullCircle(itemCount: ringState.nodes.count)
                    continue
                }
                
                // Use parent's specified sizes or defaults
                ringThickness = parentInfo.node.childRingThickness ?? defaultRingThickness
                iconSize = parentInfo.node.childIconSize ?? defaultIconSize
                
                let itemCount = ringState.nodes.count
                let preferredLayout = parentInfo.node.preferredLayout ?? .partialSlice
                
                // Decide slice type based on preference and item count
                if preferredLayout == .partialSlice && itemCount >= 12 {
                    // Auto-convert to full circle (too many items)
                    print("🔵 Ring \(index): Auto-converting to FULL CIRCLE (too many items: \(itemCount) >= 12)")
                    sliceConfig = .fullCircle(itemCount: itemCount, startingAt: parentInfo.angle)
                    
                } else if preferredLayout == .fullCircle {
                    // Explicit full circle request
                    print("🔵 Ring \(index): Using FULL CIRCLE layout (parent '\(parentInfo.node.name)' preference)")
                    sliceConfig = .fullCircle(itemCount: itemCount, startingAt: parentInfo.angle)
                    
                } else {
                    // Partial slice
                    print("🔵 Ring \(index): Using PARTIAL SLICE layout (parent '\(parentInfo.node.name)' preference, \(itemCount) items)")
                    
                    print("🎯 Ring \(index) alignment:")
                    print("   Parent angle: \(parentInfo.angle)°")
                    print("   Child slice will start at: \(parentInfo.angle)°")
                    
                    let customAngle = parentInfo.node.itemAngleSize ?? 30.0
                    print("   Using custom angle size: \(customAngle)° (parent itemAngleSize: \(parentInfo.node.itemAngleSize?.description ?? "nil"))")
                    
                    if itemCount == 1 {
                        sliceConfig = .partialSlice(
                            itemCount: 1,
                            centeredAt: parentInfo.angle,
                            defaultItemAngle: parentInfo.node.itemAngleSize ?? parentInfo.parentItemAngle
                        )
                    } else {
                        sliceConfig = .partialSlice(
                            itemCount: itemCount,
                            centeredAt: parentInfo.angle,
                            defaultItemAngle: customAngle
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
                sliceConfig: sliceConfig,
                iconSize: iconSize
            ))
            currentRadius += ringThickness + ringMargin
        }
        
        return configs
    }
    
    private func getParentInfo(for ringIndex: Int, configs: [RingConfiguration]) -> ParentInfo? {
        guard ringIndex > 0, rings.indices.contains(ringIndex - 1) else {
            return nil
        }
        
        let parentRing = rings[ringIndex - 1]
        guard let parentSelectedIndex = parentRing.selectedIndex,
              parentSelectedIndex < parentRing.nodes.count else {
            return nil
        }
        
        let parentNode = parentRing.nodes[parentSelectedIndex]
        
        // Calculate parent's angle
        let parentAngle: Double
        let parentItemAngle: Double
        
        if ringIndex - 1 < configs.count {
            let parentSliceConfig = configs[ringIndex - 1].sliceConfig
            
            if parentSliceConfig.isFullCircle {
                // Parent is full circle - account for its start angle
                parentItemAngle = 360.0 / Double(parentRing.nodes.count)
                let parentStartAngle = parentSliceConfig.startAngle
                parentAngle = parentStartAngle + (Double(parentSelectedIndex) * parentItemAngle)
            } else {
                // Parent is partial slice - align to START of parent item
                let baseAngle = parentSliceConfig.startAngle
                parentItemAngle = parentSliceConfig.itemAngle
                parentAngle = baseAngle + (Double(parentSelectedIndex) * parentItemAngle)
            }
        } else {
            // Fallback (shouldn't happen normally)
            parentItemAngle = 360.0 / Double(max(parentRing.nodes.count, 1))
            parentAngle = Double(parentSelectedIndex) * parentItemAngle
        }
        
        return ParentInfo(angle: parentAngle, node: parentNode, parentItemAngle: parentItemAngle)
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
        cachedConfigurations.removeAll()
        lastRingsHash = 0
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
