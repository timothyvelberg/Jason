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
        // Wrap everything in ZStack to add drag overlay on top
        ZStack {
            // Existing circular UI content
            GeometryReader { geometry in
                let window = NSApp.windows.first(where: { $0 is OverlayWindow }) as? OverlayWindow
                
                // Get the screen the overlay is on (fallback to main screen)
                let screen = window?.currentScreen ?? NSScreen.main
                
                // Global mouse coordinates (from NSEvent.mouseLocation)
                let globalMouseX = window?.uiCenterLocation.x ?? 0
                let globalMouseY = window?.uiCenterLocation.y ?? 0
                
                // Convert global coordinates to screen-local coordinates
                // Global origin is at bottom-left of primary screen
                // Screen-local origin is at bottom-left of THIS screen
                let screenOriginX = screen?.frame.origin.x ?? 0
                let screenOriginY = screen?.frame.origin.y ?? 0
                let screenHeight = screen?.frame.height ?? 1080
                
                // Convert to screen-local AppKit coordinates
                let localMouseX = globalMouseX - screenOriginX
                let localMouseY = globalMouseY - screenOriginY
                
                // Convert Y from AppKit (Y=0 at bottom) to SwiftUI (Y=0 at top)
                let swiftUIY = screenHeight - localMouseY
                
                ZStack {
                    // Generate rings dynamically
                    ForEach(rings) { ring in
                        RingView(
                            startRadius: ring.startRadius,
                            thickness: ring.thickness,
                            nodes: ring.nodes,
                            selectedIndex: ring.selectedIndex,
                            shouldDimOpacity: shouldDimRing(ring.level),
                            sliceConfig: ring.sliceConfig,
                            iconSize: ring.iconSize
                        )
                        .transition(.customScale(from: 0.7))
                        .id("\(ring.level)-\(functionManager.ringResetTrigger)")
                    }
                }
                .animation(.easeOut(duration: 0.2), value: rings.count)
                .frame(width: totalSize, height: totalSize)
                .position(x: localMouseX, y: swiftUIY)
            }
            .ignoresSafeArea()
            
            // Drag overlay - sits on top to handle drag gestures
            DraggableOverlay(
                dragProvider: $circularUI.currentDragProvider,
                dragStartPoint: $circularUI.dragStartPoint
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)  // CRITICAL: Don't block clicks, only handle drags
        }
    }
    
    private func shouldDimRing(_ level: Int) -> Bool {
        // Dim all rings except the active one
        return level != functionManager.activeRingLevel
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
    let iconSize: CGFloat
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
