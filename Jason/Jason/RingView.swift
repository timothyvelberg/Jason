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
    
    // Visual properties
    private let backgroundColor: Color = .black.opacity(0.8)
    private let selectionColor: Color = .blue.opacity(0.8)
    private let iconSize: CGFloat = 48
    
    // Animation state - matching the old working version
    @State private var startAngle: Angle = .degrees(0)
    @State private var endAngle: Angle = .degrees(90)
    @State private var angleOffset: Double = 0
    @State private var previousIndex: Int = 0
    @State private var rotationIndex: Int = 0
    
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
    
    // Convert to percentage for shapes (relative to total diameter)
    private var innerRadiusRatio: CGFloat {
        return startRadius / endRadius
    }
    
    var body: some View {
        ZStack {
            // Ring background
            DonutShape(
                holePercentage: innerRadiusRatio,
                outerPercentage: 1.0
            )
            .fill(backgroundColor, style: FillStyle(eoFill: true))
            .frame(width: totalDiameter, height: totalDiameter)
            
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
        .onChange(of: nodes.count) {
            // Reset animation state when node count changes
            if let index = selectedIndex {
                rotationIndex = index
                previousIndex = index
                updateSlice(for: index, totalCount: nodes.count)
            }
        }
        .onChange(of: selectedIndex) {
            if let index = selectedIndex {
                updateSlice(for: index, totalCount: nodes.count)
            }
        }
    }
    
    private func updateSlice(for index: Int, totalCount: Int) {
        guard index != previousIndex else { return }
        guard totalCount > 0 else { return }
        
        let sliceSize = 360.0 / Double(totalCount)
        var newRotationIndex = rotationIndex
        
        // Calculate shortest rotation direction (same as old version)
        let forwardSteps = (index - previousIndex + totalCount) % totalCount
        let backwardSteps = (previousIndex - index + totalCount) % totalCount
        
        if forwardSteps <= backwardSteps {
            newRotationIndex += forwardSteps
        } else {
            newRotationIndex -= backwardSteps
        }
        
        // Use the EXACT same formula as the old working version
        let newAngleOffset = Double(newRotationIndex) * sliceSize - 90
        
        withAnimation(.easeOut(duration: 0.08)) {
            angleOffset = newAngleOffset
            startAngle = Angle(degrees: angleOffset - sliceSize / 2)
            endAngle = Angle(degrees: angleOffset + sliceSize / 2)
        }
        
        previousIndex = index
        rotationIndex = newRotationIndex
    }
    
    private func iconPosition(for index: Int) -> CGPoint {
        guard nodes.count > 0 else {
            return CGPoint(x: totalDiameter / 2, y: totalDiameter / 2)
        }
        
        let sliceSize = 360.0 / CGFloat(nodes.count)
        // Position icon at the start of its slice (aligned with mouse tracking)
        let iconAngle = -90 + (sliceSize * CGFloat(index))
        let angleInRadians = iconAngle * (.pi / 180)
        
        // Calculate position relative to this ring's center
        let center = CGPoint(x: totalDiameter / 2, y: totalDiameter / 2)
        let x = center.x + middleRadius * cos(angleInRadians)
        let y = center.y + middleRadius * sin(angleInRadians)
        
        return CGPoint(x: x, y: y)
    }
}
