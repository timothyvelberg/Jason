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
    
    var onItemLeftClick: ((FunctionNode, NSEvent.ModifierFlags) -> Void)?
    var onItemRightClick: ((FunctionNode, NSEvent.ModifierFlags) -> Void)?

    private(set) var currentAngle: Double = 0
    private(set) var currentRingCenter: CGPoint = .zero
    private(set) var currentRingOuterRadius: CGFloat = 0
    
    // MARK: - Positioned Show

    /// Show the panel as an extension of a ring item
    func show(
        items: [FunctionNode],
        ringCenter: CGPoint,
        ringOuterRadius: CGFloat,
        angle: Double,
        panelWidth: CGFloat = 260
    ) {
        // Store for cascading
        self.currentAngle = angle
        self.currentRingCenter = ringCenter
        self.currentRingOuterRadius = ringOuterRadius
        
        // Convert angle to radians (subtract 90° to match ring coordinate system)
        let angleInRadians = (angle - 90) * (.pi / 180)
        
        // Gap between ring edge and panel
        let gapFromRing: CGFloat = 8
        
        // Calculate anchor point at ring edge
        let anchorRadius = ringOuterRadius + gapFromRing
        let anchorX = ringCenter.x + anchorRadius * cos(angleInRadians)
        let anchorY = ringCenter.y - anchorRadius * sin(angleInRadians)
        
        // Calculate panel height
        let maxVisibleItems = 10
        let rowHeight: CGFloat = 32
        let padding: CGFloat = 8
        let itemCount = min(items.count, maxVisibleItems)
        let panelHeight = CGFloat(itemCount) * rowHeight + padding
        
        // Base offset: half-dimensions in angle direction
        let offsetX = (panelWidth / 2) * cos(angleInRadians)
        let offsetY = (panelHeight / 2) * -sin(angleInRadians)
        
        // Diagonal factor: peaks at 45°, 135°, 225°, 315° (0 at cardinal angles)
        let angleWithinQuadrant = angle.truncatingRemainder(dividingBy: 90)
        let diagonalFactor = sin(angleWithinQuadrant * 2 * .pi / 180)
        
        // Extra offset for diagonal angles (25% extra at peak)
        let extraFactor: CGFloat = 0.18 * CGFloat(diagonalFactor)
        let extraOffsetX = extraFactor * panelWidth * cos(angleInRadians)
        let extraOffsetY = extraFactor * panelHeight * -sin(angleInRadians)
        
        let panelX = anchorX + offsetX + extraOffsetX
        let panelY = anchorY + offsetY + extraOffsetY
        
        let position = CGPoint(x: panelX, y: panelY)
        
        print("📋 [ListPanelManager] Showing panel at angle \(angle)°")
        print("   Diagonal factor: \(diagonalFactor), extra: \(extraFactor * 100)%")
        print("   Panel center: \(position)")
        
        self.items = items
        self.position = position
        self.isVisible = true
    }
    /// Show the panel with the given items at a specific position
    func show(items: [FunctionNode], at position: CGPoint) {
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
    func showTestPanel(at position: CGPoint = NSEvent.mouseLocation) {
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
        
        show(items: testItems, at: position)
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
