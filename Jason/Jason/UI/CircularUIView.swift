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
    
    // Get ring configurations directly from FunctionManager
    private var rings: [RingConfiguration] {
        return functionManager.ringConfigurations
    }
    
    // Total size for all rings
    private var totalSize: CGFloat {
        guard let lastRing = rings.last else { return 100 }
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
                        },
                        shouldDimOpacity: shouldDimRing(ring.level),
                        sliceConfig: ring.sliceConfig  // NEW: Pass slice configuration
                    )
                    .transition(.customScale(from: 0.7))
                    .id("\(ring.level)-\(functionManager.ringResetTrigger)")
                }
            }
            .animation(.easeOut(duration: 0.1), value: rings.count)
            .frame(width: totalSize, height: totalSize)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .ignoresSafeArea()
    }
    
    private func shouldDimRing(_ level: Int) -> Bool {
        // Dim all rings except the active one
        return level != functionManager.activeRingLevel
    }
    
    private func handleRingTap(level: Int, index: Int) {
        // Select the node
        functionManager.selectNode(ringLevel: level, index: index)
        
        // Get the node to check what to do
        guard level < functionManager.rings.count else { return }
        guard index < functionManager.rings[level].nodes.count else { return }
        
        let node = functionManager.rings[level].nodes[index]
        
        // NEW LOGIC: Check if node has a primary action first
        if let action = node.onSelect {
            // Has a primary action - execute it (whether leaf or branch)
            print("🖱️ Tapped node: \(node.name) - executing primary action")
            action()
            
            // Hide UI after action completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                circularUI.hide()
            }
        } else if node.isBranch {
            // No primary action, but has children - expand on click as fallback
            print("🖱️ Tapped branch node without action: \(node.name) - expanding")
            functionManager.expandCategory(ringLevel: level, index: index)
        } else {
            // No action and no children - do nothing
            print("⚠️ Tapped node with no action or children: \(node.name)")
        }
    }
}

// MARK: - Ring Configuration

struct RingConfiguration: Identifiable {
    var id: Int { level }
    let level: Int
    let startRadius: CGFloat
    let thickness: CGFloat
    let nodes: [FunctionNode]
    let selectedIndex: Int?
    let sliceConfig: PieSliceConfig  // NEW: Pie slice configuration
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
