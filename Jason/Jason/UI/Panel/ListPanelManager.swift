//
//  ListPanelManager.swift
//  Jason
//
//  Created by Timothy Velberg on 14/01/2026.
//
//  Manages state and logic for the list panel UI.
//  Owned by CircularUIManager, coordinates panel visibility and content.


import Foundation
import AppKit
import SwiftUI

class ListPanelManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published var isVisible: Bool = false
    @Published var items: [ListPanelItem] = []
    
    /// Position for the panel (screen coordinates, for later integration)
    @Published var position: CGPoint = .zero
    
    // MARK: - Show / Hide
    
    /// Show the panel with the given items
    func show(items: [ListPanelItem], at position: CGPoint = .zero) {
        print("📋 [ListPanelManager] Showing panel with \(items.count) items")
        self.items = items
        self.position = position
        self.isVisible = true
    }
    
    /// Hide the panel
    func hide() {
        print("📋 [ListPanelManager] Hiding panel")
        self.isVisible = false
        self.items = []
    }
    
    // MARK: - Test Helpers
    
    /// Show panel with sample test data (for development/testing)
    func showTestPanel() {
        let testItems: [ListPanelItem] = [
            ListPanelItem(
                name: "Documents",
                icon: NSWorkspace.shared.icon(forFileType: "public.folder"),
                isFolder: true
            ),
            ListPanelItem(
                name: "Screenshots",
                icon: NSWorkspace.shared.icon(forFileType: "public.folder"),
                isFolder: true
            ),
            ListPanelItem(
                name: "report_final_v2.pdf",
                icon: NSWorkspace.shared.icon(forFileType: "com.adobe.pdf"),
                isFolder: false
            ),
            ListPanelItem(
                name: "notes.txt",
                icon: NSWorkspace.shared.icon(forFileType: "public.plain-text"),
                isFolder: false
            ),
            ListPanelItem(
                name: "presentation.key",
                icon: NSWorkspace.shared.icon(forFileType: "com.apple.keynote.key"),
                isFolder: false
            ),
            ListPanelItem(
                name: "budget_2024.xlsx",
                icon: NSWorkspace.shared.icon(forFileType: "org.openxmlformats.spreadsheetml.sheet"),
                isFolder: false
            ),
            ListPanelItem(
                name: "photo_001.jpg",
                icon: NSWorkspace.shared.icon(forFileType: "public.jpeg"),
                isFolder: false
            ),
            ListPanelItem(
                name: "archive.zip",
                icon: NSWorkspace.shared.icon(forFileType: "public.zip-archive"),
                isFolder: false
            ),
        ]
        
        // Center of screen for testing
        let screenCenter = NSScreen.main?.frame.center ?? CGPoint(x: 500, y: 500)
        
        show(items: testItems, at: screenCenter)
    }
}

// MARK: - NSRect Extension

private extension NSRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
