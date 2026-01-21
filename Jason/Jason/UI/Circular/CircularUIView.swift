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
    @ObservedObject var listPanelManager: ListPanelManager
    
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
                let window = circularUI.overlayWindow
                
                // Get the screen the overlay is on (fallback to main screen)
                let screen = window?.currentScreen ?? NSScreen.main
                
                // Use CircularUIManager's published mousePosition instead of window property
                // This ensures SwiftUI reactivity and avoids timing issues
                let globalMouseX = circularUI.mousePosition.x
                let globalMouseY = circularUI.mousePosition.y
                
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
                    // Close button in center
                    CloseButtonView()
                        .animation(nil, value: rings.count)
                    
                    // Generate rings dynamically
                    ForEach(rings) { ring in
                        RingView(
                            startRadius: ring.startRadius,
                            thickness: ring.thickness,
                            nodes: ring.nodes,
                            selectedIndex: ring.selectedIndex,
                            shouldDimOpacity: shouldDimRing(ring.level),
                            sliceConfig: ring.sliceConfig,
                            iconSize: ring.iconSize,
                            triggerDirection: circularUI.triggerDirection
                        )
                        .transition(.customScale(from: 0.7))
                        .id("\(ring.level)-\(functionManager.ringResetTrigger)")
                    }
                }
                .animation(.easeOut(duration: 0.2), value: rings.count)
                .frame(width: totalSize, height: totalSize)
                .position(x: localMouseX, y: swiftUIY)
                
                // List Panels (when visible)
                ForEach(listPanelManager.panelStack) { panel in
                    let window = circularUI.overlayWindow
                    let screen = window?.currentScreen ?? NSScreen.main
                    let screenOriginX = screen?.frame.origin.x ?? 0
                    let screenOriginY = screen?.frame.origin.y ?? 0
                    let screenHeight = screen?.frame.height ?? 1080
                    
                    // Use currentPosition which accounts for overlap state
                    let currentPos = listPanelManager.currentPosition(for: panel)
                    let panelLocalX = currentPos.x - screenOriginX
                    let panelLocalY = currentPos.y - screenOriginY
                    let panelSwiftUIY = screenHeight - panelLocalY
                    
                    // Capture panel level for the closure
                    let panelLevel = panel.level
                    
                    ListPanelView(
                        title: panel.title,
                        items: panel.items,
                        onItemLeftClick: listPanelManager.onItemLeftClick,
                        onItemRightClick: listPanelManager.onItemRightClick,
                        onContextAction: listPanelManager.onContextAction,
                        onItemHover: { node, rowIndex in
                            listPanelManager.handleItemHover(node: node, level: panelLevel, rowIndex: rowIndex)
                        },
                        onHeaderHover: {
                            listPanelManager.handleHeaderHover(level: panelLevel)
                        },
                        onScrollOffsetChanged: { offset in
                            listPanelManager.updateScrollOffset(offset, forLevel: panelLevel)
                        },
                        onScrollStateChanged: { isScrolling in
                            listPanelManager.handleScrollStateChanged(isScrolling: isScrolling, forLevel: panelLevel)
                        },
                        contextActions: panel.contextActions,
                        expandedItemId: expandedItemIdBinding(for: panel.level)
                        
                    )
                    .position(x: panelLocalX, y: panelSwiftUIY)
                    .transition(panel.level == 0
                        ? .slideFromAngle(angle: panel.spawnAngle ?? 0, distance: PanelState.cascadeSlideDistance)
                        : .slideFromLeft(distance: PanelState.cascadeSlideDistance))    
                    .animation(.easeInOut(duration: 0.2), value: panel.isOverlapping)             }
            }
            .animation(.easeOut(duration: 0.1), value: listPanelManager.panelStack.count)
            .ignoresSafeArea()
            
            // Drag overlay - sits on top to handle drag gestures
            DraggableOverlay(
                dragProvider: $circularUI.currentDragProvider,
                dragStartPoint: $circularUI.dragStartPoint
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)  //Don't block clicks, only handle drags
        }
    }
    
    private func shouldDimRing(_ level: Int) -> Bool {
        // Dim all rings except the active one
        return level != functionManager.activeRingLevel
    }
    
    // Helper to create binding for panel's expandedItemId
    private func expandedItemIdBinding(for level: Int) -> Binding<String?> {
        Binding(
            get: {
                listPanelManager.panelStack.first { $0.level == level }?.expandedItemId
            },
            set: { newValue in
                if let index = listPanelManager.panelStack.firstIndex(where: { $0.level == level }) {
                    listPanelManager.panelStack[index].expandedItemId = newValue
                }
            }
        )
    }
}

// MARK: - Close Button View

struct CloseButtonView: View {
    private let size: CGFloat = FunctionManager.closeZoneRadius * 2
    
    var body: some View {
            ZStack {
                // Dark tint layer
                Circle()
                    .fill(Color.black.opacity(0.33))
                
                // Blur material layer
                Circle()
                    .fill(.ultraThinMaterial)
                
                // Border
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                
                // X icon
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }
            .frame(width: size, height: size)
            .allowsHitTesting(false)
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

// MARK: - Slide From Left Transition

extension AnyTransition {
    static func slideFromLeft(distance: CGFloat) -> AnyTransition {
        .modifier(
            active: SlideFromLeftModifier(offset: -distance, opacity: 0),
            identity: SlideFromLeftModifier(offset: 0, opacity: 1)
        )
    }
}

struct SlideFromLeftModifier: ViewModifier {
    let offset: CGFloat
    let opacity: Double
    
    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .opacity(opacity)
    }
}

// MARK: - Angle-Based Slide Transition

extension AnyTransition {
    static func slideFromAngle(angle: Double, distance: CGFloat) -> AnyTransition {
        // Calculate offset based on angle (Jason's system: 0° = top, clockwise)
        let angleRadians = angle * .pi / 180
        let offsetX = -distance * sin(angleRadians)
        let offsetY = distance * cos(angleRadians)
        
        return .modifier(
            active: AngleSlideModifier(offsetX: offsetX, offsetY: offsetY, opacity: 0),
            identity: AngleSlideModifier(offsetX: 0, offsetY: 0, opacity: 1)
        )
    }
}

struct AngleSlideModifier: ViewModifier {
    let offsetX: CGFloat
    let offsetY: CGFloat
    let opacity: Double
    
    func body(content: Content) -> some View {
        content
            .offset(x: offsetX, y: offsetY)
            .opacity(opacity)
    }
}
