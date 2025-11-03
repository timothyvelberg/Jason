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
                    let itemAngle = sliceConfig.itemAngle
                    
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
                    .fill(Color.white.opacity(0.4))
                    .opacity(runningIndicatorOpacities[node.id] ?? 0)  // Animated opacity
                    .frame(width: totalDiameter, height: totalDiameter)
                    .allowsHitTesting(false)
                }
            }
            
            // Icons positioned around the ring (non-interactive, just visual)
            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                Image(nsImage: node.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .scaleEffect(iconScales[node.id] ?? animationStartScale)  // Start at configured scale
                    .opacity(iconOpacities[node.id] ?? 0)                     // Start at 0, animate to 1
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
        .onChange(of: nodes.count) {
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
            
            // Reset and re-animate the background slice
            if !sliceConfig.isFullCircle && sliceConfig.positioning == .center {
                let initialSliceSize = 10.0  // Start with 10° slice
                
                // Calculate true center angle, handling wraparound
                let centerAngle: Double
                if sliceConfig.endAngle < sliceConfig.startAngle {
                    // Wraparound case: add 360 to endAngle for proper center calculation
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
            
            // Trigger staggered fade-in animation for icons
            animateIconsIn()
        }
        .onChange(of: selectedIndex) {
            if let index = selectedIndex {
                updateSlice(for: index, totalCount: nodes.count)
                // Only set opacity immediately AFTER the initial fade-in has completed
                // This prevents overriding the delayed fade-in on first appearance
                print("📍 [Selection] onChange fired - hasCompleted: \(hasCompletedInitialSelectionFade), current opacity: \(selectionIndicatorOpacity)")
                if hasCompletedInitialSelectionFade {
                    selectionIndicatorOpacity = 1.0
                    print("   ✅ Setting opacity to 1.0 (hover change)")
                } else {
                    print("   ⏳ Waiting for initial fade to complete")
                }
            }
        }
        .onAppear {
            // Reset selection indicator opacity and completion flag
            selectionIndicatorOpacity = 0
            hasCompletedInitialSelectionFade = false
            print("🎬 [Selection] onAppear - reset opacity=0, selectedIndex: \(selectedIndex?.description ?? "nil")")
            
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
                
                print("🎭 [RingView] SLICE ANIMATION START")
                print("   Center: \(centerAngle)° (wraparound: \(sliceConfig.endAngle < sliceConfig.startAngle))")
                print("   Initial: [\(centerAngle - initialSliceSize / 2)°, \(centerAngle + initialSliceSize / 2)°] (size: \(initialSliceSize)°)")
                print("   Final: [\(sliceConfig.startAngle)°, \(adjustedEndAngle)°]")
                
                withAnimation(.easeOut(duration: 0.24)) {
                    animatedSliceStartAngle = Angle(degrees: sliceConfig.startAngle)
                    animatedSliceEndAngle = Angle(degrees: adjustedEndAngle)
                    print("   ✅ Animation triggered!")
                }
                
                // Fade in selection indicator with a simple hardcoded delay
                let selectionDelay = 0.05
                print("🕐 [Selection] Scheduling delayed fade-in: delay=\(selectionDelay)s, duration=0.2s")
                
                // Use DispatchQueue instead of withAnimation delay to survive view recreation
                DispatchQueue.main.asyncAfter(deadline: .now() + selectionDelay) {
                    withAnimation(.easeIn(duration: 0.2)) {
                        selectionIndicatorOpacity = 1.0
                        print("   ✅ Selection opacity -> 1.0")
                    }
                }
                
                // Mark as completed after animation finishes
                DispatchQueue.main.asyncAfter(deadline: .now() + selectionDelay + 0.2) {
                    hasCompletedInitialSelectionFade = true
                    print("   ✅ Selection fade completed - flag set to true")
                }
            } else {
                // For non-center or full circle: set angles directly without animation
                print("🎭 [RingView] No slice animation (fullCircle: \(sliceConfig.isFullCircle), positioning: \(sliceConfig.positioning))")
                animatedSliceStartAngle = Angle(degrees: sliceConfig.startAngle)
                animatedSliceEndAngle = Angle(degrees: sliceConfig.endAngle)
                
                // Fade in selection indicator with a simple hardcoded delay
                let selectionDelay = 0.05
                print("🕐 [Selection] Scheduling delayed fade-in (no bg animation): delay=\(selectionDelay)s, duration=0.2s")
                
                // Use DispatchQueue instead of withAnimation delay
                DispatchQueue.main.asyncAfter(deadline: .now() + selectionDelay) {
                    withAnimation(.easeIn(duration: 0.2)) {
                        selectionIndicatorOpacity = 1.0
                        print("   ✅ Selection opacity -> 1.0")
                    }
                }
                
                // Mark as completed after animation finishes
                DispatchQueue.main.asyncAfter(deadline: .now() + selectionDelay + 0.2) {
                    hasCompletedInitialSelectionFade = true
                    print("   ✅ Selection fade completed - flag set to true")
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
        guard totalCount > 0 else { return }
        
        let itemAngle = sliceConfig.itemAngle
        
        if previousIndex == nil || !hasAppeared {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                rotationIndex = index
                previousIndex = index
                hasAppeared = true
                
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
            }
            return
        }
        
        guard let prevIndex = previousIndex, index != prevIndex else { return }
        
        var newRotationIndex: Int
        
        if sliceConfig.isFullCircle {
            let forwardSteps = (index - prevIndex + totalCount) % totalCount
            let backwardSteps = (prevIndex - index + totalCount) % totalCount
            
            if forwardSteps <= backwardSteps {
                newRotationIndex = rotationIndex + forwardSteps
            } else {
                newRotationIndex = rotationIndex - backwardSteps
            }
        } else {
            newRotationIndex = index
        }
        
        let newAngleOffset: Double
        if sliceConfig.direction == .counterClockwise {
            let baseAngle = sliceConfig.endAngle
            newAngleOffset = baseAngle - (Double(newRotationIndex) * itemAngle) - (itemAngle / 2)
        } else {
            let baseAngle = sliceConfig.startAngle
            newAngleOffset = baseAngle + (Double(newRotationIndex) * itemAngle) + (itemAngle / 2)
        }
        
        withAnimation(.easeOut(duration: 0.08)) {
            angleOffset = newAngleOffset
            startAngle = Angle(degrees: angleOffset - itemAngle / 2 - 90)
            endAngle = Angle(degrees: angleOffset + itemAngle / 2 - 90)
        }
        
        previousIndex = index
        rotationIndex = newRotationIndex
    }
    
    private func iconPosition(for index: Int) -> CGPoint {
        guard nodes.count > 0 else {
            return CGPoint(x: totalDiameter / 2, y: totalDiameter / 2)
        }
        
        let itemAngle = sliceConfig.itemAngle
        
        let iconAngle: Double
        
        if sliceConfig.direction == .counterClockwise {
            // Counter-clockwise: Position from END angle going backwards
            // Item 0 starts at endAngle, item 1 is further counter-clockwise, etc.
            let baseAngle = sliceConfig.endAngle
            iconAngle = baseAngle - (itemAngle * Double(index)) - (itemAngle / 2)
        } else {
            // Clockwise: Position from START angle going forwards
            let baseAngle = sliceConfig.startAngle
            iconAngle = baseAngle + (itemAngle * Double(index)) + (itemAngle / 2)
        }
        
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
        
        let itemAngle = sliceConfig.itemAngle
        
        if sliceConfig.direction == .counterClockwise {
            // Counter-clockwise: Calculate from END angle going backwards
            let baseAngle = sliceConfig.endAngle
            return baseAngle - (itemAngle * Double(index)) - (itemAngle / 2)
        } else {
            // Clockwise: Calculate from START angle going forwards
            let baseAngle = sliceConfig.startAngle
            return baseAngle + (itemAngle * Double(index)) + (itemAngle / 2)
        }
    }
    
    // MARK: - Staggered Animation
    
    private func animateIconsIn() {
        // Dispatch to appropriate animation based on mode
        print("🎬 [RingView] animateIconsIn called - mode: \(animationMode)")
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
        
        // 🆕 Animate running indicators after all icons are done
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
        print("🎯 [CENTER-OUT] Starting animation for \(nodes.count) nodes")
        
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
        print("   Center point: \(centerPoint)")
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
            print("   Item \(index): rotation offset = \(rotationOffset)°")
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
            print("   Group 0 (center): [\(centerIndex)]")
        } else {
            // Even count: two center items
            let centerLeft = (totalCount / 2) - 1
            let centerRight = totalCount / 2
            animationGroups.append([centerLeft, centerRight])
            processed.insert(centerLeft)
            processed.insert(centerRight)
            print("   Group 0 (center): [\(centerLeft), \(centerRight)]")
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
                print("   Group \(animationGroups.count) (distance \(distance)): \(group)")
                animationGroups.append(group)
            }
            
            distance += 1
        }
        
        print("   Total groups: \(animationGroups.count)")
        print("   Stagger delay: \(effectiveStaggerDelay)s")
        
        // Animate each group with increasing delay
        for (groupIndex, group) in animationGroups.enumerated() {
            let delay = animationInitialDelay + (Double(groupIndex) * effectiveStaggerDelay)
            print("   Group \(groupIndex) will animate at \(delay)s")
            
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
}
