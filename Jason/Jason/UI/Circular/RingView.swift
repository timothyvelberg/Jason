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
    let triggerDirection: RotationDirection?
    
    // Animation configuration
    let animationInitialDelay: Double = 0.06
    let animationBaseStaggerDelay: Double = 0.02
    let animationDuration: Double = 0.25
    let animationStartScale: CGFloat = 0.9
    let animationRotationOffset: Double = -10
    
    // Effective rotation offset - flipped for counter-clockwise triggers
    var effectiveRotationOffset: Double {
        print("🎬 [RingView] triggerDirection: \(String(describing: triggerDirection)), using offset: \(triggerDirection == .counterClockwise ? -animationRotationOffset : animationRotationOffset)")
        if triggerDirection == .counterClockwise {
            return -animationRotationOffset  // Flip: -10 becomes +10
        }
        return animationRotationOffset  // Default: -10 (clockwise)
    }
    
    // Animation mode selection
    enum AnimationMode {
        case linear
        case centerOut
    }
    
    // Automatically select animation mode based on slice positioning
    var animationMode: AnimationMode {
        return sliceConfig.positioning == .center ? .centerOut : .linear
    }
    
    // Animation state
    @State var startAngle: Angle = .degrees(0)
    @State var endAngle: Angle = .degrees(90)
    @State var angleOffset: Double = 0
    @State var previousIndex: Int? = nil
    @State var previousTotalCount: Int = 0
    @State var rotationIndex: Int = 0
    @State var hasAppeared: Bool = false
    @State var iconOpacities: [String: Double] = [:]
    @State var iconScales: [String: CGFloat] = [:]
    @State var iconRotationOffsets: [String: Double] = [:]
    @State var runningIndicatorOpacities: [String: Double] = [:]
    @State var badgeOpacities: [String: Double] = [:]
    
    // Animated slice background angles (for partial slice opening animation)
    @State var animatedSliceStartAngle: Angle = .degrees(0)
    @State var animatedSliceEndAngle: Angle = .degrees(0)
    
    // Selection indicator opacity (delayed fade-in)
    @State var selectionIndicatorOpacity: Double = 0
    @State var hasCompletedInitialSelectionFade: Bool = false
    
    // Diffing state: Track previous nodes for surgical updates
    @State var previousNodes: [FunctionNode] = []
    @State var isFirstRender: Bool = true
    
    // Computed adaptive stagger delay based on item count
    var adaptiveStaggerDelay: Double {
        let itemCount = nodes.count
        
        if itemCount <= 10 {
            return animationBaseStaggerDelay
        }
        
        let maxTotalStagger: Double = 0.05
        let calculatedDelay = maxTotalStagger / Double(itemCount - 1)
        
        return max(0.01, min(calculatedDelay, animationBaseStaggerDelay))
    }
    
    // Effective stagger delay based on animation mode
    var effectiveStaggerDelay: Double {
        switch animationMode {
        case .linear:
            return adaptiveStaggerDelay
        case .centerOut:
            return adaptiveStaggerDelay * 3.0
        }
    }
    
    // Calculated properties
    var endRadius: CGFloat {
        return startRadius + thickness
    }
    
    var middleRadius: CGFloat {
        return (startRadius + endRadius) / 2
    }
    
    var totalDiameter: CGFloat {
        return endRadius * 2
    }
    
    var innerRadiusRatio: CGFloat {
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
        ZStack {
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
                .allowsHitTesting(false)
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
                .allowsHitTesting(false)
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
                .opacity(selectionIndicatorOpacity)
                .allowsHitTesting(false)
            }
            
            // Icons positioned around the ring (non-interactive, just visual)
            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                let opacity = iconOpacities[node.id] ?? 0
                let scale = iconScales[node.id] ?? animationStartScale
                
                if node.type == .spacer {
                    // Render spacer as small dot
                    Circle()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 3, height: 3)
                        .scaleEffect(scale)
                        .opacity(opacity)
                        .position(iconPosition(for: index))
                        .allowsHitTesting(false)
                } else {
                    // Render icon with optional running indicator
                    let isRunning = (node.metadata?["isRunning"] as? Bool) ?? false
                    
                    ZStack {
                        Image(nsImage: node.icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: iconSize, height: iconSize)
                        
                        if isRunning {
                            Circle()
                                .fill(Color.white.opacity(0.16))
                                .frame(width: 3, height: 3)
                                .offset(y: iconSize / 2 + 2)
                                .opacity(runningIndicatorOpacities[node.id] ?? 0)
                        }
                    }
                    .rotationEffect(Angle(degrees: iconRotationOffsets[node.id] ?? 0))
                    .scaleEffect(scale)
                    .opacity(opacity)
                    .position(iconPosition(for: index))
                    .allowsHitTesting(false)
                }
            }
            // Badges positioned at top-right of icons
            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                badgeView(for: node, at: index)
            }
        }
        .frame(width: totalDiameter, height: totalDiameter)
        .scaleEffect(ringScale)
        .overlay(
            Group {
                if let selectedIndex = selectedIndex,
                   !shouldDimOpacity {
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
            handleNodesChanged()
        }
        .onChange(of: selectedIndex) {
            handleSelectedIndexChanged()
        }
        .onAppear {
            handleOnAppear()
        }
    }
    
    // MARK: - Lifecycle Handlers
    
    private func handleNodesChanged() {
        print("🔄 [RingView] Content changed - count: \(nodes.count)")
        print("   📌 State: isFirstRender=\(isFirstRender), previousNodes.count=\(previousNodes.count)")
        
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
        
        if previousNodes.count == nodes.count &&
           Set(previousNodes.map { $0.id }) == Set(nodes.map { $0.id }) {
            
            if !sliceConfig.isFullCircle && sliceConfig.positioning == .center {
                animatedSliceStartAngle = Angle(degrees: sliceConfig.startAngle)
                animatedSliceEndAngle = Angle(degrees: sliceConfig.endAngle)
            }
            
            // Always restore selection indicator for all layouts
            let selectionDelay = 0.05
            DispatchQueue.main.asyncAfter(deadline: .now() + selectionDelay) {
                withAnimation(.easeIn(duration: 0.2)) {
                    selectionIndicatorOpacity = 1.0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + selectionDelay + 0.2) {
                hasCompletedInitialSelectionFade = true
            }
            
            return
        }
        
        // First render vs Surgical update
        let isSurgicalUpdate: Bool
        if isFirstRender {
            isSurgicalUpdate = false
            isFirstRender = false
            print("   🎬 First render - full entrance animation")
        } else if previousNodes.isEmpty {
            isSurgicalUpdate = false
            print("   🎬 Previous nodes empty - full entrance animation")
        } else {
            let oldIds = Set(previousNodes.map { $0.id })
            let newIds = Set(nodes.map { $0.id })
            let changeCount = oldIds.symmetricDifference(newIds).count
            isSurgicalUpdate = changeCount <= 3
            print("   🔧 Change count: \(changeCount), surgical: \(isSurgicalUpdate)")
        }
        
        // Animate the background slice
        animateSliceBackground(isSurgicalUpdate: isSurgicalUpdate)
        
        if isSurgicalUpdate {
            print("   🎯 Surgical icon update - animating changed icons only")
            let oldNodesSnapshot = previousNodes
            previousNodes = nodes
            animateIconsSurgical(oldNodes: oldNodesSnapshot, newNodes: nodes)
        } else {
            print("   🎬 Full icon entrance animation")
            previousNodes = nodes
            animateIconsIn()
        }
    }
    
    private func handleSelectedIndexChanged() {
        if let index = selectedIndex {
            if index < nodes.count {
                let selectedNode = nodes[index]
            } else {
                print("   ❌ INVALID: index \(index) >= count \(nodes.count)")
            }
        }
        
        if let index = selectedIndex {
            updateSlice(for: index, totalCount: nodes.count)
            if hasCompletedInitialSelectionFade {
                selectionIndicatorOpacity = 1.0
            }
        }
    }
    
    private func handleOnAppear() {
        print("   🎬 [RingView] onAppear called - nodes.count=\(nodes.count), previousNodes.count=\(previousNodes.count)")
        
        selectionIndicatorOpacity = 0
        hasCompletedInitialSelectionFade = false
        
        if nodes.count > 0 {
            print("   🎬 Triggering initial icon entrance animation")
            animateIconsIn()
            previousNodes = nodes
            isFirstRender = false
        }
        
        // Animate the background slice opening
        animateSliceBackgroundOnAppear()
        
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
    
    // MARK: - Slice Background Animation Helpers
    
    private func animateSliceBackground(isSurgicalUpdate: Bool) {
        if !sliceConfig.isFullCircle && sliceConfig.positioning == .center {
            if isSurgicalUpdate {
                print("   ✨ Smooth resize animation")
                
                let adjustedEndAngle = sliceConfig.endAngle < sliceConfig.startAngle
                    ? sliceConfig.endAngle + 360
                    : sliceConfig.endAngle
                
                withAnimation(.easeOut(duration: 0.3)) {
                    animatedSliceStartAngle = Angle(degrees: sliceConfig.startAngle)
                    animatedSliceEndAngle = Angle(degrees: adjustedEndAngle)
                }
            } else {
                print("   🎬 Full entrance animation for slice")
                
                let initialSliceSize = 10.0
                
                let centerAngle: Double
                if sliceConfig.endAngle < sliceConfig.startAngle {
                    centerAngle = (sliceConfig.startAngle + (sliceConfig.endAngle + 360)) / 2
                } else {
                    centerAngle = (sliceConfig.startAngle + sliceConfig.endAngle) / 2
                }
                
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
            
            let selectionDelay = 0.05
            DispatchQueue.main.asyncAfter(deadline: .now() + selectionDelay) {
                withAnimation(.easeIn(duration: 0.2)) {
                    selectionIndicatorOpacity = 1.0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + selectionDelay + 0.2) {
                hasCompletedInitialSelectionFade = true
            }
        } else if !sliceConfig.isFullCircle {
            let adjustedEndAngle = sliceConfig.endAngle < sliceConfig.startAngle
                ? sliceConfig.endAngle + 360
                : sliceConfig.endAngle
            
            if isSurgicalUpdate {
                withAnimation(.easeOut(duration: 0.3)) {
                    animatedSliceStartAngle = Angle(degrees: sliceConfig.startAngle)
                    animatedSliceEndAngle = Angle(degrees: adjustedEndAngle)
                }
            } else {
                let initialSliceSize = 10.0
                
                if sliceConfig.direction == .counterClockwise {
                    animatedSliceStartAngle = Angle(degrees: adjustedEndAngle - initialSliceSize)
                    animatedSliceEndAngle = Angle(degrees: adjustedEndAngle)
                    
                    withAnimation(.easeOut(duration: 0.3)) {
                        animatedSliceStartAngle = Angle(degrees: sliceConfig.startAngle)
                    }
                } else {
                    animatedSliceStartAngle = Angle(degrees: sliceConfig.startAngle)
                    animatedSliceEndAngle = Angle(degrees: sliceConfig.startAngle + initialSliceSize)
                    
                    withAnimation(.easeOut(duration: 0.3)) {
                        animatedSliceEndAngle = Angle(degrees: adjustedEndAngle)
                    }
                }
            }
            
            let selectionDelay = 0.05
            DispatchQueue.main.asyncAfter(deadline: .now() + selectionDelay) {
                withAnimation(.easeIn(duration: 0.2)) {
                    selectionIndicatorOpacity = 1.0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + selectionDelay + 0.2) {
                hasCompletedInitialSelectionFade = true
            }
        } else {
            animatedSliceStartAngle = Angle(degrees: sliceConfig.startAngle)
            animatedSliceEndAngle = Angle(degrees: sliceConfig.endAngle)
            
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
    }
    
    private func animateSliceBackgroundOnAppear() {
        if !sliceConfig.isFullCircle && sliceConfig.positioning == .center {
            let initialSliceSize = 10.0
            
            let centerAngle: Double
            if sliceConfig.endAngle < sliceConfig.startAngle {
                centerAngle = (sliceConfig.startAngle + (sliceConfig.endAngle + 360)) / 2
            } else {
                centerAngle = (sliceConfig.startAngle + sliceConfig.endAngle) / 2
            }
            
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
            
            let selectionDelay = 0.05
            DispatchQueue.main.asyncAfter(deadline: .now() + selectionDelay) {
                withAnimation(.easeIn(duration: 0.2)) {
                    selectionIndicatorOpacity = 1.0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + selectionDelay + 0.2) {
                hasCompletedInitialSelectionFade = true
            }
        } else if !sliceConfig.isFullCircle {
            let initialSliceSize = 10.0
            
            let adjustedEndAngle = sliceConfig.endAngle < sliceConfig.startAngle
                ? sliceConfig.endAngle + 360
                : sliceConfig.endAngle
            
            if sliceConfig.direction == .counterClockwise {
                animatedSliceStartAngle = Angle(degrees: adjustedEndAngle - initialSliceSize)
                animatedSliceEndAngle = Angle(degrees: adjustedEndAngle)
                
                withAnimation(.easeOut(duration: 0.24)) {
                    animatedSliceStartAngle = Angle(degrees: sliceConfig.startAngle)
                }
            } else {
                animatedSliceStartAngle = Angle(degrees: sliceConfig.startAngle)
                animatedSliceEndAngle = Angle(degrees: sliceConfig.startAngle + initialSliceSize)
                
                withAnimation(.easeOut(duration: 0.24)) {
                    animatedSliceEndAngle = Angle(degrees: adjustedEndAngle)
                }
            }
            
            let selectionDelay = 0.05
            DispatchQueue.main.asyncAfter(deadline: .now() + selectionDelay) {
                withAnimation(.easeIn(duration: 0.2)) {
                    selectionIndicatorOpacity = 1.0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + selectionDelay + 0.2) {
                hasCompletedInitialSelectionFade = true
            }
        } else {
            animatedSliceStartAngle = Angle(degrees: sliceConfig.startAngle)
            animatedSliceEndAngle = Angle(degrees: sliceConfig.endAngle)
            
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
    }
    
    // MARK: - Badge Rendering

    @ViewBuilder
    func badgeView(for node: FunctionNode, at index: Int) -> some View {
        if let metadata = node.metadata,
           let badge = metadata["badge"] as? String,
           !badge.isEmpty {
            
            let badgeSize: CGFloat = badge.count > 2 ? 20 : 16
            let position = iconPosition(for: index)
            let badgeOffset = iconSize / 2 - 4
            
            ZStack {
                Capsule()
                    .fill(Color.red)
                    .frame(width: badgeSize, height: 16)
                
                Text(badge)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
            .opacity(badgeOpacities[node.id] ?? 0)
            .position(
                x: position.x + badgeOffset,
                y: position.y - badgeOffset
            )
            .allowsHitTesting(false)
        }
    }
}
