//
//  InputCoordinator.swift
//  Jason
//
//  Created by Timothy Velberg on 25/01/2026.
//  Coordinates input mode (mouse vs keyboard) and active focus
//  across ring and panel UI components.
//

import Foundation
import AppKit

// MARK: - Input Mode

enum InputMode {
    case mouse
    case keyboard
}

// MARK: - Active Focus

enum ActiveFocus: Equatable {
    case ring(level: Int)
    case panel(level: Int)
    case none
}

// MARK: - Input Coordinator

class InputCoordinator: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var inputMode: InputMode = .mouse
    @Published private(set) var activeFocus: ActiveFocus = .none
    
    // MARK: - Mouse Tracking
    
    private var lastMousePosition: CGPoint?
    private let movementThreshold: CGFloat = 10.0
    
    // MARK: - Initialization
    
    init() {
        print("[InputCoordinator] Initialized")
    }
    
    // MARK: - Mode Transitions

    /// Switch to keyboard mode (call when arrow keys or characters pressed)
    func switchToKeyboard() {
        // Always refresh mouse position to prevent accumulated drift from triggering mode switch
        lastMousePosition = NSEvent.mouseLocation
        guard inputMode != .keyboard else { return }
        
        inputMode = .keyboard
        lastMousePosition = NSEvent.mouseLocation
        print("[InputCoordinator] Mode → keyboard")
    }

    /// Handle mouse movement, returns true if mode switched to mouse
    @discardableResult
    func handleMouseMoved(to position: CGPoint) -> Bool {
        // If already in mouse mode, just update position
        guard inputMode == .keyboard else {
            lastMousePosition = position
            return false
        }
        
        // Check if movement exceeds threshold
        if let last = lastMousePosition {
            let distance = hypot(position.x - last.x, position.y - last.y)
            
            if distance > movementThreshold {
                inputMode = .mouse
                lastMousePosition = position
                print("[InputCoordinator] Mode → mouse (moved \(String(format: "%.1f", distance))px)")
                return true
            }
        } else {
            lastMousePosition = position
        }
        
        return false
    }
    
    // MARK: - Focus Transitions

    /// Set focus to a ring at the given level
    func focusRing(level: Int) {
        let newFocus = ActiveFocus.ring(level: level)
        guard activeFocus != newFocus else { return }
        
        activeFocus = newFocus
        print("[InputCoordinator] Focus → ring(\(level))")
    }

    /// Set focus to a panel at the given level
    func focusPanel(level: Int) {
        let newFocus = ActiveFocus.panel(level: level)
        guard activeFocus != newFocus else { return }
        
        activeFocus = newFocus
        print("[InputCoordinator] Focus → panel(\(level))")
    }

    /// Clear focus (nothing active)
    func clearFocus() {
        guard activeFocus != .none else { return }
        
        activeFocus = .none
        print("[InputCoordinator] Focus → none")
    }

    /// Reset all state (call when UI hides)
    func reset() {
        inputMode = .mouse
        activeFocus = .none
        lastMousePosition = nil
        print("[InputCoordinator] Reset")
    }
    
    // MARK: - Query Methods

    /// Whether ring at given level should process mouse input
    func shouldRingProcessMouse(level: Int) -> Bool {
        guard inputMode == .mouse else { return false }
        
        switch activeFocus {
        case .ring(let focusLevel):
            return focusLevel == level
        case .panel, .none:
            return false
        }
    }

    /// Whether ring at given level should process keyboard input
    func shouldRingProcessKeyboard(level: Int) -> Bool {
        guard inputMode == .keyboard else { return false }
        
        switch activeFocus {
        case .ring(let focusLevel):
            return focusLevel == level
        case .panel, .none:
            return false
        }
    }

    /// Whether panel at given level should process mouse input
    func shouldPanelProcessMouse(level: Int) -> Bool {
        guard inputMode == .mouse else { return false }
        
        switch activeFocus {
        case .panel(let focusLevel):
            return focusLevel == level
        case .ring, .none:
            return false
        }
    }

    /// Whether panel at given level should process keyboard input
    func shouldPanelProcessKeyboard(level: Int) -> Bool {
        guard inputMode == .keyboard else { return false }
        
        switch activeFocus {
        case .panel(let focusLevel):
            return focusLevel == level
        case .ring, .none:
            return false
        }
    }

    /// Whether any mouse tracking should occur at all
    func isMouseTrackingEnabled() -> Bool {
        return inputMode == .mouse
    }
}
