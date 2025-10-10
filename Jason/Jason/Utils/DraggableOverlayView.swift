//
//  DraggableOverlayView.swift
//  Jason
//
//  Created by Timothy Velberg on 09/10/2025.
//
//  Created for drag-and-drop support
//

import Cocoa
import SwiftUI

/// AppKit bridge for drag-and-drop operations
/// SwiftUI doesn't support drag sources well for overlay windows, so we use AppKit
class DraggableOverlayView: NSView {
    
    // MARK: - Properties
    var dragProvider: DragProvider?
    private var dragStartPoint: CGPoint = .zero
    private var isDragging = false
    
    // MARK: - Initialization
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        // Register for drag types
        registerForDraggedTypes([.fileURL, .URL, .string])
    }
    
    // MARK: - Drag Initiation
    func startDragSession(at point: CGPoint, provider: DragProvider) {
        guard !provider.fileURLs.isEmpty else {
            print("⚠️ No files to drag")
            return
        }
        
        self.dragProvider = provider
        self.dragStartPoint = point
        self.isDragging = true
        
        // Call drag started callback
        provider.onDragStarted?()
        
        // Create pasteboard and write files
        let pasteboard = NSPasteboard(name: .drag)
        pasteboard.clearContents()
        
        // Write file URLs to pasteboard
        pasteboard.writeObjects(provider.fileURLs as [NSPasteboardWriting])
        
        // Create drag image
        let dragImage = createDragImage(for: provider)
        
        // Create dragging items
        var draggingItems: [NSDraggingItem] = []
        for fileURL in provider.fileURLs {
            let item = NSDraggingItem(pasteboardWriter: fileURL as NSPasteboardWriting)
            item.setDraggingFrame(NSRect(origin: point, size: dragImage.size), contents: dragImage)
            draggingItems.append(item)
        }
        
        // Create fake mouse event at the drag point
        let event = NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )
        
        guard let event = event else {
            print("⚠️ Failed to create drag event")
            return
        }
        
        print("🎯 Starting drag session with \(provider.fileURLs.count) file(s)")
        
        // Begin dragging session
        beginDraggingSession(with: draggingItems, event: event, source: self)
    }
    
    // MARK: - Drag Image Creation
    private func createDragImage(for provider: DragProvider) -> NSImage {
        // Use custom image if provided
        if let customImage = provider.dragImage {
            return customImage
        }
        
        // Create default drag image
        let fileCount = provider.fileURLs.count
        
        if fileCount == 1, let url = provider.fileURLs.first {
            // Single file - use icon
            return createFileIcon(for: url)
        } else {
            // Multiple files - create badge
            return createMultiFileImage(count: fileCount)
        }
    }
    
    private func createFileIcon(for url: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64)
        return icon
    }
    
    private func createMultiFileImage(count: Int) -> NSImage {
        let size = NSSize(width: 80, height: 80)
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        // Draw stacked file icons
        let iconSize: CGFloat = 60
        let offset: CGFloat = 6
        
        // Background files
        for i in 0..<min(3, count) {
            let rect = NSRect(
                x: CGFloat(i) * offset,
                y: CGFloat(i) * offset,
                width: iconSize,
                height: iconSize
            )
            
            NSColor.controlBackgroundColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            
            NSColor.systemGray.setStroke()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).stroke()
        }
        
        // Badge with count
        if count > 1 {
            let badgeSize: CGFloat = 24
            let badgeRect = NSRect(
                x: size.width - badgeSize - 4,
                y: 4,
                width: badgeSize,
                height: badgeSize
            )
            
            NSColor.systemBlue.setFill()
            NSBezierPath(ovalIn: badgeRect).fill()
            
            let text = "\(count)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 12),
                .foregroundColor: NSColor.white
            ]
            let textSize = text.size(withAttributes: attrs)
            let textPoint = NSPoint(
                x: badgeRect.midX - textSize.width / 2,
                y: badgeRect.midY - textSize.height / 2
            )
            text.draw(at: textPoint, withAttributes: attrs)
        }
        
        image.unlockFocus()
        return image
    }
}

// MARK: - NSDraggingSource
extension DraggableOverlayView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // CRITICAL: Return a MASK of allowed operations, not just one!
        // This tells macOS "these operations are allowed, pick one based on modifiers"
        
        if context == .outsideApplication {
            // Dragging outside the app - allow both move and copy
            return [.move, .copy]
        } else {
            // Dragging within the app - allow both move and copy
            return [.move, .copy]
        }
        
        // macOS will automatically choose:
        // - .move if no modifiers
        // - .copy if Option is held
        // The cursor updates automatically!
    }
    
    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        print("🎯 Drag session beginning at \(screenPoint)")
        
        // Log the initial operation
        let currentModifiers = NSEvent.modifierFlags
        if currentModifiers.contains(.option) {
            print("   → Starting with: COPY (Option held)")
        } else {
            print("   → Starting with: MOVE (no modifiers)")
        }
    }
    
    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        // Optional: Log modifier changes in real-time (for debugging)
        // Uncomment to see live modifier detection:
        /*
        let currentModifiers = NSEvent.modifierFlags
        if currentModifiers.contains(.option) {
            print("   → Currently: COPY (Option held)")
        } else {
            print("   → Currently: MOVE (no modifiers)")
        }
        */
    }
    
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let success = operation != []
        
        // Log what actually happened
        var operationType = "unknown"
        if operation.contains(.copy) {
            operationType = "COPY"
        } else if operation.contains(.move) {
            operationType = "MOVE"
        } else if operation.contains(.link) {
            operationType = "LINK"
        } else if operation == [] {
            operationType = "cancelled"
        }
        
        print("🎯 Drag session ended at \(screenPoint)")
        print("   → Success: \(success), Final Operation: \(operationType)")
        
        // Call completion callback
        dragProvider?.onDragCompleted?(success)
        
        // Clean up
        isDragging = false
        dragProvider = nil
    }
    
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        // CRITICAL: Return false so modifier changes are detected during drag!
        return false
    }
}

// MARK: - SwiftUI Wrapper
struct DraggableOverlay: NSViewRepresentable {
    @Binding var dragProvider: DragProvider?
    @Binding var dragStartPoint: CGPoint?
    
    func makeNSView(context: Context) -> DraggableOverlayView {
        let view = DraggableOverlayView()
        return view
    }
    
    func updateNSView(_ nsView: DraggableOverlayView, context: Context) {
        // Check if we should start a drag
        if let provider = dragProvider, let startPoint = dragStartPoint {
            nsView.startDragSession(at: startPoint, provider: provider)
            
            // Clear the trigger
            DispatchQueue.main.async {
                self.dragProvider = nil
                self.dragStartPoint = nil
            }
        }
    }
}
