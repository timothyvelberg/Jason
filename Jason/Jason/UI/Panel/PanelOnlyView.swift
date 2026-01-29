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
    }
    
    @ViewBuilder
    private func panelView(for panel: PanelState, in geometry: GeometryProxy) -> some View {
        let position = listPanelManager.currentPosition(for: panel)
        
        // Convert from screen coordinates to view coordinates
        let viewX = position.x
        let viewY = geometry.size.height - position.y  // Flip Y for SwiftUI
        
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
                listPanelManager.handleItemHover(node: node, level: panel.level, rowIndex: rowIndex)
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
            contextActions: panel.contextActions,
            expandedItemId: Binding(
                get: { panel.expandedItemId },
                set: { newValue in
                    if let index = listPanelManager.panelStack.firstIndex(where: { $0.id == panel.id }) {
                        listPanelManager.panelStack[index].expandedItemId = newValue
                    }
                }
            ),
            hoveredRowIndex: listPanelManager.effectiveSelectedRow(for: panel.level),
            isKeyboardDriven: listPanelManager.isKeyboardDriven
        )
        .position(x: viewX, y: viewY)
    }
}
