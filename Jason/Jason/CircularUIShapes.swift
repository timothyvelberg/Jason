//
//  CircularUIShapes.swift
//  Jason
//
//  Created by Timothy Velberg on 05/10/2025.
//

import SwiftUI

// MARK: - Donut Shape

struct DonutShape: Shape {
    let holePercentage: CGFloat
    let outerPercentage: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maxRadius = rect.width / 2
        let outerRadius = maxRadius * outerPercentage
        let innerRadius = maxRadius * holePercentage

        path.addArc(center: center, radius: outerRadius, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)

        var innerPath = Path()
        innerPath.addArc(center: center, radius: innerRadius, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        
        path.addPath(innerPath)
        
        return path
    }
}

// MARK: - Pie Slice Shape

struct PieSliceShape: Shape {
    var startAngle: Angle
    var endAngle: Angle
    var innerRadiusRatio: CGFloat
    var outerRadiusRatio: CGFloat

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
        let maxRadius = rect.width / 2
        let outerRadius = maxRadius * outerRadiusRatio
        let innerRadius = maxRadius * innerRadiusRatio

        path.move(to: center)
        path.addArc(center: center, radius: outerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.closeSubpath()

        var innerPath = Path()
        innerPath.move(to: center)
        innerPath.addArc(center: center, radius: innerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        innerPath.closeSubpath()

        path.addPath(innerPath)

        return path
    }
}
