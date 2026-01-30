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
        
        panelStack[index].isSearchActive = true
        panelStack[index].searchQuery = ""
        print("[Search] Activated on level \(activePanelLevel)")
    }
    
    /// Deactivate search on the active panel
    func deactivateSearch() {
        guard let index = panelStack.firstIndex(where: { $0.level == activePanelLevel }) else {
            return
        }
        
        panelStack[index].isSearchActive = false
        panelStack[index].searchQuery = ""
        print("[Search] Deactivated on level \(activePanelLevel)")
    }
    
    // MARK: - Escape Handling
    
    /// Handle escape key during search
    /// Returns true if escape was consumed (search handled it)
    func handleSearchEscape() -> Bool {
        
        print("[Search] handleSearchEscape called, activePanelLevel=\(activePanelLevel), panelStack.count=\(panelStack.count)")

        guard let index = panelStack.firstIndex(where: { $0.level == activePanelLevel }),
              panelStack[index].isSearchActive else {
            print("[Search] No panel at active level")
            return false  // Not in search mode
        }
        
        if !panelStack[index].searchQuery.isEmpty {
            // Has text - clear it
            panelStack[index].searchQuery = ""
            print("[Search] Cleared query")
            return true
        } else {
            // Empty query - exit search mode
            panelStack[index].isSearchActive = false
            print("[Search] Exited search mode")
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
    }
    
    // MARK: - Search State
    
    /// Check if search is active on the current panel
    var isSearchActive: Bool {
        panelStack.contains { $0.isSearchActive }
    }
}
