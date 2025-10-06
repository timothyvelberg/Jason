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
    
    // Ring configuration
    private let centerHoleRadius: CGFloat = 50
    private let ringThickness: CGFloat = 80
    private let ringMargin: CGFloat = 4  // Gap between rings
    
    // Calculate rings to display
    private var rings: [RingConfiguration] {
        var result: [RingConfiguration] = []
        var currentRadius = centerHoleRadius
        
        // Inner ring - always shown
        result.append(RingConfiguration(
            level: 0,
            startRadius: currentRadius,
            thickness: ringThickness,
            nodes: functionManager.innerRingNodes,
            selectedIndex: functionManager.hoveredIndex
        ))
        currentRadius += ringThickness + ringMargin
        
        // Outer ring - only if expanded
        if functionManager.shouldShowOuterRing {
            result.append(RingConfiguration(
                level: 1,
                startRadius: currentRadius,
                thickness: ringThickness,
                nodes: functionManager.outerRingNodes,
                selectedIndex: functionManager.hoveredOuterIndex  // Changed from selectedOuterIndex
            ))
            currentRadius += ringThickness + ringMargin
        }
        
        return result
    }
    
    // Total size for all rings
    private var totalSize: CGFloat {
        guard let lastRing = rings.last else { return centerHoleRadius * 2 }
        return (lastRing.startRadius + lastRing.thickness) * 2 + 40
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Generate rings dynamically
                ForEach(rings) { ring in
                    RingView(
                        startRadius: ring.startRadius,
                        thickness: ring.thickness,
                        nodes: ring.nodes,
                        selectedIndex: ring.selectedIndex,
                        onNodeTapped: { index in
                            handleRingTap(level: ring.level, index: index)
                        }
                    )
                    .transition(.customScale(from: 0.7))  // Customize starting scale here
                    .id(ring.level)  // Use stable identifier based on ring level
                }
            }
            .animation(.easeOut(duration: 0.05), value: rings.count)
            .frame(width: totalSize, height: totalSize)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .ignoresSafeArea()
    }
    
    private func handleRingTap(level: Int, index: Int) {
        switch level {
        case 0:
            functionManager.selectInnerRing(at: index)
        case 1:
            functionManager.selectOuterRing(at: index)
        default:
            print("Unknown ring level: \(level)")
        }
    }
}

// MARK: - Ring Configuration

struct RingConfiguration: Identifiable {
    // Use level as stable identifier instead of UUID
    var id: Int { level }
    let level: Int
    let startRadius: CGFloat
    let thickness: CGFloat
    let nodes: [FunctionNode]
    let selectedIndex: Int?
}

// MARK: - Custom Scale Transition

extension AnyTransition {
    static func customScale(from startScale: CGFloat) -> AnyTransition {
        .modifier(
            active: ScaleModifier(scale: startScale, opacity: 0),
            identity: ScaleModifier(scale: 1.0, opacity: 1)
        )
    }
}

struct ScaleModifier: ViewModifier {
    let scale: CGFloat
    let opacity: Double
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
    }
}
