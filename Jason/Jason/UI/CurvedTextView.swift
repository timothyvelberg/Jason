//
//  CurvedTextView.swift
//  Jason
//
//  Created by Timothy Velberg on 12/10/2025.
//

import SwiftUI

struct CurvedTextView: View {
    let text: String
    let radius: CGFloat
    let centerAngle: Double  // Center angle in degrees (0° = top)
    let font: NSFont
    let color: Color
    
    private let characterSpacing: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Individual characters positioned around the circle
            ForEach(Array(text.enumerated()), id: \.offset) { index, char in
                Text(String(char))
                    .font(Font(font))
                    .foregroundColor(color)
                    .position(positionFor(character: index))
                    .rotationEffect(rotationFor(character: index))
            }
        }
        .frame(width: radius * 2, height: radius * 2)
    }
    
    // MARK: - Character Positioning
    
    private func positionFor(character index: Int) -> CGPoint {
        let angle = angleFor(character: index)
        let angleInRadians = (angle - 90) * (.pi / 180)  // -90 because 0° = top
        
        let center = CGPoint(x: radius, y: radius)
        let x = center.x + radius * cos(angleInRadians)
        let y = center.y + radius * sin(angleInRadians)
        
        return CGPoint(x: x, y: y)
    }
    
    private func rotationFor(character index: Int) -> Angle {
        let angle = angleFor(character: index)
        return .degrees(angle + 90)  // Tangent to circle
    }
    
    private func angleFor(character index: Int) -> Double {
        let textWidth = calculateTextWidth()
        let textAngularWidth = angularWidth(textWidth: textWidth, radius: radius)
        
        // Start angle: center the text around centerAngle
        let halfWidth = textAngularWidth / 2.0
        let startAngle = centerAngle - halfWidth
        
        // Distribute characters evenly
        let charAngularWidth = textAngularWidth / Double(text.count)
        return startAngle + (Double(index) * charAngularWidth) + (charAngularWidth / 2.0)
    }
    
    // MARK: - Math Helpers
    
    private func angularWidth(textWidth: CGFloat, radius: CGFloat) -> Double {
        let arcLength = textWidth
        let circumference = 2 * .pi * radius
        let ratio = arcLength / circumference
        return ratio * 360.0  // degrees
    }
    
    private func calculateTextWidth() -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attributes)
        return size.width + (CGFloat(text.count - 1) * characterSpacing)
    }
}
