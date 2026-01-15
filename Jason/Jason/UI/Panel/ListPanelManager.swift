//
//  ListPanelManager.swift
//  Jason
//
//  Manages state and logic for the list panel UI.
//  Supports stack-based cascading panels (column view).
//

import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Panel State

struct PanelState: Identifiable {
    let id: UUID = UUID()
    let items: [FunctionNode]
    let position: CGPoint
    let level: Int                    // 0 = from ring, 1+ = from panel
    let sourceNodeId: String?         // Which node spawned this panel
    var expandedItemId: String?       // Which row has context actions showing
    
    // Panel dimensions (constants for now, could be configurable)
    static let panelWidth: CGFloat = 260
    static let rowHeight: CGFloat = 32
    static let maxVisibleItems: Int = 10
    static let padding: CGFloat = 8
    
    /// Calculate panel height based on item count
    var panelHeight: CGFloat {
        let itemCount = min(items.count, Self.maxVisibleItems)
        return CGFloat(itemCount) * Self.rowHeight + Self.padding
    }
    
    /// Panel bounds in screen coordinates
    var bounds: NSRect {
        NSRect(
            x: position.x - Self.panelWidth / 2,
            y: position.y - panelHeight / 2,
            width: Self.panelWidth,
            height: panelHeight
        )
    }
}

// MARK: - List Panel Manager

class ListPanelManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published var panelStack: [PanelState] = []
    
    // MARK: - Computed Properties
    
    var isVisible: Bool {
        !panelStack.isEmpty
    }
    
    /// First panel's position (for backward compatibility)
    var position: CGPoint {
        panelStack.first?.position ?? .zero
    }
    
    /// First panel's items (for backward compatibility)
    var items: [FunctionNode] {
        panelStack.first?.items ?? []
    }
    
    /// Expanded item ID for first panel (for backward compatibility with binding)
    var expandedItemId: String? {
        get { panelStack.first?.expandedItemId }
        set {
            guard !panelStack.isEmpty else { return }
            panelStack[0].expandedItemId = newValue
        }
    }
    
    /// Current ring context (stored for cascading position calculations)
    private(set) var currentRingCenter: CGPoint = .zero
    private(set) var currentRingOuterRadius: CGFloat = 0
    private(set) var currentAngle: Double = 0
    
    // MARK: - Callbacks (wired by CircularUIManager)
    
    var onItemLeftClick: ((FunctionNode, NSEvent.ModifierFlags) -> Void)?
    var onItemRightClick: ((FunctionNode, NSEvent.ModifierFlags) -> Void)?
    var onContextAction: ((FunctionNode, NSEvent.ModifierFlags) -> Void)?
    var onItemHover: ((FunctionNode?, Int, Int?) -> Void)?
    
    // MARK: - Show Panel (from Ring)
    
    /// Show a panel as an extension of a ring item
    func show(
        items: [FunctionNode],
        ringCenter: CGPoint,
        ringOuterRadius: CGFloat,
        angle: Double,
        panelWidth: CGFloat = PanelState.panelWidth
    ) {
        // Store ring context for cascading
        self.currentAngle = angle
        self.currentRingCenter = ringCenter
        self.currentRingOuterRadius = ringOuterRadius
        
        // Calculate position
        let position = calculatePanelPosition(
            fromRing: (center: ringCenter, outerRadius: ringOuterRadius, angle: angle),
            panelWidth: panelWidth,
            itemCount: items.count
        )
        
        print("📋 [ListPanelManager] Showing panel at angle \(angle)°")
        print("   Items: \(items.count)")
        print("   Panel center: \(position)")
        
        // Clear any existing panels and push new one
        panelStack = [
            PanelState(
                items: items,
                position: position,
                level: 0,
                sourceNodeId: nil,
                expandedItemId: nil
            )
        ]
    }
    
    /// Show panel at a specific position (for testing)
    func show(items: [FunctionNode], at position: CGPoint) {
        print("📋 [ListPanelManager] Showing panel with \(items.count) items")
        panelStack = [
            PanelState(
                items: items,
                position: position,
                level: 0,
                sourceNodeId: nil,
                expandedItemId: nil
            )
        ]
    }
    
    // MARK: - Push Panel (Cascading)

    /// Push a new panel from an existing panel (cascade to the right)
    func pushPanel(
        items: [FunctionNode],
        fromPanelAtLevel level: Int,
        sourceNodeId: String,
        sourceRowIndex: Int? = nil  // ADD THIS
    ) {
        // Find the source panel
        guard let sourcePanel = panelStack.first(where: { $0.level == level }) else {
            print("❌ [ListPanelManager] Cannot find panel at level \(level)")
            return
        }
        
        // Pop any panels above this level first
        popToLevel(level)
        
        // Calculate position: to the right of source panel
        let sourceBounds = sourcePanel.bounds
        let gap: CGFloat = 8
        
        let newPanelWidth = PanelState.panelWidth
        let itemCount = min(items.count, PanelState.maxVisibleItems)
        let newPanelHeight = CGFloat(itemCount) * PanelState.rowHeight + PanelState.padding
        
        // New panel's left edge aligns with source panel's right edge + gap
        let newX = sourceBounds.maxX + gap + (newPanelWidth / 2)
        
        // Calculate Y position based on source row
        let newY: CGFloat
        if let rowIndex = sourceRowIndex {
            // Align new panel's top with the source row's vertical center
            let rowCenterY = sourceBounds.maxY - (PanelState.padding / 2) - (CGFloat(rowIndex) * PanelState.rowHeight) - (PanelState.rowHeight / 2)
            // New panel's center Y = top of new panel + half height
            // We want new panel's top row to align with source row
            newY = rowCenterY - (newPanelHeight / 2) + (PanelState.rowHeight / 2) + (PanelState.padding / 2)
        } else {
            // Fallback: center vertically with source panel
            newY = sourceBounds.midY
        }
        
        let newPosition = CGPoint(x: newX, y: newY)
        
        let newPanel = PanelState(
            items: items,
            position: newPosition,
            level: level + 1,
            sourceNodeId: sourceNodeId,
            expandedItemId: nil
        )
        
        panelStack.append(newPanel)
        
        print("📋 [ListPanelManager] Pushed panel level \(level + 1)")
        print("   Items: \(items.count)")
        print("   Position: \(newPosition)")
        print("   Source row: \(sourceRowIndex ?? -1)")
    }

    /// Pop panels above a certain level
    func popToLevel(_ level: Int) {
        let before = panelStack.count
        panelStack.removeAll { $0.level > level }
        let removed = before - panelStack.count
        if removed > 0 {
            print("📋 [ListPanelManager] Popped \(removed) panel(s), now at level \(level)")
        }
    }

    /// Pop the topmost panel
    func popPanel() {
        guard !panelStack.isEmpty else { return }
        let removed = panelStack.removeLast()
        print("📋 [ListPanelManager] Popped panel level \(removed.level)")
    }
    
    // MARK: - Position Calculation
    
    private func calculatePanelPosition(
        fromRing ring: (center: CGPoint, outerRadius: CGFloat, angle: Double),
        panelWidth: CGFloat,
        itemCount: Int
    ) -> CGPoint {
        let angle = ring.angle
        let angleInRadians = (angle - 90) * (.pi / 180)
        
        // Gap between ring edge and panel
        let gapFromRing: CGFloat = 8
        
        // Calculate anchor point at ring edge
        let anchorRadius = ring.outerRadius + gapFromRing
        let anchorX = ring.center.x + anchorRadius * cos(angleInRadians)
        let anchorY = ring.center.y - anchorRadius * sin(angleInRadians)
        
        // Calculate panel height
        let itemCountClamped = min(itemCount, PanelState.maxVisibleItems)
        let panelHeight = CGFloat(itemCountClamped) * PanelState.rowHeight + PanelState.padding
        
        // Base offset: half-dimensions in angle direction
        let offsetX = (panelWidth / 2) * cos(angleInRadians)
        let offsetY = (panelHeight / 2) * -sin(angleInRadians)
        
        // Diagonal factor: peaks at 45°, 135°, 225°, 315° (0 at cardinal angles)
        let angleWithinQuadrant = angle.truncatingRemainder(dividingBy: 90)
        let diagonalFactor = sin(angleWithinQuadrant * 2 * .pi / 180)
        
        // Extra offset for diagonal angles (18% extra at peak)
        let extraFactor: CGFloat = 0.18 * CGFloat(diagonalFactor)
        let extraOffsetX = extraFactor * panelWidth * cos(angleInRadians)
        let extraOffsetY = extraFactor * panelHeight * -sin(angleInRadians)
        
        let panelX = anchorX + offsetX + extraOffsetX
        let panelY = anchorY + offsetY + extraOffsetY
        
        return CGPoint(x: panelX, y: panelY)
    }
    
    // MARK: - Hide / Clear
    
    /// Hide all panels
    func hide() {
        guard isVisible else { return }
        print("📋 [ListPanelManager] Hiding all panels")
        panelStack.removeAll()
    }
    
    /// Alias for hide (clearer intent)
    func clear() {
        hide()
    }
    
    // MARK: - Hit Testing
    
    /// Check if a point is inside ANY panel
    func contains(point: CGPoint) -> Bool {
        panelStack.contains { $0.bounds.contains(point) }
    }
    
    /// Check if point is in the panel zone (any panel OR gaps between)
    func isInPanelZone(point: CGPoint) -> Bool {
        guard !panelStack.isEmpty else { return false }
        
        var minX = CGFloat.infinity
        var minY = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var maxY = -CGFloat.infinity
        
        for panel in panelStack {
            let bounds = panel.bounds
            minX = min(minX, bounds.minX)
            minY = min(minY, bounds.minY)
            maxX = max(maxX, bounds.maxX)
            maxY = max(maxY, bounds.maxY)
        }
        
        let combinedBounds = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return combinedBounds.contains(point)
    }
    
    /// Find which panel level contains the point (nil if none)
    func panelLevel(at point: CGPoint) -> Int? {
        // Check from rightmost to leftmost (higher levels first)
        for panel in panelStack.reversed() {
            if panel.bounds.contains(point) {
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
    
    // MARK: - Right Click Handling
    
    /// Handle right-click at position, returns true if handled
    func handleRightClick(at point: CGPoint) -> Bool {
        // Find which panel was clicked
        guard let level = panelLevel(at: point),
              let panelIndex = panelStack.firstIndex(where: { $0.level == level }) else {
            return false
        }
        
        let panel = panelStack[panelIndex]
        let bounds = panel.bounds
        
        // Calculate which row was clicked
        let relativeY = bounds.maxY - point.y - (PanelState.padding / 2)
        let rowIndex = Int(relativeY / PanelState.rowHeight)
        
        guard rowIndex >= 0 && rowIndex < panel.items.count else {
            print("📋 [Panel] Right-click outside rows")
            panelStack[panelIndex].expandedItemId = nil
            return true
        }
        
        let clickedItem = panel.items[rowIndex]
        print("📋 [Panel \(level)] Right-click on row \(rowIndex): '\(clickedItem.name)'")
        
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
        let bounds = panel.bounds
        
        // Calculate which row was clicked
        let relativeY = bounds.maxY - point.y - (PanelState.padding / 2)
        let rowIndex = Int(relativeY / PanelState.rowHeight)
        
        guard rowIndex >= 0 && rowIndex < panel.items.count else {
            return nil
        }
        
        // Collapse any expanded row in this panel
        panelStack[panelIndex].expandedItemId = nil
        
        return (panel.items[rowIndex], level)
    }
    
    // MARK: - Test Helpers
    
    /// Show panel with sample test data
    func showTestPanel(at position: CGPoint = NSEvent.mouseLocation) {
        let testItems: [FunctionNode] = [
            createTestFolderWithChildren(name: "Documents"),
            createTestFolderWithChildren(name: "Screenshots"),
            createTestFileNode(name: "report.pdf", utType: .pdf),
            createTestFileNode(name: "notes.txt", utType: .plainText),
            createTestFolderWithChildren(name: "Projects"),
        ]
        
        show(items: testItems, at: position)
    }
    
    private func createTestFolderWithChildren(name: String, depth: Int = 0) -> FunctionNode {
        let icon = NSWorkspace.shared.icon(for: .folder)
        
        // Create nested children (limit depth to prevent infinite recursion)
        let children: [FunctionNode]
        if depth < 3 {
            children = [
                createTestFolderWithChildren(name: "Subfolder A", depth: depth + 1),
                createTestFolderWithChildren(name: "Subfolder B", depth: depth + 1),
                createTestFileNode(name: "file1.txt", utType: .plainText),
                createTestFileNode(name: "file2.pdf", utType: .pdf),
            ]
        } else {
            // At max depth, only files
            children = [
                createTestFileNode(name: "file1.txt", utType: .plainText),
                createTestFileNode(name: "file2.pdf", utType: .pdf),
            ]
        }
        
        return FunctionNode(
            id: UUID().uuidString,
            name: name,
            type: .folder,
            icon: icon,
            children: children,
            childDisplayMode: .panel,
            onLeftClick: ModifierAwareInteraction(base: .navigateInto)
        )
    }

    private func createTestFileNode(name: String, utType: UTType) -> FunctionNode {
        let icon = NSWorkspace.shared.icon(for: utType)
        
        return FunctionNode(
            id: UUID().uuidString,
            name: name,
            type: .file,
            icon: icon,
            onLeftClick: ModifierAwareInteraction(base: .execute {
                print("🧪 [Test] Would open: \(name)")
            })
        )
    }
}
