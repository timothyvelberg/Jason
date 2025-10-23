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
    private var centerPoint: CGPoint = .zero
    private var previousApp: NSRunningApplication?
    private var isIntentionallySwitching: Bool = false
    
    private var isInAppSwitcherMode: Bool = false
    private var wasCtrlPressedInAppSwitcherMode: Bool = false

    
    init() {
        print("CircularUIManager initialized")
        
        // Connect scroll handler
        overlayWindow?.onScrollBack = { [weak self] in
            self?.handleScrollBack()
        }
        
        QuickLookManager.shared.onVisibilityChanged = { [weak self] isShowing in
            if isShowing {
                // QuickLook is showing - lower our window
                self?.overlayWindow?.lowerWindowLevel()
            } else {
                // QuickLook is hidden - restore our window
                self?.overlayWindow?.restoreWindowLevel()
            }
        }
    }
    
    func setup(with appSwitcher: AppSwitcherManager) {
        
        self.appSwitcher = appSwitcher
        
        appSwitcher.circularUIManager = self
        
        // Create FunctionManager with providers
        self.functionManager = FunctionManager()
        
        // Register AppSwitcher as a provider
        functionManager?.registerProvider(appSwitcher)
        
        functionManager?.registerProvider(SystemActionsProvider())
        
        // Register Favorites Provider
        functionManager?.registerProvider(FavoriteAppsProvider())

        functionManager?.registerProvider(FinderLogic())

        if let functionManager = functionManager {
            self.mouseTracker = MouseTracker(functionManager: functionManager)
            
            mouseTracker?.onExecuteAction = { [weak self] in
                self?.hide()
            }
            
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
    
    private func handleScrollBack() {
        guard let functionManager = functionManager else { return }
        
        let currentLevel = functionManager.activeRingLevel
        
        if currentLevel > 0 {
            let targetLevel = currentLevel - 1
            print("🔙 [CircularUIManager] Scrolling back from ring \(currentLevel) to \(targetLevel)")
            functionManager.collapseToRing(level: targetLevel)
            
            // Only hide UI if we just collapsed TO Ring 0
            if targetLevel == 0 {
                print("👋 [handleScrollBack] Collapsed to Ring 0 - hiding UI")
                hide()
            } else {
                print("✅ [handleScrollBack] Collapsed to Ring \(targetLevel) - staying open")
                mouseTracker?.pauseAfterScroll()
            }
        } else {
            print("⚠️ [CircularUIManager] Already at Ring 0 - cannot scroll back further")
        }
    }
    
    // MARK: - Gesture Event Handler
    
    private func handleGestureEvent(_ event: GestureManager.GestureEvent) {
        guard isVisible else { return }
        
        switch event.type {
        case .click(.left):
            print("🖱️ Left-click detected at \(event.position)")
            handleLeftClick(event: event)
            
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
    
    // MARK: - Left Click Handler

    private func handleLeftClick(event: GestureManager.GestureEvent) {
        guard let functionManager = functionManager else { return }
        
        // Use position-based detection instead of hoveredIndex
        guard let (ringLevel, index, node) = functionManager.getItemAt(position: event.position, centerPoint: centerPoint) else {
            print("⚠️ Left-click not on any item")
            return
        }
        
        print("🖱️ [Left Click] On item: '\(node.name)' at ring \(ringLevel), index \(index)")
        
        switch node.onLeftClick {
        case .execute(let action):
            action()
            hide()
        case .executeKeepOpen(let action):
            action()
        case .expand:
            functionManager.expandCategory(ringLevel: ringLevel, index: index, openedByClick: true)
        case .navigateInto:
            print("📂 Navigating into folder: '\(node.name)'")
            functionManager.navigateIntoFolder(ringLevel: ringLevel, index: index)
        case .drag(let provider):
            // Execute onClick if provided
            if let onClick = provider.onClick {
                onClick()
                hide()
            }
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
        guard let functionManager = functionManager else { return }
        
        // Use position-based detection instead of hoveredIndex
        guard let (ringLevel, index, node) = functionManager.getItemAt(position: event.position, centerPoint: centerPoint) else {
            print("⚠️ Right-click not on any item")
            return
        }
        
        print("🖱️ [Right Click] On item: '\(node.name)' at ring \(ringLevel), index \(index)")
        
        switch node.onRightClick {
        case .expand:
            functionManager.expandCategory(ringLevel: ringLevel, index: index, openedByClick: true)
            // Pause mouse tracking to prevent immediate collapse
            mouseTracker?.pauseAfterScroll()
            
        case .navigateInto:
            print("📂 Navigating into folder: '\(node.name)'")
            functionManager.navigateIntoFolder(ringLevel: ringLevel, index: index)
            // Pause mouse tracking to prevent immediate collapse
            mouseTracker?.pauseAfterScroll()
            
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
        guard let functionManager = functionManager else { return }
        
        // Use position-based detection instead of hoveredIndex
        guard let (ringLevel, index, node) = functionManager.getItemAt(position: event.position, centerPoint: centerPoint) else {
            print("⚠️ Middle-click not on any item")
            return
        }
        
        print("🖱️ [Middle Click] On item: '\(node.name)' at ring \(ringLevel), index \(index)")
        
        // Check if node is previewable - if so, show preview instead of executing action
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
    
    // MARK: - Modified setupGlobalHotkeys method

    private func setupGlobalHotkeys() {
        print("⌨️ Setting up circular UI hotkeys (Ctrl+Shift+K and Ctrl+`)")
        
        // Listen for global key events (keyDown only)
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleGlobalKeyEvent(event)
        }
        
        // Listen for global modifier key changes (for SHIFT detection and Ctrl release)
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
    
    // MARK: - Modified handleGlobalKeyEvent

    private func handleGlobalKeyEvent(_ event: NSEvent) {
        let isCtrlPressed = event.modifierFlags.contains(.control)
        let isShiftPressed = event.modifierFlags.contains(.shift)
        let isKKey = event.keyCode == 40  // K key
        let isTildeKey = event.keyCode == 50  // ` key (backtick/tilde)
        
        // CTRL+` - App Switcher Mode
        if event.type == .keyDown && isCtrlPressed && isTildeKey {
            print("⌨️ [GLOBAL] Ctrl+` detected - showing app switcher")
            
            if !isVisible {
                // Show app switcher
                isInAppSwitcherMode = true
                wasCtrlPressedInAppSwitcherMode = true
                show(expandingCategory: "app-switcher")
                
                // Automatically select next app (index 1) to mimic Cmd+Tab behavior
                selectNextAppInSwitcher()
            } else if isInAppSwitcherMode {
                // Already visible in app switcher mode - cycle to next app
                selectNextAppInSwitcher()
            }
            
            return
        }
        
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
            exitAppSwitcherMode()
            hide()
        }
        
        if event.type == .keyDown && event.keyCode == 56 && isVisible {  // 56 = Left Shift
            print("⌨️ [GLOBAL] SHIFT pressed - checking for previewable node")
            handlePreviewRequest()
            return
        }
    }
    
    // MARK: - App Switcher Mode Helper Methods

    private func selectNextAppInSwitcher() {
        guard let functionManager = functionManager else { return }
        
        // Make sure we're at Ring 1 (app switcher)
        guard functionManager.activeRingLevel == 1 else {
            print("⚠️ Not in app switcher ring (level \(functionManager.activeRingLevel))")
            return
        }
        
        guard functionManager.rings.count > 1 else {
            print("⚠️ App switcher ring not available")
            return
        }
        
        let ring = functionManager.rings[1]
        let nodeCount = ring.nodes.count
        
        guard nodeCount > 0 else {
            print("⚠️ No apps in switcher")
            return
        }
        
        // Get current hovered index, or start at -1
        let currentIndex = ring.hoveredIndex ?? -1
        
        // Move to next app
        let nextIndex = (currentIndex + 1) % nodeCount
        
        print("⌨️ Cycling to next app: index \(nextIndex) (\(ring.nodes[nextIndex].name))")
        functionManager.hoverNode(ringLevel: 1, index: nextIndex)
    }

    private func handleCtrlReleaseInAppSwitcher() {
        guard let functionManager = functionManager else { return }
        
        // Only act on Ctrl release if we're still in Ring 1 (app switcher)
        guard functionManager.activeRingLevel == 1 else {
            print("✅ Ctrl released but not in Ring 1 (level \(functionManager.activeRingLevel)) - exiting app switcher mode")
            exitAppSwitcherMode()
            return
        }
        
        // Get the currently hovered app
        guard functionManager.rings.count > 1 else {
            print("⚠️ No app switcher ring available")
            exitAppSwitcherMode()
            hide()
            return
        }
        
        let ring = functionManager.rings[1]
        
        guard let hoveredIndex = ring.hoveredIndex,
              hoveredIndex < ring.nodes.count else {
            print("⚠️ No app selected in switcher")
            exitAppSwitcherMode()
            hide()
            return
        }
        
        let selectedNode = ring.nodes[hoveredIndex]
        
        print("✅ Ctrl released - switching to app: \(selectedNode.name)")
        
        // Execute the app's left click action (which switches to it)
        switch selectedNode.onLeftClick {
        case .execute(let action):
            action()
            exitAppSwitcherMode()
            hide()
        default:
            print("⚠️ Selected node doesn't have execute action")
            exitAppSwitcherMode()
            hide()
        }
    }

    private func exitAppSwitcherMode() {
        if isInAppSwitcherMode {
            print("🚪 Exiting app switcher mode")
        }
        isInAppSwitcherMode = false
        wasCtrlPressedInAppSwitcherMode = false
    }
    
    
    
    
    // MARK: - Modified handleLocalKeyEvent

    private func handleLocalKeyEvent(_ event: NSEvent) -> NSEvent? {
        let isCtrlPressed = event.modifierFlags.contains(.control)
        let isShiftPressed = event.modifierFlags.contains(.shift)
        let isKKey = event.keyCode == 40  // K key
        let isTildeKey = event.keyCode == 50  // ` key
        let isEscapeKey = event.keyCode == 53
        
        // CTRL+` - App Switcher Mode (LOCAL)
        if event.type == .keyDown && isCtrlPressed && isTildeKey {
            print("⌨️ [LOCAL] Ctrl+` detected - showing app switcher")
            
            if !isVisible {
                isInAppSwitcherMode = true
                wasCtrlPressedInAppSwitcherMode = true
                show(expandingCategory: "app-switcher")
                selectNextAppInSwitcher()
            } else if isInAppSwitcherMode {
                selectNextAppInSwitcher()
            }
            
            return nil  // Consume event
        }
        
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
            exitAppSwitcherMode()
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

    // MARK: - Modified handleLocalFlagsChanged

    private func handleLocalFlagsChanged(_ event: NSEvent) -> NSEvent? {
        guard isVisible else { return event }
        
        let isShiftPressed = event.modifierFlags.contains(.shift)
        let isCtrlPressed = event.modifierFlags.contains(.control)
        
        // Handle Ctrl release in App Switcher Mode
        if isInAppSwitcherMode && wasCtrlPressedInAppSwitcherMode && !isCtrlPressed {
            print("⌨️ [LOCAL] Ctrl released in app switcher mode")
            handleCtrlReleaseInAppSwitcher()
            wasCtrlPressedInAppSwitcherMode = isCtrlPressed
            return nil  // Consume event
        }
        
        // Track Ctrl state
        wasCtrlPressedInAppSwitcherMode = isCtrlPressed
        
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
    // MARK: - Overlay Window
    
    private func setupOverlayWindow() {
        guard let functionManager = functionManager else { return }
        
        overlayWindow = OverlayWindow()
        
        // Connect the callback for scroll events
        overlayWindow?.onScrollBack = { [weak self] in
            self?.handleScrollBack()
        }
        
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

    // MARK: - Preview Handler

    private func handlePreviewRequest() {
        guard let functionManager = functionManager else { return }
        
        // NEW: If QuickLook is already showing, just close it
        if QuickLookManager.shared.isShowing {
            print("👁️ [Preview] QuickLook is already open - closing it")
            QuickLookManager.shared.hidePreview()
            return
        }
        
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
        QuickLookManager.shared.showPreview(for: previewURL)  // 👈 Changed from togglePreview to showPreview
    }
    
    // MARK: - Modified handleGlobalFlagsChanged

    private func handleGlobalFlagsChanged(_ event: NSEvent) {
        guard isVisible else { return }
        
        let isShiftPressed = event.modifierFlags.contains(.shift)
        let isCtrlPressed = event.modifierFlags.contains(.control)
        
        // Handle Ctrl release in App Switcher Mode
        if isInAppSwitcherMode && wasCtrlPressedInAppSwitcherMode && !isCtrlPressed {
            print("⌨️ [GLOBAL] Ctrl released in app switcher mode")
            handleCtrlReleaseInAppSwitcher()
            return
        }
        
        // Track Ctrl state
        wasCtrlPressedInAppSwitcherMode = isCtrlPressed
        
        // Only trigger on SHIFT press (transition from not-pressed to pressed)
        if isShiftPressed && !wasShiftPressed {
            print("⌨️ [GLOBAL] SHIFT pressed - toggling preview")
            handlePreviewRequest()
        }
        
        wasShiftPressed = isShiftPressed
    }
    
    // MARK: - Show Methods

    /// Show the UI at the root level (Ring 0)
    func show() {
        show(expandingCategory: nil)
    }

    /// Show the UI already expanded to a specific category
    /// - Parameter providerId: The ID of the provider to expand (e.g., "app-switcher"), or nil to show Ring 0
    func show(expandingCategory providerId: String?) {
        guard let functionManager = functionManager else {
            print("FunctionManager not initialized")
            return
        }
        
        // Save the currently active app BEFORE we show our UI
        previousApp = NSWorkspace.shared.frontmostApplication
        if let prevApp = previousApp {
            print("💾 Saved previous app: \(prevApp.localizedName ?? "Unknown")")
        }
        
        // Load functions (and optionally expand to a category)
        if let providerId = providerId {
            print("🎯 [CircularUIManager] Showing UI expanded to: \(providerId)")
            functionManager.loadAndExpandToCategory(providerId: providerId)
            
            // IMPORTANT: Tell MouseTracker we're starting at Ring 0 (even though Ring 1 is active)
            // This way, when user moves back to Ring 0, it will collapse
            mouseTracker?.ringLevelAtPause = 0
        } else {
            functionManager.loadFunctions()
        }
        
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
        
        guard !functionManager.rings.isEmpty && !functionManager.rings[0].nodes.isEmpty else {
            print("No functions to display")
            return
        }
        
        mousePosition = NSEvent.mouseLocation
        centerPoint = mousePosition
        isVisible = true
        wasShiftPressed = false
        overlayWindow?.showOverlay(at: mousePosition)
        
        mouseTracker?.startTrackingMouse()
        gestureManager?.startMonitoring()
        
        print("✅ Showing circular UI at position: \(mousePosition)")
        if let providerId = providerId {
            print("   Expanded to category: \(providerId)")
        }
        print("   Active ring level: \(functionManager.activeRingLevel)")
        print("   Total rings: \(functionManager.rings.count)")
    }
    
    // MARK: - Modified hide() method

    func hide() {
        mouseTracker?.stopTrackingMouse()
        gestureManager?.stopMonitoring()
        
        isVisible = false
        overlayWindow?.hideOverlay()
        
        // Exit app switcher mode when hiding
        exitAppSwitcherMode()
        
        // 🆕 Only restore previous app if we're NOT intentionally switching
        if !isIntentionallySwitching {
            if let prevApp = previousApp, prevApp.isTerminated == false {
                print("🔄 Restoring focus to: \(prevApp.localizedName ?? "Unknown")")
                prevApp.activate()
            }
        } else {
            print("⏭️ Skipping restore - intentionally switching apps")
        }
        
        // Reset all state for clean slate on next show
        functionManager?.reset()
        
        // Close any open preview
        QuickLookManager.shared.hidePreview()
        wasShiftPressed = false
        previousApp = nil
        isIntentionallySwitching = false  // 🆕 Reset flag
        
        print("Hiding circular UI")
    }
    
    func hideAndSwitchTo(app: NSRunningApplication) {
        // 🆕 Set flag to prevent hide() from restoring previous app
        isIntentionallySwitching = true
        
        // Hide the UI (this will trigger onLostFocus -> hide())
        mouseTracker?.stopTrackingMouse()
        gestureManager?.stopMonitoring()
        
        isVisible = false
        overlayWindow?.hideOverlay()
        
        print("🎯 Switching to selected app: \(app.localizedName ?? "Unknown")")
        
        // Activate the app AFTER setting the flag
        app.activate()
        
        // Note: hide() will be called by onLostFocus, and it will see our flag
        print("Switching to app (hide() will clean up)")
    }
}
