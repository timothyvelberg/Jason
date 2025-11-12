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
    
    // MARK: - Configuration Constants
    
    /// Default angle per item when stacking (Phase 1) - for Ring 0
    private let defaultAngle: Double = 30
    
    /// Maximum arc angle before switching to distribution (Phase 2 trigger) - for Ring 0
    private let maxAngle: Double = 180
    
    /// Minimum angle per item - hard limit for spacing (Phase 3 trigger & hard cap) - for Ring 0
    private let minimalAngle: Double = 20
    
    /// Angle scaling per ring depth (0.0-1.0)
    /// 1.0 = no scaling (same angles for all rings)
    /// 0.9 = each ring uses 90% of previous ring's angles (10% reduction per level)
    /// 0.8 = each ring uses 80% of previous ring's angles (20% reduction per level)
    private let angleScalePerRing: Double = 0.8
    
    // MARK: - Ring 0 Auto-Sizing Constants
    
    /// Optimal angle per item for Ring 0 (comfortable spacing)
    /// When item count causes angles smaller than this, ring will grow to maintain comfort
    private let optimalAnglePerItem: Double = 30.0
    
    /// Minimum angle per item before auto-sizing kicks in
    /// Below this threshold, we calculate optimal ring size
    private let minimumComfortableAngle: Double = 25.0
    
    /// Maximum items that can be displayed (calculated from minimalAngle)
    private var maxItems: Int {
        return Int(360.0 / minimalAngle)
    }
    
    // MARK: - Ring Configuration (Phase 3)
    
    /// Default ring thickness (radius) in points - can be overridden by configuration
    private let defaultRingThickness: CGFloat
    private let centerHoleRadius: CGFloat
    
    /// Default icon size in points - can be overridden by configuration
    private let defaultIconSize: CGFloat
    
    /// Collapsed ring thickness (for breadcrumb trail)
    private let collapsedRingThickness: CGFloat = 32
    
    /// Collapsed icon size (for breadcrumb trail)
    private let collapsedIconSize: CGFloat = 16
    
    // MARK: - Ring State Structure
    
    struct RingState {
        var nodes: [FunctionNode]
        var hoveredIndex: Int?
        var selectedIndex: Int?
        var isCollapsed: Bool = false
        var openedByClick: Bool = false
        
        // Track what this ring represents
        var providerId: String?           // Which provider owns this content
        var contentIdentifier: String?    // For folders: folderPath, for apps: nil
        
        init(nodes: [FunctionNode],
            isCollapsed: Bool = false,
            openedByClick: Bool = false,
            providerId: String? = nil,
            contentIdentifier: String? = nil) {
                self.nodes = nodes
                self.hoveredIndex = nil
                self.selectedIndex = nil
                self.isCollapsed = isCollapsed
                self.openedByClick = openedByClick
                self.providerId = providerId
                self.contentIdentifier = contentIdentifier
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
    
    /// Provider configurations indexed by providerId
    /// Used for display mode transformations and other provider-specific settings
    private var providerConfigurations: [String: ProviderConfiguration] = [:]
    
    private(set) var favoriteAppsProvider: FavoriteAppsProvider?
    
    // MARK: - Cache for Ring Configurations
    
    private var cachedConfigurations: [RingConfiguration] = []
    private var lastRingsHash: Int = 0
    
    // MARK: - Initialization
    
    /// Initialize FunctionManager with ring configuration
    /// - Parameters:
    ///   - ringThickness: Thickness of rings in points
    ///   - iconSize: Size of icons in points
    init(
        ringThickness: CGFloat,
        centerHoleRadius: CGFloat,
        iconSize: CGFloat)
    {
        self.defaultRingThickness = ringThickness
        self.centerHoleRadius = centerHoleRadius
        self.defaultIconSize = iconSize
        
        // Initialize providers and favoriteAppsProvider
        self.providers = []
        let appsProvider = FavoriteAppsProvider()
        self.favoriteAppsProvider = appsProvider
        
        print("🎯 [FunctionManager] Initialized with:")
        print("   - Ring Thickness: \(ringThickness)px")
        print("   - Icon Size: \(iconSize)px")
    }
    
    // MARK: - Helper Types
    
    private struct ParentInfo {
        let leftEdge: Double   // Start angle of parent's slice
        let rightEdge: Double  // End angle of parent's slice
        let node: FunctionNode
        let parentItemAngle: Double
    }
    
    // MARK: - Ring 0 Auto-Sizing
    
    /// Calculate optimal Ring 0 dimensions based on item count
    /// Uses mathematical scaling to maintain comfortable spacing as item count increases
    /// - Parameters:
    ///   - itemCount: Number of items to display in Ring 0
    ///   - baseRadius: Base center hole radius from configuration
    ///   - baseThickness: Base ring thickness from configuration
    /// - Returns: Tuple of (adjusted center radius, adjusted ring thickness)
    private func calculateOptimalRing0Size(
        itemCount: Int,
        baseRadius: CGFloat,
        baseThickness: CGFloat
    ) -> (centerRadius: CGFloat, thickness: CGFloat) {
        
        print("📏 [Ring 0 Auto-Size] CALLED with:")
        print("   Item count: \(itemCount)")
        print("   Base center radius: \(baseRadius)")
        print("   Base thickness: \(baseThickness)")
        
        // Calculate angle per item if we use base dimensions
        let anglePerItem = 360.0 / Double(itemCount)
        
        print("   Calculated angle per item: \(String(format: "%.2f°", anglePerItem))")
        print("   minimumComfortableAngle threshold: \(minimumComfortableAngle)°")
        
        // If angle is comfortable, no adjustment needed
        guard anglePerItem < minimumComfortableAngle else {
            print("   ✅ Angle is comfortable - NO RESIZE NEEDED")
            print("   Returning: centerRadius=\(baseRadius), thickness=\(baseThickness)")
            return (baseRadius, baseThickness)
        }
        
        print("   ⚠️ Angle TOO SMALL - TRIGGERING AUTO-RESIZE")
        
        // Calculate how much we need to grow to achieve optimal spacing
        // We want to maintain optimalAnglePerItem worth of arc length
        
        // Current arc length per item at base radius
        let currentArcLength = baseRadius * (anglePerItem * .pi / 180.0)
        
        // Desired arc length per item for optimal spacing
        let desiredArcLength = baseRadius * (optimalAnglePerItem * .pi / 180.0)
        
        // Scale factor needed to achieve desired arc length
        let scaleFactor = desiredArcLength / currentArcLength
        
        print("   Arc calculations:")
        print("      Current arc length: \(String(format: "%.2f", currentArcLength))")
        print("      Desired arc length: \(String(format: "%.2f", desiredArcLength))")
        print("      Scale factor: \(String(format: "%.2f", scaleFactor))")
        
        // Grow the center hole radius proportionally
        let adjustedRadius = baseRadius * scaleFactor
        
        // Also grow thickness to maintain visual balance
        // Use square root of scale factor for less aggressive growth
        let thicknessScaleFactor = sqrt(scaleFactor)
        let adjustedThickness = baseThickness * thicknessScaleFactor
        
        print("   🎯 RESIZING:")
        print("      Angle: \(String(format: "%.1f°", anglePerItem)) → target: \(String(format: "%.1f°", optimalAnglePerItem))")
        print("      Center radius: \(String(format: "%.0f", baseRadius)) → \(String(format: "%.0f", adjustedRadius)) (+\(String(format: "%.0f", adjustedRadius - baseRadius))px)")
        print("      Thickness: \(String(format: "%.0f", baseThickness)) → \(String(format: "%.0f", adjustedThickness)) (+\(String(format: "%.0f", adjustedThickness - baseThickness))px)")
        
        return (adjustedRadius, adjustedThickness)
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
        print("🔧 [calculateRingConfigurations] START - Processing \(rings.count) ring(s)")
        
        var configs: [RingConfiguration] = []
        let centerHoleRadius = self.centerHoleRadius
        // Use instance properties instead of local variables
        let ringThickness = defaultRingThickness
        let iconSize = defaultIconSize
        let ringMargin: CGFloat = 2
        var currentRadius = centerHoleRadius
        
        print("   Base configuration:")
        print("      centerHoleRadius: \(centerHoleRadius)")
        print("      ringThickness: \(ringThickness)")
        print("      iconSize: \(iconSize)")
        
        for (index, ringState) in rings.enumerated() {
            print("🔧 [Ring \(index)] Processing ring with \(ringState.nodes.count) node(s), collapsed: \(ringState.isCollapsed)")
            
            // Enforce hard cap on number of items (truncate excess nodes)
            let nodes = Array(ringState.nodes.prefix(maxItems))
            if ringState.nodes.count > maxItems {
                print("✂️ [Ring \(index)] Truncated from \(ringState.nodes.count) to \(nodes.count) items (hard cap)")
            }
            
            let sliceConfig: PieSliceConfig
            
            // Determine thickness and icon size for this specific ring
            let thisRingThickness: CGFloat
            let thisIconSize: CGFloat
            
            // Check if ring is collapsed
            if ringState.isCollapsed {
                thisRingThickness = collapsedRingThickness
                thisIconSize = collapsedIconSize
                print("📦 Ring \(index) is COLLAPSED: thickness=\(thisRingThickness), iconSize=\(thisIconSize)")
                
                // Collapsed rings use their existing slice config
                if index == 0 {
                    let itemCount = nodes.count
                    let itemAngle = 360.0 / Double(itemCount)
                    sliceConfig = .fullCircle(itemCount: itemCount, anglePerItem: itemAngle)
                } else {
                    guard let parentInfo = getParentInfo(for: index, configs: configs) else {
                        print("❌ [Ring \(index)] No parent info - using defaults and CONTINUING")
                        let itemCount = nodes.count
                        let itemAngle = 360.0 / Double(itemCount)
                        sliceConfig = .fullCircle(itemCount: itemCount, anglePerItem: itemAngle)
                        configs.append(RingConfiguration(
                            level: index,
                            startRadius: currentRadius,
                            thickness: ringThickness,
                            nodes: nodes,
                            selectedIndex: ringState.hoveredIndex,
                            sliceConfig: sliceConfig,
                            iconSize: iconSize
                        ))
                        currentRadius += ringThickness + ringMargin
                        continue
                    }
                    
                    let itemCount = nodes.count
                    let preferredLayout = parentInfo.node.preferredLayout ?? .partialSlice
                    
                    // Check if node has custom itemAngleSize override
                    let (shouldConvertToFull, anglePerItem, totalAngle): (Bool, Double, Double)
                    if let customAngle = parentInfo.node.itemAngleSize {
                        // Override: use custom angle size
                        let total = Double(itemCount) * customAngle
                        if total >= 360.0 {
                            // Exceeds full circle - convert and distribute
                            let distributed = 360.0 / Double(itemCount)
                            print("📐 Custom Override: \(itemCount) items × \(customAngle)° = \(total)° → Full Circle at \(distributed)° each")
                            (shouldConvertToFull, anglePerItem, totalAngle) = (true, distributed, 360.0)
                        } else {
                            // Use custom angle as-is
                            print("📐 Custom Override: \(itemCount) items × \(customAngle)° = \(total)°")
                            (shouldConvertToFull, anglePerItem, totalAngle) = (false, customAngle, total)
                        }
                    } else {
                        // Use phase-based configuration system
                        (shouldConvertToFull, anglePerItem, totalAngle) = calculateSliceConfiguration(itemCount: itemCount, ringIndex: index)
                    }
                    
                    let positioning = parentInfo.node.slicePositioning ?? .startClockwise
                    
                    if preferredLayout == .fullCircle || shouldConvertToFull {
                        // Full circle layout
                        let startAngle: Double
                        switch positioning {
                        case .center:
                            let centerIndex = Double(itemCount) / 2.0 - 0.5
                            let parentAngle = (parentInfo.leftEdge + parentInfo.rightEdge) / 2
                            startAngle = parentAngle - (centerIndex * anglePerItem) - (anglePerItem / 2)
                        case .startCounterClockwise:
                            startAngle = parentInfo.rightEdge
                        case .startClockwise:
                            startAngle = parentInfo.leftEdge
                        }
                        sliceConfig = .fullCircle(itemCount: itemCount, anglePerItem: anglePerItem, startingAt: startAngle, positioning: positioning)
                    } else {
                        // Partial slice layout
                        let startingAngle: Double
                        switch positioning {
                        case .center:
                            startingAngle = (parentInfo.leftEdge + parentInfo.rightEdge) / 2
                        case .startCounterClockwise:
                            startingAngle = parentInfo.rightEdge
                        case .startClockwise:
                            startingAngle = parentInfo.leftEdge
                        }
                        
                        sliceConfig = .partialSlice(
                            itemCount: itemCount,
                            centeredAt: startingAngle,
                            defaultItemAngle: anglePerItem,
                            positioning: positioning
                        )
                    }
                }
            }else if index == 0 {
                // Ring 0 is always a full circle, shifted so first item is at top (0°)
                let itemCount = nodes.count
                
                print("🔵 [calculateRingConfigurations] Processing Ring 0:")
                print("   Item count: \(itemCount)")
                print("   Base centerHoleRadius: \(centerHoleRadius)")
                print("   Base ringThickness: \(ringThickness)")
                
                // 🆕 Calculate optimal dimensions for Ring 0 based on item count
                let (adjustedCenterRadius, adjustedThickness) = calculateOptimalRing0Size(
                    itemCount: itemCount,
                    baseRadius: centerHoleRadius,
                    baseThickness: ringThickness
                )
                
                print("   Returned from auto-size:")
                print("      adjustedCenterRadius: \(adjustedCenterRadius)")
                print("      adjustedThickness: \(adjustedThickness)")
                
                // Use adjusted dimensions
                thisRingThickness = adjustedThickness
                thisIconSize = iconSize  // Keep icon size consistent
                
                // Update currentRadius to use the adjusted center hole radius
                // This becomes the inner edge (startRadius) of Ring 0
                currentRadius = adjustedCenterRadius
                
                print("   Final Ring 0 config:")
                print("      currentRadius (startRadius): \(currentRadius)")
                print("      thisRingThickness: \(thisRingThickness)")
                print("      thisIconSize: \(thisIconSize)")
                
                // Calculate per-item angles (with custom parentAngleSize support)
                let perItemAngles = calculateRing0Angles(for: nodes)
                
                // Use first item's angle for offset calculation
                let firstItemAngle = perItemAngles.first ?? (360.0 / Double(itemCount))
                let offset = -(firstItemAngle / 2)
                
                // For backwards compatibility, still set itemAngle (used as fallback)
                let averageItemAngle = 360.0 / Double(itemCount)
                
                sliceConfig = .fullCircle(
                    itemCount: itemCount,
                    anglePerItem: averageItemAngle,
                    startingAt: offset,
                    positioning: .startClockwise,
                    perItemAngles: perItemAngles
                )
                
            } else {
                // Ring 1+ - get parent info
                guard let parentInfo = getParentInfo(for: index, configs: configs) else {
                    thisRingThickness = ringThickness  // Use default from config
                    thisIconSize = iconSize  // Use default from config
                    let itemCount = nodes.count
                    let itemAngle = 360.0 / Double(itemCount)
                    sliceConfig = .fullCircle(itemCount: itemCount, anglePerItem: itemAngle)
                    configs.append(RingConfiguration(
                        level: index,
                        startRadius: currentRadius,
                        thickness: thisRingThickness,
                        nodes: nodes,
                        selectedIndex: ringState.hoveredIndex,
                        sliceConfig: sliceConfig,
                        iconSize: thisIconSize
                    ))
                    currentRadius += thisRingThickness + ringMargin
                    continue
                }
                
                // Use parent's specified sizes or defaults
                thisRingThickness = parentInfo.node.childRingThickness ?? ringThickness
                thisIconSize = parentInfo.node.childIconSize ?? iconSize
                
                let itemCount = nodes.count
                let preferredLayout = parentInfo.node.preferredLayout ?? .partialSlice
                
                // Check if node has custom itemAngleSize override
                let (shouldConvertToFull, anglePerItem, totalAngle): (Bool, Double, Double)
                if let customAngle = parentInfo.node.itemAngleSize {
                    // Override: use custom angle size
                    let total = Double(itemCount) * customAngle
                    if total >= 360.0 {
                        // Exceeds full circle - convert and distribute
                        let distributed = 360.0 / Double(itemCount)
                        print("📐 Custom Override: \(itemCount) items × \(customAngle)° = \(total)° → Full Circle at \(distributed)° each")
                        (shouldConvertToFull, anglePerItem, totalAngle) = (true, distributed, 360.0)
                    } else {
                        // Use custom angle as-is
                        print("📐 Custom Override: \(itemCount) items × \(customAngle)° = \(total)°")
                        (shouldConvertToFull, anglePerItem, totalAngle) = (false, customAngle, total)
                    }
                } else {
                    // Use phase-based configuration system
                    (shouldConvertToFull, anglePerItem, totalAngle) = calculateSliceConfiguration(itemCount: itemCount, ringIndex: index)
                }
                
                let positioning = parentInfo.node.slicePositioning ?? .startClockwise
                
                if preferredLayout == .fullCircle || shouldConvertToFull {
                    // Full circle layout
                    let startAngle: Double
                    switch positioning {
                    case .center:
                        let centerIndex = Double(itemCount) / 2.0 - 0.5
                        let parentAngle = (parentInfo.leftEdge + parentInfo.rightEdge) / 2
                        startAngle = parentAngle - (centerIndex * anglePerItem) - (anglePerItem / 2)
                    case .startCounterClockwise:
                        startAngle = parentInfo.rightEdge
                    case .startClockwise:
                        startAngle = parentInfo.leftEdge
                    }
                    sliceConfig = .fullCircle(itemCount: itemCount, anglePerItem: anglePerItem, startingAt: startAngle, positioning: positioning)
                } else {
                    // Partial slice layout
                    let startingAngle: Double
                    switch positioning {
                    case .center:
                        startingAngle = (parentInfo.leftEdge + parentInfo.rightEdge) / 2
                    case .startCounterClockwise:
                        startingAngle = parentInfo.rightEdge
                    case .startClockwise:
                        startingAngle = parentInfo.leftEdge
                    }
                    
                    sliceConfig = .partialSlice(
                        itemCount: itemCount,
                        centeredAt: startingAngle,
                        defaultItemAngle: anglePerItem,
                        positioning: positioning
                    )
                }
            }
            
            configs.append(RingConfiguration(
                level: index,
                startRadius: currentRadius,
                thickness: thisRingThickness,
                nodes: nodes,
                selectedIndex: ringState.hoveredIndex,
                sliceConfig: sliceConfig,
                iconSize: thisIconSize
            ))
            currentRadius += thisRingThickness + ringMargin
        }
        
        print("🔧 [calculateRingConfigurations] COMPLETE - Generated \(configs.count) ring configuration(s)")
        for (idx, config) in configs.enumerated() {
            print("   Ring \(idx): startRadius=\(String(format: "%.0f", config.startRadius)), thickness=\(String(format: "%.0f", config.thickness)), nodes=\(config.nodes.count)")
        }
        
        return configs
    }
    
    /// Calculate configuration for a partial slice based on item count
    /// Returns: (shouldConvertToFullCircle, anglePerItem, totalAngle)
    private func calculateSliceConfiguration(itemCount: Int, ringIndex: Int) -> (shouldConvertToFullCircle: Bool, anglePerItem: Double, totalAngle: Double) {
        // Apply scaling based on ring depth
        let scaleFactor = pow(angleScalePerRing, Double(ringIndex - 1))
        let scaledDefaultAngle = defaultAngle * scaleFactor
        let scaledMaxAngle = maxAngle * scaleFactor
        let scaledMinimalAngle = minimalAngle * scaleFactor
        
        // Enforce hard cap
        let cappedCount = min(itemCount, maxItems)
        
        // Phase 1: Stacking at defaultAngle
        // Continue until total would exceed maxAngle
        let phase1Threshold = Int(scaledMaxAngle / scaledDefaultAngle)
        
        if cappedCount <= phase1Threshold {
            // Phase 1: Stack at defaultAngle
            let totalAngle = Double(cappedCount) * scaledDefaultAngle
            return (false, scaledDefaultAngle, totalAngle)
        }
        
        // Phase 2: Distribute over maxAngle
        // Continue until anglePerItem would drop below minimalAngle
        let phase2Threshold = Int(scaledMaxAngle / scaledMinimalAngle)
        
        if cappedCount <= phase2Threshold {
            // Phase 2: Distribute over maxAngle
            let anglePerItem = scaledMaxAngle / Double(cappedCount)
            return (false, anglePerItem, scaledMaxAngle)
        }
        
        // Phase 3: Stack at minimalAngle
        // Continue until total reaches 360°
        let totalAngle = Double(cappedCount) * scaledMinimalAngle
        
        // If we're close to 360° (within one item's worth), convert to full circle
        let fullCircleThreshold = 360.0 - scaledMinimalAngle
        
        if totalAngle >= fullCircleThreshold {
            // Close enough to 360° - convert to full circle and distribute evenly
            let anglePerItem = 360.0 / Double(cappedCount)
            return (true, anglePerItem, 360.0)
        }
        
        if totalAngle < 360.0 {
            // Phase 3: Stack at minimalAngle
            return (false, scaledMinimalAngle, totalAngle)
        }
        
        // Phase 4: Full circle (total >= 360°)
        let anglePerItem = 360.0 / Double(cappedCount)
        return (true, anglePerItem, 360.0)
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
                // Parent is full circle - handle variable angles
                let parentStartAngle = parentSliceConfig.startAngle
                
                // Check if parent has variable angles
                if let perItemAngles = parentSliceConfig.perItemAngles,
                   parentSelectedIndex < perItemAngles.count {
                    // Variable angles: calculate cumulative position
                    var cumulativeAngle: Double = 0
                    for i in 0..<parentSelectedIndex {
                        cumulativeAngle += perItemAngles[i]
                    }
                    
                    leftEdge = parentStartAngle + cumulativeAngle
                    parentItemAngle = perItemAngles[parentSelectedIndex]
                    rightEdge = leftEdge + parentItemAngle
                } else {
                    // Uniform angles (original logic)
                    parentItemAngle = 360.0 / Double(parentRing.nodes.count)
                    leftEdge = parentStartAngle + (Double(parentSelectedIndex) * parentItemAngle)
                    rightEdge = leftEdge + parentItemAngle
                }
            }else {
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
        return ParentInfo(leftEdge: leftEdge, rightEdge: rightEdge, node: parentNode, parentItemAngle: parentItemAngle)
    }
    
    /// Calculate per-item angles for Ring 0 with custom parentAngleSize support
    private func calculateRing0Angles(for nodes: [FunctionNode]) -> [Double] {
        // Check if any nodes have custom parentAngleSize
        let customSizes = nodes.map { $0.parentAngleSize }
        let hasCustomSizes = customSizes.contains(where: { $0 != nil })
        
        // If no custom sizes, use uniform distribution
        guard hasCustomSizes else {
            let uniformAngle = 360.0 / Double(nodes.count)
            return Array(repeating: uniformAngle, count: nodes.count)
        }
        
        // Calculate angles with custom sizes
        var totalCustomAngle: CGFloat = 0
        var customCount = 0
        
        for size in customSizes {
            if let size = size {
                totalCustomAngle += size
                customCount += 1
            }
        }
        
        // Validate: custom sizes must not exceed 360°
        if totalCustomAngle > 360 {
            print("⚠️ [Ring 0 Angles] Custom sizes total \(totalCustomAngle)° exceeds 360°. Falling back to equal distribution.")
            let uniformAngle = 360.0 / Double(nodes.count)
            return Array(repeating: uniformAngle, count: nodes.count)
        }
        
        // Calculate remaining space for auto-sized items
        let remainingAngle = 360.0 - totalCustomAngle
        let autoSizedCount = nodes.count - customCount
        let autoAngle = autoSizedCount > 0 ? remainingAngle / CGFloat(autoSizedCount) : 0
        
        // Warn if auto-sized items are very small
        if autoAngle > 0 && autoAngle < 15 {
            print("⚠️ [Ring 0 Angles] Auto-sized items are only \(autoAngle)° each. May be hard to select.")
        }
        
        // Build final angle array
        var angles: [Double] = []
        for node in nodes {
            if let customSize = node.parentAngleSize {
                angles.append(Double(customSize))
            } else {
                angles.append(Double(autoAngle))
            }
        }
        
        print("📐 [Ring 0 Angles] Calculated: \(angles.map { String(format: "%.1f°", $0) }.joined(separator: ", "))")
        
        return angles
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
    
    // MARK: - Display Mode Transformation
    
    /// Transform provider output based on display mode configuration
    /// - Only applies to .category nodes - extracts children if mode is .direct
    /// - Other node types (.action, .file, .folder, .app) are unchanged
    /// - Parameters:
    ///   - nodes: The nodes returned by the provider
    ///   - providerId: The provider's ID to look up its configuration
    /// - Returns: Transformed nodes based on display mode
    private func applyDisplayMode(
        _ nodes: [FunctionNode],
        providerId: String
    ) -> [FunctionNode] {
        
        // Look up provider configuration
        guard let providerConfig = providerConfigurations[providerId] else {
            // No configuration found - default to parent mode (no transformation)
            return nodes
        }
        
        // Get effective display mode (defaults to parent)
        let displayMode = providerConfig.effectiveDisplayMode
        
        // If parent mode, return nodes unchanged
        guard displayMode == .direct else {
            return nodes
        }
        
        // Direct mode: Extract children from category nodes
        let transformedNodes = nodes.flatMap { node -> [FunctionNode] in
            // Only apply to category types
            guard node.type == .category else {
                return [node]  // Non-categories pass through unchanged
            }
            
            // Extract children from category
            if let children = node.children, !children.isEmpty {
                // Return children directly, discarding category wrapper
                print("🔄 [DisplayMode] Extracting \(children.count) children from category '\(node.name)' (provider: \(providerId))")
                return children
            } else {
                // Empty category - log warning and pass through
                print("⚠️ [DisplayMode] Category '\(node.name)' has no children in direct mode (provider: \(providerId))")
                return [node]  // Keep the category rather than showing nothing
            }
        }
        
        return transformedNodes
    }
    
    // MARK: - Provider Management
    
    func registerProvider(_ provider: FunctionProvider, configuration: ProviderConfiguration? = nil) {
        providers.append(provider)
        
        // Store configuration if provided
        if let config = configuration {
            providerConfigurations[provider.providerId] = config
            print("📦 Registered provider: \(provider.providerName) (displayMode: \(config.effectiveDisplayMode))")
        } else {
            print("📦 Registered provider: \(provider.providerName)")
        }
    }
    
    func removeProvider(withId id: String) {
        providers.removeAll { $0.providerId == id }
        providerConfigurations.removeValue(forKey: id)
        print("🗑️ Removed provider: \(id)")
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
        
        // 🆕 Ring 0 has no single providerId (it's a mix of all providers)
        rings.append(RingState(
            nodes: currentNodes,
            providerId: nil,
            contentIdentifier: nil
        ))
        
        // If there's a selected category in ring 0, show its children in ring 1
        if let ring0 = rings.first,
           let selectedIndex = ring0.selectedIndex,
           selectedIndex < ring0.nodes.count {
            let selectedNode = ring0.nodes[selectedIndex]
            if selectedNode.isBranch, let children = selectedNode.children, !children.isEmpty {
                // 🆕 Ring 1 gets context from the selected Ring 0 node
                let providerId = selectedNode.providerId
                let contentIdentifier = selectedNode.metadata?["folderURL"] as? String
                
                rings.append(RingState(
                    nodes: children,
                    providerId: providerId,
                    contentIdentifier: contentIdentifier
                ))
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
        
        // Early return if already hovering this node
        if rings[ringLevel].hoveredIndex == index {
            return
        }
        
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
        
        // 🆕 Get context from the node
        let providerId = node.providerId
        let contentIdentifier = node.metadata?["folderURL"] as? String
        
        // Add new ring with displayed children and context tracking
        rings.append(RingState(
            nodes: displayedChildren,
            isCollapsed: false,
            openedByClick: openedByClick,
            providerId: providerId,
            contentIdentifier: contentIdentifier
        ))
        activeRingLevel = ringLevel + 1
        
        print("✅ Expanded category '\(node.name)' at ring \(ringLevel), created ring \(ringLevel + 1) with \(displayedChildren.count) nodes (providerId: \(providerId ?? "nil"), contentId: \(contentIdentifier ?? "nil"))")
    }

    // MARK: - Direct Category Expansion
    
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
            let providerId = node.providerId
            let contentIdentifier = node.metadata?["folderURL"] as? String
            rings.append(RingState(
                nodes: childrenToDisplay,
                isCollapsed: false,
                openedByClick: true,
                providerId: providerId,
                contentIdentifier: contentIdentifier
            ))
            
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
        
        // Collect functions from all providers with display mode transformation
        rootNodes = providers.flatMap { provider in
            let providerNodes = provider.provideFunctions()
            
            // Apply display mode transformation based on provider configuration
            let transformedNodes = applyDisplayMode(providerNodes, providerId: provider.providerId)
            
            return transformedNodes
        }
        
        rebuildRings()
        print("✅ Loaded \(rootNodes.count) total root nodes from \(providers.count) provider(s)")
    }
    
    // MARK: - Surgical Ring Updates

    /// Update a specific ring with fresh data from its provider
    /// Preserves navigation state and only updates the affected ring
    func updateRing(providerId: String, contentIdentifier: String? = nil) {
        print("🔄 [updateRing] Looking for ring with providerId: \(providerId), contentId: \(contentIdentifier ?? "nil")")
        
        // Find the provider
        guard let provider = providers.first(where: { $0.providerId == providerId }) else {
            print("❌ Provider '\(providerId)' not found")
            return
        }
        
        // Find the ring(s) that match this context
        for (level, ring) in rings.enumerated() {
            // Check if provider matches at ring level OR node level (for mixed rings)
            let providerMatches: Bool
            if ring.providerId == providerId {
                providerMatches = true
            } else if ring.providerId == nil {
                // 🆕 For mixed rings, check if any nodes belong to this provider
                // BUT: Only match actual content nodes, not category wrappers
                providerMatches = ring.nodes.contains { node in
                    node.providerId == providerId && node.type != .category
                }
            } else {
                providerMatches = false
            }
            
            let contentMatches = contentIdentifier == nil || ring.contentIdentifier == contentIdentifier
            
            if providerMatches && contentMatches {
                print("✅ Found matching ring at level \(level)")
                
                // 🆕 CRITICAL: Close any child rings BEFORE updating
                // This prevents orphaned context menus with invalid parent references
                if level + 1 < rings.count {
                    print("🗑️ Closing \(rings.count - level - 1) child ring(s) before update")
                    collapseToRing(level: level)
                }
                
                // Refresh the provider
                provider.refresh()
                
                // Get fresh nodes
                let freshNodes: [FunctionNode]
                
                if level == 0 {
                    // Ring 0: Mixed providers - preserve provider order during updates
                    
                    let providerNodes = provider.provideFunctions()
                    let updatedRootNodes = applyDisplayMode(providerNodes, providerId: providerId)
                    
                    // Preserve provider registration order
                    let providerOrder = providers.map { $0.providerId }
                    
                    var newRing0Nodes: [FunctionNode] = []
                    
                    for orderedProviderId in providerOrder {
                        if orderedProviderId == providerId {
                            // Use fresh nodes for updated provider
                            newRing0Nodes.append(contentsOf: updatedRootNodes)
                        } else {
                            // Keep existing nodes from unchanged providers
                            let existingNodes = rings[0].nodes.filter { $0.providerId == orderedProviderId }
                            newRing0Nodes.append(contentsOf: existingNodes)
                        }
                    }
                    
                    rings[0].nodes = newRing0Nodes
                    
                    // Clear hover/selection state after updating nodes
                    rings[0].hoveredIndex = nil
                    rings[0].selectedIndex = nil
                    
                    print("✅ Updated Ring 0: replaced nodes from provider '\(providerId)'")
                }else {
                    // Ring 1+: Get children from FRESH parent node
                    guard level > 0, level - 1 < rings.count else {
                        print("❌ Cannot find parent ring for level \(level)")
                        continue
                    }
                    
                    let parentRing = rings[level - 1]
                    guard let selectedIndex = parentRing.selectedIndex,
                          selectedIndex < parentRing.nodes.count else {
                        print("❌ No selected node in parent ring")
                        continue
                    }
                    
                    // 🆕 Get FRESH parent node after provider refresh
                    let freshRootNodes = provider.provideFunctions()
                    
                    // If parent is Ring 0, find the fresh root node
                    if level == 1 && !freshRootNodes.isEmpty {
                        let freshParentNode = freshRootNodes[0]  // Provider returns one root node
                        
                        // 🆕 UPDATE Ring 0's node with fresh data to prevent stale cache
                        if let parentIndex = rings[0].nodes.firstIndex(where: { $0.providerId == providerId }) {
                            print("🔄 Updating Ring 0's '\(freshParentNode.name)' node with fresh children")
                            rings[0].nodes[parentIndex] = freshParentNode
                        }
                        
                        // For dynamic loading (folders)
                        if freshParentNode.needsDynamicLoading {
                            Task { @MainActor in
                                let loadedNodes = await provider.loadChildren(for: freshParentNode)
                                
                                // Check if ring still exists and matches
                                guard level < self.rings.count,
                                      self.rings[level].providerId == providerId,
                                      self.rings[level].contentIdentifier == contentIdentifier else {
                                    print("⚠️ Ring changed during async load - ignoring update")
                                    return
                                }
                                
                                self.rings[level].nodes = loadedNodes
                                
                                // 🆕 CRITICAL: Clear hover/selection state after updating nodes
                                self.rings[level].hoveredIndex = nil
                                self.rings[level].selectedIndex = nil
                                
                                print("✅ Updated Ring \(level) with \(loadedNodes.count) dynamically loaded nodes")
                            }
                        } else {
                            // For static children (apps) - use FRESH displayedChildren
                            freshNodes = freshParentNode.displayedChildren
                            rings[level].nodes = freshNodes
                            
                            // 🆕 CRITICAL: Clear hover/selection state after updating nodes
                            rings[level].hoveredIndex = nil
                            rings[level].selectedIndex = nil
                            
                            print("✅ Updated Ring \(level) with \(freshNodes.count) nodes")
                        }
                    } else {
                        print("⚠️ Cannot get fresh parent node for Ring \(level)")
                    }
                }
                
                // Only update the first matching ring
                return
            }
        }
        
        print("⚠️ No matching ring found for providerId: \(providerId), contentId: \(contentIdentifier ?? "nil")")
    }
}
