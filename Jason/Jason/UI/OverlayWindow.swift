//
//  OverlayWindow.swift
//  Jason
//
//  Created by Timothy Velberg on 31/07/2025.
//

import SwiftUI
import AppKit

class OverlayWindow: NSWindow {
    
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 800),  // Increased from 600x400
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // Make window behavior suitable for overlay
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.hasShadow = true
        self.isMovable = false
        self.canHide = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        
        // Accept key events
        self.acceptsMouseMovedEvents = true
        
        // Center the window on screen
        self.center()
        
        // Initially hidden
        self.orderOut(nil)
        
        print("🪟 Overlay window created")
    }
    
    func showOverlay(at mouseLocation: NSPoint) {
        print("Showing overlay window at mouse location: \(mouseLocation)")
        
        // Position window centered at mouse location
        let newX = mouseLocation.x - (self.frame.width / 2)
        let newY = mouseLocation.y - (self.frame.height / 2)
        self.setFrameOrigin(NSPoint(x: newX, y: newY))
        
        // Bring to front and show
        self.makeKeyAndOrderFront(nil)
        self.level = .screenSaver
        
        NSApp.activate(ignoringOtherApps: true)
        self.makeKey()
    }
    
    func hideOverlay() {
        print("🙈 Hiding overlay window")
        self.orderOut(nil)
    }
    
    // Allow window to become key to receive keyboard events
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
    
    // Prevent window from being closed
    override func close() {
        hideOverlay()
    }
    
    // Handle escape key and clicks outside
    override func keyDown(with event: NSEvent) {
        print("🎯 OverlayWindow received key: \(event.keyCode)")
        if event.keyCode == 53 { // Escape
            hideOverlay()
        } else {
            super.keyDown(with: event)
        }
    }
}
