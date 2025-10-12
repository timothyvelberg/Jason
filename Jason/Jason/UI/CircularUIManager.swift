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
    
    // Drag support
    @Published var currentDragProvider: DragProvider?
    @Published var dragStartPoint: CGPoint?
    private var draggedNode: FunctionNode?
    
    private var overlayWindow: OverlayWindow?
    private var appSwitcher: AppSwitcherManager?
    var functionManager: FunctionManager?
    private var mouseTracker: MouseTracker?
    private var gestureManager: GestureManager?
    private var isHandlingShortcut: Bool = false  // Prevent double-handling
    private var wasShiftPressed: Bool = false
    
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
//        functionManager?.registerProvider(MockFunctionProvider())
        
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
        setupGestureManager()
    }
    
    // MARK: - Gesture Manager Setup
    
    private func setupGestureManager() {
        print("🖱️ Setting up GestureManager")
        
        gestureManager = GestureManager()
        
        // Use centralized event handler
        gestureManager?.onGesture = { [weak self] event in
            self?.handleGestureEvent(event)
        }
        
        print("✅ GestureManager ready")
    }
    
    // MARK: - Gesture Event Handler
    
    private func handleGestureEvent(_ event: GestureManager.GestureEvent) {
        guard isVisible else { return }
        
        switch event.type {
        case .click(.left):
            // Pass through to SwiftUI - handled in CircularUIView
            break
            
        case .click(.right):
            print("🖱️ Right-click detected at \(event.position)")
            handleRightClick(event: event)
            
        case .click(.middle):
            print("🖱️ Middle-click detected at \(event.position)")
            handleMiddleClick(event: event)
            
        case .dragStarted(let button, let startPoint):
            if button == .left {
                handleDragStarted(at: event.position, startPoint: startPoint)
            }
            
        case .dragMoved(let currentPoint, let delta):
            handleDragMoved(to: currentPoint, delta: delta)
            
        case .dragEnded(let endPoint, let didComplete):
            handleDragEnded(at: endPoint, completed: didComplete)
            
        default:
            break
        }
    }
    
    // MARK: - Drag Handlers
    
    private func handleDragStarted(at position: CGPoint, startPoint: CGPoint) {
        // Get the currently hovered node from FunctionManager
        guard let functionManager = functionManager else {
            print("🎯 No FunctionManager available")
            return
        }
        
        let activeRingLevel = functionManager.activeRingLevel
        guard activeRingLevel < functionManager.rings.count else {
            print("🎯 No active ring for drag")
            return
        }
        
        guard let hoveredIndex = functionManager.rings[activeRingLevel].hoveredIndex else {
            print("🎯 No node currently hovered for drag")
            return
        }
        
        guard hoveredIndex < functionManager.rings[activeRingLevel].nodes.count else {
            print("🎯 Invalid hovered index for drag")
            return
        }
        
        let node = functionManager.rings[activeRingLevel].nodes[hoveredIndex]
        
        guard node.isDraggable, var provider = node.onDrag.dragProvider else {
            print("🎯 Node '\(node.name)' is not draggable")
            return
        }
        
        // NEW: Capture current modifier flags
        let currentModifiers = NSEvent.modifierFlags
        provider.modifierFlags = currentModifiers
        
        // Log modifiers for debugging
        var modifierNames: [String] = []
        if currentModifiers.contains(.option) { modifierNames.append("Option") }
        if currentModifiers.contains(.command) { modifierNames.append("Cmd") }
        if currentModifiers.contains(.shift) { modifierNames.append("Shift") }
        if currentModifiers.contains(.control) { modifierNames.append("Control") }
        
        let modifierText = modifierNames.isEmpty ? "none" : modifierNames.joined(separator: "+")
        print("🎯 Drag started on node: \(node.name) with modifiers: \(modifierText)")
        
        // Store the dragged node
        draggedNode = node
        
        // Trigger the drag in the overlay view
        DispatchQueue.main.async {
            self.currentDragProvider = provider
            self.dragStartPoint = startPoint
        }
    }
    
    private func handleDragMoved(to position: CGPoint, delta: CGPoint) {
        // Optional: Update UI during drag
        // The AppKit layer handles the drag image
    }
    
    private func handleDragEnded(at position: CGPoint, completed: Bool) {
        if completed {
            print("✅ Drag completed successfully for: \(draggedNode?.name ?? "unknown")")
        } else {
            print("❌ Drag cancelled for: \(draggedNode?.name ?? "unknown")")
        }
        
        // Clean up
        draggedNode = nil
        currentDragProvider = nil
        dragStartPoint = nil
    }
    
    // MARK: - Click Handlers
    
    private func handleRightClick(event: GestureManager.GestureEvent) {
        // Get the currently hovered node from FunctionManager
        guard let functionManager = functionManager else { return }
        
        let activeRingLevel = functionManager.activeRingLevel
        guard activeRingLevel < functionManager.rings.count else { return }
        
        guard let hoveredIndex = functionManager.rings[activeRingLevel].hoveredIndex else {
            print("⚠️ No item currently hovered for right-click")
            return
        }
        
        guard hoveredIndex < functionManager.rings[activeRingLevel].nodes.count else {
            print("⚠️ Invalid hovered index for right-click")
            return
        }
        
        let node = functionManager.rings[activeRingLevel].nodes[hoveredIndex]
        
        print("🖱️ [Right Click] On item: '\(node.name)'")
        
        switch node.onRightClick {
        case .expand:
            functionManager.expandCategory(ringLevel: activeRingLevel, index: hoveredIndex)
        case .execute(let action):
            action()
            hide()
        case .executeKeepOpen(let action):
            action()
        default:
            break
        }
    }
    
    private func handleMiddleClick(event: GestureManager.GestureEvent) {
        // Get the currently hovered node from FunctionManager
        guard let functionManager = functionManager else { return }
        
        let activeRingLevel = functionManager.activeRingLevel
        guard activeRingLevel < functionManager.rings.count else { return }
        
        guard let hoveredIndex = functionManager.rings[activeRingLevel].hoveredIndex else {
            print("⚠️ No item currently hovered for middle-click")
            return
        }
        
        guard hoveredIndex < functionManager.rings[activeRingLevel].nodes.count else {
            print("⚠️ Invalid hovered index for middle-click")
            return
        }
        
        let node = functionManager.rings[activeRingLevel].nodes[hoveredIndex]
        
        print("🖱️ [Middle Click] On item: '\(node.name)'")
        
        // NEW: Check if node is previewable - if so, show preview instead of executing action
        if node.isPreviewable, let previewURL = node.previewURL {
            print("👁️ [Middle Click] Node is previewable - showing Quick Look")
            QuickLookManager.shared.togglePreview(for: previewURL)
            return
        }
        
        // Otherwise, execute the middle-click action
        switch node.onMiddleClick {
        case .execute(let action):
            action()
            hide()
        case .executeKeepOpen(let action):
            action()
        default:
            break
        }
    }
    
    // MARK: - Global Hotkeys
    
    private func setupGlobalHotkeys() {
        print("⌨️ Setting up circular UI hotkeys (Ctrl+Shift+K)")
        
        // Listen for global key events (keyDown only)
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleGlobalKeyEvent(event)
        }
        
        // Listen for global modifier key changes (for SHIFT detection)
        NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleGlobalFlagsChanged(event)
        }
        
        // Also listen for local events
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            return self?.handleLocalKeyEvent(event) ?? event
        }
        
        // Listen for local modifier key changes
        NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            return self?.handleLocalFlagsChanged(event) ?? event
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
        if event.type == .keyDown && event.keyCode == 56 && isVisible {  // 56 = Left Shift
            print("⌨️ [GLOBAL] SHIFT pressed - checking for previewable node")
            handlePreviewRequest()
            return
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

        // NEW: Check if this is SHIFT and UI is visible
        if event.type == .keyDown && event.keyCode == 56 && isVisible {  // 56 = Left Shift
            print("⌨️ [LOCAL] SHIFT pressed - checking for previewable node")
            handlePreviewRequest()
            return nil  // Consume the event
        }

        // Not our shortcut - let the system handle it
        return event
    }
    
    // MARK: - Overlay Window
    
    private func setupOverlayWindow() {
        guard let functionManager = functionManager else { return }
        
        overlayWindow = OverlayWindow()
        
        // Set up focus loss callback
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
    
    // MARK: - Preview Handler

    private func handlePreviewRequest() {
        guard let functionManager = functionManager else { return }
        
        let activeRingLevel = functionManager.activeRingLevel
        guard activeRingLevel < functionManager.rings.count else {
            print("⚠️ No active ring for preview")
            return
        }
        
        guard let hoveredIndex = functionManager.rings[activeRingLevel].hoveredIndex else {
            print("⚠️ No item currently hovered for preview")
            return
        }
        
        guard hoveredIndex < functionManager.rings[activeRingLevel].nodes.count else {
            print("⚠️ Invalid hovered index for preview")
            return
        }
        
        let node = functionManager.rings[activeRingLevel].nodes[hoveredIndex]
        
        // Check if node is previewable
        guard node.isPreviewable, let previewURL = node.previewURL else {
            print("⚠️ Node '\(node.name)' is not previewable")
            return
        }
        
        print("👁️ [Preview] Showing Quick Look for: \(node.name)")
        QuickLookManager.shared.togglePreview(for: previewURL)
    }
    
    // Handle global flag changes (modifier keys like SHIFT)
    private func handleGlobalFlagsChanged(_ event: NSEvent) {
        guard isVisible else { return }
        
        let isShiftPressed = event.modifierFlags.contains(.shift)
        
        // Only trigger on SHIFT press (transition from not-pressed to pressed)
        if isShiftPressed && !wasShiftPressed {
            print("⌨️ [GLOBAL] SHIFT pressed - toggling preview")
            handlePreviewRequest()
        }
        
        wasShiftPressed = isShiftPressed
    }

    // Handle local flag changes (modifier keys like SHIFT)
    private func handleLocalFlagsChanged(_ event: NSEvent) -> NSEvent? {
        guard isVisible else { return event }
        
        let isShiftPressed = event.modifierFlags.contains(.shift)
        
        // Only trigger on SHIFT press (transition from not-pressed to pressed)
        if isShiftPressed && !wasShiftPressed {
            print("⌨️ [LOCAL] SHIFT pressed - toggling preview")
            handlePreviewRequest()
            wasShiftPressed = isShiftPressed
            return nil  // Consume the event
        }
        
        wasShiftPressed = isShiftPressed
        return event
    }
    
    // MARK: - Show/Hide
    
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
        wasShiftPressed = false
        overlayWindow?.showOverlay(at: mousePosition)
        
        mouseTracker?.startTrackingMouse()
        gestureManager?.startMonitoring()
        
        print("Showing circular UI at position: \(mousePosition)")
    }
    
    func hide() {
        mouseTracker?.stopTrackingMouse()
        gestureManager?.stopMonitoring()
        
        isVisible = false
        overlayWindow?.hideOverlay()
        
        // Reset all state for clean slate on next show
        functionManager?.reset()
        
        // NEW: Close any open preview
        QuickLookManager.shared.hidePreview()
        wasShiftPressed = false  // Reset SHIFT state
        
        print("Hiding circular UI")
    }
    
    func executeSelectedFunction() {
        guard let functionManager = functionManager else { return }
        functionManager.executeSelected()
    }
}
