//
//  FunctionModels.swift
//  Jason
//
//  Created by Timothy Velberg on 06/10/2025.
//

import Foundation
import AppKit

// MARK: - Layout Style

enum LayoutStyle {
    case fullCircle   // 360° ring, items evenly distributed
    case partialSlice // Partial arc centered on parent
}

// MARK: - FunctionNode (Tree Structure)

class FunctionNode: Identifiable, ObservableObject {
    let id: String
    let name: String
    let icon: NSImage
    let children: [FunctionNode]?
    let contextActions: [FunctionNode]?
    let onSelect: (() -> Void)?
    let onHover: (() -> Void)?
    let onHoverExit: (() -> Void)?
    let maxDisplayedChildren: Int?
    let preferredLayout: LayoutStyle?
    
    init(
        id: String,
        name: String,
        icon: NSImage,
        children: [FunctionNode]? = nil,
        contextActions: [FunctionNode]? = nil,
        onSelect: (() -> Void)? = nil,
        onHover: (() -> Void)? = nil,
        onHoverExit: (() -> Void)? = nil,
        maxDisplayedChildren: Int? = nil,
        preferredLayout: LayoutStyle? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.children = children
        self.contextActions = contextActions
        self.onSelect = onSelect
        self.onHover = onHover
        self.onHoverExit = onHoverExit
        self.maxDisplayedChildren = maxDisplayedChildren
        self.preferredLayout = preferredLayout
    }
    
    // DEPRECATED: For backward compatibility
    var action: (() -> Void)? {
        return onSelect
    }
    
    // Leaf = has onSelect action, no children or contextActions
    var isLeaf: Bool {
        return children == nil && contextActions == nil && onSelect != nil
    }
    
    // Branch = has children OR contextActions
    var isBranch: Bool {
        return children != nil || contextActions != nil
    }
    
    // NEW: Is this a context menu (has contextActions, not regular children)?
    var isContextMenu: Bool {
        return contextActions != nil && children == nil
    }
    
    // NEW: Should this auto-expand on boundary cross?
    // Regular categories (children) = yes
    // Context menus (contextActions) = no (right-click only)
    var shouldAutoExpand: Bool {
        return children != nil && children!.count > 0
    }
    
    // Is this a valid branch (has actual children or context actions)?
    var hasChildren: Bool {
        return (children?.count ?? 0) > 0 || (contextActions?.count ?? 0) > 0
    }
    
    var childCount: Int {
        return children?.count ?? contextActions?.count ?? 0
    }
    
    // Get children with limit applied (works for both children and contextActions)
    var displayedChildren: [FunctionNode] {
        // Prefer children over contextActions
        let actualChildren = children ?? contextActions ?? []
        
        if let maxChildren = maxDisplayedChildren, actualChildren.count > maxChildren {
            // Return limited children + a "view more" node
            let limitedChildren = Array(actualChildren.prefix(maxChildren))
            // TODO: Add "View More..." node here
            return limitedChildren
        }
        
        return actualChildren
    }
}

// MARK: - Pie Slice Configuration

struct PieSliceConfig {
    let startAngle: Double  // In degrees
    let endAngle: Double    // In degrees
    let itemAngle: Double   // Angle per item (default 30°)
    
    var totalAngle: Double {
        return endAngle - startAngle
    }
    
    var isFullCircle: Bool {
        return totalAngle >= 360.0
    }
    
    // Factory method for full circle
    // Automatically calculates itemAngle based on item count
    static func fullCircle(itemCount: Int) -> PieSliceConfig {
        let itemAngle = 360.0 / Double(max(itemCount, 1))
        return PieSliceConfig(
            startAngle: 0,
            endAngle: 360,
            itemAngle: itemAngle
        )
    }
    
    // Factory method for partial slice (Ring 1+)
    static func partialSlice(itemCount: Int, centeredAt parentAngle: Double, defaultItemAngle: Double = 30.0) -> PieSliceConfig {
        let totalAngle = min(Double(itemCount) * defaultItemAngle, 360.0)  // Cap at 360°
        
        // Handle single item case - inherit parent's angle
        let itemAngle: Double
        if itemCount == 1 {
            itemAngle = defaultItemAngle
        } else {
            itemAngle = totalAngle / Double(itemCount)
        }
        
        // Align first item with parent, extend clockwise
        let startAngle = parentAngle
        let endAngle = (parentAngle + totalAngle).truncatingRemainder(dividingBy: 360)
        
        return PieSliceConfig(
            startAngle: startAngle,
            endAngle: endAngle,
            itemAngle: itemAngle
        )
    }
}

// MARK: - Legacy Structures (to be removed after migration)

struct FunctionItem {
    let id: String
    let name: String
    let icon: NSImage
    let action: () -> Void
}

struct FunctionCategory {
    let id: String
    let name: String
    let icon: NSImage
    let functions: [FunctionItem]
}
