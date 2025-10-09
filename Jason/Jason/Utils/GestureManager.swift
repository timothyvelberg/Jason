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
    
    enum MouseButton {
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
        // Future extensibility:
        // case scroll(CGFloat)
        // case drag(from: CGPoint, to: CGPoint)
        // case longPress(MouseButton)
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
    
    // MARK: - State
    
    private var isMonitoring: Bool = false
    private var globalMonitors: [Any] = []
    private var localMonitors: [Any] = []
    
    // Callbacks
    var onGesture: ((GestureEvent) -> Void)?
    
    // MARK: - Lifecycle
    
    init() {
        print("🖱️ GestureManager initialized")
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
        print("✅ GestureManager started monitoring")
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
        
        isMonitoring = false
        print("🛑 GestureManager stopped monitoring")
    }
    
    // MARK: - Monitor Setup
    
    private func setupGlobalMonitors() {
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
        
        // Left mouse button (for completeness, though we handle this in CircularUIView)
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.handleMouseEvent(event, type: .click(.left))
        } {
            globalMonitors.append(monitor)
        }
    }
    
    // In GestureManager.swift, find setupLocalMonitors() method
    private func setupLocalMonitors() {
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
        
        // Left mouse button - DON'T consume it, let SwiftUI tap gesture handle it
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.handleMouseEvent(event, type: .click(.left))
            return event  // ← CHANGED: DON'T consume - let it pass through to CircularUIView
        } {
            localMonitors.append(monitor)
        }
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
        }
        
        print("🖱️ GestureManager: \(buttonName) click at \(gestureEvent.position)")
        
        // Fire callback
        onGesture?(gestureEvent)
    }
}
