//
//  DragProvider.swift
//  Jason
//
//  Created by Timothy Velberg on 27/12/2025.
//
//  Drag-and-drop support structures
//

import Cocoa

// MARK: - Drag Click Behavior

/// Defines what happens when a draggable item is clicked (not dragged)
enum DragClickBehavior {
    case execute(() -> Void)   // Run action then hide UI (e.g., open file)
    case navigate              // Navigate into folder (stay open)
    case none                  // Do nothing on click
}

// MARK: - Drag Provider

struct DragProvider {
    let fileURLs: [URL]
    let dragImage: NSImage?
    let allowedOperations: NSDragOperation
    let clickBehavior: DragClickBehavior
    var onDragStarted: (() -> Void)?
    var onDragSessionBegan: (() -> Void)?
    var onDragCompleted: ((Bool) -> Void)?
    
    // Modifier flags captured when drag starts (and updated during drag)
    var modifierFlags: NSEvent.ModifierFlags = []
    
    /// Full initializer with explicit click behavior
    init(
        fileURLs: [URL],
        dragImage: NSImage? = nil,
        allowedOperations: NSDragOperation = [.move],
        clickBehavior: DragClickBehavior = .none,
        onDragStarted: (() -> Void)? = nil,
        onDragCompleted: ((Bool) -> Void)? = nil
    ) {
        self.fileURLs = fileURLs
        self.dragImage = dragImage
        self.allowedOperations = allowedOperations
        self.clickBehavior = clickBehavior
        self.onDragStarted = onDragStarted
        self.onDragCompleted = onDragCompleted
    }
    
    /// Convenience initializer for backwards compatibility
    /// Maps onClick closure to DragClickBehavior.execute
    init(
        fileURLs: [URL],
        dragImage: NSImage? = nil,
        allowedOperations: NSDragOperation = [.move],
        onClick: (() -> Void)?,
        onDragStarted: (() -> Void)? = nil,
        onDragCompleted: ((Bool) -> Void)? = nil
    ) {
        self.fileURLs = fileURLs
        self.dragImage = dragImage
        self.allowedOperations = allowedOperations
        self.clickBehavior = onClick.map { .execute($0) } ?? .none
        self.onDragStarted = onDragStarted
        self.onDragCompleted = onDragCompleted
    }
}
