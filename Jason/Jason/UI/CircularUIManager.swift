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
    private var isCtrlPressed: Bool = false  // NEW: Track Ctrl key state
    
    init() {
        print("CircularUIManager initialized")
    }
    
    func setup(with appSwitcher: AppSwitcherManager) {
        self.appSwitcher = appSwitcher
        
        // Create FunctionManager with providers
        self.functionManager = FunctionManager()
        
        // Register AppSwitcher as a provider
        functionManager?.registerProvider(appSwitcher)
        
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
        setupGlobalHotkeys()  // NEW: Setup keyboard shortcuts
    }
    
    // NEW: Setup keyboard shortcut listener
    private func setupGlobalHotkeys() {
        print("⌨️ Setting up circular UI hotkeys")
        
        // Listen for global key events (keyDown and flagsChanged)
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleGlobalKeyEvent(event)
        }
        
        // Also listen for local events
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleLocalKeyEvent(event)
            return event
        }
        
        print("✅ Circular UI hotkey monitoring started")
    }
    
    // NEW: Handle global keyboard events
    private func handleGlobalKeyEvent(_ event: NSEvent) {
        let isCtrlCurrentlyPressed = event.modifierFlags.contains(.control)
        let isShiftPressed = event.modifierFlags.contains(.shift)
        let isTildeKey = event.keyCode == 50
        
        // Show UI when Ctrl + Shift + Tilde is pressed
        if event.type == .keyDown && isCtrlCurrentlyPressed && isShiftPressed && isTildeKey && !isVisible {
            print("⌨️ Ctrl+Shift+~ detected - showing circular UI")
            isCtrlPressed = true
            show()
            return
        }
        
        // Track Ctrl key state changes
        if event.type == .flagsChanged {
            let wasCtrlPressed = isCtrlPressed
            isCtrlPressed = isCtrlCurrentlyPressed
            
            // If Ctrl was released and UI is visible, hide it
            if wasCtrlPressed && !isCtrlCurrentlyPressed && isVisible {
                print("⌨️ Ctrl released - hiding circular UI")
                hide()
            }
        }
        
        // Hide UI on Escape
        if event.type == .keyDown && event.keyCode == 53 && isVisible {
            print("⌨️ Escape pressed - hiding circular UI")
            hide()
        }
    }
    
    // NEW: Handle local keyboard events
    private func handleLocalKeyEvent(_ event: NSEvent) {
        handleGlobalKeyEvent(event)
    }
    
    private func setupOverlayWindow() {
        guard let functionManager = functionManager else { return }
        
        overlayWindow = OverlayWindow()
        
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
        
        print("Showing circular UI at position: \(mousePosition)")
    }
    
    func hide() {
        mouseTracker?.stopTrackingMouse()
        
        isVisible = false
        isCtrlPressed = false  // NEW: Reset Ctrl state
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
