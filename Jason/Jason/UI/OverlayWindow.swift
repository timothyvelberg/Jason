//
//  OverlayWindow.swift
//  Jason
//
//  Created by Timothy Velberg on 31/07/2025.
//

import SwiftUI
import AppKit

class OverlayWindow: NSWindow {
    
    // Callback for when window loses focus
    var onLostFocus: (() -> Void)?
    
    // Add callback property for scroll events
    var onScrollBack: (() -> Void)?
    
    // Store mouse location for positioning UI
    var uiCenterLocation: NSPoint = .zero
    
    init() {
        // Get the main screen size for fullscreen overlay
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        
        super.init(
            contentRect: screenFrame,  // Changed from fixed 800x800
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        // Make window behavior suitable for fullscreen overlay
        self.level = .screenSaver  // High level so it's always on top
        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.hasShadow = false  // No shadow for fullscreen
        self.isMovable = false
        self.canHide = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        
        // CRITICAL: Accept mouse events (both movement and clicks)
        self.acceptsMouseMovedEvents = true
        self.ignoresMouseEvents = false
        
        print("🪟 [OverlayWindow] Created fullscreen overlay: \(screenFrame.size)")
        
        // Initially hidden
        self.orderOut(nil)
        
        print("🪟 Overlay window created")
    }
    
    func showOverlay(at mouseLocation: NSPoint) {
        print("Showing fullscreen overlay with UI centered at: \(mouseLocation)")
        
        // Store the location
        self.uiCenterLocation = mouseLocation
        
        // Position window to cover entire screen
        if let screenFrame = NSScreen.main?.frame {
            self.setFrame(screenFrame, display: true)
        }
        
        // Bring to front and show
        self.makeKeyAndOrderFront(nil)
        self.level = .screenSaver
        
        NSApp.activate(ignoringOtherApps: true)
        self.makeKey()
        
        print("🪟 Window is now fullscreen, key: \(self.isKeyWindow), ignoresMouseEvents: \(self.ignoresMouseEvents)")
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
    
    // Handle scroll events
    override func scrollWheel(with event: NSEvent) {
        print("🎡 [OverlayWindow] Scroll detected: deltaY=\(event.deltaY), deltaX=\(event.deltaX)")
        
        // Threshold to avoid accidental triggers from tiny movements
        let scrollThreshold: CGFloat = 0.1
        
        // Scroll down (positive deltaY) = go back/collapse
        if event.deltaY > scrollThreshold {
            print("🔙 Scroll DOWN - collapsing ring")
            onScrollBack?()
        }
        // Scroll up (negative deltaY) = could be used for something else
        else if event.deltaY < -scrollThreshold {
            print("🔼 Scroll UP - (not implemented)")
            // Could be used to re-expand collapsed rings or other features
        }
        
        // Don't call super to prevent any default scroll behavior
    }
    
    // NEW: Detect when window loses focus
    override func resignKey() {
        print("🔴 [OverlayWindow] Window lost focus")
        super.resignKey()
        
        // Don't hide if Quick Look is showing - it steals focus but we want to stay visible
        if QuickLookManager.shared.isShowing {
            print("   👁️ Quick Look is visible - keeping UI open")
            return
        }
        
        print("   Triggering hide")
        // Call the callback to hide the UI
        onLostFocus?()
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
