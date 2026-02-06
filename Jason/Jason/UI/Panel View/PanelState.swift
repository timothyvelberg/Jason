//
//  PanelState.swift
//  Jason
//
//  Created by Timothy Velberg on 29/01/2026.
//  Data model for a single panel in the list panel stack.
//

import Foundation
import AppKit

// MARK: - Typing Mode

/// Determines how character input is handled in this panel
enum TypingMode {
    /// Characters trigger type-ahead search (jump to matching item)
    case typeAhead
    
    /// Characters activate and populate search filter
    case search
    
    /// Characters populate input field for adding new items (header field always visible)
    case input
}

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
    
    /// Panel layout configuration (dimensions, line limit, etc.)
    let config: PanelConfig
    
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
    var typingMode: TypingMode = .typeAhead

    /// Active typing mode (can differ from default when CMD+F toggles)
    var activeTypingMode: TypingMode
    
    /// Original panel height before search filtering (for top-anchored resizing)
    var searchAnchorHeight: CGFloat?
    
    // MARK: - Computed Properties
    
    /// Calculate panel height based on item count and config
    var panelHeight: CGFloat {
        let itemCount = min(items.count, config.maxVisibleItems)
        return PanelConfig.titleHeight + CGFloat(itemCount) * config.rowHeight + PanelConfig.padding
    }
    
    /// Panel bounds in screen coordinates (at original position, not accounting for overlap)
    var bounds: NSRect {
        NSRect(
            x: position.x - config.panelWidth / 2,
            y: position.y - panelHeight / 2,
            width: config.panelWidth,
            height: panelHeight
        )
    }
}
