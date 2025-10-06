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
            
            // Selection indicator (if any item is selected)
            if let selectedIndex = selectedIndex, nodes.indices.contains(selectedIndex) {
                let sliceSize = 360.0 / Double(nodes.count)
                let angleOffset = -90 + (Double(selectedIndex) * sliceSize)
                
                PieSliceShape(
                    startAngle: Angle(degrees: angleOffset - sliceSize / 2),
                    endAngle: Angle(degrees: angleOffset + sliceSize / 2),
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
