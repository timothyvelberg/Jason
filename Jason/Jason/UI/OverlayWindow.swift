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
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 800),
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
        
        // CRITICAL: Accept mouse events (both movement and clicks)
        self.acceptsMouseMovedEvents = true
        self.ignoresMouseEvents = false
        
        print("🪟 [OverlayWindow] ignoresMouseEvents set to: \(self.ignoresMouseEvents)")
        
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
        
        print("🪟 Window is now key: \(self.isKeyWindow), ignoresMouseEvents: \(self.ignoresMouseEvents)")
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
    
    // Handle keyboard events - FIXED: Don't call super to prevent beep
    override func keyDown(with event: NSEvent) {
        print("🎯 OverlayWindow received key: \(event.keyCode)")
        
        let isCtrlPressed = event.modifierFlags.contains(.control)
        let isShiftPressed = event.modifierFlags.contains(.shift)
        let isKKey = event.keyCode == 40  // K key
        
        // Handle Escape
        if event.keyCode == 53 { // Escape
            hideOverlay()
            return  // Consumed - no beep
        }
        
        // Handle our shortcut Ctrl+Shift+K
        if isCtrlPressed && isShiftPressed && isKKey {
            // Shortcut is being handled by CircularUIManager
            // Just consume it here to prevent beep
            print("🎯 OverlayWindow consuming Ctrl+Shift+K (no beep)")
            return  // Consumed - no beep
        }
        
        // IMPORTANT: Don't call super.keyDown() - this prevents the beep!
        // All other keys are silently consumed
    }
    
    // Log mouse events for debugging
    override func mouseDown(with event: NSEvent) {
        print("🖱️ [OverlayWindow] mouseDown detected at: \(event.locationInWindow)")
        super.mouseDown(with: event)
    }
}
