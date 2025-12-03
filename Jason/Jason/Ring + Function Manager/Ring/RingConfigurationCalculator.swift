//
//  RingConfigurationCalculator.swift
//  Jason
//
//  Created by Timothy Velberg on 29/11/2025.
//

import Foundation

/// Calculates ring configurations including sizing, angles, and slice layouts
class RingConfigurationCalculator {
    
    // MARK: - Configuration Constants
    
    /// Default angle per item when stacking (Phase 1) - for Ring 0
    private let defaultAngle: Double = 30
    
    /// Maximum arc angle before switching to distribution (Phase 2 trigger) - for Ring 0
    private let maxAngle: Double = 180
    
    /// Minimum angle per item - hard limit for spacing (Phase 3 trigger & hard cap) - for Ring 0
    private let minimalAngle: Double = 15  // 24 items max (360° / 15° = 24)
    
    /// Angle scaling per ring depth (0.0-1.0)
    private let angleScalePerRing: Double = 0.8
    
    // MARK: - Ring 0 Auto-Sizing Constants
    
    /// Optimal angle per item for Ring 0 (comfortable spacing)
    private let optimalAnglePerItem: Double = 30.0
    
    /// Minimum angle per item before auto-sizing kicks in
    private let minimumComfortableAngle: Double = 25.0
    
    /// Maximum items that can be displayed (calculated from minimalAngle)
    var maxItems: Int {
        return Int(360.0 / minimalAngle)
    }
    
    // MARK: - Ring Configuration
    
    private let defaultRingThickness: CGFloat
    private let centerHoleRadius: CGFloat
    private let defaultIconSize: CGFloat
    private let startAngle: CGFloat
    
    /// Collapsed ring thickness (for breadcrumb trail)
    private let collapsedRingThickness: CGFloat = 32
    
    /// Collapsed icon size (for breadcrumb trail)
    private let collapsedIconSize: CGFloat = 16
    
    // MARK: - Initialization
    
    init(
        ringThickness: CGFloat,
        centerHoleRadius: CGFloat,
        iconSize: CGFloat,
        startAngle: CGFloat = 0.0
    ) {
        self.defaultRingThickness = ringThickness
        self.centerHoleRadius = centerHoleRadius
        self.defaultIconSize = iconSize
        self.startAngle = startAngle
    }
    
    // MARK: - Helper Types
    
    struct ParentInfo {
        let leftEdge: Double
        let rightEdge: Double
        let node: FunctionNode
        let parentItemAngle: Double
    }
    
    // MARK: - Ring 0 Auto-Sizing
    
    /// Calculate optimal Ring 0 dimensions based on item count
    func calculateOptimalRing0Size(
        itemCount: Int,
        baseRadius: CGFloat,
        baseThickness: CGFloat
    ) -> (centerRadius: CGFloat, thickness: CGFloat) {
        
        print("📏 [Ring 0 Auto-Size] CALLED with:")
        print("   Item count: \(itemCount)")
        print("   Base center radius: \(baseRadius)")
        print("   Base thickness: \(baseThickness)")
        
        let anglePerItem = 360.0 / Double(itemCount)
        
        print("   Calculated angle per item: \(String(format: "%.2f°", anglePerItem))")
        print("   minimumComfortableAngle threshold: \(minimumComfortableAngle)°")
        
        guard anglePerItem < minimumComfortableAngle else {
            print("   ✅ Angle is comfortable - NO RESIZE NEEDED")
            print("   Returning: centerRadius=\(baseRadius), thickness=\(baseThickness)")
            return (baseRadius, baseThickness)
        }
        
        print("   ⚠️ Angle TOO SMALL - TRIGGERING AUTO-RESIZE")
        
        let currentArcLength = baseRadius * (anglePerItem * .pi / 180.0)
        let desiredArcLength = baseRadius * (optimalAnglePerItem * .pi / 180.0)
        let scaleFactor = desiredArcLength / currentArcLength
        
        print("   Arc calculations:")
        print("      Current arc length: \(String(format: "%.2f", currentArcLength))")
        print("      Desired arc length: \(String(format: "%.2f", desiredArcLength))")
        print("      Scale factor: \(String(format: "%.2f", scaleFactor))")
        
        let adjustedRadius = baseRadius * scaleFactor
        let thicknessScaleFactor = sqrt(scaleFactor)
        let adjustedThickness = baseThickness * thicknessScaleFactor
        
        print("   🎯 RESIZING:")
        print("      Angle: \(String(format: "%.1f°", anglePerItem)) → target: \(String(format: "%.1f°", optimalAnglePerItem))")
        print("      Center radius: \(String(format: "%.0f", baseRadius)) → \(String(format: "%.0f", adjustedRadius)) (+\(String(format: "%.0f", adjustedRadius - baseRadius))px)")
        print("      Thickness: \(String(format: "%.0f", baseThickness)) → \(String(format: "%.0f", adjustedThickness)) (+\(String(format: "%.0f", adjustedThickness - baseThickness))px)")
        
        return (adjustedRadius, adjustedThickness)
    }
    
    // MARK: - Main Configuration Calculator
    
    /// Calculate configurations for all rings
    func calculateRingConfigurations(rings: [RingState]) -> [RingConfiguration] {
        var configs: [RingConfiguration] = []
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
            
            let nodes = Array(ringState.nodes.prefix(maxItems))
            if ringState.nodes.count > maxItems {
                print("✂️ [Ring \(index)] Truncated from \(ringState.nodes.count) to \(nodes.count) items (hard cap)")
            }
            
            let sliceConfig: PieSliceConfig
            let thisRingThickness: CGFloat
            let thisIconSize: CGFloat
            
            if ringState.isCollapsed {
                thisRingThickness = collapsedRingThickness
                thisIconSize = collapsedIconSize
                print("📦 Ring \(index) is COLLAPSED: thickness=\(thisRingThickness), iconSize=\(thisIconSize)")
                
                if let existingSliceConfig = ringState.sliceConfig,
                   existingSliceConfig.itemCount == nodes.count {
                    print("     Collapsed Ring \(index) has existing sliceConfig - preserving it (isFullCircle: \(existingSliceConfig.isFullCircle))")
                    sliceConfig = existingSliceConfig
                } else {
                    if let existingSliceConfig = ringState.sliceConfig {
                        print("   🔄 Collapsed Ring \(index) item count changed (\(existingSliceConfig.itemCount) → \(nodes.count)) - recalculating...")
                    } else {
                        print("   🆕 Collapsed Ring \(index) needs new sliceConfig - calculating...")
                    }
                    sliceConfig = calculateCollapsedRingSliceConfig(
                        index: index,
                        nodes: nodes,
                        rings: rings,
                        configs: configs,
                        ringThickness: ringThickness,
                        iconSize: iconSize,
                        currentRadius: &currentRadius,
                        ringMargin: ringMargin
                    )
                }
                
                
            } else if index == 0 {
                let itemCount = nodes.count
                
                print("🔵 [calculateRingConfigurations] Processing Ring 0:")
                print("   Item count: \(itemCount)")
                print("   Base centerHoleRadius: \(centerHoleRadius)")
                print("   Base ringThickness: \(ringThickness)")
                
                let (adjustedCenterRadius, adjustedThickness) = calculateOptimalRing0Size(
                    itemCount: itemCount,
                    baseRadius: centerHoleRadius,
                    baseThickness: ringThickness
                )
                
                print("   Returned from auto-size:")
                print("      adjustedCenterRadius: \(adjustedCenterRadius)")
                print("      adjustedThickness: \(adjustedThickness)")
                
                thisRingThickness = adjustedThickness
                thisIconSize = iconSize
                currentRadius = adjustedCenterRadius
                
                print("   Final Ring 0 config:")
                print("      currentRadius (startRadius): \(currentRadius)")
                print("      thisRingThickness: \(thisRingThickness)")
                print("      thisIconSize: \(thisIconSize)")
                
                let perItemAngles = calculateRing0Angles(for: nodes)
                let firstItemAngle = perItemAngles.first ?? (360.0 / Double(itemCount))
                let offset = Double(startAngle) - (firstItemAngle / 2)
                let averageItemAngle = 360.0 / Double(itemCount)
                
                sliceConfig = .fullCircle(
                    itemCount: itemCount,
                    anglePerItem: averageItemAngle,
                    startingAt: offset,
                    positioning: .startClockwise,
                    perItemAngles: perItemAngles
                )
            } else {
                guard let parentInfo = getParentInfo(for: index, rings: rings, configs: configs) else {
                    thisRingThickness = ringThickness
                    thisIconSize = iconSize
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
                
                thisRingThickness = parentInfo.node.childRingThickness ?? ringThickness
                thisIconSize = parentInfo.node.childIconSize ?? iconSize
                
                if let existingSliceConfig = ringState.sliceConfig,
                   existingSliceConfig.itemCount == nodes.count {
                    print("   ♻️  Ring \(index) has existing sliceConfig - preserving it (isFullCircle: \(existingSliceConfig.isFullCircle))")
                    sliceConfig = existingSliceConfig
                } else {
                    if let existingSliceConfig = ringState.sliceConfig {
                        print("   🔄 Ring \(index) item count changed (\(existingSliceConfig.itemCount) → \(nodes.count)) - recalculating...")
                    } else {
                        print("   🆕 Ring \(index) needs new sliceConfig - calculating...")
                    }
                    sliceConfig = calculateNewRingSliceConfig(
                        index: index,
                        nodes: nodes,
                        parentInfo: parentInfo
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
    
    // MARK: - Slice Configuration Helpers
    
    private func calculateCollapsedRingSliceConfig(
        index: Int,
        nodes: [FunctionNode],
        rings: [RingState],
        configs: [RingConfiguration],
        ringThickness: CGFloat,
        iconSize: CGFloat,
        currentRadius: inout CGFloat,
        ringMargin: CGFloat
    ) -> PieSliceConfig {
        if index == 0 {
            let itemCount = nodes.count
            let itemAngle = 360.0 / Double(itemCount)
            return .fullCircle(itemCount: itemCount, anglePerItem: itemAngle)
        }
        
        guard let parentInfo = getParentInfo(for: index, rings: rings, configs: configs) else {
            print("❌ [Ring \(index)] No parent info - using defaults and CONTINUING")
            let itemCount = nodes.count
            let itemAngle = 360.0 / Double(itemCount)
            return .fullCircle(itemCount: itemCount, anglePerItem: itemAngle)
        }
        
        let itemCount = nodes.count
        let preferredLayout = parentInfo.node.preferredLayout ?? .partialSlice
        
        let perItemAngles = calculateChildRingAngles(
            for: nodes,
            parentNode: parentInfo.node,
            ringIndex: index
        )
        
        let totalAngle = perItemAngles.reduce(0, +)
        let shouldConvertToFull = totalAngle >= 360.0
        let averageAngle = totalAngle / Double(itemCount)
        
        if shouldConvertToFull {
            print("📐 Ring \(index): Total angle \(String(format: "%.1f", totalAngle))° ≥ 360° → Converting to Full Circle")
        } else {
            print("📐 Ring \(index): Partial slice with \(String(format: "%.1f", totalAngle))° total")
        }
        
        let positioning = parentInfo.node.slicePositioning ?? .startClockwise
        
        if preferredLayout == .fullCircle || shouldConvertToFull {
            let startAngle: Double
            switch positioning {
            case .center:
                let halfTotalAngle = totalAngle / 2.0
                let parentAngle = (parentInfo.leftEdge + parentInfo.rightEdge) / 2
                startAngle = parentAngle - halfTotalAngle
            case .startCounterClockwise:
                startAngle = parentInfo.rightEdge
            case .startClockwise:
                startAngle = parentInfo.leftEdge
            }
            
            return .fullCircle(
                itemCount: itemCount,
                anglePerItem: averageAngle,
                startingAt: startAngle,
                positioning: positioning,
                perItemAngles: perItemAngles
            )
        } else {
            let startingAngle: Double
            switch positioning {
            case .center:
                startingAngle = (parentInfo.leftEdge + parentInfo.rightEdge) / 2
            case .startCounterClockwise:
                startingAngle = parentInfo.rightEdge
            case .startClockwise:
                startingAngle = parentInfo.leftEdge
            }
            
            return .partialSlice(
                itemCount: itemCount,
                centeredAt: startingAngle,
                defaultItemAngle: averageAngle,
                positioning: positioning,
                perItemAngles: perItemAngles
            )
        }
    }
    
    private func calculateNewRingSliceConfig(
        index: Int,
        nodes: [FunctionNode],
        parentInfo: ParentInfo
    ) -> PieSliceConfig {
        let itemCount = nodes.count
        let preferredLayout = parentInfo.node.preferredLayout ?? .partialSlice
        
        let (shouldConvertToFull, anglePerItem, _): (Bool, Double, Double)
        if let customAngle = parentInfo.node.itemAngleSize {
            let total = Double(itemCount) * customAngle
            if total >= 360.0 {
                let distributed = 360.0 / Double(itemCount)
                print("📐 Custom Override: \(itemCount) items × \(customAngle)° = \(total)° → Full Circle at \(distributed)° each")
                (shouldConvertToFull, anglePerItem, _) = (true, distributed, 360.0)
            } else {
                print("📐 Custom Override: \(itemCount) items × \(customAngle)° = \(total)°")
                (shouldConvertToFull, anglePerItem, _) = (false, customAngle, total)
            }
        } else {
            (shouldConvertToFull, anglePerItem, _) = calculateSliceConfiguration(itemCount: itemCount, ringIndex: index)
        }
        
        let positioning = parentInfo.node.slicePositioning ?? .startClockwise
        
        if preferredLayout == .fullCircle || shouldConvertToFull {
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
            return .fullCircle(itemCount: itemCount, anglePerItem: anglePerItem, startingAt: startAngle, positioning: positioning)
        } else {
            let startingAngle: Double
            switch positioning {
            case .center:
                startingAngle = (parentInfo.leftEdge + parentInfo.rightEdge) / 2
            case .startCounterClockwise:
                startingAngle = parentInfo.rightEdge
            case .startClockwise:
                startingAngle = parentInfo.leftEdge
            }
            
            return .partialSlice(
                itemCount: itemCount,
                centeredAt: startingAngle,
                defaultItemAngle: anglePerItem,
                positioning: positioning
            )
        }
    }
    
    /// Calculate configuration for a partial slice based on item count
    func calculateSliceConfiguration(itemCount: Int, ringIndex: Int) -> (shouldConvertToFullCircle: Bool, anglePerItem: Double, totalAngle: Double) {
        let scaleFactor = pow(angleScalePerRing, Double(ringIndex - 1))
        let scaledDefaultAngle = defaultAngle * scaleFactor
        let scaledMaxAngle = maxAngle * scaleFactor
        let scaledMinimalAngle = minimalAngle * scaleFactor
        
        let cappedCount = min(itemCount, maxItems)
        
        let phase1Threshold = Int(scaledMaxAngle / scaledDefaultAngle)
        
        if cappedCount <= phase1Threshold {
            let totalAngle = Double(cappedCount) * scaledDefaultAngle
            return (false, scaledDefaultAngle, totalAngle)
        }
        
        let phase2Threshold = Int(scaledMaxAngle / scaledMinimalAngle)
        
        if cappedCount <= phase2Threshold {
            let anglePerItem = scaledMaxAngle / Double(cappedCount)
            return (false, anglePerItem, scaledMaxAngle)
        }
        
        let totalAngle = Double(cappedCount) * scaledMinimalAngle
        let fullCircleThreshold = 360.0 - scaledMinimalAngle
        
        if totalAngle >= fullCircleThreshold {
            let anglePerItem = 360.0 / Double(cappedCount)
            return (true, anglePerItem, 360.0)
        }
        
        if totalAngle < 360.0 {
            return (false, scaledMinimalAngle, totalAngle)
        }
        
        let anglePerItem = 360.0 / Double(cappedCount)
        return (true, anglePerItem, 360.0)
    }
    
    // MARK: - Parent Info
    
    func getParentInfo(for ringIndex: Int, rings: [RingState], configs: [RingConfiguration]) -> ParentInfo? {
        guard ringIndex > 0, rings.indices.contains(ringIndex - 1) else {
            return nil
        }
        
        let parentRing = rings[ringIndex - 1]
        guard let parentSelectedIndex = parentRing.selectedIndex,
              parentSelectedIndex < parentRing.nodes.count else {
            return nil
        }
        
        let parentNode = parentRing.nodes[parentSelectedIndex]
        
        let leftEdge: Double
        let rightEdge: Double
        let parentItemAngle: Double
        
        if ringIndex - 1 < configs.count {
            let parentSliceConfig = configs[ringIndex - 1].sliceConfig
            
            if parentSliceConfig.isFullCircle {
                let parentStartAngle = parentSliceConfig.startAngle
                
                if let perItemAngles = parentSliceConfig.perItemAngles,
                   parentSelectedIndex < perItemAngles.count {
                    var cumulativeAngle: Double = 0
                    for i in 0..<parentSelectedIndex {
                        cumulativeAngle += perItemAngles[i]
                    }
                    
                    leftEdge = parentStartAngle + cumulativeAngle
                    parentItemAngle = perItemAngles[parentSelectedIndex]
                    rightEdge = leftEdge + parentItemAngle
                } else {
                    parentItemAngle = 360.0 / Double(parentRing.nodes.count)
                    leftEdge = parentStartAngle + (Double(parentSelectedIndex) * parentItemAngle)
                    rightEdge = leftEdge + parentItemAngle
                }
            } else {
                parentItemAngle = parentSliceConfig.itemAngle
                
                if parentSliceConfig.direction == .counterClockwise {
                    rightEdge = parentSliceConfig.endAngle - (Double(parentSelectedIndex) * parentItemAngle)
                    leftEdge = rightEdge - parentItemAngle
                } else {
                    leftEdge = parentSliceConfig.startAngle + (Double(parentSelectedIndex) * parentItemAngle)
                    rightEdge = leftEdge + parentItemAngle
                }
            }
        } else {
            parentItemAngle = 360.0 / Double(max(parentRing.nodes.count, 1))
            leftEdge = Double(parentSelectedIndex) * parentItemAngle
            rightEdge = leftEdge + parentItemAngle
        }
        
        return ParentInfo(leftEdge: leftEdge, rightEdge: rightEdge, node: parentNode, parentItemAngle: parentItemAngle)
    }
    
    // MARK: - Angle Calculations
    
    /// Calculate per-item angles for Ring 0 with custom parentAngleSize support
    func calculateRing0Angles(for nodes: [FunctionNode]) -> [Double] {
        let customSizes = nodes.map { $0.parentAngleSize }
        let hasCustomSizes = customSizes.contains(where: { $0 != nil })
        
        guard hasCustomSizes else {
            let uniformAngle = 360.0 / Double(nodes.count)
            return Array(repeating: uniformAngle, count: nodes.count)
        }
        
        var totalCustomAngle: CGFloat = 0
        var customCount = 0
        
        for size in customSizes {
            if let size = size {
                totalCustomAngle += size
                customCount += 1
            }
        }
        
        if totalCustomAngle > 360 {
            print("⚠️ [Ring 0 Angles] Custom sizes total \(totalCustomAngle)° exceeds 360°. Falling back to equal distribution.")
            let uniformAngle = 360.0 / Double(nodes.count)
            return Array(repeating: uniformAngle, count: nodes.count)
        }
        
        let remainingAngle = 360.0 - totalCustomAngle
        let autoSizedCount = nodes.count - customCount
        let autoAngle = autoSizedCount > 0 ? remainingAngle / CGFloat(autoSizedCount) : 0
        
        if autoAngle > 0 && autoAngle < 15 {
            print("⚠️ [Ring 0 Angles] Auto-sized items are only \(autoAngle)° each. May be hard to select.")
        }
        
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
    
    /// Calculate angles for child ring items based on their itemAngleSize and parent's childItemAngleSize
    func calculateChildRingAngles(
        for nodes: [FunctionNode],
        parentNode: FunctionNode,
        ringIndex: Int
    ) -> [Double] {
        let parentDefaultAngle = parentNode.childItemAngleSize.map { Double($0) }
        let customSizes = nodes.map { $0.itemAngleSize }
        let hasCustomSizes = customSizes.contains(where: { $0 != nil })
        
        guard hasCustomSizes || parentDefaultAngle != nil else {
            let uniformAngle = 360.0 / Double(nodes.count)
            return Array(repeating: uniformAngle, count: nodes.count)
        }
        
        var totalCustomAngle: Double = 0
        var customCount = 0
        
        for node in nodes {
            if let customSize = node.itemAngleSize {
                totalCustomAngle += Double(customSize)
                customCount += 1
            } else if let parentDefault = parentDefaultAngle {
                totalCustomAngle += parentDefault
                customCount += 1
            }
        }
        
        if totalCustomAngle > 360 {
            print("⚠️ [Ring \(ringIndex) Angles] Custom sizes total \(totalCustomAngle)° exceeds 360°. Falling back to equal distribution.")
            let uniformAngle = 360.0 / Double(nodes.count)
            return Array(repeating: uniformAngle, count: nodes.count)
        }
        
        let remainingAngle = 360.0 - totalCustomAngle
        let autoSizedCount = nodes.count - customCount
        let autoAngle = autoSizedCount > 0 ? remainingAngle / Double(autoSizedCount) : 0
        
        if autoAngle > 0 && autoAngle < 15 {
            print("⚠️ [Ring \(ringIndex) Angles] Auto-sized items are only \(String(format: "%.1f", autoAngle))° each. May be hard to select.")
        }
        
        var angles: [Double] = []
        for node in nodes {
            if let customSize = node.itemAngleSize {
                angles.append(Double(customSize))
            } else if let parentDefault = parentDefaultAngle {
                angles.append(parentDefault)
            } else {
                angles.append(autoAngle)
            }
        }
        
        print("📐 [Ring \(ringIndex) Angles] Calculated: \(angles.map { String(format: "%.1f°", $0) }.joined(separator: ", "))")
        
        return angles
    }
}
