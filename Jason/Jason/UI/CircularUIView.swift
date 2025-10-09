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
                // Global click handler - executes currently hovered item
                // This allows clicking ANYWHERE to execute the hovered item
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .onTapGesture {
                        handleGlobalClick()
                    }
                
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
                        sliceConfig: ring.sliceConfig
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CircularUIRightClick"))) { _ in
            handleGlobalRightClick()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CircularUIMiddleClick"))) { _ in
            handleGlobalMiddleClick()
        }
    }
    
    private func shouldDimRing(_ level: Int) -> Bool {
        // Dim all rings except the active one
        return level != functionManager.activeRingLevel
    }
    
    // MARK: - Middle Click Handler
    
    private func handleGlobalMiddleClick() {
        let activeRingLevel = functionManager.activeRingLevel
        
        guard activeRingLevel < functionManager.rings.count else {
            print("⚠️ No active ring for middle-click")
            return
        }
        
        // Get the currently hovered item
        guard let hoveredIndex = functionManager.rings[activeRingLevel].hoveredIndex else {
            print("⚠️ No item currently hovered for middle-click")
            return
        }
        
        guard hoveredIndex < functionManager.rings[activeRingLevel].nodes.count else {
            print("⚠️ Invalid hovered index for middle-click")
            return
        }
        
        let node = functionManager.rings[activeRingLevel].nodes[hoveredIndex]
        
        print("🖱️ [Middle Click] On item: '\(node.name)' at ring \(activeRingLevel), index \(hoveredIndex)")
        
        // USE EXPLICIT INTERACTION MODEL
        switch node.onMiddleClick {
        case .execute(let action):
            print("   ✅ Executing action (will close UI)")
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                circularUI.hide()
            }
            
        case .executeKeepOpen(let action):
            print("   ✅ Executing action (UI stays open)")
            action()
            // Don't hide UI
            
        case .expand:
            print("   ✅ Expanding")
            functionManager.expandCategory(ringLevel: activeRingLevel, index: hoveredIndex)
            
        case .doNothing:
            print("   ⚠️ No middle-click action defined")
        }
    }
    
    // MARK: - Right Click Handler
    
    private func handleGlobalRightClick() {
        let activeRingLevel = functionManager.activeRingLevel
        
        guard activeRingLevel < functionManager.rings.count else {
            print("⚠️ No active ring for right-click")
            return
        }
        
        // Get the currently hovered item
        guard let hoveredIndex = functionManager.rings[activeRingLevel].hoveredIndex else {
            print("⚠️ No item currently hovered for right-click")
            return
        }
        
        guard hoveredIndex < functionManager.rings[activeRingLevel].nodes.count else {
            print("⚠️ Invalid hovered index for right-click")
            return
        }
        
        let node = functionManager.rings[activeRingLevel].nodes[hoveredIndex]
        
        print("🖱️ [Right Click] On item: '\(node.name)' at ring \(activeRingLevel), index \(hoveredIndex)")
        
        // USE EXPLICIT INTERACTION MODEL
        switch node.onRightClick {
        case .execute(let action):
            print("   ✅ Executing action (will close UI)")
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                circularUI.hide()
            }
            
        case .executeKeepOpen(let action):
            print("   ✅ Executing action (UI stays open)")
            action()
            // Don't hide UI
            
        case .expand:
            print("   ✅ Expanding")
            functionManager.expandCategory(ringLevel: activeRingLevel, index: hoveredIndex)
            
        case .doNothing:
            print("   ⚠️ No right-click action defined")
        }
    }
    
    // MARK: - Left Click Handler (Global)
    
    private func handleGlobalClick() {
        let activeRingLevel = functionManager.activeRingLevel
        
        guard activeRingLevel < functionManager.rings.count else {
            print("⚠️ No active ring to execute")
            return
        }
        
        // Get the currently hovered item
        guard let hoveredIndex = functionManager.rings[activeRingLevel].hoveredIndex else {
            print("⚠️ No item currently hovered")
            return
        }
        
        guard hoveredIndex < functionManager.rings[activeRingLevel].nodes.count else {
            print("⚠️ Invalid hovered index")
            return
        }
        
        let node = functionManager.rings[activeRingLevel].nodes[hoveredIndex]
        
        print("🖱️ [Global Click] Executing hovered item: '\(node.name)' at ring \(activeRingLevel), index \(hoveredIndex)")
        
        // USE EXPLICIT INTERACTION MODEL
        switch node.onLeftClick {
        case .execute(let action):
            print("   ✅ Executing action (will close UI)")
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                circularUI.hide()
            }
            
        case .executeKeepOpen(let action):
            print("   ✅ Executing action (UI stays open)")
            action()
            // Don't hide UI
            
        case .expand:
            print("   ✅ Expanding category")
            functionManager.expandCategory(ringLevel: activeRingLevel, index: hoveredIndex)
            
        case .doNothing:
            print("   ⚠️ No left-click action defined")
        }
    }
    
    // MARK: - Ring Tap Handler (Legacy/Compatibility)
    
    private func handleRingTap(level: Int, index: Int) {
        // Select the node
        functionManager.selectNode(ringLevel: level, index: index)
        
        // Get the node to check what to do
        guard level < functionManager.rings.count else { return }
        guard index < functionManager.rings[level].nodes.count else { return }
        
        let node = functionManager.rings[level].nodes[index]
        
        print("🖱️ [Ring Tap] Clicked: '\(node.name)' at ring \(level), index \(index)")
        
        // USE EXPLICIT INTERACTION MODEL (same as global click)
        switch node.onLeftClick {
        case .execute(let action):
            print("   ✅ Executing action (will close UI)")
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                circularUI.hide()
            }
            
        case .executeKeepOpen(let action):
            print("   ✅ Executing action (UI stays open)")
            action()
            // Don't hide UI
            
        case .expand:
            print("   ✅ Expanding category")
            functionManager.expandCategory(ringLevel: level, index: index)
            
        case .doNothing:
            print("   ⚠️ No left-click action defined")
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
    let sliceConfig: PieSliceConfig
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
