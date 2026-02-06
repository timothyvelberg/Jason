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
    
    /// Measured row heights from SwiftUI (indexed by item position)
    /// Falls back to config.baseRowHeight for unmeasured rows
    var rowHeights: [CGFloat] = []
    
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
    
    // MARK: - Row Height Helpers
    
    /// Get the height for a specific row (measured or fallback to base)
    func heightForRow(_ index: Int) -> CGFloat {
        if index < rowHeights.count {
            return rowHeights[index]
        }
        return config.baseRowHeight
    }
    
    /// Total content height for all items
    var totalContentHeight: CGFloat {
        if rowHeights.count == items.count {
            return rowHeights.reduce(0, +)
        }
        // Mixed: sum measured + estimate unmeasured
        var total: CGFloat = 0
        for i in 0..<items.count {
            total += heightForRow(i)
        }
        return total
    }
    
    /// Content height for visible items (up to maxVisibleItems)
    var visibleContentHeight: CGFloat {
        let visibleCount = min(items.count, config.maxVisibleItems)
        var total: CGFloat = 0
        for i in 0..<visibleCount {
            total += heightForRow(i)
        }
        return total
    }
    
    /// Y offset from the top of the content area to the top of a given row
    /// (sum of heights of all rows above it)
    func yOffsetForRow(_ index: Int) -> CGFloat {
        var offset: CGFloat = 0
        for i in 0..<min(index, items.count) {
            offset += heightForRow(i)
        }
        return offset
    }
    
    /// Find which row index a given Y offset (from top of content) falls into
    /// Returns nil if offset is outside all rows
    func rowIndex(atContentOffset offset: CGFloat) -> Int? {
        guard offset >= 0 else { return nil }
        var accumulated: CGFloat = 0
        for i in 0..<items.count {
            let rowH = heightForRow(i)
            if offset < accumulated + rowH {
                return i
            }
            accumulated += rowH
        }
        return nil
    }
    
    // MARK: - Computed Properties
    
    /// Calculate panel height based on visible content height
    var panelHeight: CGFloat {
        return PanelConfig.titleHeight + visibleContentHeight + ((PanelConfig.padding * 2) + PanelConfig.padding / 2)
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
