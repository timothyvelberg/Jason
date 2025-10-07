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
    
    // Visual properties
    private let backgroundColor: Color = .black.opacity(0.8)
    private let selectionColor: Color = .blue.opacity(0.8)
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
    
    // NEW: Computed opacity based on shouldDimOpacity
    private var ringOpacity: Double {
        return shouldDimOpacity ? 0.9 : 1.0
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
        .opacity(ringOpacity)  // NEW: Apply opacity to entire ring
        .animation(.easeInOut(duration: 0.2), value: shouldDimOpacity)  // NEW: Animate opacity changes
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
                let sliceSize = 360.0 / Double(totalCount)
                let angleOffset = Double(index) * sliceSize - 90
                startAngle = Angle(degrees: angleOffset - sliceSize / 2)
                endAngle = Angle(degrees: angleOffset + sliceSize / 2)
            } else {
                rotationIndex = 0
                previousIndex = nil
                hasAppeared = false
                startAngle = .degrees(0)
                endAngle = .degrees(90)
            }
        }
    }
    
    private func updateSlice(for index: Int, totalCount: Int) {
        guard totalCount > 0 else { return }
        
        let sliceSize = 360.0 / Double(totalCount)
        
        if previousIndex == nil || !hasAppeared {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                rotationIndex = index
                previousIndex = index
                hasAppeared = true
                let angleOffset = Double(index) * sliceSize - 90
                startAngle = Angle(degrees: angleOffset - sliceSize / 2)
                endAngle = Angle(degrees: angleOffset + sliceSize / 2)
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
        let iconAngle = -90 + (sliceSize * CGFloat(index))
        let angleInRadians = iconAngle * (.pi / 180)
        
        let center = CGPoint(x: totalDiameter / 2, y: totalDiameter / 2)
        let x = center.x + middleRadius * cos(angleInRadians)
        let y = center.y + middleRadius * sin(angleInRadians)
        
        return CGPoint(x: x, y: y)
    }
}
