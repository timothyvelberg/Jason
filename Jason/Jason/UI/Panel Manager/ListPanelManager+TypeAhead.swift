//
//  ListPanelManager+TypeAhead.swift
//  Jason
//
//  Created by Timothy Velberg on 29/01/2026.
//  Type-ahead search functionality for list panels.
//

import Foundation

extension ListPanelManager {
    
    // MARK: - Type-Ahead Search
    
    /// Handle character input for type-ahead search in active panel
    func handleCharacterInput(_ character: String) {
        
        guard let index = panelStack.firstIndex(where: { $0.level == activePanelLevel }) else {
            print("[TypeAhead] No active panel")
            return
        }
        
        // If search is already active, route to search query
        if panelStack[index].isSearchActive {
            panelStack[index].searchQuery += character
            
            if panelStack[index].activeTypingMode == .search {
                print("[Search] Query updated: '\(panelStack[index].searchQuery)'")
                filterSearchResults()
            } else {
                print("[Input] Text: '\(panelStack[index].searchQuery)'")
            }
            return
        }
        
        // Check panel's typing mode
        if panelStack[index].typingMode == .search {
            // Auto-activate search and add the character
            activateSearch()
            // Set the initial character (activateSearch sets query to "")
            if let idx = panelStack.firstIndex(where: { $0.level == activePanelLevel }) {
                panelStack[idx].searchQuery = character
            }
            print("[Search] Auto-activated with: '\(character)'")
            filterSearchResults()
            return
        }
        
        // Input mode - show field, accumulate text, but DON'T filter
        if panelStack[index].typingMode == .input {
            if !panelStack[index].isSearchActive {
                panelStack[index].isSearchActive = true
                panelStack[index].activeTypingMode = .input
                panelStack[index].searchAnchorHeight = panelStack[index].panelHeight
            }
            panelStack[index].searchQuery += character
            print("[Input] Text: '\(panelStack[index].searchQuery)'")
            return
        }
        
        // Cancel existing timer
        searchBufferTimer?.cancel()
        
        // Append to buffer
        searchBuffer += character.lowercased()
        
        print("[TypeAhead] Buffer: '\(searchBuffer)'")
        
        // Find matching item in active panel
        guard let panel = panelStack.first(where: { $0.level == activePanelLevel }) else {
            print("[TypeAhead] No active panel")
            searchBuffer = ""
            return
        }
        
        // Get current selection to determine starting point
        let currentSelection = keyboardSelectedRow[activePanelLevel] ?? -1
        
        // Search from current position + 1 to end, then from start to current position
        let items = panel.items
        var matchIndex: Int? = nil
        
        // First: search from after current selection to end
        for i in 0..<max(0, currentSelection + 1) {
            if items[i].name.lowercased().hasPrefix(searchBuffer) {
                matchIndex = i
                break
            }
        }
        
        // If no match found and we have a multi-char buffer, also check from start
        // (but only if buffer has more than 1 char, meaning user is refining search)
        if matchIndex == nil && searchBuffer.count > 1 {
            for i in 0..<max(0, currentSelection + 1) {
                if items[i].name.lowercased().hasPrefix(searchBuffer) {
                    matchIndex = i
                    break
                }
            }
        }
        
        // If still no match with multi-char, try single char from current position
        if matchIndex == nil && searchBuffer.count > 1 {
            let firstChar = String(searchBuffer.prefix(1))
            searchBuffer = firstChar  // Reset to single char
            print("[TypeAhead] No match, reset to: '\(searchBuffer)'")
            
            for i in (currentSelection + 1)..<items.count {
                if items[i].name.lowercased().hasPrefix(searchBuffer) {
                    matchIndex = i
                    break
                }
            }
        }
        
        if let index = matchIndex {
            print("[TypeAhead] Found match at index \(index): '\(items[index].name)'")
            
            // Update selection
            inputCoordinator?.switchToKeyboard()
            keyboardSelectedRow[activePanelLevel] = index
            
            // Close any existing preview
            popToLevel(activePanelLevel)
            
            // Arm for children and trigger hover to spawn preview
            if let panelIndex = panelStack.firstIndex(where: { $0.level == activePanelLevel }) {
                panelStack[panelIndex].areChildrenArmed = true
            }
            
            let selectedNode = items[index]
            currentlyHoveredNodeId[activePanelLevel] = selectedNode.id
            handleItemHover(node: selectedNode, level: activePanelLevel, rowIndex: index)
        } else {
            print("[TypeAhead] No match found")
        }
        
        // Start timer to reset buffer
        let timer = DispatchWorkItem { [weak self] in
            self?.searchBuffer = ""
            print("[TypeAhead] Buffer reset")
        }
        searchBufferTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + searchTimeout, execute: timer)
    }

    /// Reset type-ahead search state (call when hiding panels)
    func resetTypeAheadSearch() {
        searchBufferTimer?.cancel()
        searchBufferTimer = nil
        searchBuffer = ""
    }
}
