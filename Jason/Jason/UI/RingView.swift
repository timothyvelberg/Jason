//
//  RingView.swift
//  Jason
//
//  Created by Timothy Velberg on 06/10/2025.
//

import SwiftUI
import AppKit

struct RingView: View {
    let startRadius: CGFloat
    let thickness: CGFloat
    let nodes: [FunctionNode]
    let selectedIndex: Int?
    let shouldDimOpacity: Bool
    let sliceConfig: PieSliceConfig
    let iconSize: CGFloat
    
    // Animation configuration
    private let animationInitialDelay: Double = 0.06         // Initial delay before animation starts (seconds)
    private let animationBaseStaggerDelay: Double = 0.02    // Delay between each icon (seconds)
    private let animationDuration: Double = 0.25            // Duration of fade/scale animation
    private let animationStartScale: CGFloat = 0.9          // Starting scale (0.9 = 90% size)
    private let animationRotationOffset: Double = -10       // Starting rotation offset in degrees (negative = counter-clockwise)
    
    // Animation mode selection
    enum AnimationMode {
        case linear       // Animate from start to end (clockwise/counter-clockwise layouts)
        case centerOut    // Animate from center outward (center layout)
    }
    
    // Automatically select animation mode based on slice positioning
    private var animationMode: AnimationMode {
        return sliceConfig.positioning == .center ? .centerOut : .linear
    }
    
    // Animation state
    @State private var startAngle: Angle = .degrees(0)
    @State private var endAngle: Angle = .degrees(90)
    @State private var angleOffset: Double = 0
    @State private var previousIndex: Int? = nil
    @State private var previousTotalCount: Int = 0
    @State private var rotationIndex: Int = 0
    @State private var hasAppeared: Bool = false
    @State private var iconOpacities: [String: Double] = [:]       // Track opacity per icon ID
    @State private var iconScales: [String: CGFloat] = [:]         // Track scale per icon ID
    @State private var iconRotationOffsets: [String: Double] = [:] // Track rotation offset per icon ID
    @State private var runningIndicatorOpacities: [String: Double] = [:]  // Track running indicator opacity per icon ID
    
    
    // Animated slice background angles (for partial slice opening animation)
    @State private var animatedSliceStartAngle: Angle = .degrees(0)
    @State private var animatedSliceEndAngle: Angle = .degrees(0)
    
    // Selection indicator opacity (delayed fade-in)
    @State private var selectionIndicatorOpacity: Double = 0
    @State private var hasCompletedInitialSelectionFade: Bool = false
    
    // 🆕 DIFFING STATE: Track previous nodes for surgical updates
    @State private var previousNodes: [FunctionNode] = []
    @State private var isFirstRender: Bool = true
    
    // Computed adaptive stagger delay based on item count
    private var adaptiveStaggerDelay: Double {
        let itemCount = nodes.count
        
        // For small rings (≤10 items), use base delay
        if itemCount <= 10 {
            return animationBaseStaggerDelay
        }
        
        // For larger rings, reduce delay to keep total animation time reasonable
        let maxTotalStagger: Double = 0.05
        let calculatedDelay = maxTotalStagger / Double(itemCount - 1)
        
        // Clamp to reasonable bounds (20ms minimum, base delay maximum)
        return max(0.01, min(calculatedDelay, animationBaseStaggerDelay))
    }
    
    // Effective stagger delay based on animation mode
    private var effectiveStaggerDelay: Double {
        switch animationMode {
        case .linear:
            return adaptiveStaggerDelay
        case .centerOut:
            // Use 3x larger delay for center-out to make the effect more pronounced
            return adaptiveStaggerDelay * 3.0
        }
    }
    
    // Calculated properties
    private var endRadius: CGFloat {
        return startRadius + thickness
    }
    
    private var middleRadius: CGFloat {
        return (startRadius + endRadius) / 2
    }
    
    private var totalDiameter: CGFloat {
        return endRadius * 2
    }
    
    private var innerRadiusRatio: CGFloat {
        return startRadius / endRadius
    }
    
    // Computed opacity based on shouldDimOpacity
    private var ringOpacity: Double {
        return shouldDimOpacity ? 0.9 : 1.0
    }
    
    private var ringScale: CGFloat {
        return shouldDimOpacity ? 0.95 : 1.0
    }
    
    private var selectionColor: Color {
        return shouldDimOpacity ? .black.opacity(0.6) : .black.opacity(0.6)
    }
    
    var body: some View {
//        let _ = print("🔵 [RingView] Rendering - Nodes: \(nodes.count), Selected: \(selectedIndex?.description ?? "none")")
//        let _ = print("   SliceConfig - Start: \(sliceConfig.startAngle)°, End: \(sliceConfig.endAngle)°, ItemAngle: \(sliceConfig.itemAngle)°, IsFullCircle: \(sliceConfig.isFullCircle)")
        
        return ZStack {
            // Ring background - either full circle or partial slice
            if sliceConfig.isFullCircle {
                // Full circle background with blur material
                ZStack {
                    // Dark tint layer
                        DonutShape(
                            holePercentage: innerRadiusRatio,
                            outerPercentage: 1.0
                        )
                        .fill(Color.black.opacity(0.33), style: FillStyle(eoFill: true))
                    
                    // Blur material layer
                    DonutShape(
                        holePercentage: innerRadiusRatio,
                        outerPercentage: 1.0
                    )
                    .fill(.ultraThinMaterial, style: FillStyle(eoFill: true))
                    
                    // Border
                    DonutShape(
                        holePercentage: innerRadiusRatio,
                        outerPercentage: 1.0
                    )
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                }
                .frame(width: totalDiameter, height: totalDiameter)
                .allowsHitTesting(false)  // Don't block clicks
            } else {
                // Partial slice background with blur material
                ZStack {
                    // Dark tint layer
                    PieSliceShape(
                        startAngle: animatedSliceStartAngle - .degrees(90),
                        endAngle: animatedSliceEndAngle - .degrees(90),
                        innerRadiusRatio: innerRadiusRatio,
                        outerRadiusRatio: 1.0
                    )
                    .fill(Color.black.opacity(0.33))
                    
                    // Blur material layer
                    PieSliceShape(
                        startAngle: animatedSliceStartAngle - .degrees(90),
                        endAngle: animatedSliceEndAngle - .degrees(90),
                        innerRadiusRatio: innerRadiusRatio,
                        outerRadiusRatio: 1.0
                    )
                    .fill(.ultraThinMaterial)
                    
                    // Border
                    PieSliceShape(
                        startAngle: animatedSliceStartAngle - .degrees(90),
                        endAngle: animatedSliceEndAngle - .degrees(90),
                        innerRadiusRatio: innerRadiusRatio,
                        outerRadiusRatio: 1.0
                    )
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                }
                .frame(width: totalDiameter, height: totalDiameter)
                .allowsHitTesting(false)  // Don't block clicks
            }
            
            // Animated selection indicator
            if selectedIndex != nil {
                PieSliceShape(
                    startAngle: startAngle,
                    endAngle: endAngle,
                    innerRadiusRatio: innerRadiusRatio,
                    outerRadiusRatio: 1.0,
                    insetPercentage: 1
                )
                .fill(selectionColor, style: FillStyle(eoFill: true))
                .frame(width: totalDiameter, height: totalDiameter)
                .opacity(selectionIndicatorOpacity)  // Animated opacity
                .allowsHitTesting(false)  // Don't block clicks
            }
            
            // Running app indicators (thin arc at inner edge)
            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                if let metadata = node.metadata,
                   let isRunning = metadata["isRunning"] as? Bool,
                   isRunning {
                    
                    let centerAngle = calculateCenterAngle(for: index)
                    let itemAngle = angleForItem(at: index)  // ← Use variable angle

                    // Make indicator 5° narrower on each side (10° total)
                    let indicatorStartAngle = centerAngle - (itemAngle / 2) + 1
                    let indicatorEndAngle = centerAngle + (itemAngle / 2) - 1
                    // Calculate outer radius ratio for thin band (5 points)
                    let indicatorThickness: CGFloat = 2
                    let indicatorOuterRadiusRatio = innerRadiusRatio + (indicatorThickness / endRadius)
                    
                    PieSliceShape(
                        startAngle: .degrees(indicatorStartAngle - 90),
                        endAngle: .degrees(indicatorEndAngle - 90),
                        innerRadiusRatio: innerRadiusRatio,
                        outerRadiusRatio: indicatorOuterRadiusRatio
                    )
                    .fill(Color.white.opacity(0.32))
                    .opacity(runningIndicatorOpacities[node.id] ?? 0)  // Animated opacity
                    .frame(width: totalDiameter, height: totalDiameter)
                    .allowsHitTesting(false)
                }
            }
            
            // Icons positioned around the ring (non-interactive, just visual)
            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                let opacity = iconOpacities[node.id] ?? 0
                let scale = iconScales[node.id] ?? animationStartScale
                
                // 🆕 Defensive logging for missing states
                if opacity == 0 && iconOpacities[node.id] == nil {
                    let _ = print("      ⚠️ RENDER: Node \(node.id) has no opacity entry (defaulting to 0)")
                }
                
                Image(nsImage: node.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .scaleEffect(scale)
                    .opacity(opacity)
                    .position(iconPosition(for: index))
                    .allowsHitTesting(false)  // Icons don't intercept clicks
            }
        }
        .frame(width: totalDiameter, height: totalDiameter)
        .scaleEffect(ringScale)
        .overlay(
            Group {
                if let selectedIndex = selectedIndex,
                   !shouldDimOpacity {  // Only show on active ring
                    let node = nodes[selectedIndex]
                    if node.showLabel {
                        TitleTextView(
                            text: node.name,
                            radius: endRadius + 15,
                            frameSize: totalDiameter,
                            centerAngle: calculateCenterAngle(for: selectedIndex),
                            font: NSFont.systemFont(ofSize: 14, weight: .medium),
                            color: .white
                        )
                    }
                }
            }
        )
        .onChange(of: nodes.map { $0.id }) { _, _ in
            print("🔄 [RingView] Content changed - count: \(nodes.count)")
            print("   📌 State: isFirstRender=\(isFirstRender), previousNodes.count=\(previousNodes.count)")
            
            // 🆕 ADD THIS LOGGING:
            print("   🎯 Selection state: selectedIndex=\(selectedIndex?.description ?? "nil")")
            if let index = selectedIndex {
                if index < nodes.count {
                    let selectedNode = nodes[index]
                    print("   ✅ Selected node at index \(index): \(selectedNode.name)")
                } else {
                    print("   ❌ Selected index \(index) is OUT OF BOUNDS (count=\(nodes.count))")
                }
            }
            print("   📐 Current slice angles: start=\(startAngle.degrees)°, end=\(endAngle.degrees)°")
            
            if let index = selectedIndex {
                rotationIndex = index
                previousIndex = index
                updateSlice(for: index, totalCount: nodes.count)
            } else {
                previousIndex = nil
            }
            
            // Reset selection indicator opacity and completion flag
            selectionIndicatorOpacity = 0
            hasCompletedInitialSelectionFade = false
            
            // 🆕 SKIP ANIMATION if this is being called right after onAppear handled it
            // Check if previousNodes exactly matches current nodes (onAppear just set it)
            if previousNodes.count == nodes.count &&
               Set(previousNodes.map { $0.id }) == Set(nodes.map { $0.id }) {
                print("   ⏭️  SKIPPING: onChange fired right after onAppear - animation already handled")
                
                // Still animate slice if needed
                if !sliceConfig.isFullCircle && sliceConfig.positioning == .center {
                    animatedSliceStartAngle = Angle(degrees: sliceConfig.startAngle)
                    animatedSliceEndAngle = Angle(degrees: sliceConfig.endAngle)
                    
                    // Fade in selection indicator
                    let selectionDelay = 0.05
                    DispatchQueue.main.asyncAfter(deadline: .now() + selectionDelay) {
                        withAnimation(.easeIn(duration: 0.2)) {
                            selectionIndicatorOpacity = 1.0
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + selectionDelay + 0.2) {
                        hasCompletedInitialSelectionFade = true
                    }
                }
                return
            }
            
            // 🆕 DETERMINE UPDATE TYPE: First render vs Surgical update
            let isSurgicalUpdate: Bool
            if isFirstRender {
                isSurgicalUpdate = false
                isFirstRender = false
                print("   🎬 First render - full entrance animation")
            } else if previousNodes.isEmpty {
                isSurgicalUpdate = false
                print("   🎬 Previous nodes empty - full entrance animation")
            } else {
                // Diff the nodes to determine if surgical
                let oldIds = Set(previousNodes.map { $0.id })
                let newIds = Set(nodes.map { $0.id })
                let changeCount = oldIds.symmetricDifference(newIds).count
                isSurgicalUpdate = changeCount <= 3  // Small change = surgical
                print("   🔧 Change count: \(changeCount), surgical: \(isSurgicalUpdate)")
            }
            
            // Animate the background slice
            if !sliceConfig.isFullCircle && sliceConfig.positioning == .center {
                if isSurgicalUpdate {
                    // Smooth resize from current to new
                    print("   ✨ Smooth resize animation")
                    
                    let adjustedEndAngle = sliceConfig.endAngle < sliceConfig.startAngle
                        ? sliceConfig.endAngle + 360
                        : sliceConfig.endAngle
                    
                    withAnimation(.easeOut(duration: 0.3)) {
                        animatedSliceStartAngle = Angle(degrees: sliceConfig.startAngle)
                        animatedSliceEndAngle = Angle(degrees: adjustedEndAngle)
                    }
                } else {
                    //Full entrance animation
                    print("   🎬 Full entrance animation for slice")
                    
                    let initialSliceSize = 10.0  // Start with 10° slice
                    
                    // Calculate true center angle, handling wraparound
                    let centerAngle: Double
                    if sliceConfig.endAngle < sliceConfig.startAngle {
                        centerAngle = (sliceConfig.startAngle + (sliceConfig.endAngle + 360)) / 2
                    } else {
                        centerAngle = (sliceConfig.startAngle + sliceConfig.endAngle) / 2
                    }
                    
                    // Handle angle wraparound for animation target
                    let adjustedEndAngle = sliceConfig.endAngle < sliceConfig.startAngle
                        ? sliceConfig.endAngle + 360
                        : sliceConfig.endAngle
                    
                    animatedSliceStartAngle = Angle(degrees: centerAngle - initialSliceSize / 2)
                    animatedSliceEndAngle = Angle(degrees: centerAngle + initialSliceSize / 2)
                    
                    withAnimation(.easeOut(duration: 0.3)) {
                        animatedSliceStartAngle = Angle(degrees: sliceConfig.startAngle)
                        animatedSliceEndAngle = Angle(degrees: adjustedEndAngle)
                    }
                }
                
                // Fade in selection indicator with a simple hardcoded delay
                let selectionDelay = 0.05
                DispatchQueue.main.asyncAfter(deadline: .now() + selectionDelay) {
                    withAnimation(.easeIn(duration: 0.2)) {
                        selectionIndicatorOpacity = 1.0
                    }
                }
                
                // Mark as completed after animation finishes
                DispatchQueue.main.asyncAfter(deadline: .now() + selectionDelay + 0.2) {
                    hasCompletedInitialSelectionFade = true
                }
            } else {
                animatedSliceStartAngle = Angle(degrees: sliceConfig.startAngle)
                animatedSliceEndAngle = Angle(degrees: sliceConfig.endAngle)
                
                // Fade in selection indicator with a simple hardcoded delay
                let selectionDelay = 0.05
                DispatchQueue.main.asyncAfter(deadline: .now() + selectionDelay) {
                    withAnimation(.easeIn(duration: 0.2)) {
                        selectionIndicatorOpacity = 1.0
                    }
                }
                
                // Mark as completed after animation finishes
                DispatchQueue.main.asyncAfter(deadline: .now() + selectionDelay + 0.2) {
                    hasCompletedInitialSelectionFade = true
                }
            }
            if isSurgicalUpdate {
                // Only animate changed icons
                print("   🎯 Surgical icon update - animating changed icons only")
                // Store current nodes as "old" before they get updated
                let oldNodesSnapshot = previousNodes
                previousNodes = nodes  // Update for next time
                animateIconsSurgical(oldNodes: oldNodesSnapshot, newNodes: nodes)
            } else {
                // STRUCTURAL: Full entrance animation
                print("   🎬 Full icon entrance animation")
                previousNodes = nodes  // Update for next time
                animateIconsIn()
            }
        }
        .onChange(of: selectedIndex) {
            if let index = selectedIndex {
                if index < nodes.count {
                    let selectedNode = nodes[index]
                } else {
                    print("   ❌ INVALID: index \(index) >= count \(nodes.count)")
                }
            }
            
            if let index = selectedIndex {
                updateSlice(for: index, totalCount: nodes.count)
                // Only set opacity immediately AFTER the initial fade-in has completed
                // This prevents overriding the delayed fade-in on first appearance
                if hasCompletedInitialSelectionFade {
                    selectionIndicatorOpacity = 1.0
                }
            }
        }
        .onAppear {
            print("   🎬 [RingView] onAppear called - nodes.count=\(nodes.count), previousNodes.count=\(previousNodes.count)")
            
            // Reset selection indicator opacity and completion flag
            selectionIndicatorOpacity = 0
            hasCompletedInitialSelectionFade = false
            
            // 🆕 CRITICAL FIX: Always animate icons on first appearance
            // Even if previousNodes gets initialized for tracking, we still need entrance animation
            if nodes.count > 0 {
                print("   🎬 Triggering initial icon entrance animation")
                animateIconsIn()
                
                // Set previousNodes for future surgical updates
                previousNodes = nodes
                isFirstRender = false
            }

            
            // Animate the background slice opening
            if !sliceConfig.isFullCircle && sliceConfig.positioning == .center {
                // For center positioning: start with small slice, then expand to full size
                let initialSliceSize = 10.0  // Start with 10° slice (smaller = more obvious)
                
                // Calculate true center angle, handling wraparound
                let centerAngle: Double
                if sliceConfig.endAngle < sliceConfig.startAngle {
                    // Wraparound case: slice crosses 0°/360°
                    // Add 360 to endAngle for proper center calculation
                    centerAngle = (sliceConfig.startAngle + (sliceConfig.endAngle + 360)) / 2
                    // Normalize if needed
                } else {
                    centerAngle = (sliceConfig.startAngle + sliceConfig.endAngle) / 2
                }
                
                // Handle angle wraparound for animation target
                let adjustedEndAngle = sliceConfig.endAngle < sliceConfig.startAngle
                    ? sliceConfig.endAngle + 360
                    : sliceConfig.endAngle
                
                animatedSliceStartAngle = Angle(degrees: centerAngle - initialSliceSize / 2)
                animatedSliceEndAngle = Angle(degrees: centerAngle + initialSliceSize / 2)
                
                withAnimation(.easeOut(duration: 0.24)) {
                    animatedSliceStartAngle = Angle(degrees: sliceConfig.startAngle)
                    animatedSliceEndAngle = Angle(degrees: adjustedEndAngle)
                    print("   ✅ Animation triggered!")
                }
                
                // Fade in selection indicator with a simple hardcoded delay
                let selectionDelay = 0.05
                
                // Use DispatchQueue instead of withAnimation delay to survive view recreation
                DispatchQueue.main.asyncAfter(deadline: .now() + selectionDelay) {
                    withAnimation(.easeIn(duration: 0.2)) {
                        selectionIndicatorOpacity = 1.0
                    }
                }
                
                // Mark as completed after animation finishes
                DispatchQueue.main.asyncAfter(deadline: .now() + selectionDelay + 0.2) {
                    hasCompletedInitialSelectionFade = true
                }
            } else {
                // For non-center or full circle: set angles directly without animation
                animatedSliceStartAngle = Angle(degrees: sliceConfig.startAngle)
                animatedSliceEndAngle = Angle(degrees: sliceConfig.endAngle)
                
                // Fade in selection indicator with a simple hardcoded delay
                let selectionDelay = 0.05
                
                // Use DispatchQueue instead of withAnimation delay
                DispatchQueue.main.asyncAfter(deadline: .now() + selectionDelay) {
                    withAnimation(.easeIn(duration: 0.2)) {
                        selectionIndicatorOpacity = 1.0
                    }
                }
                
                // Mark as completed after animation finishes
                DispatchQueue.main.asyncAfter(deadline: .now() + selectionDelay + 0.2) {
                    hasCompletedInitialSelectionFade = true
                }
            }
            
            // Trigger staggered fade-in animation
            animateIconsIn()
            
            if let index = selectedIndex {
                rotationIndex = index
                previousIndex = index
                hasAppeared = true
                let totalCount = nodes.count
                guard totalCount > 0 else { return }
                
                let itemAngle = sliceConfig.itemAngle
                
                let angleOffset: Double
                if sliceConfig.direction == .counterClockwise {
                    let baseAngle = sliceConfig.endAngle
                    angleOffset = baseAngle - (Double(index) * itemAngle) - (itemAngle / 2)
                } else {
                    let baseAngle = sliceConfig.startAngle
                    angleOffset = baseAngle + (Double(index) * itemAngle) + (itemAngle / 2)
                }
                
                startAngle = Angle(degrees: angleOffset - itemAngle / 2 - 90)
                endAngle = Angle(degrees: angleOffset + itemAngle / 2 - 90)
            } else {
                rotationIndex = 0
                previousIndex = nil
                hasAppeared = false
                startAngle = .degrees(0)
                endAngle = .degrees(sliceConfig.itemAngle)
            }
        }
    }
    
    private func updateSlice(for index: Int, totalCount: Int) {
        // 🆕 Logging
        print("🔧 [updateSlice] Called with index=\(index), totalCount=\(totalCount)")
        print("   Previous state: previousIndex=\(previousIndex?.description ?? "nil"), rotationIndex=\(rotationIndex), previousTotalCount=\(previousTotalCount)")
        
        guard totalCount > 0 else {
            angleOffset = 0
            startAngle = .degrees(0)
            endAngle = .degrees(0)
            print("   ⚠️ totalCount is 0, resetting angles")
            return
        }
        
        let itemAngle = angleForItem(at: index)
        print("   📏 itemAngle for index \(index): \(itemAngle)°")
        
        if previousIndex == nil {
            // First selection - calculate center angle for this item
            let centerAngle = calculateCenterAngle(for: index)
            angleOffset = centerAngle
            startAngle = Angle(degrees: centerAngle - itemAngle / 2 - 90)
            endAngle = Angle(degrees: centerAngle + itemAngle / 2 - 90)
            
            print("   🆕 FIRST SELECTION:")
            print("      centerAngle=\(centerAngle)°")
            print("      angleOffset=\(angleOffset)°")
            print("      startAngle=\(startAngle.degrees)°, endAngle=\(endAngle.degrees)°")
            
            previousIndex = index
            previousTotalCount = totalCount  // 🆕 Track totalCount
            rotationIndex = index
            return
        }
        
        // 🆕 FIXED: Also check if totalCount changed
        guard let prevIndex = previousIndex,
              index != prevIndex || totalCount != previousTotalCount else {
            print("   ⏭️ SKIPPING: index and totalCount unchanged (index=\(index), totalCount=\(totalCount))")
            return
        }
        
        // 🆕 Check if totalCount changed even though index stayed the same
        if index == prevIndex && totalCount != previousTotalCount {
            print("   🔄 TOTALCOUNT CHANGED: Same index (\(index)) but count changed from \(previousTotalCount) to \(totalCount)")
            print("      Need to recalculate angles for new layout!")
        } else {
            print("   🔄 UPDATING SELECTION: from \(prevIndex) to \(index)")
        }
        
        var newRotationIndex: Int
        
        if sliceConfig.isFullCircle {
            let forwardSteps = (index - prevIndex + totalCount) % totalCount
            let backwardSteps = (prevIndex - index + totalCount) % totalCount
            
            if forwardSteps <= backwardSteps {
                newRotationIndex = rotationIndex + forwardSteps
                print("      Moving FORWARD: \(forwardSteps) steps, newRotationIndex=\(newRotationIndex)")
            } else {
                newRotationIndex = rotationIndex - backwardSteps
                print("      Moving BACKWARD: \(backwardSteps) steps, newRotationIndex=\(newRotationIndex)")
            }
        } else {
            newRotationIndex = index
            print("      Partial slice: newRotationIndex=\(newRotationIndex)")
        }
        
        // Calculate angle offset using rotationIndex for smooth wraparound animation
        let newAngleOffset: Double
        if sliceConfig.direction == .counterClockwise {
            let baseAngle = sliceConfig.endAngle
            newAngleOffset = cumulativeAngleAtRotationIndex(newRotationIndex, baseAngle: baseAngle, clockwise: false)
            print("      CCW: baseAngle=\(baseAngle)°, newAngleOffset=\(newAngleOffset)°")
        } else {
            let baseAngle = sliceConfig.startAngle
            newAngleOffset = cumulativeAngleAtRotationIndex(newRotationIndex, baseAngle: baseAngle, clockwise: true)
            print("      CW: baseAngle=\(baseAngle)°, newAngleOffset=\(newAngleOffset)°")
        }
        
        let newStartAngle = newAngleOffset - itemAngle / 2 - 90
        let newEndAngle = newAngleOffset + itemAngle / 2 - 90
        
        withAnimation(.easeOut(duration: 0.08)) {
            angleOffset = newAngleOffset
            startAngle = Angle(degrees: newStartAngle)
            endAngle = Angle(degrees: newEndAngle)
        }
        
        previousIndex = index
        previousTotalCount = totalCount  // 🆕 Track totalCount for next time
        rotationIndex = newRotationIndex
        
        print("   ✅ Update complete: previousIndex=\(previousIndex?.description ?? "nil"), previousTotalCount=\(previousTotalCount), rotationIndex=\(rotationIndex)")
    }

    /// Calculate the angle at a given rotationIndex (which can be negative or > totalCount for wraparound animation)
    private func cumulativeAngleAtRotationIndex(_ rotIndex: Int, baseAngle: Double, clockwise: Bool) -> Double {
        let totalCount = nodes.count
        guard totalCount > 0 else { return baseAngle }
        
        // Check if we have variable angles
        guard let perItemAngles = sliceConfig.perItemAngles, perItemAngles.count == totalCount else {
            // Fallback to uniform angle calculation
            let itemAngle = sliceConfig.itemAngle
            if clockwise {
                return baseAngle + (Double(rotIndex) * itemAngle) + (itemAngle / 2)
            } else {
                return baseAngle - (Double(rotIndex) * itemAngle) - (itemAngle / 2)
            }
        }
        
        // Variable angles: need to calculate cumulative
        let actualIndex = ((rotIndex % totalCount) + totalCount) % totalCount
        let fullRotations = rotIndex >= 0 ? rotIndex / totalCount : (rotIndex - totalCount + 1) / totalCount
        
        // Calculate cumulative angle to actualIndex
        var cumulative: Double = 0
        for i in 0..<actualIndex {
            cumulative += perItemAngles[i]
        }
        
        // Add center offset for this item
        let itemAngle = perItemAngles[actualIndex]
        let centerOffset = cumulative + (itemAngle / 2)
        
        if clockwise {
            return baseAngle + centerOffset + (Double(fullRotations) * 360.0)
        } else {
            return baseAngle - centerOffset - (Double(fullRotations) * 360.0)
        }
    }
    
    private func iconPosition(for index: Int) -> CGPoint {
        guard nodes.count > 0 else {
            return CGPoint(x: totalDiameter / 2, y: totalDiameter / 2)
        }
        
        // Use helper to get center angle (handles variable angles)
        let iconAngle = calculateCenterAngle(for: index)
        
        // Apply rotation offset for animation
        let node = nodes[index]
        let rotationOffset = iconRotationOffsets[node.id] ?? 0
        let finalAngle = iconAngle + rotationOffset
        
        let angleInRadians = (finalAngle - 90) * (.pi / 180)
        
        let center = CGPoint(x: totalDiameter / 2, y: totalDiameter / 2)
        let x = center.x + middleRadius * cos(angleInRadians)
        let y = center.y + middleRadius * sin(angleInRadians)
        
        return CGPoint(x: x, y: y)
    }
    
    private func calculateCenterAngle(for index: Int) -> Double {
        guard nodes.count > 0 else { return 0 }
        
        let startAngle = cumulativeStartAngle(for: index)
        let itemAngle = angleForItem(at: index)
        
        // Return the center of this item's slice
        if sliceConfig.direction == .counterClockwise {
            return startAngle - (itemAngle / 2)
        } else {
            return startAngle + (itemAngle / 2)
        }
    }
    
    // MARK: - Variable Angle Helpers

    /// Get the angle size for a specific item (supports variable angles)
    private func angleForItem(at index: Int) -> Double {
        if let perItemAngles = sliceConfig.perItemAngles,
           index < perItemAngles.count {
            let angle = perItemAngles[index]
            return angle
        }
        let fallback = sliceConfig.itemAngle
        return fallback
    }

    /// Calculate the cumulative start angle for an item (where its slice begins)
    private func cumulativeStartAngle(for index: Int) -> Double {
        let baseAngle = sliceConfig.direction == .counterClockwise
            ? sliceConfig.endAngle
            : sliceConfig.startAngle
        
        guard let perItemAngles = sliceConfig.perItemAngles else {
            // Uniform angles: simple multiplication
            let offset = sliceConfig.itemAngle * Double(index)
            return sliceConfig.direction == .counterClockwise
                ? baseAngle - offset
                : baseAngle + offset
        }
        
        // Variable angles: sum all previous angles
        var cumulativeAngle: Double = 0
        for i in 0..<index {
            if i < perItemAngles.count {
                cumulativeAngle += perItemAngles[i]
            }
        }
        
        return sliceConfig.direction == .counterClockwise
            ? baseAngle - cumulativeAngle
            : baseAngle + cumulativeAngle
    }
    
    // MARK: - Staggered Animation
    
    private func animateIconsIn() {
        // Dispatch to appropriate animation based on mode
        switch animationMode {
        case .linear:
            animateIconsInLinear()
        case .centerOut:
            animateIconsInFromCenter()
        }
    }
    
    // MARK: - Linear Animation (Original)
    
    private func animateIconsInLinear() {
        // Reset all opacities to 0, scales to starting value, and rotation offsets
        for node in nodes {
            iconOpacities[node.id] = 0
            iconScales[node.id] = animationStartScale
            iconRotationOffsets[node.id] = animationRotationOffset
            runningIndicatorOpacities[node.id] = 0  // 🆕 Initialize running indicators to 0
        }
        
        // Animate each icon in with initial delay + staggered delay
        for (index, node) in nodes.enumerated() {
            let delay = animationInitialDelay + (Double(index) * effectiveStaggerDelay)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: self.animationDuration)) {
                    iconOpacities[node.id] = 1.0
                    iconScales[node.id] = 1.0
                    iconRotationOffsets[node.id] = 0  // Rotate to final position
                }
            }
        }
        
        // Animate running indicators after all icons are done
        let lastIconDelay = animationInitialDelay + (Double(nodes.count - 1) * effectiveStaggerDelay)
        let indicatorDelay = lastIconDelay + animationDuration
        
        for node in nodes {
            // Check if this node is a running app
            if let metadata = node.metadata,
               let isRunning = metadata["isRunning"] as? Bool,
               isRunning {
                DispatchQueue.main.asyncAfter(deadline: .now() + indicatorDelay) {
                    withAnimation(.easeIn(duration: 0.3)) {
                        runningIndicatorOpacities[node.id] = 1.0
                    }
                }
            }
        }
    }
    
    // MARK: - Center-Out Animation
    
    private func animateIconsInFromCenter() {
        
        let totalCount = nodes.count
        guard totalCount > 0 else { return }
        
        // Determine center point for rotation offset calculation
        let centerPoint: Double
        if totalCount % 2 == 1 {
            // Odd count: center is at the middle index
            centerPoint = Double(totalCount / 2)
        } else {
            // Even count: center is between the two middle indices
            centerPoint = Double(totalCount) / 2.0 - 0.5
        }
        
        // Reset all opacities to 0, scales to starting value, and rotation offsets
        // Apply symmetric rotation: left of center = +10°, right of center = -10°
        for (index, node) in nodes.enumerated() {
            iconOpacities[node.id] = 0
            iconScales[node.id] = animationStartScale
            runningIndicatorOpacities[node.id] = 0  // 🆕 Initialize running indicators to 0
            
            // Determine rotation offset based on position relative to center
            let rotationOffset: Double
            if Double(index) < centerPoint {
                // Left of center: rotate from +10° to 0° (counter-clockwise)
                rotationOffset = abs(animationRotationOffset)
            } else if Double(index) > centerPoint {
                // Right of center: rotate from -10° to 0° (clockwise)
                rotationOffset = -abs(animationRotationOffset)
            } else {
                // Exactly at center (odd count only): no rotation
                rotationOffset = 0
            }
            iconRotationOffsets[node.id] = rotationOffset
        }
        
        // Build animation groups: items at same distance from center animate together
        var animationGroups: [[Int]] = []
        var processed = Set<Int>()
        
        // Start with center item(s)
        if totalCount % 2 == 1 {
            // Odd count: one center item
            let centerIndex = totalCount / 2
            animationGroups.append([centerIndex])
            processed.insert(centerIndex)
        } else {
            // Even count: two center items
            let centerLeft = (totalCount / 2) - 1
            let centerRight = totalCount / 2
            animationGroups.append([centerLeft, centerRight])
            processed.insert(centerLeft)
            processed.insert(centerRight)
        }
        
        // Build outward groups symmetrically
        var distance = 1
        while processed.count < totalCount {
            var group: [Int] = []
            
            if totalCount % 2 == 1 {
                // Odd count: expand from single center
                let centerIndex = totalCount / 2
                let leftIndex = centerIndex - distance
                let rightIndex = centerIndex + distance
                
                if leftIndex >= 0 && !processed.contains(leftIndex) {
                    group.append(leftIndex)
                    processed.insert(leftIndex)
                }
                if rightIndex < totalCount && !processed.contains(rightIndex) {
                    group.append(rightIndex)
                    processed.insert(rightIndex)
                }
            } else {
                // Even count: expand from the gap between center items
                let centerLeft = (totalCount / 2) - 1
                let leftIndex = centerLeft - distance
                let rightIndex = centerLeft + 1 + distance
                
                if leftIndex >= 0 && !processed.contains(leftIndex) {
                    group.append(leftIndex)
                    processed.insert(leftIndex)
                }
                if rightIndex < totalCount && !processed.contains(rightIndex) {
                    group.append(rightIndex)
                    processed.insert(rightIndex)
                }
            }
            
            if !group.isEmpty {
                animationGroups.append(group)
            }
            
            distance += 1
        }

        // Animate each group with increasing delay
        for (groupIndex, group) in animationGroups.enumerated() {
            let delay = animationInitialDelay + (Double(groupIndex) * effectiveStaggerDelay)
            
            for index in group {
                let node = nodes[index]
                
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.easeOut(duration: self.animationDuration)) {
                        iconOpacities[node.id] = 1.0
                        iconScales[node.id] = 1.0
                        iconRotationOffsets[node.id] = 0
                    }
                }
            }
        }
        
        // 🆕 Animate running indicators after all icons are done
        let lastGroupDelay = animationInitialDelay + (Double(animationGroups.count - 1) * effectiveStaggerDelay)
        let indicatorDelay = lastGroupDelay + animationDuration
        
        for node in nodes {
            // Check if this node is a running app
            if let metadata = node.metadata,
               let isRunning = metadata["isRunning"] as? Bool,
               isRunning {
                DispatchQueue.main.asyncAfter(deadline: .now() + indicatorDelay) {
                    withAnimation(.easeIn(duration: 0.3)) {
                        runningIndicatorOpacities[node.id] = 1.0
                    }
                }
            }
        }
    }
    
    // MARK: - 🆕 Surgical Icon Animation
    
    private func animateIconsSurgical(oldNodes: [FunctionNode], newNodes: [FunctionNode]) {
        let oldIds = Set(oldNodes.map { $0.id })
        let newIds = Set(newNodes.map { $0.id })
        
        let addedIds = newIds.subtracting(oldIds)
        let removedIds = oldIds.subtracting(newIds)
        let persistingIds = oldIds.intersection(newIds)
        
        print("      🔍 Surgical Animation Analysis:")
        print("         Old nodes: \(oldNodes.count), New nodes: \(newNodes.count)")
        print("         Added: \(addedIds.count), Removed: \(removedIds.count), Persisting: \(persistingIds.count)")
        if !addedIds.isEmpty {
            print("         ➕ Added IDs: \(Array(addedIds).joined(separator: ", "))")
        }
        if !removedIds.isEmpty {
            print("         ➖ Removed IDs: \(Array(removedIds).joined(separator: ", "))")
        }

        // Guard against empty old nodes (shouldn't happen, but just in case)
        if oldNodes.isEmpty && newNodes.count > 0 {
            print("      ⚠️ Old nodes empty - treating as first appearance, calling full animation")
            animateIconsIn()
            return
        }
        
        // 1. REMOVED ICONS: Fade out
        for id in removedIds {
            withAnimation(.easeIn(duration: 0.2)) {
                iconOpacities[id] = 0
                iconScales[id] = 0.8
                runningIndicatorOpacities[id] = 0
            }
            
            // Clean up after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                iconOpacities.removeValue(forKey: id)
                iconScales.removeValue(forKey: id)
                iconRotationOffsets.removeValue(forKey: id)
                runningIndicatorOpacities.removeValue(forKey: id)
            }
        }
        
        // 2. PERSISTING ICONS: Ensure visible, no animation
        for id in persistingIds {
            // Just make sure they're visible (in case they weren't before)
            if iconOpacities[id] != 1.0 {
                iconOpacities[id] = 1.0
                iconScales[id] = 1.0
                iconRotationOffsets[id] = 0
            }
            
            // Update running indicator if metadata changed
            if let node = newNodes.first(where: { $0.id == id }),
               let metadata = node.metadata,
               let isRunning = metadata["isRunning"] as? Bool {
                let currentOpacity = runningIndicatorOpacities[id] ?? 0
                let targetOpacity = isRunning ? 1.0 : 0.0
                if currentOpacity != targetOpacity {
                    withAnimation(.easeIn(duration: 0.3)) {
                        runningIndicatorOpacities[id] = targetOpacity
                    }
                }
            }
        }
        
        // 3. ADDED ICONS: Fade in
        for id in addedIds {
            print("      ➕ Fading in new icon: \(id)")
            
            // Start invisible
            iconOpacities[id] = 0
            iconScales[id] = animationStartScale
            iconRotationOffsets[id] = 0
            runningIndicatorOpacities[id] = 0
            
            // Fade in with slight delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeOut(duration: 0.25)) {
                    iconOpacities[id] = 1.0
                    iconScales[id] = 1.0
                }
                
                // Check if should show running indicator
                if let node = newNodes.first(where: { $0.id == id }),
                   let metadata = node.metadata,
                   let isRunning = metadata["isRunning"] as? Bool,
                   isRunning {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        withAnimation(.easeIn(duration: 0.3)) {
                            runningIndicatorOpacities[id] = 1.0
                        }
                    }
                }
            }
        }
        
        // 🆕 4. SAFETY NET: Ensure ALL current nodes have animation states
        // This catches any nodes that might have been missed (e.g., due to truncation edge cases)
        var safetyNetTriggered = false
        for node in newNodes {
            if iconOpacities[node.id] == nil {
                print("      ⚠️ SAFETY NET: Initializing missing animation state for: \(node.id)")
                safetyNetTriggered = true
                iconOpacities[node.id] = 0
                iconScales[node.id] = animationStartScale
                iconRotationOffsets[node.id] = 0
                runningIndicatorOpacities[node.id] = 0
                
                // Immediately fade in (this shouldn't normally happen)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        iconOpacities[node.id] = 1.0
                        iconScales[node.id] = 1.0
                    }
                    
                    // Running indicator if needed
                    if let metadata = node.metadata,
                       let isRunning = metadata["isRunning"] as? Bool,
                       isRunning {
                        runningIndicatorOpacities[node.id] = 1.0
                    }
                }
            }
        }
        
        if !safetyNetTriggered {
            print("      ✅ All \(newNodes.count) nodes have animation states")
        }
    }
}
