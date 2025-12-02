//
//  GestureManager.swift
//  Jason
//
//  Created by Timothy Velberg on 09/10/2025.
//
//  Created for centralized gesture handling
//

import Cocoa
import Foundation

class GestureManager {
    
    // MARK: - Gesture Types
    
    enum MouseButton: Equatable {
        case left
        case right
        case middle
        case other(Int)  // For additional mouse buttons
        
        static func from(buttonNumber: Int) -> MouseButton {
            switch buttonNumber {
            case 0: return .left
            case 1: return .right
            case 2: return .middle
            default: return .other(buttonNumber)
            }
        }
    }
    
    enum GestureType {
        case click(MouseButton)
        case doubleClick(MouseButton)
        case mouseDown(MouseButton)
        case mouseUp(MouseButton)
        // Drag support
        case dragStarted(MouseButton, startPoint: CGPoint)
        case dragMoved(currentPoint: CGPoint, delta: CGPoint)
        case dragEnded(endPoint: CGPoint, didComplete: Bool)
    }
    
    // MARK: - Gesture Event
    
    struct GestureEvent {
        let type: GestureType
        let position: CGPoint
        let timestamp: Date
        let modifierFlags: NSEvent.ModifierFlags
        
        var button: MouseButton {
            switch type {
            case .click(let button),
                 .doubleClick(let button),
                 .mouseDown(let button),
                 .mouseUp(let button):
                return button
            case .dragStarted(let button, _):
                return button
            case .dragMoved, .dragEnded:
                return .left  // Drags are typically left button
            }
        }
        
        var isLeftClick: Bool {
            if case .click(.left) = type { return true }
            return false
        }
        
        var isRightClick: Bool {
            if case .click(.right) = type { return true }
            return false
        }
        
        var isMiddleClick: Bool {
            if case .click(.middle) = type { return true }
            return false
        }
    }
    
    // MARK: - Drag State
    
    private struct DragState {
        let button: MouseButton
        let startPoint: CGPoint
        let startTime: Date
        var hasMoved: Bool = false
    }
    
    private var currentDrag: DragState?
    
    // Drag configuration
    private let dragThreshold: CGFloat = 5.0        // Pixels to move before drag starts
    private let dragTimeThreshold: TimeInterval = 0.15  // Seconds to wait before considering drag
    
    // MARK: - State
    
    private var isMonitoring: Bool = false
    private var globalMonitors: [Any] = []
    private var localMonitors: [Any] = []
    
    // Callbacks
    var onGesture: ((GestureEvent) -> Void)?
    
    // MARK: - Lifecycle
    
    init() {
//        print("🖱️ GestureManager initialized")
        return
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Monitoring Control
    
    func startMonitoring() {
        guard !isMonitoring else {
            print("⚠️ GestureManager already monitoring")
            return
        }
        
        setupGlobalMonitors()
        setupLocalMonitors()
        
        isMonitoring = true
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        // Remove all monitors
        for monitor in globalMonitors {
            NSEvent.removeMonitor(monitor)
        }
        for monitor in localMonitors {
            NSEvent.removeMonitor(monitor)
        }
        
        globalMonitors.removeAll()
        localMonitors.removeAll()
        currentDrag = nil
        
        isMonitoring = false
        print("🛑 GestureManager stopped monitoring")
    }
    
    // MARK: - Monitor Setup
    
    private func setupGlobalMonitors() {
        // Left mouse button - track down, drag, up for drag detection
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.handleMouseDown(event, button: .left)
        } {
            globalMonitors.append(monitor)
        }
        
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            self?.handleMouseDragged(event, button: .left)
        } {
            globalMonitors.append(monitor)
        }
        
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            self?.handleMouseUp(event, button: .left)
        } {
            globalMonitors.append(monitor)
        }
        
        // Right mouse button
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
            self?.handleMouseEvent(event, type: .click(.right))
        } {
            globalMonitors.append(monitor)
        }
        
        // Middle mouse button
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.otherMouseDown]) { [weak self] event in
            if event.buttonNumber == 2 {  // Middle button
                self?.handleMouseEvent(event, type: .click(.middle))
            }
        } {
            globalMonitors.append(monitor)
        }
    }
    
    private func setupLocalMonitors() {
        // Left mouse button - track down, drag, up for drag detection
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.handleMouseDown(event, button: .left)
            return event  // Let it pass through to SwiftUI
        } {
            localMonitors.append(monitor)
        }
        
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            self?.handleMouseDragged(event, button: .left)
            return event  // Let it pass through
        } {
            localMonitors.append(monitor)
        }
        
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            self?.handleMouseUp(event, button: .left)
            return event  // Let it pass through
        } {
            localMonitors.append(monitor)
        }
        
        // Right mouse button
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
            self?.handleMouseEvent(event, type: .click(.right))
            return nil  // Consume event
        } {
            localMonitors.append(monitor)
        }
        
        // Middle mouse button
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown]) { [weak self] event in
            if event.buttonNumber == 2 {  // Middle button
                self?.handleMouseEvent(event, type: .click(.middle))
                return nil  // Consume event
            }
            return event
        } {
            localMonitors.append(monitor)
        }
    }
    
    // MARK: - Drag Detection
    
    private func handleMouseDown(_ event: NSEvent, button: MouseButton) {
        let position = NSEvent.mouseLocation
        
        // Start potential drag
        currentDrag = DragState(
            button: button,
            startPoint: position,
            startTime: Date(),
            hasMoved: false
        )
        
        print("🖱️ Mouse down at \(position) - potential drag started")
    }
    
    private func handleMouseDragged(_ event: NSEvent, button: MouseButton) {
        guard var drag = currentDrag, drag.button == button else {
            return
        }
        
        let position = NSEvent.mouseLocation
        let distance = hypot(position.x - drag.startPoint.x, position.y - drag.startPoint.y)
        let elapsed = Date().timeIntervalSince(drag.startTime)
        
        // Check if we've crossed the drag threshold
        if !drag.hasMoved && distance > dragThreshold && elapsed > dragTimeThreshold {
            // Drag started!
            drag.hasMoved = true
            currentDrag = drag
            
            let gestureEvent = GestureEvent(
                type: .dragStarted(button, startPoint: drag.startPoint),
                position: position,
                timestamp: Date(),
                modifierFlags: event.modifierFlags
            )
            
            print("🎯 Drag started from \(drag.startPoint) to \(position) (distance: \(distance)px)")
            onGesture?(gestureEvent)
            
        } else if drag.hasMoved {
            // Drag in progress
            let delta = CGPoint(
                x: position.x - drag.startPoint.x,
                y: position.y - drag.startPoint.y
            )
            
            let gestureEvent = GestureEvent(
                type: .dragMoved(currentPoint: position, delta: delta),
                position: position,
                timestamp: Date(),
                modifierFlags: event.modifierFlags
            )
            
            onGesture?(gestureEvent)
        }
    }
    
    private func handleMouseUp(_ event: NSEvent, button: MouseButton) {
        let position = NSEvent.mouseLocation
        
        guard let drag = currentDrag, drag.button == button else {
            // No drag state - this is just a click
            handleMouseEvent(event, type: .click(button))
            return
        }
        
        if drag.hasMoved {
            // Drag ended
            let gestureEvent = GestureEvent(
                type: .dragEnded(endPoint: position, didComplete: true),
                position: position,
                timestamp: Date(),
                modifierFlags: event.modifierFlags
            )
            
            print("🎯 Drag ended at \(position)")
            onGesture?(gestureEvent)
            
        } else {
            // Never moved enough - treat as click
            handleMouseEvent(event, type: .click(button))
        }
        
        currentDrag = nil
    }
    
    // MARK: - Cancel Drag
    
    func cancelCurrentDrag() {
        if let drag = currentDrag, drag.hasMoved {
            let gestureEvent = GestureEvent(
                type: .dragEnded(endPoint: drag.startPoint, didComplete: false),
                position: drag.startPoint,
                timestamp: Date(),
                modifierFlags: NSEvent.modifierFlags
            )
            onGesture?(gestureEvent)
        }
        currentDrag = nil
    }
    
    // MARK: - Event Handling
    
    private func handleMouseEvent(_ event: NSEvent, type: GestureType) {
        let gestureEvent = GestureEvent(
            type: type,
            position: NSEvent.mouseLocation,
            timestamp: Date(),
            modifierFlags: event.modifierFlags
        )
        
        // Log for debugging
        let buttonName: String
        switch type {
        case .click(let button),
             .doubleClick(let button),
             .mouseDown(let button),
             .mouseUp(let button):
            buttonName = "\(button)"
        case .dragStarted(let button, _):
            buttonName = "\(button)"
        case .dragMoved:
            buttonName = "drag"
        case .dragEnded:
            buttonName = "drag"
        }
        
        print("🖱️ GestureManager: \(buttonName) at \(gestureEvent.position)")
        
        // Fire callback
        onGesture?(gestureEvent)
    }
}
