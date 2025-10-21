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
    
    // Animation state
    @State private var startAngle: Angle = .degrees(0)
    @State private var endAngle: Angle = .degrees(90)
    @State private var angleOffset: Double = 0
    @State private var previousIndex: Int? = nil
    @State private var rotationIndex: Int = 0
    @State private var hasAppeared: Bool = false
    
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
                        startAngle: .degrees(sliceConfig.startAngle - 90),
                        endAngle: .degrees(sliceConfig.endAngle - 90),
                        innerRadiusRatio: innerRadiusRatio,
                        outerRadiusRatio: 1.0
                    )
                    .fill(Color.black.opacity(0.33))
                    
                    // Blur material layer
                    PieSliceShape(
                        startAngle: .degrees(sliceConfig.startAngle - 90),
                        endAngle: .degrees(sliceConfig.endAngle - 90),
                        innerRadiusRatio: innerRadiusRatio,
                        outerRadiusRatio: 1.0
                    )
                    .fill(.ultraThinMaterial)
                    
                    // Border
                    PieSliceShape(
                        startAngle: .degrees(sliceConfig.startAngle - 90),
                        endAngle: .degrees(sliceConfig.endAngle - 90),
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
                .allowsHitTesting(false)  // Don't block clicks
            }
            
            // Icons positioned around the ring (non-interactive, just visual)
            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                Image(nsImage: node.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
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
        }
        .onChange(of: selectedIndex) {
            if let index = selectedIndex {
                updateSlice(for: index, totalCount: nodes.count)
            }
        }
        .onAppear {
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
        
        let angleInRadians = (iconAngle - 90) * (.pi / 180)
        
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
}
