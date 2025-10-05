//
//  CircularUIView.swift
//  Jason
//
//  Created by Timothy Velberg on 05/10/2025.
//

import SwiftUI
import AppKit

struct CircularUIView: View {
    @ObservedObject var circularUI: CircularUIManager
    @ObservedObject var functionManager: FunctionManager
    
    private var functionList: [FunctionItem] {
        functionManager.currentFunctionList
    }
    
    private var selectedFunctionIndex: Int {
        functionManager.currentSelectedIndex  // Changed to use computed property
    }
    
    // Dynamic wheel size based on function count
    private var wheelSize: CGFloat {
        let baseSize: CGFloat = 160
        let extraSizePerItem: CGFloat = 24
        let maxSize: CGFloat = 1000
        
        let calculatedSize = baseSize + (CGFloat(functionList.count) * extraSizePerItem)
        return min(maxSize, calculatedSize)
    }
    
    private var holePercentage: CGFloat { 0.33 }
    
    private var calculatedRadius: CGFloat {
        let outerRadius: CGFloat = wheelSize / 2
        let holeRadius: CGFloat = outerRadius * holePercentage
        let middleRadius: CGFloat = (outerRadius + holeRadius) / 2
        return middleRadius
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
                
                // Background donut
                DonutShape(holePercentage: holePercentage)
                    .fill(donutBackgroundColor, style: FillStyle(eoFill: true))
                    .frame(width: wheelSize, height: wheelSize)
                
                // Animated highlight slice
                PieSliceShape(
                    startAngle: startAngle,
                    endAngle: endAngle,
                    innerRadiusRatio: holePercentage
                )
                .fill(sliceColor, style: FillStyle(eoFill: true))
                .frame(width: wheelSize, height: wheelSize)
                
                // App icons positioned in a circle
                ForEach(Array(functionList.enumerated()), id: \.offset) { index, item in
                    let icon = item.icon
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .position(centeredCircularPosition(index: index, total: functionList.count, radius: calculatedRadius))
                }
            }
            .frame(width: wheelSize, height: wheelSize)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .ignoresSafeArea()
        .onAppear {
            // Initialize slice on first appearance
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
        
        // Only animate if index changed, but always set the angles
        if index != previousIndex {
            var newRotationIndex = rotationIndex
            
            // Calculate shortest rotation direction
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
            // Initial setup without animation
            let angleOffset = Double(index) * sliceSize - 90 - sliceSize
            startAngle = Angle(degrees: angleOffset - sliceSize / 2)
            endAngle = Angle(degrees: angleOffset + sliceSize / 2)
        }
    }
    
    private func centeredCircularPosition(index: Int, total: Int, radius: CGFloat) -> CGPoint {
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
