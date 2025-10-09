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

// MARK: - Interaction Model

/// Defines what happens when a user interacts with a FunctionNode
enum InteractionBehavior {
    case execute(() -> Void)           // Execute an action (and usually close UI)
    case executeKeepOpen(() -> Void)   // Execute an action but keep UI open
    case expand                         // Expand to show children or contextActions
    case doNothing                      // No interaction
    
    var shouldExecute: Bool {
        switch self {
        case .execute, .executeKeepOpen:
            return true
        case .expand, .doNothing:
            return false
        }
    }
    
    var shouldCloseUI: Bool {
        switch self {
        case .execute:
            return true
        case .executeKeepOpen, .expand, .doNothing:
            return false
        }
    }
    
    func perform() {
        switch self {
        case .execute(let action), .executeKeepOpen(let action):
            action()
        case .expand, .doNothing:
            break
        }
    }
}

// MARK: - FunctionNode (Tree Structure)

// MARK: - FunctionNode (Tree Structure)

class FunctionNode: Identifiable, ObservableObject {
    let id: String
    let name: String
    let icon: NSImage
    let children: [FunctionNode]?
    let contextActions: [FunctionNode]?
    let maxDisplayedChildren: Int?
    let preferredLayout: LayoutStyle?
    
    // MARK: - Interaction Model (Explicit Behavior)
    let onLeftClick: InteractionBehavior
    let onRightClick: InteractionBehavior
    let onMiddleClick: InteractionBehavior
    let onBoundaryCross: InteractionBehavior
    
    // MARK: - Legacy Events (Deprecated - use interaction model instead)
    let onHover: (() -> Void)?
    let onHoverExit: (() -> Void)?
    
    init(
        id: String,
        name: String,
        icon: NSImage,
        children: [FunctionNode]? = nil,
        contextActions: [FunctionNode]? = nil,
        maxDisplayedChildren: Int? = nil,
        preferredLayout: LayoutStyle? = nil,
        // Explicit interaction declarations
        onLeftClick: InteractionBehavior = .doNothing,
        onRightClick: InteractionBehavior = .doNothing,
        onMiddleClick: InteractionBehavior = .doNothing,
        onBoundaryCross: InteractionBehavior = .doNothing,
        // Legacy
        onHover: (() -> Void)? = nil,
        onHoverExit: (() -> Void)? = nil,
        // DEPRECATED: Old onSelect parameter
        onSelect: (() -> Void)? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.children = children
        self.contextActions = contextActions
        self.maxDisplayedChildren = maxDisplayedChildren
        self.preferredLayout = preferredLayout
        
        // Set interaction behaviors
        // If old onSelect was provided, convert it to onLeftClick for backward compatibility
        if let onSelect = onSelect {
            self.onLeftClick = .execute(onSelect)
        } else {
            self.onLeftClick = onLeftClick
        }
        
        self.onRightClick = onRightClick
        self.onMiddleClick = onMiddleClick
        self.onBoundaryCross = onBoundaryCross
        
        self.onHover = onHover
        self.onHoverExit = onHoverExit
    }
    
    // MARK: - Computed Properties
    
    // DEPRECATED: For backward compatibility only
    var action: (() -> Void)? {
        return nil  // Use onLeftClick instead
    }
    
    var onSelect: (() -> Void)? {
        return nil  // Use onLeftClick instead
    }
    
    // Leaf = has executable left-click action, no children or contextActions
    var isLeaf: Bool {
        return children == nil && contextActions == nil && onLeftClick.shouldExecute
    }
    
    // Branch = has children OR contextActions
    var isBranch: Bool {
        return children != nil || contextActions != nil
    }
    
    // REMOVED: isContextMenu - use onRightClick behavior instead
    // REMOVED: shouldAutoExpand - use onBoundaryCross behavior instead
    
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
