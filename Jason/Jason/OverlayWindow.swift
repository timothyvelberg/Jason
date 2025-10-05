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
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.borderless], // No title bar or decorations
            backing: .buffered,
            defer: false
        )
        
        // Make window behavior suitable for overlay
        self.level = .floating // Appears above most other windows
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
    
    func showOverlay() {
        print("👁️ Showing overlay window")
        
        // Center on the current screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = self.frame
            let x = screenFrame.midX - windowFrame.width / 2
            let y = screenFrame.midY - windowFrame.height / 2
            self.setFrame(NSRect(x: x, y: y, width: windowFrame.width, height: windowFrame.height), display: true)
        }
        
        // Bring to front and show
        self.makeKeyAndOrderFront(nil)
        self.level = .screenSaver // Even higher level to ensure it's on top
        
        // Activate our app to receive key events
        NSApp.activate(ignoringOtherApps: true)
        
        // Make sure this window can become key to receive keyboard events
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
