//
//  PanelOnlyView.swift
//  Jason
//
//  Created by Timothy Velberg on 29/01/2026.
//  SwiftUI view for standalone panel presentation (no ring).
//

import SwiftUI

struct PanelOnlyView: View {
    @ObservedObject var panelUIManager: PanelUIManager
    @ObservedObject var listPanelManager: ListPanelManager
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                ZStack {
                    // Transparent background
                    Color.clear
                    
                    // Panel stack
                    if listPanelManager.isVisible {
                        ForEach(listPanelManager.panelStack) { panel in
                            panelView(for: panel, in: geometry)
                        }
                    }
                }
            }
            .ignoresSafeArea()
            
            // Drag overlay - sits on top to handle drag gestures
            DraggableOverlay(
                dragProvider: $panelUIManager.currentDragProvider,
                dragStartPoint: $panelUIManager.dragStartPoint
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
    }
    
    @ViewBuilder
    private func panelView(for panel: PanelState, in geometry: GeometryProxy) -> some View {
        // Get the screen the overlay is on
        let screen = panelUIManager.overlayWindow?.currentScreen ?? NSScreen.main
        let screenOriginX = screen?.frame.origin.x ?? 0
        let screenOriginY = screen?.frame.origin.y ?? 0
        let screenHeight = screen?.frame.height ?? 1080
        
        // Get global position
        let globalPosition = listPanelManager.currentPosition(for: panel)
        
        // Convert GLOBAL → SCREEN-LOCAL coordinates
        let localX = globalPosition.x - screenOriginX
        let localY = globalPosition.y - screenOriginY
        
        // Flip Y for SwiftUI (Y=0 at top)
        let viewY = screenHeight - localY
        
        // Adjust Y to keep top anchored during search
        let adjustedViewY = panel.isSearchActive && panel.searchAnchorHeight != nil
            ? viewY - ((panel.searchAnchorHeight! - panel.panelHeight) / 2)
            : viewY
        
        Group {
            if let previewContent = panel.previewContent {
                PreviewPanelView(
                    content: previewContent,
                    config: panel.config,
                    title: panel.title
                )
            } else {
                ListPanelView(
                    title: panel.title,
                    items: panel.items,
                    onItemLeftClick: { node, modifiers in
                        listPanelManager.onItemLeftClick?(node, modifiers)
                    },
                    onItemRightClick: { node, modifiers in
                        listPanelManager.onItemRightClick?(node, modifiers)
                    },
                    onContextAction: { action, modifiers in
                        listPanelManager.onContextAction?(action, modifiers)
                    },
                    onItemHover: { node, rowIndex in
                        listPanelManager.handleViewHover(node: node, level: panel.level, rowIndex: rowIndex)
                    },
                    onHeaderHover: {
                        listPanelManager.handleHeaderHover(level: panel.level)
                    },
                    onScrollOffsetChanged: { offset in
                        listPanelManager.updateScrollOffset(offset, forLevel: panel.level)
                    },
                    onScrollStateChanged: { isScrolling in
                        listPanelManager.handleScrollStateChanged(isScrolling: isScrolling, forLevel: panel.level)
                    },
                    onRowHeightsMeasured: { heights in
                        listPanelManager.updateRowHeights(heights, forLevel: panel.level)
                    },
                    contextActions: panel.contextActions,
                    typingMode: panel.activeTypingMode,
                    expandedItemId: Binding(
                        get: { panel.expandedItemId },
                        set: { newValue in
                            if let index = listPanelManager.panelStack.firstIndex(where: { $0.id == panel.id }) {
                                listPanelManager.panelStack[index].expandedItemId = newValue
                            }
                        }
                    ),
                    isSearchActive: Binding(
                        get: { panel.isSearchActive },
                        set: { newValue in
                            if let index = listPanelManager.panelStack.firstIndex(where: { $0.id == panel.id }) {
                                listPanelManager.panelStack[index].isSearchActive = newValue
                            }
                        }
                    ),
                    searchQuery: Binding(
                        get: { panel.searchQuery },
                        set: { newValue in
                            if let index = listPanelManager.panelStack.firstIndex(where: { $0.id == panel.id }) {
                                listPanelManager.panelStack[index].searchQuery = newValue
                            }
                        }
                    ),
                    hoveredRowIndex: listPanelManager.effectiveSelectedRow(for: panel.level),
                    isKeyboardDriven: listPanelManager.isKeyboardDriven,
                    config: panel.config
                )
            }
        }
        .position(x: localX, y: adjustedViewY)
        .transition(panel.level == 0
            ? .slideFromAngle(angle: panel.spawnAngle ?? 0, distance: PanelConfig.cascadeSlideDistance)
            : .slideFromLeft(distance: PanelConfig.cascadeSlideDistance))
        .animation(.easeInOut(duration: 0.2), value: panel.isOverlapping)
    }
}
