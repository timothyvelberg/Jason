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

// MARK: - Drag Provider
struct DragProvider {
    let fileURLs: [URL]
    let dragImage: NSImage?
    let allowedOperations: NSDragOperation
    let onClick: (() -> Void)?
    let onDragStarted: (() -> Void)?
    let onDragCompleted: ((Bool) -> Void)?
    
    //Modifier flags captured when drag starts
    var modifierFlags: NSEvent.ModifierFlags = []
    
    init(fileURLs: [URL],
         dragImage: NSImage? = nil,
         allowedOperations: NSDragOperation = [.move],
         onClick: (() -> Void)? = nil,
         onDragStarted: (() -> Void)? = nil,
         onDragCompleted: ((Bool) -> Void)? = nil) {
        self.fileURLs = fileURLs
        self.dragImage = dragImage
        self.allowedOperations = allowedOperations
        self.onClick = onClick
        self.onDragStarted = onDragStarted
        self.onDragCompleted = onDragCompleted
    }
}

// MARK: - Extended InteractionBehavior
enum InteractionBehavior {
    case execute(() -> Void)           // Execute action, close UI
    case executeKeepOpen(() -> Void)   // Execute action, keep UI open
    case expand                         // Show children/contextActions
    case drag(DragProvider)            // Enable drag-and-drop
    case doNothing                      // No interaction
    
    var shouldExecute: Bool {
        switch self {
        case .execute, .executeKeepOpen:
            return true
        default:
            return false
        }
    }
    
    var shouldCloseUI: Bool {
        switch self {
        case .execute:
            return true
        case .executeKeepOpen, .expand, .drag, .doNothing:
            return false
        }
    }
    
    var isDraggable: Bool {
        if case .drag = self {
            return true
        }
        return false
    }
    
    var dragProvider: DragProvider? {
        if case .drag(let provider) = self {
            return provider
        }
        return nil
    }
    
    func perform() {
        switch self {
        case .execute(let action), .executeKeepOpen(let action):
            action()
        case .expand:
            print("⚠️ Expand should be handled by UI layer")
        case .drag:
            print("⚠️ Drag should be handled by gesture system")
        case .doNothing:
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
    let itemAngleSize: CGFloat?
    let previewURL: URL?
    let showCurvedLabel: Bool
    
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
        itemAngleSize: CGFloat? = nil,
        previewURL: URL? = nil,
        showCurvedLabel: Bool = false,
        
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
        self.itemAngleSize = itemAngleSize
        self.previewURL = previewURL
        self.showCurvedLabel = showCurvedLabel
        
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
    
    var isPreviewable: Bool {
        return previewURL != nil
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
    static func fullCircle(itemCount: Int, startingAt angle: Double = 0) -> PieSliceConfig {
        let itemAngle = 360.0 / Double(max(itemCount, 1))
        return PieSliceConfig(
            startAngle: angle,
            endAngle: angle + 360,  // Don't use modulo - we need 360° span!
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

// MARK: - Updated FunctionNode
extension FunctionNode {
    // Add drag behavior property
    var onDrag: InteractionBehavior {
        // Check if left click is draggable
        if case .drag = onLeftClick {
            return onLeftClick
        }
        // Default: not draggable
        return .doNothing
    }
    
    var isDraggable: Bool {
        return onDrag.isDraggable
    }
}
