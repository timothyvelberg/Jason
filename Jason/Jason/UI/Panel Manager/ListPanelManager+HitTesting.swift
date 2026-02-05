//
//  ListPanelManager+HitTesting.swift
//  Jason
//
//  Created by Timothy Velberg on 29/01/2026.
//  Hit testing and click handling for list panels.
//



import Foundation
import AppKit

extension ListPanelManager {
    
    // MARK: - Hit Testing
    
    /// Check if a point is inside ANY panel
    func contains(point: CGPoint) -> Bool {
        panelStack.contains { currentBounds(for: $0).contains(point) }
    }
    
    /// Check if point is in the panel zone (inside any actual panel)
    func isInPanelZone(point: CGPoint) -> Bool {
        guard !panelStack.isEmpty else { return false }
        
        // Check if point is inside any actual panel
        if panelStack.first(where: { currentBounds(for: $0).contains(point) }) != nil {
            return true
        }
        
        return false
    }
    
    /// Find which panel level contains the point (nil if none)
    func panelLevel(at point: CGPoint) -> Int? {
        // Check from rightmost to leftmost (higher levels first)
        for panel in panelStack.reversed() {
            if currentBounds(for: panel).contains(point) {
                return panel.level
            }
        }
        return nil
    }
    
    /// Get the panel at a specific level
    func panel(at level: Int) -> PanelState? {
        panelStack.first { $0.level == level }
    }
    
    /// Left edge of leftmost panel (for ring boundary detection)
    var leftmostPanelEdge: CGFloat? {
        panelStack.first.map { $0.bounds.minX }
    }
    
    // MARK: - Click Handling
    
    /// Handle right-click at position, returns true if handled
    func handleRightClick(at point: CGPoint) -> Bool {
        // Find which panel was clicked
        guard let level = panelLevel(at: point),
              let panelIndex = panelStack.firstIndex(where: { $0.level == level }) else {
            return false
        }
        
        let panel = panelStack[panelIndex]
        let bounds = currentBounds(for: panel)
        
        // Calculate which row was clicked (accounting for title and scroll)
        let relativeY = bounds.maxY - point.y - (PanelState.padding / 2) - PanelState.titleHeight
        
        // Adjust for scroll: relativeY is in visual space, need to convert to logical row index
        let scrollAdjustedY = relativeY + panel.scrollOffset
        let rowIndex = Int(scrollAdjustedY / PanelState.rowHeight)
        
        guard rowIndex >= 0 && rowIndex < panel.items.count else {
            print("[Panel] Right-click outside rows")
            panelStack[panelIndex].expandedItemId = nil
            return true
        }
        
        let clickedItem = panel.items[rowIndex]
        print("[Panel \(level)] Right-click on row \(rowIndex): '\(clickedItem.name)'")
        
        // Toggle expanded state
        if panelStack[panelIndex].expandedItemId == clickedItem.id {
            panelStack[panelIndex].expandedItemId = nil
        } else {
            panelStack[panelIndex].expandedItemId = clickedItem.id
        }
        
        return true
    }
    
    /// Handle left-click at position, returns the clicked item and panel level if inside a panel
    func handleLeftClick(at point: CGPoint) -> (node: FunctionNode, level: Int)? {
        // Find which panel was clicked
        guard let level = panelLevel(at: point),
              let panelIndex = panelStack.firstIndex(where: { $0.level == level }) else {
            return nil
        }
        
        let panel = panelStack[panelIndex]
        let bounds = currentBounds(for: panel)
        
        // Check if click is in title bar area
        let distanceFromTop = bounds.maxY - point.y
        if distanceFromTop < PanelState.titleHeight + (PanelState.padding / 2) {
            return nil  // Let SwiftUI handle title bar clicks
        }
        
        // Calculate which row was clicked (accounting for title and scroll)
        let relativeY = bounds.maxY - point.y - (PanelState.padding / 2) - PanelState.titleHeight
        
        // Adjust for scroll: relativeY is in visual space, need to convert to logical row index
        let scrollAdjustedY = relativeY + panel.scrollOffset
        let rowIndex = Int(scrollAdjustedY / PanelState.rowHeight)
        
        guard rowIndex >= 0 && rowIndex < panel.items.count else {
            return nil
        }
        
        let clickedItem = panel.items[rowIndex]
        
        // If this row is expanded (showing context actions), let SwiftUI handle the click
        if panel.expandedItemId == clickedItem.id {
            print("[Panel] Click on expanded row - letting SwiftUI handle context actions")
            return nil
        }
        
        // Collapse any expanded row in this panel
        panelStack[panelIndex].expandedItemId = nil
        
        return (clickedItem, level)
    }
    
    /// Handle drag start at position, returns the node and its DragProvider if draggable
    func handleDragStart(at point: CGPoint) -> (node: FunctionNode, dragProvider: DragProvider, level: Int)? {
        // Find which panel was clicked
        guard let level = panelLevel(at: point),
              let panelIndex = panelStack.firstIndex(where: { $0.level == level }) else {
            return nil
        }
        
        let panel = panelStack[panelIndex]
        let bounds = currentBounds(for: panel)
        
        // Calculate which row was clicked (accounting for title and scroll)
        let relativeY = bounds.maxY - point.y - (PanelState.padding / 2) - PanelState.titleHeight
        
        // Adjust for scroll: relativeY is in visual space, need to convert to logical row index
        let scrollAdjustedY = relativeY + panel.scrollOffset
        let rowIndex = Int(scrollAdjustedY / PanelState.rowHeight)
        
        guard rowIndex >= 0 && rowIndex < panel.items.count else {
            return nil
        }
        
        let node = panel.items[rowIndex]
        
        // Check if node is draggable (resolve with current modifiers)
        let behavior = node.onLeftClick.resolve(with: NSEvent.modifierFlags)
        
        if case .drag(let provider) = behavior {
            return (node, provider, level)
        }
        
        return nil
    }
}
