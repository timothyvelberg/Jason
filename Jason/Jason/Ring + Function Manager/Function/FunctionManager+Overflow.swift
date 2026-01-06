//
//  FunctionManager+Overflow.swift
//  Jason
//
//  Created by Timothy Velberg on 05/01/2026.
//

import Foundation
import AppKit

// MARK: - Overflow Handling

extension FunctionManager {
    
    // MARK: - Constants
    
    /// Minimum arc length per item in pixels (usability threshold for child rings)
    private var minArcPerItem: CGFloat { 25 }
    
    // MARK: - Ring 0 Overflow (Fixed Threshold)
    
    /// Apply overflow handling for Ring 0 (fixed threshold of maxItems)
    /// - Parameter nodes: All nodes to display
    /// - Returns: Nodes with overflow applied, or original nodes if under threshold
    func applyRing0OverflowIfNeeded(_ nodes: [FunctionNode]) -> [FunctionNode] {
        let threshold = maxItems  // 24
        
        guard nodes.count > threshold else {
            return nodes
        }
        
        let visibleCount = threshold - 1  // Leave room for overflow node
        let visibleNodes = Array(nodes.prefix(visibleCount))
        let overflowNodes = Array(nodes.dropFirst(visibleCount))
        
        print("➕ [Ring 0 Overflow] \(nodes.count) items → \(visibleCount) visible + overflow (\(overflowNodes.count) items)")
        
        let overflowNode = createOverflowNode(
            id: "ring0-overflow",
            children: overflowNodes
        )
        
        return visibleNodes + [overflowNode]
    }
    
    // MARK: - Child Ring Overflow (Dynamic Threshold)
    
    /// Calculate threshold for a child ring based on geometry
    /// - Parameters:
    ///   - parentOuterRadius: The outer radius of the parent ring
    ///   - childThickness: The thickness of the child ring
    /// - Returns: Maximum items that fit comfortably in the child ring
    func calculateChildRingThreshold(parentOuterRadius: CGFloat, childThickness: CGFloat) -> Int {
        let margin: CGFloat = 2
        let childStartRadius = parentOuterRadius + margin
        let childMiddleRadius = childStartRadius + (childThickness / 2)
        let circumference = 2 * .pi * childMiddleRadius
        
        return Int(circumference / minArcPerItem)
    }
    
    /// Apply overflow handling for child rings (dynamic threshold based on geometry)
    /// - Parameters:
    ///   - nodes: All nodes to display
    ///   - parentOuterRadius: The outer radius of the parent ring
    ///   - childThickness: The thickness of this child ring
    ///   - overflowId: Unique ID for the overflow node
    /// - Returns: Nodes with overflow applied, or original nodes if under threshold
    func applyChildRingOverflowIfNeeded(
        _ nodes: [FunctionNode],
        parentOuterRadius: CGFloat,
        childThickness: CGFloat,
        overflowId: String
    ) -> [FunctionNode] {
        let threshold = calculateChildRingThreshold(
            parentOuterRadius: parentOuterRadius,
            childThickness: childThickness
        )
        
        guard nodes.count > threshold else {
            return nodes
        }
        
        let visibleCount = threshold - 1
        let visibleNodes = Array(nodes.prefix(visibleCount))
        let overflowNodes = Array(nodes.dropFirst(visibleCount))
        
        print("➕ [Child Ring Overflow] \(nodes.count) items → \(visibleCount) visible + overflow (\(overflowNodes.count) items) [threshold: \(threshold)]")
        
        let overflowNode = createOverflowNode(
            id: overflowId,
            children: overflowNodes
        )
        
        return visibleNodes + [overflowNode]
    }
    
    // MARK: - Overflow Node Creation
    
    private func createOverflowNode(id: String, children: [FunctionNode]) -> FunctionNode {
        // Filter out spacers - they don't serve a purpose in overflow
        let filteredChildren = children.filter { $0.type != .spacer }
        
        let icon = NSImage(systemSymbolName: "plus", accessibilityDescription: "More items")?
            .withSymbolConfiguration(.init(pointSize: 32, weight: .medium)) ?? NSImage()
        
        return FunctionNode(
            id: id,
            name: "More",
            type: .category,
            icon: icon,
            children: filteredChildren,
            preferredLayout: .partialSlice,
            showLabel: false,
            slicePositioning: .center,
            onLeftClick: ModifierAwareInteraction(base: .expand),
            onRightClick: ModifierAwareInteraction(base: .expand),
            onMiddleClick: ModifierAwareInteraction(base: .expand),
            onBoundaryCross: ModifierAwareInteraction(base: .expand)
        )
    }
}
