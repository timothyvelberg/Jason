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
    
    // MARK: - Text Input Forwarding (for Panel Search)
    
    /// Called when printable characters are typed (when panel is visible)
    var onTextInput: ((String) -> Void)?
    
    /// Called when backspace/delete is pressed (when panel is visible)
    var onDeleteBackward: (() -> Void)?
    
    /// Called when Escape is pressed. Return true if consumed (search cleared), false to hide UI
    var onEscapePressed: (() -> Bool)?
    
    /// Check if keyboard input should be forwarded to search
    var shouldForwardKeyboardInput: (() -> Bool)?
    
    init() {
        // Get the main screen size for fullscreen overlay
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        
        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        // Make window behavior suitable for fullscreen overlay
        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.hasShadow = false
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
            print("❌ No screen found for mouse location")
            return
        }
        
        self.currentScreen = screen
        self.uiCenterLocation = mouseLocation
        self.setFrame(screen.frame, display: true)
        
        self.makeKeyAndOrderFront(nil)
        self.level = .screenSaver
        
        NSApp.activate(ignoringOtherApps: true)
        self.makeKey()
    }
    
    func hideOverlay() {
        print("🙈 Hiding overlay window")
        self.orderOut(nil)
    }
    
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
    
    func lowerWindowLevel() {
        self.level = .normal
        print("🔽 [OverlayWindow] Lowered window level to .normal")
    }
    
    func restoreWindowLevel() {
        self.level = normalLevel
        print("🔼 [OverlayWindow] Restored window level to \(normalLevel)")
    }
    
    func ignoreFocusChangesTemporarily(duration: TimeInterval = 0.5) {
        shouldIgnoreFocusChanges = true
        print("🔇 [OverlayWindow] Ignoring focus changes for \(duration)s")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.shouldIgnoreFocusChanges = false
            print("🔊 [OverlayWindow] Resumed listening to focus changes")
        }
    }
    
    // Handle scroll events
    override func scrollWheel(with event: NSEvent) {
        let isTrackpad = event.hasPreciseScrollingDeltas
        let scrollThreshold: CGFloat = isTrackpad ? 0.9 : 0.1
        
        // Ignore trackpad momentum scrolling
        if isTrackpad && !event.momentumPhase.isEmpty {
            return
        }
        
        if event.deltaY > scrollThreshold {
            onScrollBack?()
        }
    }
    
    override func resignKey() {
        print("🔴 [OverlayWindow] Window lost focus")
        super.resignKey()
        
        if shouldIgnoreFocusChanges {
            print("   🔇 Ignoring focus change (app operation in progress)")
            return
        }
        
        if QuickLookManager.shared.isShowing {
            print("   👁️ Quick Look is visible - keeping UI open")
            return
        }
        
        print("   Triggering hide")
        onLostFocus?()
    }
    
    override func close() {
        hideOverlay()
    }
    
    // MARK: - Keyboard Event Handling
    
    override func keyDown(with event: NSEvent) {
        let keyCode = event.keyCode
        
        // Handle Escape - try clearing search first, then hide
        if keyCode == 53 {
            if onEscapePressed?() == true {
                return  // Search was cleared, consume event
            }
            hideOverlay()
            return
        }
        
        // Modifier key combos (Ctrl/Cmd) - let HotkeyManager handle
        let hasControlOrCommand = event.modifierFlags.contains(.control) || event.modifierFlags.contains(.command)
        if hasControlOrCommand {
            return
        }
        
        // Forward text input when panel search is active
        if shouldForwardKeyboardInput?() == true {
            // Backspace or Delete
            if keyCode == 51 || keyCode == 117 {
                onDeleteBackward?()
                return
            }
            
            // Printable characters (no control/command/option)
            let blockingModifiers: NSEvent.ModifierFlags = [.control, .command, .option]
            if event.modifierFlags.intersection(blockingModifiers).isEmpty {
                if let characters = event.characters, !characters.isEmpty {
                    let printable = characters.filter { char in
                        char.isLetter || char.isNumber || char.isPunctuation ||
                        char.isSymbol || char.isWhitespace
                    }
                    
                    if !printable.isEmpty {
                        onTextInput?(String(printable))
                        return
                    }
                }
            }
        }
        
        // All other keys silently consumed (no beep)
    }
    
    override func rightMouseDown(with event: NSEvent) {
        print("🖱️ [OverlayWindow] rightMouseDown detected at: \(event.locationInWindow)")
        super.rightMouseDown(with: event)
        
        let screenLocation = NSEvent.mouseLocation
        print("🖱️ [OverlayWindow] Right-click at screen location: \(screenLocation)")
    }
    
    override func mouseDown(with event: NSEvent) {
        print("🖱️ [OverlayWindow] mouseDown detected at: \(event.locationInWindow)")
        super.mouseDown(with: event)
    }
}
