//
//  CircularUIManager+Lifecycle.swift
//  Jason
//
//  Created by Timothy Velberg on 29/01/2026.
//

import Foundation
import AppKit

extension CircularUIManager {
    
    // MARK: - Show Methods

    /// Show the UI at the root level (Ring 0)
    func show(triggerDirection: RotationDirection? = nil) {
        show(expandingCategory: nil, triggerDirection: triggerDirection)
    }

    /// Show the UI already expanded to a specific category
    /// - Parameter providerId: The ID of the provider to expand (e.g., "app-switcher"), or nil to show Ring 0
    func show(expandingCategory providerId: String?, triggerDirection: RotationDirection? = nil) {

        guard let functionManager = functionManager else {
            print("FunctionManager not initialized")
            return
        }
        
        // Store trigger direction for animation
        self.triggerDirection = triggerDirection
        print("[CircularUIManager] triggerDirection set to: \(String(describing: triggerDirection))")

        // Refresh badge cache before loading functions
        DockBadgeReader.shared.forceRefresh()
        
        // Register as the active CircularUIManager
        print("[CircularUIManager-\(configId)] Registering as active instance with AppSwitcherManager")
        AppSwitcherManager.shared.activeCircularUIManager = self
        
        // Save the currently active app BEFORE we show our UI
        previousApp = NSWorkspace.shared.frontmostApplication
        if let prevApp = previousApp {
            print("Saved previous app: \(prevApp.localizedName ?? "Unknown")")
        }
        
        // Load functions (and optionally expand to a category)
        if let providerId = providerId {
            print("[CircularUIManager] Showing UI expanded to: \(providerId)")
            functionManager.loadAndExpandToCategory(providerId: providerId)
            
            // Tell MouseTracker we're starting at Ring 0 (even though Ring 1 is active)
            // This way, when user moves back to Ring 0, it will collapse
            mouseTracker?.ringLevelAtPause = 0
        } else {
            functionManager.loadFunctions()
        }
        
        guard !functionManager.rings.isEmpty && !functionManager.rings[0].nodes.isEmpty else {
            print("No functions to display")
            return
        }
        
        mousePosition = NSEvent.mouseLocation
        centerPoint = mousePosition
        isVisible = true
        overlayWindow?.showOverlay(at: mousePosition)
        
        mouseTracker?.startTrackingMouse()
        gestureManager?.startMonitoring()
        resumeMouseMonitor()
        
        // Set initial focus to ring
        inputCoordinator?.focusRing(level: functionManager.activeRingLevel)
        
        if let providerId = providerId {
            print("   Expanded to category: \(providerId)")
        }
    }
    
    // MARK: - Hide Method

    func hide() {
        // Stop mouse monitor FIRST to prevent blocking permission dialogs
        pauseMouseMonitor()
        
        if isInHoldMode {
            executeHoveredItemIfInHoldMode()
        }
        
        mouseTracker?.stopTrackingMouse()
        gestureManager?.stopMonitoring()
        
        isVisible = false
        overlayWindow?.hideOverlay()
        
        // Exit hold mode when hiding (prevents double-hide on key release)
        isInHoldMode = false
        
        // Unregister as the active CircularUIManager
        if AppSwitcherManager.shared.activeCircularUIManager === self {
            print("[CircularUIManager-\(configId)] Unregistering as active instance")
            AppSwitcherManager.shared.activeCircularUIManager = nil
        }
        
        // Only restore previous app if we're NOT intentionally switching
        if !isIntentionallySwitching {
            if let prevApp = previousApp, prevApp.isTerminated == false {
                print("Restoring focus to: \(prevApp.localizedName ?? "Unknown")")
                prevApp.activate()
            }
        } else {
            print("Skipping restore - intentionally switching apps")
        }
        
        // Reset all state for clean slate on next show
        functionManager?.reset()
        listPanelManager?.hide()
        inputCoordinator?.reset()

        // Close any open preview
        QuickLookManager.shared.hidePreview()
        previousApp = nil
        isIntentionallySwitching = false
        
        print("Hiding circular UI")
    }
    
    /// Temporarily ignore focus changes (used during app quit/launch to prevent unwanted UI hiding)
    func ignoreFocusChangesTemporarily(duration: TimeInterval = 0.5) {
        overlayWindow?.ignoreFocusChangesTemporarily(duration: duration)
    }
    
    func hideAndSwitchTo(app: NSRunningApplication) {
        // Set flag to prevent hide() from restoring previous app
        isIntentionallySwitching = true
        
        // Hide the UI (this will trigger onLostFocus -> hide())
        mouseTracker?.stopTrackingMouse()
        gestureManager?.stopMonitoring()
        
        isVisible = false
        overlayWindow?.hideOverlay()
        
        print("Switching to selected app: \(app.localizedName ?? "Unknown")")
        
        // Activate the app AFTER setting the flag
        app.activate()
        
        // Note: hide() will be called by onLostFocus, and it will see our flag
        print("Switching to app (hide() will clean up)")
    }
    
    // MARK: - Hold Mode
    
    /// Execute the hovered item when releasing hold mode (if auto-execute is enabled)
    func executeHoveredItemIfInHoldMode() {
        // Only execute in hold mode AND if auto-execute is enabled
        guard isInHoldMode else {
            print("[HoldMode] Not in hold mode - skipping auto-execute")
            return
        }
        
        // Check if auto-execute is enabled for the active trigger
        let autoExecuteEnabled = activeTrigger?.autoExecuteOnRelease ?? true
        guard autoExecuteEnabled else {
            print("[HoldMode] Auto-execute disabled for this trigger - skipping")
            return
        }
        
        guard let functionManager = functionManager else {
            print("[HoldMode] No FunctionManager")
            return
        }
        
        // Get the active ring
        let activeRingLevel = functionManager.activeRingLevel
        guard activeRingLevel < functionManager.rings.count else {
            print("[HoldMode] Invalid ring level: \(activeRingLevel)")
            return
        }
        
        let ring = functionManager.rings[activeRingLevel]
        
        // Check if there's a hovered item
        guard let hoveredIndex = ring.hoveredIndex else {
            print("[HoldMode] No item currently hovered - skipping auto-execute")
            return
        }
        
        guard hoveredIndex < ring.nodes.count else {
            print("[HoldMode] Invalid hovered index: \(hoveredIndex)")
            return
        }
        
        let selectedNode = ring.nodes[hoveredIndex]
        
        print("[HoldMode] Hold released - auto-executing: \(selectedNode.name)")
        
        // Execute the item's left click action (resolve with no modifiers since key/button was just released)
        let behavior = selectedNode.onLeftClick.resolve(with: [])
        
        switch behavior {
        case .execute(let action):
            action()
            // Note: hide() will be called after this method returns
        case .executeKeepOpen(let action):
            action()
            // Note: hide() will be called after this method returns (we don't honor keepOpen in hold mode)
        default:
            print("[HoldMode] Selected node doesn't have execute action")
        }
    }
    
    // MARK: - Preview Handler

    func handlePreviewRequest() {
        guard let functionManager = functionManager else { return }
        
        // If QuickLook is already showing, just close it
        if QuickLookManager.shared.isShowing {
            print("[Preview] QuickLook is already open - closing it")
            QuickLookManager.shared.hidePreview()
            return
        }
        
        let activeRingLevel = functionManager.activeRingLevel
        guard activeRingLevel < functionManager.rings.count else {
            print("No active ring for preview")
            return
        }
        
        guard let hoveredIndex = functionManager.rings[activeRingLevel].hoveredIndex else {
            print("No item currently hovered for preview")
            return
        }
        
        guard hoveredIndex < functionManager.rings[activeRingLevel].nodes.count else {
            print("Invalid hovered index for preview")
            return
        }
        
        let node = functionManager.rings[activeRingLevel].nodes[hoveredIndex]
        
        // Check if node is previewable
        guard node.isPreviewable, let previewURL = node.previewURL else {
            print("Node '\(node.name)' is not previewable")
            return
        }
        
        print("[Preview] Showing Quick Look for: \(node.name)")
        QuickLookManager.shared.showPreview(for: previewURL)
    }
    
    // MARK: - Mouse Monitor Control

    func pauseMouseMonitor() {
        if let monitor = panelMouseMonitor {
            NSEvent.removeMonitor(monitor)
            panelMouseMonitor = nil
            print("[MouseMonitor] Paused")
        }
    }

    func resumeMouseMonitor() {
        guard panelMouseMonitor == nil else { return }
        
        panelMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self = self,
                  self.isVisible,
                  let panelManager = self.listPanelManager,
                  panelManager.isVisible else {
                return event
            }
            
            let mousePosition = NSEvent.mouseLocation
            panelManager.handleMouseMove(at: mousePosition)
            
            return event
        }
        print("[MouseMonitor] Resumed")
    }
}
