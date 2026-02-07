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
        keyboardSelectedRow[activePanelLevel] = firstSelectableRow(in: activePanelLevel)
        
        // Arm the new active panel for its children
        panelStack[previewIndex].areChildrenArmed = true
        
        print("[Keyboard] ENTERED → active panel now level \(activePanelLevel)")
        
        // Trigger hover for first item to spawn next preview if it's a folder
        let activePanel = panelStack[previewIndex]
        if !activePanel.items.isEmpty {
            let firstNode = activePanel.items[0]
            currentlyHoveredNodeId[activePanelLevel] = firstNode.id
            handleItemHover(node: firstNode, level: activePanelLevel, rowIndex: 0)
        }
    }
    
    /// Find the first selectable (non-sectionHeader) row index in a panel
    func firstSelectableRow(in level: Int) -> Int {
        guard let panel = panelStack.first(where: { $0.level == level }) else { return 0 }
        for i in 0..<panel.items.count {
            if panel.items[i].type != .sectionHeader {
                return i
            }
        }
        return 0
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
            handleItemHover(node: selectedNode, level: parentLevel, rowIndex: selection)
        }
    }
    
    /// Get the effective selected row for a panel level
    /// Only the ACTIVE panel shows selection highlight
    func effectiveSelectedRow(for level: Int) -> Int? {
//        print("[EffectiveRow] level=\(level), activePanelLevel=\(activePanelLevel), isKeyboardDriven=\(isKeyboardDriven), hoveredRow[\(level)]=\(hoveredRow[level] ?? -999)")
        
        guard level == activePanelLevel else {
            return nil
        }
        
        if isKeyboardDriven {
//            print("[EffectiveRow] Returning keyboardSelectedRow[\(level)]=\(keyboardSelectedRow[level] ?? -999)")
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
//                print("[EffectiveRow] Returning source row \(sourceRow) from preview child (hover matches or nil)")
                return sourceRow
            }
        }
        
//        print("[EffectiveRow] Returning hoveredRow[\(level)]=\(hoveredRow[level] ?? -999)")
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
        
        var newSelection = min(currentSelection + 1, maxIndex)

        // Skip section headers
        while newSelection <= maxIndex && panel.items[newSelection].type == .sectionHeader {
            newSelection += 1
        }
        if newSelection > maxIndex {
            newSelection = currentSelection  // Stay put if nothing below
        }
        
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
        handleItemHover(node: selectedNode, level: level, rowIndex: newSelection)
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
        
        var newSelection = max(currentSelection - 1, 0)

        // Skip section headers
        while newSelection > 0 && panel.items[newSelection].type == .sectionHeader {
            newSelection -= 1
        }
        if panel.items[newSelection].type == .sectionHeader {
            newSelection = currentSelection  // Stay put if nothing above
        }
        
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
        handleItemHover(node: selectedNode, level: level, rowIndex: newSelection)
    }

    /// Clear keyboard selection state (called when switching to mouse mode)
    func resetToMouseMode() {
        guard isKeyboardDriven else { return }
        
        keyboardSelectedRow.removeAll()
        print("[Keyboard] Reset to mouse mode")
    }
    
    /// Execute the currently selected item (Enter key)
    func executeSelectedItem() {
        // Input mode with text → add item instead of executing
        if let index = panelStack.firstIndex(where: { $0.level == activePanelLevel }),
           panelStack[index].activeTypingMode == .input,
           panelStack[index].isSearchActive,
           !panelStack[index].searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            let text = panelStack[index].searchQuery.trimmingCharacters(in: .whitespaces)
            print("[Input] Adding item: '\(text)'")
            panelStack[index].searchQuery = ""
            onAddItem?(text, NSEvent.modifierFlags)
            return
        }
        
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
    
    /// Handle item hover — manages folder cascading, child panel push/pop, and dynamic loading.
    func handleItemHover(node: FunctionNode?, level: Int, rowIndex: Int) {
        print("[handleItemHover] node: '\(node?.name ?? "nil")', level: \(level), rowIndex: \(rowIndex), type: \(String(describing: node?.type))")

        guard let node = node else { return }
        
        // Only cascade for folders
        guard node.type == .folder else {
            popToLevel(level)
            return
        }
        
        // Check if this node's panel is already showing at level+1
        if let existingPanel = panelStack.first(where: { $0.level == level + 1 }),
           existingPanel.sourceNodeId == node.id {
            popToLevel(level + 1)
            return
        }
        
        // Extract identity from node
        let providerId = node.providerId
        let contentIdentifier = node.metadata?["folderURL"] as? String ?? node.previewURL?.path
        
        // Children already loaded — push immediately
        if let children = node.children, !children.isEmpty {
            pushPanel(
                title: node.name,
                items: children,
                fromPanelAtLevel: level,
                sourceNodeId: node.id,
                sourceRowIndex: rowIndex,
                providerId: providerId,
                contentIdentifier: contentIdentifier,
                contextActions: node.contextActions
            )
            activateInputModeIfNeeded(for: providerId, atLevel: level + 1)
            return
        }
        
        // Dynamic loading
        guard node.needsDynamicLoading,
              let providerId = node.providerId,
              let provider = findProvider?(providerId) else {
            popToLevel(level)
            return
        }
        
        Task {
            let children = await provider.loadChildren(for: node)
            
            guard !children.isEmpty else {
                await MainActor.run {
                    self.popToLevel(level)
                }
                return
            }
            
            await MainActor.run {
                self.pushPanel(
                    title: node.name,
                    items: children,
                    fromPanelAtLevel: level,
                    sourceNodeId: node.id,
                    sourceRowIndex: rowIndex,
                    providerId: providerId,
                    contentIdentifier: contentIdentifier,
                    contextActions: node.contextActions
                )
                self.activateInputModeIfNeeded(for: providerId, atLevel: level + 1)
            }
        }
    }

    /// Activate input mode on a panel if its provider defaults to .input
    func activateInputModeIfNeeded(for providerId: String?, atLevel level: Int) {
        guard let providerId = providerId,
              let provider = findProvider?(providerId),
              provider.defaultTypingMode == .input,
              let index = panelStack.firstIndex(where: { $0.level == level }) else { return }
        
        panelStack[index].typingMode = .input
        panelStack[index].activeTypingMode = .input
        panelStack[index].isSearchActive = true
        panelStack[index].searchAnchorHeight = panelStack[index].panelHeight
    }
}
