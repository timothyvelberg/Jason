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
    let action: (() -> Void)?
    let maxDisplayedChildren: Int?  // NEW: Limit how many children to show
    
    init(
        id: String,
        name: String,
        icon: NSImage,
        children: [FunctionNode]? = nil,
        action: (() -> Void)? = nil,
        maxDisplayedChildren: Int? = nil  // NEW parameter
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.children = children
        self.action = action
        self.maxDisplayedChildren = maxDisplayedChildren
    }
    
    // Leaf = has action, no children
    var isLeaf: Bool {
        return children == nil && action != nil
    }
    
    // Branch = has children (even if empty array)
    var isBranch: Bool {
        return children != nil
    }
    
    // Is this a valid branch (has actual children)?
    var hasChildren: Bool {
        return (children?.count ?? 0) > 0
    }
    
    var childCount: Int {
        return children?.count ?? 0
    }
    
    // NEW: Get children with limit applied
    var displayedChildren: [FunctionNode] {
        guard let children = children else { return [] }
        
        if let maxChildren = maxDisplayedChildren, children.count > maxChildren {
            // Return limited children + a "view more" node
            let limitedChildren = Array(children.prefix(maxChildren))
            // TODO: Add "View More..." node here
            return limitedChildren
        }
        
        return children
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
