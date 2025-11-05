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

// MARK: - Slice Positioning

enum SlicePositioning {
    case startClockwise       // Start at left edge of parent, extend right (default)
    case startCounterClockwise // Start at right edge of parent, extend left
    case center                // Center symmetrically on parent (direction doesn't matter)
}

// MARK: - Drag Provider
struct DragProvider {
    let fileURLs: [URL]
    let dragImage: NSImage?
    let allowedOperations: NSDragOperation
    let onClick: (() -> Void)?
    var onDragStarted: (() -> Void)?  // ← Changed from let to var
    var onDragCompleted: ((Bool) -> Void)?  // ← Changed from let to var
    
    // Modifier flags captured when drag starts (and updated during drag)
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
    case navigateInto                   // Navigate into folder, collapse previous ring
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
        case .executeKeepOpen, .expand, .navigateInto, .drag, .doNothing:
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
        case .navigateInto:
            print("⚠️ NavigateInto should be handled by UI layer")
        case .drag:
            print("⚠️ Drag should be handled by gesture system")
        case .doNothing:
            break
        }
    }
}

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
    let parentAngleSize: CGFloat?
    
    let previewURL: URL?
    let showLabel: Bool
    
    let childRingThickness: CGFloat?
    let childIconSize: CGFloat?
    
    // Slice positioning preference
    let slicePositioning: SlicePositioning?
    
    //Threshold for switching from partial to fullCircle
    let partialSliceThreshold: Int?
    
    //Metadata for dynamic loading
    let metadata: [String: Any]?
    let providerId: String?
    
    // MARK: - Interaction Model (Explicit Behavior)
    let onLeftClick: ModifierAwareInteraction
    let onRightClick: ModifierAwareInteraction
    let onMiddleClick: ModifierAwareInteraction
    let onBoundaryCross: ModifierAwareInteraction
    
    // MARK: - Events
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
        parentAngleSize: CGFloat? = nil,
        itemAngleSize: CGFloat? = nil,
        
        previewURL: URL? = nil,
        showLabel: Bool = false,
        
        childRingThickness: CGFloat? = nil,
        childIconSize: CGFloat? = nil,
        
        // Slice positioning parameter
        slicePositioning: SlicePositioning? = nil,
        
        //Custom threshold for partial→fullCircle switch
        partialSliceThreshold: Int? = nil,
      
        //Metadata and provider ID
         metadata: [String: Any]? = nil,
         providerId: String? = nil,
        
        // Explicit interaction declarations
        onLeftClick: ModifierAwareInteraction = ModifierAwareInteraction(base: .doNothing),
        onRightClick: ModifierAwareInteraction = ModifierAwareInteraction(base: .doNothing),
        onMiddleClick: ModifierAwareInteraction = ModifierAwareInteraction(base: .doNothing),
        onBoundaryCross: ModifierAwareInteraction = ModifierAwareInteraction(base: .doNothing),
        
        onHover: (() -> Void)? = nil,
        onHoverExit: (() -> Void)? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.children = children
        self.contextActions = contextActions
        self.maxDisplayedChildren = maxDisplayedChildren
        
        self.preferredLayout = preferredLayout
        self.parentAngleSize = parentAngleSize
        self.itemAngleSize = itemAngleSize
        
        self.previewURL = previewURL
        self.showLabel = showLabel
        
        self.childRingThickness = childRingThickness
        self.childIconSize = childIconSize
        
        self.slicePositioning = slicePositioning
        self.partialSliceThreshold = partialSliceThreshold
        
        self.metadata = metadata
        self.providerId = providerId
        
        self.onLeftClick = onLeftClick
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
    
    // Leaf = has executable left-click action, no children or contextActions
    var isLeaf: Bool {
        return children == nil && contextActions == nil && onLeftClick.base.shouldExecute
    }
    
    // Branch = has children OR contextActions
    var isBranch: Bool {
        return children != nil || contextActions != nil
    }
    
    //Check if this node needs dynamic loading
    var needsDynamicLoading: Bool {
        // If it has navigateInto behavior and metadata, it needs dynamic loading
        if case .navigateInto = onLeftClick.base, metadata != nil {
            return true
        }
        if case .navigateInto = onBoundaryCross.base, metadata != nil {
            return true
        }
        return false
    }
    
    // Is this a valid branch (has actual children or context actions)?
    var hasChildren: Bool {
        return (children?.count ?? 0) > 0 || (contextActions?.count ?? 0) > 0 || needsDynamicLoading
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
    let perItemAngles: [Double]?  //Optional per-item angles for Ring 0
    let positioning: SlicePositioning
    
    var totalAngle: Double {
        return endAngle - startAngle
    }
    
    var isFullCircle: Bool {
        // Use tolerance to handle floating point precision
        return totalAngle >= 359.9
    }
    
    // Helper computed properties for compatibility
    var direction: SliceDirection {
        switch positioning {
        case .startClockwise, .center:
            return .clockwise
        case .startCounterClockwise:
            return .counterClockwise
        }
    }
    
    // Factory method for full circle
    static func fullCircle(
        itemCount: Int,
        anglePerItem: Double,
        positioning: SlicePositioning = .startClockwise
    ) -> PieSliceConfig {
        return PieSliceConfig(
            startAngle: 0,
            endAngle: 360,
            itemAngle: anglePerItem,
            perItemAngles: nil,
            positioning: positioning
        )
    }
    
    // Factory method for full circle with custom start
    static func fullCircle(
        itemCount: Int,
        anglePerItem: Double,
        startingAt angle: Double = 0,
        positioning: SlicePositioning = .startClockwise,
        perItemAngles: [Double]? = nil
    ) -> PieSliceConfig {
        return PieSliceConfig(
            startAngle: angle,
            endAngle: angle + 360,
            itemAngle: anglePerItem,
            perItemAngles: perItemAngles,
            positioning: positioning
        )
    }
    
    // Factory method for partial slice
    static func partialSlice(
        itemCount: Int,
        centeredAt parentAngle: Double,
        defaultItemAngle: Double = 30.0,
        positioning: SlicePositioning = .startClockwise
    ) -> PieSliceConfig {
        let totalAngle = min(Double(itemCount) * defaultItemAngle, 360.0)
        
        let itemAngle: Double
        if itemCount == 1 {
            itemAngle = defaultItemAngle
        } else {
            itemAngle = totalAngle / Double(itemCount)
        }
        
        let startAngle: Double
        let endAngle: Double
        
        switch positioning {
        case .startClockwise:
            // First item starts at parent angle, extends rightward
            startAngle = parentAngle
            endAngle = (parentAngle + totalAngle).truncatingRemainder(dividingBy: 360)
            
        case .startCounterClockwise:
            // First item starts at parent angle, extends leftward
            startAngle = (parentAngle - totalAngle).truncatingRemainder(dividingBy: 360)
            endAngle = parentAngle
            
        case .center:
            // Center the slice symmetrically on parent angle
            let halfAngle = totalAngle / 2
            startAngle = (parentAngle - halfAngle).truncatingRemainder(dividingBy: 360)
            endAngle = (parentAngle + halfAngle).truncatingRemainder(dividingBy: 360)
        }
        
        return PieSliceConfig(
            startAngle: startAngle,
            endAngle: endAngle,
            itemAngle: itemAngle,
            perItemAngles: nil,
            positioning: positioning
        )
    }
}

// MARK: - Modifier-Aware Interaction

struct ModifierAwareInteraction {
    let base: InteractionBehavior
    var shift: InteractionBehavior?
    var command: InteractionBehavior?
    var option: InteractionBehavior?
    
    /// Resolve the appropriate behavior based on current modifier flags
    func resolve(with modifiers: NSEvent.ModifierFlags) -> InteractionBehavior {
        // Check in priority order: Shift > Command > Option
        if modifiers.contains(.shift), let behavior = shift {
            return behavior
        }
        if modifiers.contains(.command), let behavior = command {
            return behavior
        }
        if modifiers.contains(.option), let behavior = option {
            return behavior
        }
        return base
    }
    
    // Convenience initializer for simple cases (no modifiers)
    init(base: InteractionBehavior) {
        self.base = base
        self.shift = nil
        self.command = nil
        self.option = nil
    }
    
    // Full initializer with all modifiers
    init(
        base: InteractionBehavior,
        shift: InteractionBehavior? = nil,
        command: InteractionBehavior? = nil,
        option: InteractionBehavior? = nil
    ) {
        self.base = base
        self.shift = shift
        self.command = command
        self.option = option
    }
}

// MARK: - Legacy Direction Enum (for compatibility)
enum SliceDirection {
    case clockwise
    case counterClockwise
}

// MARK: - Drag behavior extension
extension FunctionNode {
    // Add drag behavior property
    var onDrag: InteractionBehavior {
        // Check if base left click is draggable
        if case .drag = onLeftClick.base {
            return onLeftClick.base
        }
        // Default: not draggable
        return .doNothing
    }
    
    var isDraggable: Bool {
        return onDrag.isDraggable
    }
}
