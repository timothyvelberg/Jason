//
//  FunctionModels.swift
//  Jason
//
//  Created by Timothy Velberg on 06/10/2025.
//

import Foundation
import AppKit

// MARK: - Function Node Type

/// Explicit type declaration for function nodes
/// Defines the node's intent and capabilities independent of current state
enum FunctionNodeType {
    /// Executes a system function (Mission Control, Screenshot, etc.)
    /// - Always leaf node (no children)
    /// - Minimal or no context menu
    case action
    
    /// Organizational UI wrapper (e.g., "Applications", "Folders" category)
    /// - MUST have children or contextActions
    /// - Not a real filesystem entity
    /// - Custom context actions (provider-specific)
    case category
    
    /// Application node
    /// - Can have children (recent documents, windows)
    /// - Context: Open, Quit, Hide, Favorite/Unfavorite, Show in Finder
    case app
    
    /// Individual file or document
    /// - Always leaf node
    /// - Context: Open, Open With, Delete, Show in Finder
    case file
    
    /// Filesystem folder or directory
    /// - Can have children (folder contents)
    /// - Context: Open, Show in Finder, Add to Favorites
    case folder
}

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
    case execute(() -> Void)            // Execute action, close UI
    case executeKeepOpen(() -> Void)    // Execute action, keep UI open
    case expand                         // Show children/contextActions
    case navigateInto                   // Navigate into folder, collapse previous ring
    case launchRing(configId: Int)      // Launch another ring config
    case drag(DragProvider)             // Enable drag-and-drop
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
        case .execute, .launchRing:
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
        case .launchRing:
            print("⚠️ LaunchRing should be handled by UI layer")
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
    let type: FunctionNodeType
    let icon: NSImage
    let children: [FunctionNode]?
    let contextActions: [FunctionNode]?
    let maxDisplayedChildren: Int?
    
    let preferredLayout: LayoutStyle?
    let itemAngleSize: CGFloat?          // My own angle size when rendered as an item
    let childItemAngleSize: CGFloat?     // Default angle for my children (if they don't specify itemAngleSize)
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
        type: FunctionNodeType,
        icon: NSImage,
        children: [FunctionNode]? = nil,
        contextActions: [FunctionNode]? = nil,
        maxDisplayedChildren: Int? = nil,
        
        preferredLayout: LayoutStyle? = nil,
        parentAngleSize: CGFloat? = nil,
        itemAngleSize: CGFloat? = nil,
        childItemAngleSize: CGFloat? = nil,
        
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
        self.type = type
        self.icon = icon
        self.children = children
        self.contextActions = contextActions
        self.maxDisplayedChildren = maxDisplayedChildren
        
        self.preferredLayout = preferredLayout
        self.parentAngleSize = parentAngleSize
        self.itemAngleSize = itemAngleSize
        self.childItemAngleSize = childItemAngleSize
        
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
        
        // MARK: - Type Contract Validation
        #if DEBUG
        switch type {
        case .file:
            // Files can have contextActions (right-click menu), but not children
            assert((children?.count ?? 0) == 0,
                "[file] nodes cannot have children (node: \(name))")
            
        case .action:
            // Actions are pure leaf nodes - no children or contextActions
            assert((children?.count ?? 0) == 0 && (contextActions?.count ?? 0) == 0,
                "[action] nodes cannot have children or contextActions (node: \(name))")
        case .category:
            assert((children?.count ?? 0) > 0 || (contextActions?.count ?? 0) > 0,
                   "[.category] nodes must have children or contextActions (node: \(name))")
        case .folder, .app:
            // Can have children or be empty
            break
        }
        #endif
    }
    
    // MARK: - Computed Properties
    
    var isPreviewable: Bool {
        return previewURL != nil
    }
    
    // Leaf nodes are determined by type (actions and files are always leaves)
    var isLeaf: Bool {
        return type == .action || type == .file
    }
    
    // Branch nodes are determined by type (categories, folders, and apps can have children)
    var isBranch: Bool {
        return type == .category || type == .folder || type == .app
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
        positioning: SlicePositioning = .startClockwise,
        perItemAngles: [Double]? = nil  // 🆕 Support variable angles
    ) -> PieSliceConfig {
        // Calculate total angle from perItemAngles if provided, otherwise use default
        let totalAngle: Double
        let itemAngle: Double
        
        if let perItemAngles = perItemAngles {
            // Use variable angles
            totalAngle = min(perItemAngles.reduce(0, +), 360.0)
            itemAngle = totalAngle / Double(itemCount)  // Average for fallback
        } else {
            // Use uniform angles
            totalAngle = min(Double(itemCount) * defaultItemAngle, 360.0)
            
            if itemCount == 1 {
                itemAngle = defaultItemAngle
            } else {
                itemAngle = totalAngle / Double(itemCount)
            }
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
            perItemAngles: perItemAngles,  // 🆕 Pass through variable angles
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

extension FunctionNode {
    /// Create a copy of this node with a different providerId
    /// Used by display mode transformations to ensure extracted children
    /// retain proper provider attribution for surgical ring updates
    func withProviderId(_ newProviderId: String) -> FunctionNode {
        return FunctionNode(
            id: id,
            name: name,
            type: type,
            icon: icon,
            children: children,
            contextActions: contextActions,
            maxDisplayedChildren: maxDisplayedChildren,
            preferredLayout: preferredLayout,
            parentAngleSize: parentAngleSize,
            itemAngleSize: itemAngleSize,
            childItemAngleSize: childItemAngleSize,
            previewURL: previewURL,
            showLabel: showLabel,
            childRingThickness: childRingThickness,
            childIconSize: childIconSize,
            slicePositioning: slicePositioning,
            partialSliceThreshold: partialSliceThreshold,
            metadata: metadata,
            providerId: newProviderId,
            onLeftClick: onLeftClick,
            onRightClick: onRightClick,
            onMiddleClick: onMiddleClick,
            onBoundaryCross: onBoundaryCross,
            onHover: onHover,
            onHoverExit: onHoverExit
        )
    }
}
