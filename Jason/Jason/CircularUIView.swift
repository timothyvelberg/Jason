//
//  CircularUIView.swift
//  Jason
//
//  Created by Timothy Velberg on 31/07/2025.
//

import SwiftUI
import AppKit

struct CircularUIView: View {
    @ObservedObject var circularUI: CircularUIManager
    @ObservedObject var functionManager: FunctionManager
    
    // Inner ring properties
    private var innerRingNodes: [FunctionNode] {
        functionManager.innerRingNodes
    }
    
    // Outer ring properties
    private var outerRingNodes: [FunctionNode] {
        functionManager.outerRingNodes
    }
    
    private var shouldShowOuterRing: Bool {
        functionManager.shouldShowOuterRing
    }
    
    private var selectedInnerIndex: Int {
        functionManager.selectedIndex
    }
    
    private var selectedOuterIndex: Int {
        functionManager.selectedOuterIndex
    }
    
    // For backward compatibility with mouse tracking
    private var functionList: [FunctionItem] {
        functionManager.currentFunctionList
    }
    
    private var selectedFunctionIndex: Int {
        functionManager.currentSelectedIndex
    }
    
    // Dynamic wheel sizing
    private var baseWheelSize: CGFloat {
        let baseSize: CGFloat = 160
        let extraSizePerItem: CGFloat = 24
        let maxSize: CGFloat = 1000
        
        let calculatedSize = baseSize + (CGFloat(innerRingNodes.count) * extraSizePerItem)
        return min(maxSize, calculatedSize)
    }
    
    // Adjust wheel size if outer ring is shown
    private var wheelSize: CGFloat {
        return shouldShowOuterRing ? baseWheelSize + 120 : baseWheelSize
    }
    
    // Inner ring geometry
    private var innerHolePercentage: CGFloat { 0.33 }
    private var innerRingThickness: CGFloat { 0.30 }  // 30% of radius
    
    // Outer ring geometry (only when shown)
    private var outerRingStart: CGFloat { innerHolePercentage + innerRingThickness }
    private var outerRingThickness: CGFloat { 0.25 }
    
    private var innerRadius: CGFloat {
        let outerRadius = wheelSize / 2
        let holeRadius = outerRadius * innerHolePercentage
        let innerRingOuter = outerRadius * (innerHolePercentage + innerRingThickness)
        return (holeRadius + innerRingOuter) / 2
    }
    
    private var outerRadius: CGFloat {
        let outerRadius = wheelSize / 2
        let outerRingInner = outerRadius * outerRingStart
        return (outerRingInner + outerRadius) / 2
    }
    
    @State private var startAngle: Angle = .degrees(0)
    @State private var endAngle: Angle = .degrees(90)
    @State private var angleOffset: Double = 0
    @State private var previousIndex: Int = 0
    @State private var rotationIndex: Int = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                let donutBackgroundColor: Color = .black.opacity(0.8)
                let sliceColor: Color = .blue.opacity(0.8)
                
                // INNER RING - Background donut
                DonutShape(
                    holePercentage: innerHolePercentage,
                    outerPercentage: innerHolePercentage + innerRingThickness
                )
                .fill(donutBackgroundColor, style: FillStyle(eoFill: true))
                .frame(width: wheelSize, height: wheelSize)
                
                // INNER RING - Animated highlight slice
                PieSliceShape(
                    startAngle: startAngle,
                    endAngle: endAngle,
                    innerRadiusRatio: innerHolePercentage,
                    outerRadiusRatio: innerHolePercentage + innerRingThickness
                )
                .fill(sliceColor, style: FillStyle(eoFill: true))
                .frame(width: wheelSize, height: wheelSize)
                
                // INNER RING - Icons
                ForEach(Array(innerRingNodes.enumerated()), id: \.element.id) { index, node in
                    Image(nsImage: node.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .position(circularPosition(
                            index: index,
                            total: innerRingNodes.count,
                            radius: innerRadius
                        ))
                        .onTapGesture {
                            functionManager.selectInnerRing(at: index)
                        }
                }
                
                // OUTER RING (if should be shown)
                if shouldShowOuterRing {
                    // OUTER RING - Background donut
                    DonutShape(
                        holePercentage: outerRingStart,
                        outerPercentage: 1.0
                    )
                    .fill(donutBackgroundColor.opacity(0.6), style: FillStyle(eoFill: true))
                    .frame(width: wheelSize, height: wheelSize)
                    
                    // OUTER RING - Icons
                    ForEach(Array(outerRingNodes.enumerated()), id: \.element.id) { index, node in
                        Image(nsImage: node.icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .position(circularPosition(
                                index: index,
                                total: outerRingNodes.count,
                                radius: outerRadius
                            ))
                            .onTapGesture {
                                functionManager.selectOuterRing(at: index)
                            }
                    }
                }
            }
            .frame(width: wheelSize, height: wheelSize)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .ignoresSafeArea()
        .onAppear {
            updateSlice(for: selectedFunctionIndex, totalCount: functionList.count)
        }
        .onChange(of: functionList.count) {
            rotationIndex = selectedFunctionIndex
            previousIndex = selectedFunctionIndex
            updateSlice(for: selectedFunctionIndex, totalCount: functionList.count)
        }
        .onChange(of: selectedFunctionIndex) {
            updateSlice(for: selectedFunctionIndex, totalCount: functionList.count)
        }
    }
    
    private func updateSlice(for index: Int, totalCount: Int) {
        guard totalCount > 0 else { return }
        
        let sliceSize = 360.0 / Double(totalCount)
        
        if index != previousIndex {
            var newRotationIndex = rotationIndex
            
            let forwardSteps = (index - previousIndex + totalCount) % totalCount
            let backwardSteps = (previousIndex - index + totalCount) % totalCount
            
            if forwardSteps <= backwardSteps {
                newRotationIndex += forwardSteps
            } else {
                newRotationIndex -= backwardSteps
            }
            
            let newAngleOffset = Double(newRotationIndex) * sliceSize - 90 - sliceSize
            
            withAnimation(.easeInOut(duration: 0.08)) {
                angleOffset = newAngleOffset
                startAngle = Angle(degrees: angleOffset - sliceSize / 2)
                endAngle = Angle(degrees: angleOffset + sliceSize / 2)
            }
            
            previousIndex = index
            rotationIndex = newRotationIndex
        } else {
            let angleOffset = Double(index) * sliceSize - 90 - sliceSize
            startAngle = Angle(degrees: angleOffset - sliceSize / 2)
            endAngle = Angle(degrees: angleOffset + sliceSize / 2)
        }
    }
    
    private func circularPosition(index: Int, total: Int, radius: CGFloat) -> CGPoint {
        guard total > 0 else { return CGPoint(x: wheelSize/2, y: wheelSize/2) }
        
        let sliceSize = 360.0 / CGFloat(total)
        let iconAngle = sliceSize * CGFloat(index) - 90 + -sliceSize
        
        let angleInRadians = iconAngle * (.pi / 180)
        let center = CGPoint(x: wheelSize/2, y: wheelSize/2)
        
        let x = center.x + radius * cos(angleInRadians)
        let y = center.y + radius * sin(angleInRadians)
        
        return CGPoint(x: x, y: y)
    }
}
