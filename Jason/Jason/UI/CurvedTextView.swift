//
//  CurvedTextView.swift
//  Jason
//
//  Created by Timothy Velberg on 12/10/2025.
//

import SwiftUI

import SwiftUI

struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: Double = 0
    static func reduce(value: inout Double, nextValue: () -> Double) {
        value = nextValue()
    }
}

struct Sizeable: View {
    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .preference(key: WidthPreferenceKey.self, value: geometry.size.width)
        }
    }
}

struct CurvedTextView: View {
    let text: String
    let radius: CGFloat
    let frameSize: CGFloat
    let centerAngle: Double
    let font: NSFont
    let color: Color
    
    @State private var textWidths: [Int: Double] = [:]
    
    private var texts: [(offset: Int, element: Character)] {
        return Array(text.enumerated())
    }
    
    var body: some View {
        ZStack {
            ForEach(texts, id: \.offset) { index, letter in
                VStack {
                    Text(String(letter))
                        .font(Font(font))
                        .foregroundColor(color)
                        .background(Sizeable())
                        .onPreferenceChange(WidthPreferenceKey.self) { width in
                            textWidths[index] = width
                        }
                        .offset(y: -(radius - frameSize / 2))
                    Spacer()
                }
                .rotationEffect(angle(at: index))
            }
        }
        .frame(width: frameSize, height: frameSize)
    }
    
    private func angle(at index: Int) -> Angle {
        guard let labelWidth = textWidths[index] else { return .radians(0) }
        
        let circumference = radius * 2 * .pi
        
        let percent = labelWidth / circumference
        let labelAngle = percent * 2 * .pi
        
        let widthBeforeLabel = textWidths.filter { $0.key < index }.map { $0.value }.reduce(0, +)
        let percentBeforeLabel = widthBeforeLabel / circumference
        let angleBeforeLabel = percentBeforeLabel * 2 * .pi
        
        return .radians(angleBeforeLabel + labelAngle)
    }
}
