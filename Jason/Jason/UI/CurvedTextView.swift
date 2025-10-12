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
    let centerAngle: Double
    let font: NSFont
    let color: Color
    
    var body: some View {
        Text(text)
            .font(Font(font))
            .foregroundColor(color)
            .padding(.horizontal, 16)  // Add horizontal padding (left/right)
            .padding(.vertical, 8)    // Add vertical padding (top/bottom)
            .background(Color.black.opacity(0.8))  // DEBUG: so we can see it
    }
}
