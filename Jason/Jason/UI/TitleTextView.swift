//
//  TitleTextView.swift
//  Jason
//
//  Created by Timothy Velberg on 12/10/2025.

import SwiftUI

struct TitleTextView: View {
    let text: String
    let radius: CGFloat
    let frameSize: CGFloat
    let centerAngle: Double
    let font: NSFont
    let color: Color
    
    // Distance to offset the title from the ring (outward)
    // This accounts for visual margin + half the text box's radial dimension
    private let titleOffset: CGFloat = 36
    
    // Animation state
    @State private var opacity: Double = 0
    
    var body: some View {
        Text(text)
            .font(Font(font))
            .foregroundColor(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.95))
            .cornerRadius(4)
            .position(calculatePosition())
            .opacity(opacity)
            .onAppear {
                // Initial fade-in when view first appears
                withAnimation(.easeIn(duration: 0.3)) {
                    opacity = 1.0
                }
            }
            .onChange(of: text) {
                // Reset and fade-in when selection changes
                opacity = 0
                withAnimation(.easeIn(duration: 0.3)) {
                    opacity = 1.0
                }
            }
    }
    
    private func calculatePosition() -> CGPoint {
        // Convert centerAngle to radians (subtract 90° to align with ring coordinate system)
        let angleInRadians = (centerAngle - 90) * (.pi / 180)
        
        // Calculate position at radius + offset (places text box beyond ring edge)
        let effectiveRadius = radius + titleOffset
        
        // Center point of the ring
        let center = CGPoint(x: frameSize / 2, y: frameSize / 2)
        
        // Polar to Cartesian conversion
        let x = center.x + effectiveRadius * cos(angleInRadians)
        let y = center.y + effectiveRadius * sin(angleInRadians)
        
        return CGPoint(x: x, y: y)
    }
}
