//
//  PanelState.swift
//  Jason
//
//  Created by Timothy Velberg on 29/01/2026.
//  Data model for a single panel in the list panel stack.
//

import Foundation
import AppKit

// MARK: - Panel State

struct PanelState: Identifiable {
    let id: UUID = UUID()
    let title: String
    var items: [FunctionNode]
    let position: CGPoint
    let level: Int                    // 0 = from ring, 1+ = from panel
    let sourceNodeId: String?         // Which node spawned this panel
    let sourceRowIndex: Int?
    let spawnAngle: Double?
    let contextActions: [FunctionNode]?
    
    /// Original items before search filtering (nil when not searching)
    var unfilteredItems: [FunctionNode]?
    
    // Identity tracking for updates
    let providerId: String?
    let contentIdentifier: String?    // Folder path for folder content
    
    var expandedItemId: String?       // Which row has context actions showing
    var areChildrenArmed: Bool = false
    var isOverlapping: Bool = false
    var scrollOffset: CGFloat = 0     // Track scroll position for accurate row positioning
    var isSearchActive: Bool = false
    var searchQuery: String = ""
    
    // MARK: - Constants
    
    static let panelWidth: CGFloat = 260
    static let rowHeight: CGFloat = 32
    static let titleHeight: CGFloat = 40
    static let maxVisibleItems: Int = 10
    static let padding: CGFloat = 8
    static let cascadeSlideDistance: CGFloat = 30
    
    // MARK: - Computed Properties
    
    /// Calculate panel height based on item count
    var panelHeight: CGFloat {
        let itemCount = min(items.count, Self.maxVisibleItems)
        return Self.titleHeight + CGFloat(itemCount) * Self.rowHeight + Self.padding
    }
    
    /// Panel bounds in screen coordinates (at original position, not accounting for overlap)
    var bounds: NSRect {
        NSRect(
            x: position.x - Self.panelWidth / 2,
            y: position.y - panelHeight / 2,
            width: Self.panelWidth,
            height: panelHeight
        )
    }
}
