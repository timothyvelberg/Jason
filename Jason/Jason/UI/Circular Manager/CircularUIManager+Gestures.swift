//
//  CircularUIManager+Gestures.swift
//  Jason
//
//  Created by Timothy Velberg on 29/01/2026.
//

import Foundation
import AppKit

extension CircularUIManager {
    
    // MARK: - Left Click
    
    func handleLeftClick(event: GestureManager.GestureEvent) {
        // Resume tracking if paused for potential drag that didn't happen
         mouseTracker?.resumeFromDrag()
        
        // Check if click is inside the panel
        if let panelManager = listPanelManager {
            if let result = panelManager.handleLeftClick(at: event.position) {
                print("[Left Click] Panel item: '\(result.node.name)' at level \(result.level)")
                handlePanelItemLeftClick(node: result.node, modifiers: event.modifierFlags, fromLevel: result.level)
                return
            }
            
            // Clear context actions if any are open
            if panelManager.panelStack.contains(where: { $0.expandedItemId != nil }) {
                for i in panelManager.panelStack.indices {
                    panelManager.panelStack[i].expandedItemId = nil
                }
                return
            }
        }
        
        guard let functionManager = functionManager else { return }
        
        guard let (ringLevel, index, node) = functionManager.getItemAt(position: event.position, centerPoint: centerPoint) else {
            // Check if click was in close zone
            let distance = hypot(event.position.x - centerPoint.x, event.position.y - centerPoint.y)
            if distance < FunctionManager.closeZoneRadius {
                print("[Left Click] In close zone - closing UI")
                hide()
            } else {
                print("Left-click not on any item")
            }
            return
        }
        
        print("[Left Click] On item: '\(node.name)' at ring \(ringLevel), index \(index)")
        
        // Resolve behavior based on current modifier flags
        let behavior = node.onLeftClick.resolve(with: event.modifierFlags)
        
        switch behavior {
        case .execute(let action):
            action()
            hide()
        case .executeKeepOpen(let action):
            action()
        case .expand:
            functionManager.expandCategory(ringLevel: ringLevel, index: index, openedByClick: true)
        case .navigateInto:
            print("Navigating into folder: '\(node.name)'")
            functionManager.navigateIntoFolder(ringLevel: ringLevel, index: index)
        case .launchRing(let configId):
            print("[Left Click] Launching ring config \(configId)")
            print("[Left Click] Launching ring config \(configId) from item '\(node.name)' (id: \(node.id))")
            hide()  // Hide current ring first
            
            // Small delay to ensure clean transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                CircularUIInstanceManager.shared.show(configId: configId)
            }
        case .drag(let provider):
            // Handle click behavior based on explicit declaration
            switch provider.clickBehavior {
            case .execute(let action):
                action()
                hide()
            case .navigate:
                print("Navigating into draggable folder: '\(node.name)'")
                functionManager.navigateIntoFolder(ringLevel: ringLevel, index: index)
            case .none:
                break
            }
        default:
            break
        }
    }
    
    // MARK: - Right Click
    
    func handleRightClick(event: GestureManager.GestureEvent) {
        if let panelManager = listPanelManager, panelManager.handleRightClick(at: event.position) {
            print("[Right Click] Handled by panel")
            return
        }
        
        guard let functionManager = functionManager else { return }
        
        // Use position-based detection instead of hoveredIndex
        guard let (ringLevel, index, node) = functionManager.getItemAt(position: event.position, centerPoint: centerPoint) else {
            print("Right-click not on any item")
            return
        }
        
        print("[Right Click] On item: '\(node.name)' at ring \(ringLevel), index \(index)")
        
        // Resolve behavior based on current modifier flags
        let behavior = node.onRightClick.resolve(with: event.modifierFlags)
        
        switch behavior {
        case .expand:
            functionManager.expandCategory(ringLevel: ringLevel, index: index, openedByClick: true)
            // Pause mouse tracking to prevent immediate collapse
            mouseTracker?.pauseUntilMovement()
            
        case .navigateInto:
            print("Navigating into folder: '\(node.name)'")
            functionManager.navigateIntoFolder(ringLevel: ringLevel, index: index)
            // Pause mouse tracking to prevent immediate collapse
            mouseTracker?.pauseUntilMovement()
            
        case .launchRing(let configId):
            print("[Right Click] Launching ring config \(configId)")
            hide()  // Hide current ring first
            
            // Small delay to ensure clean transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                CircularUIInstanceManager.shared.show(configId: configId)
            }
            
        case .execute(let action):
            action()
            hide()
            
        case .executeKeepOpen(let action):
            action()
            
        default:
            break
        }
    }
    
    // MARK: - Middle Click
    
    func handleMiddleClick(event: GestureManager.GestureEvent) {
        guard let functionManager = functionManager else { return }
        
        // Use position-based detection instead of hoveredIndex
        guard let (ringLevel, index, node) = functionManager.getItemAt(position: event.position, centerPoint: centerPoint) else {
            print("Middle-click not on any item")
            return
        }
        
        print("[Middle Click] On item: '\(node.name)' at ring \(ringLevel), index \(index)")
        
        // Check if node is previewable - if so, show preview instead of executing action
        if node.isPreviewable, let previewURL = node.previewURL {
            print("[Middle Click] Node is previewable - showing Quick Look")
            QuickLookManager.shared.togglePreview(for: previewURL)
            return
        }
        
        // Otherwise, execute the middle-click action (resolve with modifiers)
        let behavior = node.onMiddleClick.resolve(with: event.modifierFlags)
        
        switch behavior {
        case .execute(let action):
            action()
            hide()
        case .executeKeepOpen(let action):
            action()
        case .launchRing(let configId):
            print("[Middle Click] Launching ring config \(configId)")
            hide()  // Hide current ring first
            
            // Small delay to ensure clean transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                CircularUIInstanceManager.shared.show(configId: configId)
            }
        default:
            break
        }
    }
    
    // MARK: - Drag Start
    
    func handleDragStart(event: GestureManager.GestureEvent) {
        // Extract the original mouse-down position for hit testing
        let hitTestPosition: CGPoint
        if case .dragStarted(_, let startPoint) = event.type {
            hitTestPosition = startPoint
        } else {
            hitTestPosition = event.position
        }
        
        // 1. Check if drag started inside a panel FIRST
        if let panelManager = listPanelManager {
            if let result = panelManager.handleDragStart(at: hitTestPosition) {  // ← changed
                print("[Drag Start] On panel item: '\(result.node.name)' at level \(result.level)")
                
                mouseTracker?.stopTrackingMouse()
                gestureManager?.stopMonitoring()
                print("Mouse tracking paused for panel drag operation")
                
                var provider = result.dragProvider
                provider.modifierFlags = event.modifierFlags
                
                provider.onDragSessionBegan = { [weak self] in
                    DispatchQueue.main.async {
                        self?.overlayWindow?.orderOut(nil)
                    }
                }
                
                let originalCompletion = provider.onDragCompleted
                provider.onDragCompleted = { [weak self] success in
                    originalCompletion?(success)
                    DispatchQueue.main.async {
                        print("Panel drag completed - hiding UI")
                        self?.hide()
                    }
                }
                
                self.currentDragProvider = provider
                self.dragStartPoint = event.position  // ← stays as current position (where cursor is)
                self.draggedNode = result.node
                
                print("Panel drag initialized for: \(result.node.name)")
                print("   Files: \(provider.fileURLs.map { $0.lastPathComponent }.joined(separator: ", "))")
                
                provider.onDragStarted?()
                return
            }
        }
        
        // 2. Fall through to ring check
        guard let functionManager = functionManager else { return }
        
        guard let (ringLevel, index, node) = functionManager.getItemAt(position: hitTestPosition, centerPoint: centerPoint) else {  // ← changed
            print("Drag start not on any item")
            return
        }
        
        print("[Drag Start] On ring item: '\(node.name)' at ring \(ringLevel), index \(index)")
        
        let behavior = node.onLeftClick.resolve(with: event.modifierFlags)
        
        if case .drag(var provider) = behavior {
            mouseTracker?.stopTrackingMouse()
            gestureManager?.stopMonitoring()
            print("Mouse tracking paused for drag operation")
            
            provider.modifierFlags = event.modifierFlags
            
            let originalCompletion = provider.onDragCompleted
            provider.onDragCompleted = { [weak self] success in
                originalCompletion?(success)
                DispatchQueue.main.async {
                    print("Drag completed - hiding UI")
                    self?.hide()
                }
            }
            
            self.currentDragProvider = provider
            self.dragStartPoint = event.position  // ← stays as current position
            self.draggedNode = node
            
            print("Ring drag initialized for: \(node.name)")
            print("   Files: \(provider.fileURLs.map { $0.lastPathComponent }.joined(separator: ", "))")
            print("   Modifiers: \(event.modifierFlags)")
            
            provider.onDragStarted?()
        } else {
            print("Node is not draggable")
        }
    }
    
    // MARK: - Scroll
    
    func handleScroll(delta: CGFloat) {
        guard let functionManager = functionManager else { return }
        
        if delta > 0 {
            // Scroll up/away = Navigate deeper
            let hoveredRingLevel = functionManager.activeRingLevel
            if let hoveredIndex = functionManager.rings[hoveredRingLevel].hoveredIndex {
                
                let node = functionManager.rings[hoveredRingLevel].nodes[hoveredIndex]
                
                // Get current modifier flags
                let currentModifiers = NSEvent.modifierFlags
                
                // Resolve behavior based on modifiers
                let behavior = node.onBoundaryCross.resolve(with: currentModifiers)
                
                switch behavior {
                case .navigateInto:
                    print("Scroll detected - navigating into folder")
                    functionManager.navigateIntoFolder(ringLevel: hoveredRingLevel, index: hoveredIndex)
                    mouseTracker?.pauseUntilMovement()
                    
                case .expand:
                    print("Scroll detected - expanding category")
                    functionManager.expandCategory(ringLevel: hoveredRingLevel, index: hoveredIndex, openedByClick: true)
                    mouseTracker?.pauseUntilMovement()
                    
                default:
                    break
                }
            }
        } else if delta < 0 {
            // Scroll down/toward = Go back
            handleScrollBack()
        }
    }
    
    func handleScrollBack() {
        guard let functionManager = functionManager else { return }
        
        // Go back one level
        let currentLevel = functionManager.activeRingLevel
        if currentLevel > 0 {
            print("Scroll back detected - collapsing to ring \(currentLevel - 1)")
            functionManager.collapseToRing(level: currentLevel - 1)
            mouseTracker?.pauseUntilMovement()
        }
    }
    
    // MARK: - Mouse Down (Pre-drag Preparation)

    func handleMouseDown(event: GestureManager.GestureEvent) {
        // Check if mouse down is on a draggable panel item
        if let panelManager = listPanelManager,
           let result = panelManager.handleDragStart(at: event.position) {
            print("[Mouse Down] On draggable panel item: '\(result.node.name)' - pausing tracker")
            mouseTracker?.pauseForDrag()
            return
        }
        
        // Check if mouse down is on a draggable ring item
        guard let functionManager = functionManager else { return }
        
        if let (_, _, node) = functionManager.getItemAt(position: event.position, centerPoint: centerPoint) {
            let behavior = node.onLeftClick.resolve(with: event.modifierFlags)
            if case .drag = behavior {
                print("[Mouse Down] On draggable ring item: '\(node.name)' - pausing tracker")
                mouseTracker?.pauseForDrag()
            }
        }
    }
}
