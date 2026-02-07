//
//  ListPanelManager+Search.swift
//  Jason
//
//  Created by Timothy Velberg on 30/01/2026.
//  Search functionality for list panels.


import Foundation

extension ListPanelManager {
    
    // MARK: - Search Activation
    
    /// Activate search on the active panel
    func activateSearch() {
        guard let index = panelStack.firstIndex(where: { $0.level == activePanelLevel }) else {
            print("[Search] No active panel to search")
            return
        }
        
        // Close any child panels when entering search
        popToLevel(activePanelLevel)
        
        // Store original items for restoration later
        panelStack[index].unfilteredItems = panelStack[index].items
        
        // Store original height for top-anchored resizing
        panelStack[index].searchAnchorHeight = panelStack[index].panelHeight
        
        panelStack[index].isSearchActive = true
        panelStack[index].activeTypingMode = .search
        panelStack[index].searchQuery = ""
        print("[Search] Activated on level \(activePanelLevel)")
    }
    
    func deactivateSearch() {
        guard let index = panelStack.firstIndex(where: { $0.level == activePanelLevel }) else {
            return
        }
        
        // Restore original items
        if let originalItems = panelStack[index].unfilteredItems {
            panelStack[index].items = originalItems
            panelStack[index].unfilteredItems = nil
        }
        
        panelStack[index].isSearchActive = false
        panelStack[index].searchQuery = ""
        panelStack[index].searchAnchorHeight = nil
        print("[Search] Deactivated on level \(activePanelLevel)")
    }
    
    /// Filter items based on current search query
    func filterSearchResults() {
        guard let index = panelStack.firstIndex(where: { $0.level == activePanelLevel }),
              panelStack[index].isSearchActive,
              let originalItems = panelStack[index].unfilteredItems else {
            return
        }
        
        let query = panelStack[index].searchQuery.lowercased()
        
        if query.isEmpty {
            // Empty query - show all items
            panelStack[index].items = originalItems
        } else {
            var filtered: [FunctionNode] = []
            var i = 0
            
            while i < originalItems.count {
                let item = originalItems[i]
                
                if item.type == .sectionHeader {
                    // Check if header matches
                    if item.name.lowercased().contains(query) {
                        // Include header + all items until next header
                        filtered.append(item)
                        i += 1
                        while i < originalItems.count && originalItems[i].type != .sectionHeader {
                            filtered.append(originalItems[i])
                            i += 1
                        }
                    } else {
                        // Header doesn't match — check children individually
                        var matchingChildren: [FunctionNode] = []
                        i += 1
                        while i < originalItems.count && originalItems[i].type != .sectionHeader {
                            if originalItems[i].name.lowercased().contains(query) {
                                matchingChildren.append(originalItems[i])
                            }
                            i += 1
                        }
                        // Include header + matching children if any matched
                        if !matchingChildren.isEmpty {
                            filtered.append(item)
                            filtered.append(contentsOf: matchingChildren)
                        }
                    }
                } else {
                    // Orphan item (no section) — filter normally
                    if item.name.lowercased().contains(query) {
                        filtered.append(item)
                    }
                    i += 1
                }
            }
            
            panelStack[index].items = filtered
        }
        
        // Switch to keyboard mode so effectiveSelectedRow uses keyboardSelectedRow
        inputCoordinator?.switchToKeyboard()
        
        // Reset selection to first item
        keyboardSelectedRow[activePanelLevel] = 0
        
        print("[Search] Filtered to \(panelStack[index].items.count) items")
    }
    
    // MARK: - Escape Handling
    
    /// Handle escape key during search
    /// Returns true if escape was consumed (search handled it)
    func handleSearchEscape() -> Bool {
        print("[Search] handleSearchEscape called, activePanelLevel=\(activePanelLevel), panelStack.count=\(panelStack.count)")

        guard let index = panelStack.firstIndex(where: { $0.level == activePanelLevel }),
              panelStack[index].isSearchActive else {
            print("[Search] No panel at active level")
            return false
        }
        
        if !panelStack[index].searchQuery.isEmpty {
            // Has text - clear it and restore all items
            panelStack[index].searchQuery = ""
            if let originalItems = panelStack[index].unfilteredItems {
                panelStack[index].items = originalItems
            }
            keyboardSelectedRow[activePanelLevel] = 0
            print("[Search] Cleared query")
            return true
        } else {
            // Empty query - exit search mode
            if let originalItems = panelStack[index].unfilteredItems {
                panelStack[index].items = originalItems
                panelStack[index].unfilteredItems = nil
            }
            
            if panelStack[index].typingMode == .input {
                if panelStack[index].activeTypingMode == .input {
                    // Already in input mode — let escape dismiss the panel
                    panelStack[index].isSearchActive = false
                    panelStack[index].searchAnchorHeight = nil
                    print("[Input] Exiting input mode")
                    return false  // Let escape propagate to dismiss
                }
                // Returning from search to input mode — keep field active
                panelStack[index].activeTypingMode = .input
                panelStack[index].searchAnchorHeight = panelStack[index].panelHeight
                print("[Input] Returned to input mode")
            } else {
                panelStack[index].isSearchActive = false
                panelStack[index].searchAnchorHeight = nil
                print("[Search] Exited search mode")
            }
            return true
        }
    }
    
    /// Handle backspace during search
    func handleBackspace() {
        guard let index = panelStack.firstIndex(where: { $0.level == activePanelLevel }),
              panelStack[index].isSearchActive,
              !panelStack[index].searchQuery.isEmpty else {
            return
        }
        
        panelStack[index].searchQuery.removeLast()
        print("[Search] Query after backspace: '\(panelStack[index].searchQuery)'")
        filterSearchResults()
    }
    
    /// Handle ALT+Backspace - delete last word
    func handleDeleteWord() {
        guard let index = panelStack.firstIndex(where: { $0.level == activePanelLevel }),
              panelStack[index].isSearchActive,
              !panelStack[index].searchQuery.isEmpty else {
            return
        }
        
        var query = panelStack[index].searchQuery
        
        // Trim trailing spaces first
        while query.last == " " {
            query.removeLast()
        }
        
        // Remove characters until we hit a space or empty
        while !query.isEmpty && query.last != " " {
            query.removeLast()
        }
        
        panelStack[index].searchQuery = query
        print("[Search] Query after delete word: '\(query)'")
        filterSearchResults()
    }

    /// Handle CMD+Backspace - delete entire input
    func handleDeleteAll() {
        guard let index = panelStack.firstIndex(where: { $0.level == activePanelLevel }),
              panelStack[index].isSearchActive else {
            return
        }
        
        panelStack[index].searchQuery = ""
        print("[Search] Query cleared")
        filterSearchResults()
    }
    
    // MARK: - Search State
    
    /// Check if search is active on the current panel
    var isSearchActive: Bool {
        panelStack.contains { $0.isSearchActive }
    }
}
