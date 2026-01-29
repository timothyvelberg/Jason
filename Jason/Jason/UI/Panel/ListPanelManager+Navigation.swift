//
//  ListPanelManager+Navigation.swift
//  Jason
//
//  Created by Timothy Velberg on 29/01/2026.
//  Keyboard navigation for list panels.
//

import Foundation
import AppKit

extension ListPanelManager {
    
    // MARK: - Keyboard Navigation
    
    /// Enter the preview panel (→ arrow) - make it active
    func enterPreviewPanel() {
        let previewLevel = activePanelLevel + 1
        
        // Check if preview panel exists
        guard let previewIndex = panelStack.firstIndex(where: { $0.level == previewLevel }) else {
            print("[Keyboard] No preview panel to enter")
            return
        }
        
        // Set parent panel(s) to overlapping
        for i in panelStack.indices where panelStack[i].level <= previewLevel {
            panelStack[i].isOverlapping = true
        }
        
        // Move focus to preview (now becomes active)
        activePanelLevel = previewLevel
        inputCoordinator?.switchToKeyboard()
        inputCoordinator?.focusPanel(level: previewLevel)
        
        // Select first row in new active panel
        keyboardSelectedRow[activePanelLevel] = 0
        
        // Arm the new active panel for its children
        panelStack[previewIndex].areChildrenArmed = true
        
        print("[Keyboard] ENTERED → active panel now level \(activePanelLevel)")
        
        // Trigger hover for first item to spawn next preview if it's a folder
        let activePanel = panelStack[previewIndex]
        if !activePanel.items.isEmpty {
            let firstNode = activePanel.items[0]
            currentlyHoveredNodeId[activePanelLevel] = firstNode.id
            onItemHover?(firstNode, activePanelLevel, 0)
        }
    }

    /// Exit to parent panel (← arrow) - close current active, parent becomes active
    func exitToParentPanel() {
        guard activePanelLevel > 0 else {
            print("[Keyboard] At root panel - exiting to ring")
            inputCoordinator?.switchToKeyboard()
            onExitToRing?()
            return
        }
        
        let parentLevel = activePanelLevel - 1
        
        // Pop all panels above parent (including current active)
        popToLevel(parentLevel)
        
        // Move focus back to parent
        activePanelLevel = parentLevel
        inputCoordinator?.switchToKeyboard()
        inputCoordinator?.focusPanel(level: parentLevel)
        
        // Un-overlap the parent (it's now active, not background)
        if let parentIndex = panelStack.firstIndex(where: { $0.level == parentLevel }) {
            panelStack[parentIndex].areChildrenArmed = true
        }
        
        print("[Exit] activePanelLevel=\(activePanelLevel), isKeyboardDriven=\(isKeyboardDriven)")
        print("[Exit] keyboardSelectedRow=\(keyboardSelectedRow)")
        
        // Clear keyboard selection in old level
        keyboardSelectedRow.removeValue(forKey: parentLevel + 1)
        
        print("[Keyboard] EXITED ← active panel now level \(activePanelLevel)")
        
        // Re-trigger preview for currently selected item in parent
        if let selection = keyboardSelectedRow[parentLevel],
           let panel = panelStack.first(where: { $0.level == parentLevel }),
           selection < panel.items.count {
            let selectedNode = panel.items[selection]
            currentlyHoveredNodeId[parentLevel] = selectedNode.id
            onItemHover?(selectedNode, parentLevel, selection)
        }
    }
    
    /// Get the effective selected row for a panel level
    /// Only the ACTIVE panel shows selection highlight
    func effectiveSelectedRow(for level: Int) -> Int? {
        print("[EffectiveRow] level=\(level), activePanelLevel=\(activePanelLevel), isKeyboardDriven=\(isKeyboardDriven), hoveredRow[\(level)]=\(hoveredRow[level] ?? -999)")
        
        guard level == activePanelLevel else {
            return nil
        }
        
        if isKeyboardDriven {
            print("[EffectiveRow] Returning keyboardSelectedRow[\(level)]=\(keyboardSelectedRow[level] ?? -999)")
            return keyboardSelectedRow[level]
        }
        
        // If this panel has a preview child, highlight the source row
        if let previewPanel = panelStack.first(where: { $0.level == level + 1 }),
           !previewPanel.isOverlapping,
           let sourceRow = previewPanel.sourceRowIndex {
            // Return source row if:
            // 1. hoveredRow matches (mouse on source row), OR
            // 2. hoveredRow is nil (transition state - assume still on source row)
            if hoveredRow[level] == sourceRow || hoveredRow[level] == nil {
                print("[EffectiveRow] Returning source row \(sourceRow) from preview child (hover matches or nil)")
                return sourceRow
            }
        }
        
        print("[EffectiveRow] Returning hoveredRow[\(level)]=\(hoveredRow[level] ?? -999)")
        return hoveredRow[level]
    }

    /// Move selection down in the active panel
    func moveSelectionDown(in level: Int) {
        // Only allow navigation in the active panel
        guard level == activePanelLevel else {
            print("[Keyboard] Ignoring - level \(level) is not active (\(activePanelLevel))")
            return
        }
        
        guard let panel = panelStack.first(where: { $0.level == level }) else { return }
        
        let maxIndex = panel.items.count - 1
        guard maxIndex >= 0 else { return }
        
        // Calculate new selection
        let currentSelection: Int
        if isKeyboardDriven, let existing = keyboardSelectedRow[level] {
            currentSelection = existing
        } else if let hovered = hoveredRow[level] {
            currentSelection = hovered
        } else {
            currentSelection = -1  // Will become 0
        }
        
        let newSelection = min(currentSelection + 1, maxIndex)
        
        // Update state
        inputCoordinator?.switchToKeyboard()
        keyboardSelectedRow[level] = newSelection
        
        print("[Keyboard] Selection DOWN in level \(level): \(newSelection)")
        
        // Auto-arm for keyboard (no threshold needed)
        if let panelIndex = panelStack.firstIndex(where: { $0.level == level }) {
            panelStack[panelIndex].areChildrenArmed = true
        }
        
        // Close any existing preview (child panel)
        popToLevel(level)
        
        // Trigger hover to spawn preview if selected item is a folder
        let selectedNode = panel.items[newSelection]
        currentlyHoveredNodeId[level] = selectedNode.id
        onItemHover?(selectedNode, level, newSelection)
    }
    
    /// Move selection up in the active panel
    func moveSelectionUp(in level: Int) {
        print("[DEBUG] inputCoordinator is \(inputCoordinator == nil ? "nil" : "set")")
        
        // Only allow navigation in the active panel
        guard level == activePanelLevel else {
            print("[Keyboard] Ignoring - level \(level) is not active (\(activePanelLevel))")
            return
        }
        
        guard let panel = panelStack.first(where: { $0.level == level }) else { return }
        guard !panel.items.isEmpty else { return }
        
        // Calculate new selection
        let currentSelection: Int
        if isKeyboardDriven, let existing = keyboardSelectedRow[level] {
            currentSelection = existing
        } else if let hovered = hoveredRow[level] {
            currentSelection = hovered
        } else {
            currentSelection = 0  // Will stay 0
        }
        
        let newSelection = max(currentSelection - 1, 0)
        
        // Update state
        inputCoordinator?.switchToKeyboard()
        keyboardSelectedRow[level] = newSelection
        
        print("[Keyboard] Selection UP in level \(level): \(newSelection)")
        
        // Auto-arm for keyboard (no threshold needed)
        if let panelIndex = panelStack.firstIndex(where: { $0.level == level }) {
            panelStack[panelIndex].areChildrenArmed = true
        }
        
        // Close any existing preview (child panel)
        popToLevel(level)
        
        // Trigger hover to spawn preview if selected item is a folder
        let selectedNode = panel.items[newSelection]
        currentlyHoveredNodeId[level] = selectedNode.id
        onItemHover?(selectedNode, level, newSelection)
    }

    /// Clear keyboard selection state (called when switching to mouse mode)
    func resetToMouseMode() {
        guard isKeyboardDriven else { return }
        
        keyboardSelectedRow.removeAll()
        print("[Keyboard] Reset to mouse mode")
    }
    
    /// Execute the currently selected item (Enter key)
    func executeSelectedItem() {
        guard let selectedRow = keyboardSelectedRow[activePanelLevel],
              let panel = panelStack.first(where: { $0.level == activePanelLevel }),
              selectedRow < panel.items.count else {
            print("[Keyboard] No item selected to execute")
            return
        }
        
        let selectedNode = panel.items[selectedRow]
        print("[Keyboard] Execute: '\(selectedNode.name)'")
        
        onItemLeftClick?(selectedNode, NSEvent.modifierFlags)
    }
}
