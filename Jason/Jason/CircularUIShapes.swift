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
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = rect.width / 2
        let innerRadius = outerRadius * holePercentage

        // Outer circle
        path.addArc(center: center, radius: outerRadius, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)

        // Inner circle (creates the hole)
        var innerPath = Path()
        innerPath.addArc(center: center, radius: innerRadius, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        
        path.addPath(innerPath)
        
        return path
    }
}

// MARK: - Pie Slice Shape (Animated highlight)

struct PieSliceShape: Shape {
    var startAngle: Angle
    var endAngle: Angle
    var innerRadiusRatio: CGFloat

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
        let outerRadius = rect.width / 2
        let innerRadius = outerRadius * innerRadiusRatio

        // Outer pie slice
        path.move(to: center)
        path.addArc(center: center, radius: outerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.closeSubpath()

        // Inner cutout
        var innerPath = Path()
        innerPath.move(to: center)
        innerPath.addArc(center: center, radius: innerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        innerPath.closeSubpath()

        // Combine paths to create cutout effect
        path.addPath(innerPath)

        return path
    }
}
