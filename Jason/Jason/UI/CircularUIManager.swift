//
//  CircularUIManager.swift
//  Jason
//
//  Created by Timothy Velberg on 31/07/2025.
//

import Foundation
import AppKit
import SwiftUI

class CircularUIManager: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var mousePosition: CGPoint = .zero
    
    private var overlayWindow: OverlayWindow?
    private var appSwitcher: AppSwitcherManager?
    var functionManager: FunctionManager?
    private var mouseTracker: MouseTracker?
    private var gestureManager: GestureManager?  // ← NEW
    private var isHandlingShortcut: Bool = false  // Prevent double-handling
    
    init() {
        print("CircularUIManager initialized")
    }
    
    func setup(with appSwitcher: AppSwitcherManager) {
        self.appSwitcher = appSwitcher
        
        // Create FunctionManager with providers
        self.functionManager = FunctionManager()
        
        // Register AppSwitcher as a provider
        functionManager?.registerProvider(appSwitcher)
        
        // Register Favorites Provider
        functionManager?.registerProvider(FavoriteAppsProvider())
        
        // Register mock provider for testing (shows alongside real apps)
        functionManager?.registerProvider(MockFunctionProvider())
        
        functionManager?.registerProvider(FinderLogic())
        
        if let functionManager = functionManager {
            self.mouseTracker = MouseTracker(functionManager: functionManager)
            
            mouseTracker?.onPieHover = { [weak functionManager] pieIndex in
                guard let pieIndex = pieIndex, let fm = functionManager else { return }
                
                let ringLevel = fm.activeRingLevel
                
                guard ringLevel < fm.rings.count else { return }
                let nodes = fm.rings[ringLevel].nodes
                
                if nodes.indices.contains(pieIndex) {
                    let node = nodes[pieIndex]
                    let type = node.isLeaf ? "FUNCTION" : "CATEGORY"
                    print("🎯 [RING \(ringLevel)] Hovering: index=\(pieIndex), name='\(node.name)', type=\(type)")
                    print("   hoveredIndex=\(fm.rings[ringLevel].hoveredIndex ?? -1), selectedIndex=\(fm.rings[ringLevel].selectedIndex ?? -1)")
                }
            }
        }
        
        setupOverlayWindow()
        setupGlobalHotkeys()
        setupGestureManager()  // ← NEW: Replace setupRightClickMonitoring()
    }
    
    // NEW: Setup GestureManager
    private func setupGestureManager() {
        print("🖱️ Setting up GestureManager")
        
        gestureManager = GestureManager()
        
        gestureManager?.onGesture = { [weak self] event in
            guard let self = self, self.isVisible else { return }
            
            switch event.type {
            case .click(.right):
                print("🖱️ Right-click detected at \(event.position)")
                self.handleRightClick(event: event)
                
            case .click(.middle):
                print("🖱️ Middle-click detected at \(event.position)")
                self.handleMiddleClick(event: event)
                
            case .click(.left):
                // Left-click is handled by CircularUIView's tap gesture
                // but we could add global left-click handling here if needed
                break
                
            default:
                break
            }
        }
        
        print("✅ GestureManager ready")
    }
    
    // NEW: Handle right-click gesture
    private func handleRightClick(event: GestureManager.GestureEvent) {
        // Post notification for CircularUIView to handle
        // (CircularUIView knows the UI context better)
        NotificationCenter.default.post(
            name: NSNotification.Name("CircularUIRightClick"),
            object: nil,
            userInfo: [
                "position": event.position,
                "timestamp": event.timestamp
            ]
        )
    }
    
    // NEW: Handle middle-click gesture
    private func handleMiddleClick(event: GestureManager.GestureEvent) {
        // Post notification for CircularUIView to handle
        NotificationCenter.default.post(
            name: NSNotification.Name("CircularUIMiddleClick"),
            object: nil,
            userInfo: [
                "position": event.position,
                "timestamp": event.timestamp
            ]
        )
    }
    
    // Setup keyboard shortcut listener
    private func setupGlobalHotkeys() {
        print("⌨️ Setting up circular UI hotkeys (Ctrl+Shift+K)")
        
        // Listen for global key events (keyDown only)
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleGlobalKeyEvent(event)
        }
        
        // Also listen for local events
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            return self?.handleLocalKeyEvent(event) ?? event
        }
        
        print("✅ Circular UI hotkey monitoring started")
    }
    
    // Handle global keyboard events (when Jason is NOT in focus)
    private func handleGlobalKeyEvent(_ event: NSEvent) {
        let isCtrlPressed = event.modifierFlags.contains(.control)
        let isShiftPressed = event.modifierFlags.contains(.shift)
        let isKKey = event.keyCode == 40  // K key
        
        // Toggle UI when Ctrl + Shift + K is pressed
        if event.type == .keyDown && isCtrlPressed && isShiftPressed && isKKey {
            // Prevent double-handling
            guard !isHandlingShortcut else {
                print("⚠️ Already handling shortcut, ignoring duplicate")
                return
            }
            
            isHandlingShortcut = true
            print("⌨️ [GLOBAL] Ctrl+Shift+K detected - toggling UI")
            
            if isVisible {
                hide()
            } else {
                show()
            }
            
            // Reset flag after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.isHandlingShortcut = false
            }
            
            return
        }
        
        // Hide UI on Escape (when visible)
        if event.type == .keyDown && event.keyCode == 53 && isVisible {
            print("⌨️ [GLOBAL] Escape pressed - hiding circular UI")
            hide()
        }
    }
    
    // Handle local keyboard events (when Jason is in focus)
    private func handleLocalKeyEvent(_ event: NSEvent) -> NSEvent? {
        let isCtrlPressed = event.modifierFlags.contains(.control)
        let isShiftPressed = event.modifierFlags.contains(.shift)
        let isKKey = event.keyCode == 40  // K key
        let isEscapeKey = event.keyCode == 53
        
        // Check if this is our shortcut (Ctrl+Shift+K)
        if event.type == .keyDown && isCtrlPressed && isShiftPressed && isKKey {
            // Prevent double-handling
            guard !isHandlingShortcut else {
                print("⚠️ Already handling shortcut, ignoring duplicate")
                return nil
            }
            
            isHandlingShortcut = true
            print("⌨️ [LOCAL] Ctrl+Shift+K detected - toggling UI")
            
            // Handle the toggle
            if isVisible {
                hide()
            } else {
                show()
            }
            
            // Reset flag after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.isHandlingShortcut = false
            }
            
            return nil  // Consume the event - prevents system beep!
        }
        
        // Check if this is Escape and UI is visible
        if event.type == .keyDown && isEscapeKey && isVisible {
            print("⌨️ [LOCAL] Escape pressed - hiding circular UI")
            hide()
            return nil  // Consume the event
        }
        
        // Not our shortcut - let the system handle it
        return event
    }
    
    private func setupOverlayWindow() {
        guard let functionManager = functionManager else { return }
        
        overlayWindow = OverlayWindow()
        
        // NEW: Set up focus loss callback
        overlayWindow?.onLostFocus = { [weak self] in
            self?.hide()
        }
        
        let contentView = CircularUIView(
            circularUI: self,
            functionManager: functionManager
        )
        overlayWindow?.contentView = NSHostingView(rootView: contentView)
        
        print("Overlay window created and configured")
    }
    
    func show() {
        guard let functionManager = functionManager else {
            print("FunctionManager not initialized")
            return
        }
        
        functionManager.loadFunctions()
        
        // Check if we have any actual content (leaf nodes or branches with children)
        let hasValidData: Bool = {
            guard functionManager.rings.count > 0 else { return false }
            guard !functionManager.rings[0].nodes.isEmpty else { return false }
            
            // Check if any root node has content
            for node in functionManager.rings[0].nodes {
                if node.isLeaf {
                    return true  // Has at least one executable function
                } else if node.childCount > 0 {
                    return true  // Has at least one category with children
                }
            }
            return false
        }()
        
        if !hasValidData {
            print("No valid function data, loading mock data for testing")
            functionManager.loadMockFunctions()
        }
        
        guard !functionManager.currentFunctionList.isEmpty else {
            print("No functions to display")
            return
        }
        
        mousePosition = NSEvent.mouseLocation
        isVisible = true
        overlayWindow?.showOverlay(at: mousePosition)
        
        mouseTracker?.startTrackingMouse()
        gestureManager?.startMonitoring()  // ← NEW: Start gesture monitoring
        
        print("Showing circular UI at position: \(mousePosition)")
    }
    
    func hide() {
        mouseTracker?.stopTrackingMouse()
        gestureManager?.stopMonitoring()  // ← NEW: Stop gesture monitoring
        
        isVisible = false
        overlayWindow?.hideOverlay()
        
        // Reset all state for clean slate on next show
        functionManager?.reset()
        
        print("Hiding circular UI")
    }
    
    func executeSelectedFunction() {
        guard let functionManager = functionManager else { return }
        functionManager.executeSelected()
    }
}
