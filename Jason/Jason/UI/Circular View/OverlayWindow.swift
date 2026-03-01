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
    
    private var normalLevel: NSWindow.Level = .statusBar
    
    // Flag to ignore focus changes during app operations (quit/launch)
    private var shouldIgnoreFocusChanges: Bool = false
    
    // Add callback property for scroll events
    var onScrollBack: (() -> Void)?
    
    // Store mouse location for positioning UI
    var uiCenterLocation: NSPoint = .zero
    
    // Store which screen the overlay is currently on
    var currentScreen: NSScreen?
    
    // Callback for search toggle (CMD+F)
    var onSearchToggle: (() -> Void)?

    // Callback for escape - returns true if consumed (search handled it)
    var onEscapePressed: (() -> Bool)?
    
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
        
        // Initially hidden
        self.orderOut(nil)
    }
    
    func showOverlay(at mouseLocation: NSPoint) {
        
        // Find which screen contains the mouse cursor
        let targetScreen = NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main
        
        guard let screen = targetScreen else {
            print("No screen found for mouse location")
            return
        }
        
        self.currentScreen = screen
        
        // Store the location (in global coordinates)
        self.uiCenterLocation = mouseLocation
        
        // Position window to cover the screen containing the mouse
        self.setFrame(screen.frame, display: true)
        
        // Bring to front and show
        self.makeKeyAndOrderFront(nil)
        self.level = .screenSaver
        
        NSApp.activate(ignoringOtherApps: true)
        self.makeKey()
    }
    
    func hideOverlay() {
        print("Hiding overlay window")
        self.orderOut(nil)
    }
    
    // Allow window to become key to receive keyboard events
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
    
    // Lower window level (so QuickLook can appear on top)
    func lowerWindowLevel() {
        self.level = .normal
        print("[OverlayWindow] Lowered window level to .normal")
    }
    
    //Restore window level to normal overlay level
    func restoreWindowLevel() {
        self.level = normalLevel
        print("[OverlayWindow] Restored window level to \(normalLevel)")
    }
    
    // Temporarily ignore focus changes (for app quit/launch operations)
    func ignoreFocusChangesTemporarily(duration: TimeInterval = 0.5) {
        shouldIgnoreFocusChanges = true
        print("[OverlayWindow] Ignoring focus changes for \(duration)s")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.shouldIgnoreFocusChanges = false
            print("[OverlayWindow] Resumed listening to focus changes")
        }
    }
    
    // Handle scroll events
    override func scrollWheel(with event: NSEvent) {
        // Detect device type
        let isTrackpad = event.hasPreciseScrollingDeltas
        let deviceName = isTrackpad ? "Trackpad" : "Mouse Wheel"
        
        // Different thresholds for different devices
        let scrollThreshold: CGFloat = isTrackpad ? 0.9 : 0.1
        
        // Ignore trackpad momentum scrolling (inertial scrolling after lifting fingers)
        if isTrackpad && !event.momentumPhase.isEmpty {
            return
        }
        
        // Scroll down (positive deltaY) = go back/collapse
        if event.deltaY > scrollThreshold {
            onScrollBack?()
        }
        // Scroll up (negative deltaY) = could be used for something else
        else if event.deltaY < -scrollThreshold {
            print("Scroll UP (\(deviceName)) - (not implemented)")
            // Could be used to re-expand collapsed rings or other features
        }
        // Don't call super to prevent any default scroll behavior
    }
    
    //Detect when window loses focus
    override func resignKey() {
        print("[OverlayWindow] Window lost focus")
        super.resignKey()
        
        // Don't hide if we're ignoring focus changes (app quit/launch in progress)
        if shouldIgnoreFocusChanges {
            print("   Ignoring focus change (app operation in progress)")
            return
        }
        
        // Don't hide if Quick Look is showing - it steals focus but we want to stay visible
        if QuickLookManager.shared.isShowing {
            print("   Quick Look is visible - keeping UI open")
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
    

    override func keyDown(with event: NSEvent) {
        print("OverlayWindow received key: \(event.keyCode)")
        
        let isCtrlPressed = event.modifierFlags.contains(.control)
        let isShiftPressed = event.modifierFlags.contains(.shift)
        let isCmdPressed = event.modifierFlags.contains(.command)
        let isKKey = event.keyCode == 40  // K key
        let isFKey = event.keyCode == 3   // F key
        
        // Handle CMD+F for search
        if isCmdPressed && isFKey {
            print("[OverlayWindow] CMD+F - toggling search")
            onSearchToggle?()
            return
        }
        
        // Handle Escape
        if event.keyCode == 53 { // Escape
            print("[OverlayWindow] Escape pressed, onEscapePressed is \(onEscapePressed == nil ? "nil" : "set")")
            // Let search handle it first
            if let handler = onEscapePressed {
                let consumed = handler()
                print("[OverlayWindow] onEscapePressed returned: \(consumed)")
                if consumed {
                    return
                }
            }
            hideOverlay()
            return
        }
        
        // Handle our shortcut Ctrl+Shift+K
        if isCtrlPressed && isShiftPressed && isKKey {
            // Shortcut is being handled by CircularUIManager
            // Just consume it here to prevent beep
            print("OverlayWindow consuming Ctrl+Shift+K (no beep)")
            return  // Consumed - no beep
        }
        
        // IMPORTANT: Don't call super.keyDown() - this prevents the beep!
        // All other keys are silently consumed
    }
    
    // Override rightMouseDown to ensure it reaches event monitors
    override func rightMouseDown(with event: NSEvent) {
        print("[OverlayWindow] rightMouseDown detected at: \(event.locationInWindow)")
        
        // CRITICAL: Call super to allow the event to propagate to local monitors
        super.rightMouseDown(with: event)
        
        // Also manually notify global monitors since NSHostingView might block it
        // Convert to screen coordinates for our gesture manager
        let screenLocation = NSEvent.mouseLocation
        print("[OverlayWindow] Right-click at screen location: \(screenLocation)")
    }
    
    
    // Log mouse events for debugging
    override func mouseDown(with event: NSEvent) {
        print("[OverlayWindow] mouseDown detected at: \(event.locationInWindow)")
        super.mouseDown(with: event)
    }
}
