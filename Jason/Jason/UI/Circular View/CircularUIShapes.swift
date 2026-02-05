//
//  CircularUIShapes.swift
//  Jason
//
//  Created by Timothy Velberg on 05/10/2025.
//

import SwiftUI

// MARK: - Donut Shape (Full circular background)
struct DonutShape: Shape {
    let holePercentage: CGFloat
    let outerPercentage: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maxRadius = min(rect.width, rect.height) / 2
        let outerRadius = maxRadius * outerPercentage
        let innerRadius = maxRadius * holePercentage
        
        // Outer circle - counterclockwise
        path.addArc(center: center, radius: outerRadius,
                    startAngle: .degrees(0), endAngle: .degrees(360),
                    clockwise: false)
        
        // Inner circle - clockwise (opposite direction creates hole)
        path.addArc(center: center, radius: innerRadius,
                    startAngle: .degrees(0), endAngle: .degrees(360),
                    clockwise: true)
        
        return path
    }
}

// MARK: - Pie Slice Shape (Animated highlight)
struct PieSliceShape: Shape {
    var startAngle: Angle
    var endAngle: Angle
    var innerRadiusRatio: CGFloat
    var outerRadiusRatio: CGFloat
    var insetPercentage: CGFloat = 0.0
    
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(startAngle.degrees, endAngle.degrees) }
        set {
            startAngle = Angle(degrees: newValue.first)
            endAngle = Angle(degrees: newValue.second)
        }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maxRadius = min(rect.width, rect.height) / 2
        let outerRadius = (maxRadius * outerRadiusRatio) - insetPercentage
        let innerRadius = (maxRadius * innerRadiusRatio) + insetPercentage
        
        path.addArc(center: center, radius: outerRadius,
                    startAngle: startAngle, endAngle: endAngle,
                    clockwise: false)
        path.addArc(center: center, radius: innerRadius,
                    startAngle: endAngle, endAngle: startAngle,
                    clockwise: true)
        path.closeSubpath()
        
        return path
    }
}
