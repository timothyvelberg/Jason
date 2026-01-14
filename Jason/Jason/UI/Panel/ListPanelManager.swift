//
//  ListPanelManager.swift
//  Jason
//
//  Manages state and logic for the list panel UI.
//  Owned by CircularUIManager, coordinates panel visibility and content.
//

import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

class ListPanelManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published var isVisible: Bool = false
    @Published var items: [FunctionNode] = []
    
    /// Position for the panel (screen coordinates, for later integration)
    @Published var position: CGPoint = .zero
    
    // MARK: - Show / Hide
    
    /// Show the panel with the given items
    func show(items: [FunctionNode], at position: CGPoint = .zero) {
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
        let testItems: [FunctionNode] = [
            createTestNode(name: "Documents", type: .folder),
            createTestNode(name: "Screenshots", type: .folder),
            createTestNode(name: "report_final_v2.pdf", type: .file, utType: .pdf),
            createTestNode(name: "notes.txt", type: .file, utType: .plainText),
            createTestNode(name: "presentation.key", type: .file, utType: .presentation),
            createTestNode(name: "budget_2024.xlsx", type: .file, utType: .spreadsheet),
            createTestNode(name: "photo_001.jpg", type: .file, utType: .jpeg),
            createTestNode(name: "archive.zip", type: .file, utType: .zip),
        ]
        
        // Center of screen for testing
        let screenCenter = NSScreen.main?.frame.center ?? CGPoint(x: 500, y: 500)
        
        show(items: testItems, at: screenCenter)
    }
    
    private func createTestNode(name: String, type: FunctionNodeType, utType: UTType? = nil) -> FunctionNode {
        let icon: NSImage
        if type == .folder {
            icon = NSWorkspace.shared.icon(for: .folder)
        } else if let utType = utType {
            icon = NSWorkspace.shared.icon(for: utType)
        } else {
            icon = NSWorkspace.shared.icon(for: .item)
        }
        
        return FunctionNode(
            id: UUID().uuidString,
            name: name,
            type: type,
            icon: icon
        )
    }
}

// MARK: - NSRect Extension

private extension NSRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
