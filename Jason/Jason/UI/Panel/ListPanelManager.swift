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
    let title: String
    let items: [FunctionNode]
    let position: CGPoint
    let level: Int                    // 0 = from ring, 1+ = from panel
    let sourceNodeId: String?         // Which node spawned this panel
    let sourceRowIndex: Int?
    var expandedItemId: String?       // Which row has context actions showing
    var areChildrenArmed: Bool = false
    var isOverlapping: Bool = false
    
    
    
    // Panel dimensions (constants for now, could be configurable)
    static let panelWidth: CGFloat = 260
    static let rowHeight: CGFloat = 32
    static let titleHeight: CGFloat = 28
    static let maxVisibleItems: Int = 10
    static let padding: CGFloat = 8
    
    /// Calculate panel height based on item count
    var panelHeight: CGFloat {
        let itemCount = min(items.count, Self.maxVisibleItems)
        return Self.titleHeight + CGFloat(itemCount) * Self.rowHeight + Self.padding    // UPDATED
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
    
    // MARK: - Sliding Configuration
    
    /// How much of the previous panel stays visible when overlapped
    let peekWidth: CGFloat = 75
    
    /// How far across the row (0-1) before triggering slide
    let slideThreshold: CGFloat = 0.75
    
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
    
    // MARK: - Pending Panel (waiting for arming)

    private var pendingPanel: (title: String, items: [FunctionNode], fromLevel: Int, sourceNodeId: String, sourceRowIndex: Int)?
    
    // MARK: - Callbacks (wired by CircularUIManager)
    
    var onItemLeftClick: ((FunctionNode, NSEvent.ModifierFlags) -> Void)?
    var onItemRightClick: ((FunctionNode, NSEvent.ModifierFlags) -> Void)?
    var onContextAction: ((FunctionNode, NSEvent.ModifierFlags) -> Void)?
    var onItemHover: ((FunctionNode?, Int, Int?) -> Void)?
    
    // MARK: - Show Panel (from Ring)
    
    /// Show a panel as an extension of a ring item
    func show(
        title: String,
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
                title: title,
                items: items,
                position: position,
                level: 0,
                sourceNodeId: nil,
                sourceRowIndex: nil,
                expandedItemId: nil,
                isOverlapping: false
            )
        ]
    }
    
    /// Show panel at a specific position (for testing)
    func show(title: String, items: [FunctionNode], at position: CGPoint) {
        print("📋 [ListPanelManager] Showing panel with \(items.count) items")
        panelStack = [
            PanelState(
                title: title,
                items: items,
                position: position,
                level: 0,
                sourceNodeId: nil,
                sourceRowIndex: nil,
                expandedItemId: nil,
                isOverlapping: false
            )
        ]
    }
    
    // MARK: - Bounds Calculation

    /// Get the current bounds for a panel (accounting for overlap state)
    func currentBounds(for panel: PanelState) -> NSRect {
        let currentPos = currentPosition(for: panel)
        return NSRect(
            x: currentPos.x - PanelState.panelWidth / 2,
            y: currentPos.y - panel.panelHeight / 2,
            width: PanelState.panelWidth,
            height: panel.panelHeight
        )
    }

    /// Calculate the screen bounds of a specific row in a panel
    func rowBounds(forPanel panel: PanelState, rowIndex: Int) -> NSRect? {
        guard rowIndex >= 0 && rowIndex < panel.items.count else { return nil }
        
        let panelBounds = currentBounds(for: panel)    // CHANGED: use current bounds
        
        // Row Y position: starts below title, each row is rowHeight tall
        // In screen coordinates, Y increases upward, so top row has highest Y
        let rowTop = panelBounds.maxY - (PanelState.padding / 2) - PanelState.titleHeight - (CGFloat(rowIndex) * PanelState.rowHeight)
        let rowBottom = rowTop - PanelState.rowHeight
        
        // Row X spans the panel width (with some padding)
        let horizontalPadding: CGFloat = 4
        let rowLeft = panelBounds.minX + horizontalPadding
        let rowRight = panelBounds.maxX - horizontalPadding
        
        return NSRect(
            x: rowLeft,
            y: rowBottom,
            width: rowRight - rowLeft,
            height: PanelState.rowHeight
        )
    }
    
    // MARK: - Mouse Movement Tracking

    /// Handle mouse movement to trigger panel sliding
    func handleMouseMove(at point: CGPoint) {
        // Check for arming on panels that might have pending children
        for index in panelStack.indices {
            let panel = panelStack[index]
            
            // Check if there's a pending panel for this level
            if let pending = pendingPanel, pending.fromLevel == panel.level {
                // Get the row bounds for the pending row
                if let sourceBounds = rowBounds(forPanel: panel, rowIndex: pending.sourceRowIndex) {
                    if sourceBounds.contains(point) {
                        let progress = (point.x - sourceBounds.minX) / sourceBounds.width
                        
                        // Check for arming
                        if !panelStack[index].areChildrenArmed && progress < slideThreshold {
                            panelStack[index].areChildrenArmed = true
                            print("📋 [Slide] Panel level \(panel.level) children now ARMED")
                            
                            // Spawn the pending panel
                            let p = pending
                            pendingPanel = nil
                            actuallyPushPanel(title: p.title, items: p.items, fromPanelAtLevel: p.fromLevel, sourceNodeId: p.sourceNodeId, sourceRowIndex: p.sourceRowIndex)
                        }
                    }
                }
            }
            
            // Find child panel (level + 1) for overlap logic
            guard let childIndex = panelStack.firstIndex(where: { $0.level == panel.level + 1 }),
                  let sourceRowIndex = panelStack[childIndex].sourceRowIndex else {
                continue
            }
            
            // Get the source row bounds
            guard let sourceBounds = rowBounds(forPanel: panel, rowIndex: sourceRowIndex) else {
                continue
            }
            
            // Check if mouse is in the source row
            if sourceBounds.contains(point) {
                let progress = (point.x - sourceBounds.minX) / sourceBounds.width
                
                // Armed - normal threshold logic applies
                let shouldOverlap = progress > slideThreshold
                
                // Update if changed
                if panelStack[childIndex].isOverlapping != shouldOverlap {
                    panelStack[childIndex].isOverlapping = shouldOverlap
                    print("📋 [Slide] Panel level \(panelStack[childIndex].level) isOverlapping: \(shouldOverlap)")
                }
            }
        }
    }

    // MARK: - Position Calculation

    /// Get the current position for a panel (accounting for overlap state)
    func currentPosition(for panel: PanelState) -> CGPoint {
        guard panel.isOverlapping else {
            // Not overlapping, but ancestors might be shifted - need to adjust
            if panel.level > 0,
               let parentPanel = panelStack.first(where: { $0.level == panel.level - 1 }) {
                let parentOriginalX = parentPanel.position.x
                let parentCurrentPos = currentPosition(for: parentPanel)
                let parentShift = parentCurrentPos.x - parentOriginalX
                
                // Only shift if there's actually a difference
                if abs(parentShift) > 0.1 {
                    return CGPoint(x: panel.position.x + parentShift, y: panel.position.y)
                }
            }
            return panel.position
        }
        
        // Panel is overlapping - calculate position relative to parent's CURRENT position
        guard let parentPanel = panelStack.first(where: { $0.level == panel.level - 1 }) else {
            return panel.position
        }
        
        // Get parent's current position (recursive - handles chain of overlaps)
        let parentCurrentPos = currentPosition(for: parentPanel)
        
        // Calculate parent's current left edge
        let parentCurrentLeftEdge = parentCurrentPos.x - (PanelState.panelWidth / 2)
        
        // Overlapping X: parent's current left edge + peekWidth + half panel width
        let overlappingX = parentCurrentLeftEdge + peekWidth + (PanelState.panelWidth / 2)
        
        return CGPoint(x: overlappingX, y: panel.position.y)
    }
    // MARK: - Push Panel (Cascading)

    /// Push a new panel from an existing panel (cascade to the right)
    func pushPanel(
        title: String,
        items: [FunctionNode],
        fromPanelAtLevel level: Int,
        sourceNodeId: String,
        sourceRowIndex: Int? = nil
    ) {
        // Find the source panel
        guard let sourcePanel = panelStack.first(where: { $0.level == level }) else {
            print("❌ [ListPanelManager] Cannot find panel at level \(level)")
            return
        }
        
        // Check if parent is armed for child spawning
        guard let sourceIndex = panelStack.firstIndex(where: { $0.level == level }) else { return }
        
        if !panelStack[sourceIndex].areChildrenArmed {
            // Not armed yet - store as pending
            if let rowIndex = sourceRowIndex {
                pendingPanel = (title, items, level, sourceNodeId, rowIndex)
                print("📋 [ListPanelManager] Panel '\(title)' PENDING - waiting for arming")
            }
            return
        }
        
        // Armed - proceed with push
        actuallyPushPanel(title: title, items: items, fromPanelAtLevel: level, sourceNodeId: sourceNodeId, sourceRowIndex: sourceRowIndex)
    }

    /// Internal: actually push the panel (called after arming check passes)
    private func actuallyPushPanel(
        title: String,
        items: [FunctionNode],
        fromPanelAtLevel level: Int,
        sourceNodeId: String,
        sourceRowIndex: Int? = nil
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
        let newPanelHeight = CGFloat(itemCount) * PanelState.rowHeight + PanelState.padding + PanelState.titleHeight
        
        // New panel's left edge aligns with source panel's right edge + gap
        let newX = sourceBounds.maxX + gap + (newPanelWidth / 2)
        
        // Calculate Y position based on source row
        let newY: CGFloat
        if let rowIndex = sourceRowIndex {
            let rowCenterY = sourceBounds.maxY - (PanelState.padding / 2) - PanelState.titleHeight - (CGFloat(rowIndex) * PanelState.rowHeight) - (PanelState.rowHeight / 2)
            newY = rowCenterY - (newPanelHeight / 2) + (PanelState.rowHeight / 2) + (PanelState.padding / 2) + PanelState.titleHeight - PanelState.rowHeight
        } else {
            newY = sourceBounds.midY
        }
        
        let newPosition = CGPoint(x: newX, y: newY)
        
        let newPanel = PanelState(
            title: title,
            items: items,
            position: newPosition,
            level: level + 1,
            sourceNodeId: sourceNodeId,
            sourceRowIndex: sourceRowIndex,
            expandedItemId: nil,
            areChildrenArmed: false,
            isOverlapping: false
        )
        
        panelStack.append(newPanel)
        
        print("📋 [ListPanelManager] Pushed panel '\(title)' at level \(level + 1)")
        print("   Items: \(items.count)")
        print("   Position: \(newPosition)")
        print("   Source row: \(sourceRowIndex ?? -1)")
    }

    func popToLevel(_ level: Int) {
        let before = panelStack.count
        panelStack.removeAll { $0.level > level }
        let removed = before - panelStack.count
        if removed > 0 {
            print("📋 [ListPanelManager] Popped \(removed) panel(s), now at level \(level)")
        }
        
        // Clear pending if it was for a level we're popping
        if let pending = pendingPanel, pending.fromLevel > level {
            pendingPanel = nil
        }
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
        pendingPanel = nil
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
            if currentBounds(for: panel).contains(point) {    // CHANGED
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
        let bounds = currentBounds(for: panel)    // CHANGED
        
        // Calculate which row was clicked (accounting for title)
        let relativeY = bounds.maxY - point.y - (PanelState.padding / 2) - PanelState.titleHeight    // CHANGED
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
        let bounds = currentBounds(for: panel)    // CHANGED
        
        // Calculate which row was clicked (accounting for title)
        let relativeY = bounds.maxY - point.y - (PanelState.padding / 2) - PanelState.titleHeight    // CHANGED
        let rowIndex = Int(relativeY / PanelState.rowHeight)
        
        guard rowIndex >= 0 && rowIndex < panel.items.count else {
            return nil
        }
        
        // Collapse any expanded row in this panel
        panelStack[panelIndex].expandedItemId = nil
        
        return (panel.items[rowIndex], level)
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
        
        // Calculate which row was clicked (accounting for title)
        let relativeY = bounds.maxY - point.y - (PanelState.padding / 2) - PanelState.titleHeight
        let rowIndex = Int(relativeY / PanelState.rowHeight)
        
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
        
        show(title: "Test Panel", items: testItems, at: position)    // UPDATED
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
