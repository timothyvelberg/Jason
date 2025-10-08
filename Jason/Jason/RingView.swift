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
    let onNodeTapped: (Int) -> Void
    let shouldDimOpacity: Bool
    let sliceConfig: PieSliceConfig  // NEW: Pie slice configuration
    
    // Visual properties
    private let backgroundColor: Color = .black.opacity(0.9)
    private let iconSize: CGFloat = 32
    
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
        return shouldDimOpacity ? .gray.opacity(0.25) : .blue.opacity(0.8)
    }
    
    var body: some View {
        ZStack {
            // Ring background - either full circle or partial slice
            if sliceConfig.isFullCircle {
                // Full circle background
                DonutShape(
                    holePercentage: innerRadiusRatio,
                    outerPercentage: 1.0
                )
                .fill(backgroundColor, style: FillStyle(eoFill: true))
                .frame(width: totalDiameter, height: totalDiameter)
            } else {
                // Partial slice background
                PieSliceShape(
                    startAngle: .degrees(sliceConfig.startAngle - 90),  // Adjust for 0° = top
                    endAngle: .degrees(sliceConfig.endAngle - 90),
                    innerRadiusRatio: innerRadiusRatio,
                    outerRadiusRatio: 1.0
                )
                .fill(backgroundColor, style: FillStyle(eoFill: true))
                .frame(width: totalDiameter, height: totalDiameter)
            }
            
            // Animated selection indicator
            if selectedIndex != nil {
                PieSliceShape(
                    startAngle: startAngle,
                    endAngle: endAngle,
                    innerRadiusRatio: innerRadiusRatio,
                    outerRadiusRatio: 1.0
                )
                .fill(selectionColor, style: FillStyle(eoFill: true))
                .frame(width: totalDiameter, height: totalDiameter)
            }
            
            // Icons positioned around the ring
            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                Image(nsImage: node.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .position(iconPosition(for: index))
                    .onTapGesture {
                        onNodeTapped(index)
                    }
            }
        }
        .frame(width: totalDiameter, height: totalDiameter)
        .opacity(ringOpacity)
        .scaleEffect(ringScale)
        .animation(.easeInOut(duration: 0.2), value: shouldDimOpacity)
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
                
                // Use slice config for initial angles
                let itemAngle = sliceConfig.itemAngle
                let baseAngle = sliceConfig.startAngle
                let angleOffset = baseAngle + (Double(index) * itemAngle) + (itemAngle / 2)
                
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
                
                let baseAngle = sliceConfig.startAngle
                let angleOffset = baseAngle + (Double(index) * itemAngle) + (itemAngle / 2)
                
                startAngle = Angle(degrees: angleOffset - itemAngle / 2 - 90)
                endAngle = Angle(degrees: angleOffset + itemAngle / 2 - 90)
            }
            return
        }
        
        guard let prevIndex = previousIndex, index != prevIndex else { return }
        
        var newRotationIndex = rotationIndex
        
        let forwardSteps = (index - prevIndex + totalCount) % totalCount
        let backwardSteps = (prevIndex - index + totalCount) % totalCount
        
        if forwardSteps <= backwardSteps {
            newRotationIndex += forwardSteps
        } else {
            newRotationIndex -= backwardSteps
        }
        
        let baseAngle = sliceConfig.startAngle
        let newAngleOffset = baseAngle + (Double(newRotationIndex) * itemAngle) + (itemAngle / 2)
        
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
        
        // Calculate position within the slice
        let itemAngle = sliceConfig.itemAngle
        let baseAngle = sliceConfig.startAngle
        
        // Position at the center of this item's slice
        let iconAngle = baseAngle + (itemAngle * Double(index)) + (itemAngle / 2)
        let angleInRadians = (iconAngle - 90) * (.pi / 180)  // Adjust for 0° = top
        
        let center = CGPoint(x: totalDiameter / 2, y: totalDiameter / 2)
        let x = center.x + middleRadius * cos(angleInRadians)
        let y = center.y + middleRadius * sin(angleInRadians)
        
        return CGPoint(x: x, y: y)
    }
}
