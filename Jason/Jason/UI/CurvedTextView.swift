//
//  CurvedTextView.swift
//  Jason
//
//  Created by Timothy Velberg on 12/10/2025.

import SwiftUI

struct CurvedTextView: View {
    let text: String
    let radius: CGFloat
    let frameSize: CGFloat
    let centerAngle: Double
    let font: NSFont
    let color: Color
    
    var body: some View {
        Text(text)
            .font(Font(font))
            .foregroundColor(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.8))
            .cornerRadius(4)
            .position(x: frameSize / 2, y: frameSize / 2 - radius - 16)
    }
}
