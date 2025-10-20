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
        var isCollapsed: Bool = false
        var openedByClick: Bool = false
        
        init(nodes: [FunctionNode], isCollapsed: Bool = false, openedByClick: Bool = false) {
            self.nodes = nodes
            self.hoveredIndex = nil
            self.selectedIndex = nil
            self.isCollapsed = isCollapsed
            self.openedByClick = openedByClick
        }
    }
    
    // MARK: - Published State
    
    @Published var rings: [RingState] = [] {
        didSet {
            // Invalidate cache when rings change
            lastRingsHash = 0
            cachedConfigurations = []
        }
    }
    @Published var activeRingLevel: Int = 0
    @Published var ringResetTrigger: UUID = UUID()
    @Published var isLoadingFolder: Bool = false
    
    // MARK: - Private State
    
    private var rootNodes: [FunctionNode] = []
    private var navigationStack: [FunctionNode] = []
    private var providers: [FunctionProvider] = []
    
    private(set) var favoriteAppsProvider: FavoriteAppsProvider?
    
    // MARK: - Cache for Ring Configurations
    
    private var cachedConfigurations: [RingConfiguration] = []
    private var lastRingsHash: Int = 0
    
    // MARK: - Helper Types
    
    private struct ParentInfo {
        let leftEdge: Double   // Start angle of parent's slice
        let rightEdge: Double  // End angle of parent's slice
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
        let collapsedRingThickness: CGFloat = 32
        let collapsedIconSize: CGFloat = 16
        let ringMargin: CGFloat = 2
        var currentRadius = centerHoleRadius
        
        print("🔧 [calculateRingConfigurations] START - Processing \(rings.count) rings")
        
        for (index, ringState) in rings.enumerated() {
            print("🔧 [Ring \(index)] Processing ring with \(ringState.nodes.count) nodes, collapsed: \(ringState.isCollapsed)")
            let sliceConfig: PieSliceConfig
            
            // Determine thickness and icon size
            let ringThickness: CGFloat
            let iconSize: CGFloat
            
            // Check if ring is collapsed
            if ringState.isCollapsed {
                ringThickness = collapsedRingThickness
                iconSize = collapsedIconSize
                print("📦 Ring \(index) is COLLAPSED: thickness=\(ringThickness), iconSize=\(iconSize)")
                
                // Collapsed rings use their existing slice config
                if index == 0 {
                    sliceConfig = .fullCircle(itemCount: ringState.nodes.count)
                } else {
                    guard let parentInfo = getParentInfo(for: index, configs: configs) else {
                        print("❌ [Ring \(index)] No parent info - using defaults and CONTINUING")
                        sliceConfig = .fullCircle(itemCount: ringState.nodes.count)
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
                        continue
                    }
                    
                    let itemCount = ringState.nodes.count
                    let preferredLayout = parentInfo.node.preferredLayout ?? .partialSlice
                    
                    if preferredLayout == .partialSlice && itemCount >= 12 {
                        // Choose angle based on positioning
                        let positioning = parentInfo.node.slicePositioning ?? .startClockwise
                        let startAngle: Double
                        switch positioning {
                        case .center:
                            startAngle = (parentInfo.leftEdge + parentInfo.rightEdge) / 2
                        case .startCounterClockwise:
                            startAngle = parentInfo.rightEdge
                        case .startClockwise:
                            startAngle = parentInfo.leftEdge
                        }
                        sliceConfig = .fullCircle(itemCount: itemCount, startingAt: startAngle)
                    } else if preferredLayout == .fullCircle {
                        let positioning = parentInfo.node.slicePositioning ?? .startClockwise
                        let startAngle: Double
                        switch positioning {
                        case .center:
                            startAngle = (parentInfo.leftEdge + parentInfo.rightEdge) / 2
                        case .startCounterClockwise:
                            startAngle = parentInfo.rightEdge
                        case .startClockwise:
                            startAngle = parentInfo.leftEdge
                        }
                        sliceConfig = .fullCircle(itemCount: itemCount, startingAt: startAngle)
                    } else {
                        // Partial slice with positioning
                        let customAngle = parentInfo.node.itemAngleSize ?? 30.0
                        let positioning = parentInfo.node.slicePositioning ?? .startClockwise
                        
                        // Choose the correct angle based on positioning
                        let startingAngle: Double
                        switch positioning {
                        case .center:
                            startingAngle = (parentInfo.leftEdge + parentInfo.rightEdge) / 2
                        case .startCounterClockwise:
                            startingAngle = parentInfo.rightEdge
                        case .startClockwise:
                            startingAngle = parentInfo.leftEdge
                        }
                        
                        if itemCount == 1 {
                            sliceConfig = .partialSlice(
                                itemCount: 1,
                                centeredAt: startingAngle,
                                defaultItemAngle: parentInfo.node.itemAngleSize ?? parentInfo.parentItemAngle,
                                positioning: positioning
                            )
                        } else {
                            sliceConfig = .partialSlice(
                                itemCount: itemCount,
                                centeredAt: startingAngle,
                                defaultItemAngle: customAngle,
                                positioning: positioning
                            )
                        }
                    }
                }
            }else if index == 0 {
                // Ring 0 is always a full circle, shifted so first item is at top (0°)
                ringThickness = defaultRingThickness
                iconSize = defaultIconSize
                
                // Calculate offset to center first item at 0° (top) this sets the default angle on the first ring
                let itemCount = ringState.nodes.count
                let itemAngle = 360.0 / Double(itemCount)
                let offset = -(itemAngle / 2)
                
                sliceConfig = .fullCircle(itemCount: itemCount, startingAt: offset)
                print("🎯 Ring 0: Shifted by \(offset)° to center first item at 0° (itemAngle: \(itemAngle)°)")
            } else {
                // Ring 1+ - get parent info
                guard let parentInfo = getParentInfo(for: index, configs: configs) else {
                    ringThickness = defaultRingThickness
                    iconSize = defaultIconSize
                    sliceConfig = .fullCircle(itemCount: ringState.nodes.count)
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
                    continue
                }
                
                // Use parent's specified sizes or defaults
                ringThickness = parentInfo.node.childRingThickness ?? defaultRingThickness
                iconSize = parentInfo.node.childIconSize ?? defaultIconSize
                
                let itemCount = ringState.nodes.count
                let preferredLayout = parentInfo.node.preferredLayout ?? .partialSlice
                
                // Decide slice type based on preference and item count
                if preferredLayout == .partialSlice && itemCount >= 12 {
                    print("🔵 Ring \(index): Auto-converting to FULL CIRCLE (too many items: \(itemCount) >= 12)")
                    let positioning = parentInfo.node.slicePositioning ?? .startClockwise
                    let startAngle: Double
                    switch positioning {
                    case .center:
                        startAngle = (parentInfo.leftEdge + parentInfo.rightEdge) / 2
                    case .startCounterClockwise:
                        startAngle = parentInfo.rightEdge
                    case .startClockwise:
                        startAngle = parentInfo.leftEdge
                    }
                    sliceConfig = .fullCircle(itemCount: itemCount, startingAt: startAngle)
                    
                } else if preferredLayout == .fullCircle {
                    print("🔵 Ring \(index): Using FULL CIRCLE layout (parent '\(parentInfo.node.name)' preference)")
                    let positioning = parentInfo.node.slicePositioning ?? .startClockwise
                    let startAngle: Double
                    switch positioning {
                    case .center:
                        startAngle = (parentInfo.leftEdge + parentInfo.rightEdge) / 2
                    case .startCounterClockwise:
                        startAngle = parentInfo.rightEdge
                    case .startClockwise:
                        startAngle = parentInfo.leftEdge
                    }
                    sliceConfig = .fullCircle(itemCount: itemCount, startingAt: startAngle)
                    
                } else {
                    print("🔵 Ring \(index): Using PARTIAL SLICE layout (parent '\(parentInfo.node.name)' preference, \(itemCount) items)")
                    
                    let customAngle = parentInfo.node.itemAngleSize ?? 30.0
                    let positioning = parentInfo.node.slicePositioning ?? .startClockwise
                    
                    // Choose the correct angle based on positioning
                    let startingAngle: Double
                    switch positioning {
                    case .center:
                        startingAngle = (parentInfo.leftEdge + parentInfo.rightEdge) / 2
                    case .startCounterClockwise:
                        startingAngle = parentInfo.rightEdge
                    case .startClockwise:
                        startingAngle = parentInfo.leftEdge
                    }
                    
                    print("🎯 Ring \(index) alignment:")
                    print("   Parent left edge: \(parentInfo.leftEdge)°, right edge: \(parentInfo.rightEdge)°")
                    print("   Positioning: \(positioning), using angle: \(startingAngle)°")
                    print("   itemAngleSize: \(customAngle)°")
                    
                    if itemCount == 1 {
                        sliceConfig = .partialSlice(
                            itemCount: 1,
                            centeredAt: startingAngle,
                            defaultItemAngle: parentInfo.node.itemAngleSize ?? parentInfo.parentItemAngle,
                            positioning: positioning
                        )
                    } else {
                        sliceConfig = .partialSlice(
                            itemCount: itemCount,
                            centeredAt: startingAngle,
                            defaultItemAngle: customAngle,
                            positioning: positioning
                        )
                    }
                    
                    print("   Result: startAngle=\(sliceConfig.startAngle)°, endAngle=\(sliceConfig.endAngle)°")
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
        
        // Calculate parent's left and right edges
        let leftEdge: Double
        let rightEdge: Double
        let parentItemAngle: Double
        
        if ringIndex - 1 < configs.count {
            let parentSliceConfig = configs[ringIndex - 1].sliceConfig
            
            if parentSliceConfig.isFullCircle {
                // Parent is full circle
                parentItemAngle = 360.0 / Double(parentRing.nodes.count)
                let parentStartAngle = parentSliceConfig.startAngle
                
                // Calculate the left edge (start) of parent's slice
                leftEdge = parentStartAngle + (Double(parentSelectedIndex) * parentItemAngle)
                rightEdge = leftEdge + parentItemAngle
                
            } else {
                // Parent is partial slice - must account for parent's OWN direction
                parentItemAngle = parentSliceConfig.itemAngle
                
                if parentSliceConfig.direction == .counterClockwise {
                    // Parent slice is counter-clockwise: items positioned from endAngle going backwards
                    rightEdge = parentSliceConfig.endAngle - (Double(parentSelectedIndex) * parentItemAngle)
                    leftEdge = rightEdge - parentItemAngle
                } else {
                    // Parent slice is clockwise: items positioned from startAngle going forwards
                    leftEdge = parentSliceConfig.startAngle + (Double(parentSelectedIndex) * parentItemAngle)
                    rightEdge = leftEdge + parentItemAngle
                }
            }
        } else {
            // Fallback (shouldn't happen normally)
            parentItemAngle = 360.0 / Double(max(parentRing.nodes.count, 1))
            leftEdge = Double(parentSelectedIndex) * parentItemAngle
            rightEdge = leftEdge + parentItemAngle
        }
        
        print("📐 Parent '\(parentNode.name)' edges: left=\(leftEdge)°, right=\(rightEdge)°")
        
        return ParentInfo(leftEdge: leftEdge, rightEdge: rightEdge, node: parentNode, parentItemAngle: parentItemAngle)
    }
    
    func getItemAt(position: CGPoint, centerPoint: CGPoint) -> (ringLevel: Int, itemIndex: Int, node: FunctionNode)? {
        // Calculate angle and distance from center
        let angle = calculateAngle(from: centerPoint, to: position)
        let distance = calculateDistance(from: centerPoint, to: position)
        
        // Determine which ring this position is in
        guard let ringLevel = getRingLevel(at: distance) else {
            print("📍 Position at distance \(distance) is not in any ring")
            return nil
        }
        
        // Check if this ring has items
        guard ringLevel < rings.count else { return nil }
        let nodes = rings[ringLevel].nodes
        guard !nodes.isEmpty else { return nil }
        
        // Get the slice configuration for this ring
        let configs = ringConfigurations
        guard ringLevel < configs.count else { return nil }
        let sliceConfig = configs[ringLevel].sliceConfig
        
        // Check if angle is within the slice (for partial slices)
        if !sliceConfig.isFullCircle {
            if !isAngleInSlice(angle, sliceConfig: sliceConfig) {
                print("📍 Angle \(angle)° is outside the slice")
                return nil
            }
        }
        
        // Calculate which item this angle corresponds to
        let itemIndex = getItemIndex(for: angle, sliceConfig: sliceConfig, itemCount: nodes.count)
        
        guard itemIndex >= 0, itemIndex < nodes.count else {
            print("📍 Invalid item index: \(itemIndex)")
            return nil
        }
        
        let node = nodes[itemIndex]
        print("📍 Found item at position: ring=\(ringLevel), index=\(itemIndex), name='\(node.name)'")
        
        return (ringLevel, itemIndex, node)
    }
    
    /// Calculate distance from center to position
    private func calculateDistance(from center: CGPoint, to position: CGPoint) -> CGFloat {
        let dx = position.x - center.x
        let dy = position.y - center.y
        return hypot(dx, dy)
    }

    /// Determine which ring level a given distance falls into
    private func getRingLevel(at distance: CGFloat) -> Int? {
        let configs = ringConfigurations
        
        // Check each ring's boundaries
        for config in configs {
            let ringInnerRadius = config.startRadius
            let ringOuterRadius = config.startRadius + config.thickness
            
            if distance >= ringInnerRadius && distance <= ringOuterRadius {
                return config.level
            }
        }
        
        // If beyond all rings, treat as being in the active (outermost) ring
        // This matches MouseTracker's behavior for boundary crossing
        if rings.count > 0 && distance > 0 {
            print("📍 Distance \(distance) is beyond all rings, treating as active ring \(activeRingLevel)")
            return activeRingLevel
        }
        
        return nil
    }
    
    private func getItemIndex(for angle: Double, sliceConfig: PieSliceConfig, itemCount: Int) -> Int {
        guard itemCount > 0 else { return -1 }
        
        let itemAngle = sliceConfig.itemAngle
        let sliceStart = sliceConfig.startAngle
        let sliceEnd = sliceConfig.endAngle
        
        if sliceConfig.isFullCircle {
            // Normalize angles to 0-360 range
            var adjustedAngle = angle
            while adjustedAngle < 0 { adjustedAngle += 360 }
            while adjustedAngle >= 360 { adjustedAngle -= 360 }
            
            var normalizedStart = sliceStart
            while normalizedStart >= 360 { normalizedStart -= 360 }
            while normalizedStart < 0 { normalizedStart += 360 }
            
            // Calculate relative angle from start
            var relativeAngle = adjustedAngle - normalizedStart
            if relativeAngle < 0 { relativeAngle += 360 }
            
            let index = Int(relativeAngle / itemAngle) % itemCount
            return index
            
        } else {
            // Partial slice
            var normalizedAngle = angle
            while normalizedAngle < 0 { normalizedAngle += 360 }
            while normalizedAngle >= 360 { normalizedAngle -= 360 }
            
            if sliceConfig.direction == .counterClockwise {
                // Counter-clockwise: Items positioned from END going backwards
                var normalizedEnd = sliceEnd
                while normalizedEnd >= 360 { normalizedEnd -= 360 }
                while normalizedEnd < 0 { normalizedEnd += 360 }
                
                var relativeAngle = normalizedEnd - normalizedAngle
                if relativeAngle < 0 { relativeAngle += 360 }
                
                let index = Int(relativeAngle / itemAngle)
                
                if index >= 0 && index < itemCount {
                    return index
                }
                
            } else {
                // Clockwise: Items positioned from START going forwards
                var normalizedStart = sliceStart
                while normalizedStart >= 360 { normalizedStart -= 360 }
                while normalizedStart < 0 { normalizedStart += 360 }
                
                var relativeAngle = normalizedAngle - normalizedStart
                if relativeAngle < 0 { relativeAngle += 360 }
                
                let index = Int(relativeAngle / itemAngle)
                
                if index >= 0 && index < itemCount {
                    return index
                }
            }
        }
        
        return -1
    }
    
    /// Check if angle is within a slice configuration
    private func isAngleInSlice(_ angle: Double, sliceConfig: PieSliceConfig) -> Bool {
        // Normalize all angles to 0-360 range
        var normalizedAngle = angle.truncatingRemainder(dividingBy: 360)
        if normalizedAngle < 0 { normalizedAngle += 360 }
        
        var normalizedStart = sliceConfig.startAngle.truncatingRemainder(dividingBy: 360)
        if normalizedStart < 0 { normalizedStart += 360 }
        
        var normalizedEnd = sliceConfig.endAngle.truncatingRemainder(dividingBy: 360)
        if normalizedEnd < 0 { normalizedEnd += 360 }
        
        // Handle wrapping (when slice crosses 0°)
        if normalizedStart <= normalizedEnd {
            // Normal case: start < end
            return normalizedAngle >= normalizedStart && normalizedAngle <= normalizedEnd
        } else {
            // Wrapped case: crosses 0°
            return normalizedAngle >= normalizedStart || normalizedAngle <= normalizedEnd
        }
    }

    /// Calculate angle from center to position (in degrees, 0° = top, clockwise)
    private func calculateAngle(from center: CGPoint, to position: CGPoint) -> Double {
        let dx = position.x - center.x
        let dy = position.y - center.y
        
        let radians = atan2(dy, dx)
        var degrees = radians * (180 / .pi)
        
        // Adjust so 0° is at top (not right)
        degrees -= 90
        
        // Normalize to 0-360 range
        if degrees < 0 { degrees += 360 }
        
        // Flip direction (screen coordinates are flipped)
        degrees = (360 - degrees).truncatingRemainder(dividingBy: 360)
        
        return degrees
    }
    
    // MARK: - Initialization
    
    init(providers: [FunctionProvider] = []) {
        self.providers = providers
        let appsProvider = FavoriteAppsProvider()
        self.favoriteAppsProvider = appsProvider
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
    
    func expandCategory(ringLevel: Int, index: Int, openedByClick: Bool = false) {
        print("⭐ expandCategory called: ringLevel=\(ringLevel), index=\(index), openedByClick=\(openedByClick)")
        
        guard rings.indices.contains(ringLevel) else {
            print("❌ Invalid ring level: \(ringLevel)")
            return
        }
        guard rings[ringLevel].nodes.indices.contains(index) else {
            print("❌ Invalid node index: \(index) for ring level: \(ringLevel)")
            return
        }
        
        let node = rings[ringLevel].nodes[index]
        
        print("⭐ Expanding node: '\(node.name)'")
        print("   - isBranch: \(node.isBranch)")
        print("   - children count: \(node.children?.count ?? 0)")
        print("   - contextActions count: \(node.contextActions?.count ?? 0)")
        
        // Use displayedChildren which respects maxDisplayedChildren limit
        let displayedChildren = node.displayedChildren
        
        print("   - displayedChildren count: \(displayedChildren.count)")
        
        guard node.isBranch, !displayedChildren.isEmpty else {
            print("❌ Cannot expand non-category or empty category: \(node.name)")
            return
        }
        
        // Select the node at this level
        rings[ringLevel].selectedIndex = index
        rings[ringLevel].hoveredIndex = index
        
        // Remove any rings beyond this level
        if ringLevel + 1 < rings.count {
            rings.removeSubrange((ringLevel + 1)...)
        }
        
        // Add new ring with displayed children - use the openedByClick parameter
        rings.append(RingState(nodes: displayedChildren, isCollapsed: false, openedByClick: openedByClick))
        activeRingLevel = ringLevel + 1
        
        print("✅ Expanded category '\(node.name)' at ring \(ringLevel), created ring \(ringLevel + 1) with \(displayedChildren.count) nodes (openedByClick=\(openedByClick))")
    }

    // MARK: - Direct Category Expansion

    /// Load functions and immediately expand to a specific category by provider ID
    /// - Parameter providerId: The ID of the provider to expand (e.g., "app-switcher")
    func loadAndExpandToCategory(providerId: String) {
        print("🎯 [FunctionManager] Loading and expanding to category: \(providerId)")
        
        // First, load all functions normally
        loadFunctions()
        
        // Verify we have a Ring 0
        guard !rings.isEmpty, !rings[0].nodes.isEmpty else {
            print("❌ No Ring 0 available after loading")
            return
        }
        
        // Find the node with matching ID in Ring 0
        guard let index = rings[0].nodes.firstIndex(where: { $0.id == providerId }) else {
            print("❌ Provider '\(providerId)' not found in Ring 0")
            print("   Available providers: \(rings[0].nodes.map { $0.id }.joined(separator: ", "))")
            return
        }
        
        let node = rings[0].nodes[index]
        
        // Verify it's expandable
        guard node.isBranch, !node.displayedChildren.isEmpty else {
            print("❌ Provider '\(providerId)' is not expandable or has no children")
            return
        }
        
        print("✅ Found provider '\(node.name)' at index \(index) with \(node.displayedChildren.count) children")
        
        // Expand this category with openedByClick: true
        // This makes it behave like a right-click context menu - stable until boundary cross
        expandCategory(ringLevel: 0, index: index, openedByClick: true)
        
        print("✅ Successfully expanded to '\(node.name)' - now at Ring \(activeRingLevel)")
    }
    
    // MARK: - Direct Category Expansion
    
    func navigateIntoFolder(ringLevel: Int, index: Int) {
        print("📂 navigateIntoFolder called: ringLevel=\(ringLevel), index=\(index)")
        
        if isLoadingFolder {
            print("⏸️ Already loading a folder - ignoring navigation request")
            return
        }
        
        guard rings.indices.contains(ringLevel) else {
            print("❌ Invalid ring level: \(ringLevel)")
            return
        }
        guard rings[ringLevel].nodes.indices.contains(index) else {
            print("❌ Invalid node index: \(index) for ring level: \(ringLevel)")
            return
        }
        
        let node = rings[ringLevel].nodes[index]
        
        // NEW: Launch async task for loading
        Task { @MainActor in
            // Set loading state
            isLoadingFolder = true
            
            let childrenToDisplay: [FunctionNode]
            
            if node.needsDynamicLoading {
                print("🔄 Node '\(node.name)' needs dynamic loading")
                
                guard let providerId = node.providerId else {
                    print("❌ Node '\(node.name)' needs dynamic loading but has no providerId")
                    isLoadingFolder = false
                    return
                }
                
                guard let provider = providers.first(where: { $0.providerId == providerId }) else {
                    print("❌ Provider '\(providerId)' not found")
                    isLoadingFolder = false
                    return
                }
                
                // Load children asynchronously (non-blocking!)
                print("📂 Loading children from provider '\(provider.providerName)'")
                childrenToDisplay = await provider.loadChildren(for: node)
                print("✅ Loaded \(childrenToDisplay.count) children dynamically")
                
            } else {
                childrenToDisplay = node.displayedChildren
            }
            
            guard !childrenToDisplay.isEmpty else {
                print("Cannot navigate into empty folder: \(node.name)")
                isLoadingFolder = false
                return
            }
            
            // 👇 ADD BOUNDS CHECK HERE (inside Task, after async work)
            guard rings.indices.contains(ringLevel),
                  rings[ringLevel].nodes.indices.contains(index) else {
                print("❌ Ring or index out of bounds after async load - rings may have changed")
                isLoadingFolder = false
                return
            }
            
            // Update UI (already on MainActor)
            rings[ringLevel].selectedIndex = index
            rings[ringLevel].hoveredIndex = index
            
            // Mark current ring as collapsed (if it's not Ring 0)
            if ringLevel > 0 {
                rings[ringLevel].isCollapsed = true
                print("📦 Collapsed ring \(ringLevel)")
            }
            
            // Remove any rings beyond this level
            if ringLevel + 1 < rings.count {
                let removed = rings.count - (ringLevel + 1)
                rings.removeSubrange((ringLevel + 1)...)
                print("🗑️ Removed \(removed) ring(s) beyond level \(ringLevel)")
            }
            
            // Add new ring with children
            rings.append(RingState(nodes: childrenToDisplay, isCollapsed: false, openedByClick: true))
            activeRingLevel = ringLevel + 1
            
            // Clear loading state
            isLoadingFolder = false
            
            print("✅ Navigated into folder '\(node.name)' at ring \(ringLevel)")
            print("   Created ring \(ringLevel + 1) with \(childrenToDisplay.count) nodes")
            print("   Active ring is now: \(activeRingLevel)")
        }
    }
    
    func collapseToRing(level: Int) {
        guard level >= 0, level < rings.count else { return }
        
        // Uncollapse the target ring (we're returning to it)
        if level > 0 {  // Don't try to uncollapse Ring 0 (it's never collapsed)
            rings[level].isCollapsed = false
            print("📦 Uncollapsed ring \(level) - returning to normal size")
        }
        
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
