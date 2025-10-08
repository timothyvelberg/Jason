//
//  FunctionModels.swift
//  Jason
//
//  Created by Timothy Velberg on 06/10/2025.
//

import Foundation
import AppKit

// MARK: - FunctionNode (Tree Structure)

class FunctionNode: Identifiable, ObservableObject {
    let id: String
    let name: String
    let icon: NSImage
    let children: [FunctionNode]?
    let contextActions: [FunctionNode]?  // NEW: Actions shown in next ring for leaf nodes
    let onSelect: (() -> Void)?  // Renamed from 'action' for clarity
    let onHover: (() -> Void)?   // NEW: Called when mouse enters
    let onHoverExit: (() -> Void)?  // NEW: Called when mouse leaves
    let maxDisplayedChildren: Int?
    
    init(
        id: String,
        name: String,
        icon: NSImage,
        children: [FunctionNode]? = nil,
        contextActions: [FunctionNode]? = nil,  // NEW parameter
        onSelect: (() -> Void)? = nil,
        onHover: (() -> Void)? = nil,   // NEW parameter
        onHoverExit: (() -> Void)? = nil,  // NEW parameter
        maxDisplayedChildren: Int? = nil
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
    
    // Is this a valid branch (has actual children or context actions)?
    var hasChildren: Bool {
        return (children?.count ?? 0) > 0 || (contextActions?.count ?? 0) > 0
    }
    
    var childCount: Int {
        return children?.count ?? contextActions?.count ?? 0
    }
    
    // NEW: Get children with limit applied (works for both children and contextActions)
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
    
    // Factory method for full circle (Ring 0)
    static func fullCircle(itemCount: Int) -> PieSliceConfig {
        return PieSliceConfig(
            startAngle: 0,
            endAngle: 360,
            itemAngle: 360.0 / Double(itemCount)
        )
    }
    
    // Factory method for partial slice (Ring 1+)
    static func partialSlice(itemCount: Int, centeredAt parentAngle: Double, defaultItemAngle: Double = 30.0) -> PieSliceConfig {
        let totalAngle = min(Double(itemCount) * defaultItemAngle, 360.0)  // Cap at 360°
        
        // Handle single item case - inherit parent's angle
        let itemAngle: Double
        if itemCount == 1 {
            // We'll need the parent's angle width - for now use default
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
