//
//  RingView+Animation.swift
//  Jason
//
//  Created by Timothy Velberg on 04/12/2025.
//

import SwiftUI

// MARK: - Staggered Icon Animations

extension RingView {
    
    func animateIconsIn() {
        // Dispatch to appropriate animation based on mode
        switch animationMode {
        case .linear:
            animateIconsInLinear()
        case .centerOut:
            animateIconsInFromCenter()
        }
    }
    
    // MARK: - Linear Animation
    
    func animateIconsInLinear() {
        // Reset all opacities to 0, scales to starting value, and rotation offsets
        for node in nodes {
            iconOpacities[node.id] = 0
            iconScales[node.id] = animationStartScale
            iconRotationOffsets[node.id] = effectiveRotationOffset
            runningIndicatorOpacities[node.id] = 0
            badgeOpacities[node.id] = 0
        }
        
        // Animate each icon in with initial delay + staggered delay
        for (index, node) in nodes.enumerated() {
            let delay = animationInitialDelay + (Double(index) * effectiveStaggerDelay)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: self.animationDuration)) {
                    self.iconOpacities[node.id] = 1.0
                    self.iconScales[node.id] = 1.0
                    self.iconRotationOffsets[node.id] = 0
                }
            }
        }
        
        // Animate running indicators after all icons are done
        let lastIconDelay = animationInitialDelay + (Double(nodes.count - 1) * effectiveStaggerDelay)
        let indicatorDelay = lastIconDelay + animationDuration
        
        for node in nodes {
            // Check if this node is a running app
            if let metadata = node.metadata,
               let isRunning = metadata["isRunning"] as? Bool,
               isRunning {
                DispatchQueue.main.asyncAfter(deadline: .now() + indicatorDelay) {
                    withAnimation(.easeIn(duration: 0.3)) {
                        self.runningIndicatorOpacities[node.id] = 1.0
                    }
                }
            }
        
            // Animate badge if present
            if let metadata = node.metadata,
               let badge = metadata["badge"] as? String,
               !badge.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + indicatorDelay) {
                    withAnimation(.easeIn(duration: 0.3)) {
                        self.badgeOpacities[node.id] = 1.0
                    }
                }
            }
        }
    }
    
    // MARK: - Center-Out Animation

    func animateIconsInFromCenter() {
        let totalCount = nodes.count
        guard totalCount > 0 else { return }
        
        // Determine center point for rotation offset calculation
        let centerPoint: Double
        if totalCount % 2 == 1 {
            // Odd count: center is at the middle index
            centerPoint = Double(totalCount / 2)
        } else {
            // Even count: center is between the two middle indices
            centerPoint = Double(totalCount) / 2.0 - 0.5
        }
        
        // Reset all opacities to 0, scales to starting value, and rotation offsets
        // Apply symmetric rotation: left of center = +10°, right of center = -10°
        for (index, node) in nodes.enumerated() {
            iconOpacities[node.id] = 0
            iconScales[node.id] = animationStartScale
            runningIndicatorOpacities[node.id] = 0
            badgeOpacities[node.id] = 0
            
            // Determine rotation offset based on position relative to center
            let rotationOffset: Double
            if Double(index) < centerPoint {
                rotationOffset = abs(effectiveRotationOffset)
            } else if Double(index) > centerPoint {
                rotationOffset = -abs(effectiveRotationOffset)
            } else {
                // Exactly at center (odd count only): no rotation
                rotationOffset = 0
            }
            iconRotationOffsets[node.id] = rotationOffset
        }
        
        // Build animation groups: items at same distance from center animate together
        var animationGroups: [[Int]] = []
        var processed = Set<Int>()
        
        // Start with center item(s)
        if totalCount % 2 == 1 {
            // Odd count: one center item
            let centerIndex = totalCount / 2
            animationGroups.append([centerIndex])
            processed.insert(centerIndex)
        } else {
            // Even count: two center items
            let centerLeft = (totalCount / 2) - 1
            let centerRight = totalCount / 2
            animationGroups.append([centerLeft, centerRight])
            processed.insert(centerLeft)
            processed.insert(centerRight)
        }
        
        // Build outward groups symmetrically
        var distance = 1
        while processed.count < totalCount {
            var group: [Int] = []
            
            if totalCount % 2 == 1 {
                // Odd count: expand from single center
                let centerIndex = totalCount / 2
                let leftIndex = centerIndex - distance
                let rightIndex = centerIndex + distance
                
                if leftIndex >= 0 && !processed.contains(leftIndex) {
                    group.append(leftIndex)
                    processed.insert(leftIndex)
                }
                if rightIndex < totalCount && !processed.contains(rightIndex) {
                    group.append(rightIndex)
                    processed.insert(rightIndex)
                }
            } else {
                // Even count: expand from the gap between center items
                let centerLeft = (totalCount / 2) - 1
                let leftIndex = centerLeft - distance
                let rightIndex = centerLeft + 1 + distance
                
                if leftIndex >= 0 && !processed.contains(leftIndex) {
                    group.append(leftIndex)
                    processed.insert(leftIndex)
                }
                if rightIndex < totalCount && !processed.contains(rightIndex) {
                    group.append(rightIndex)
                    processed.insert(rightIndex)
                }
            }
            
            if !group.isEmpty {
                animationGroups.append(group)
            }
            
            distance += 1
        }

        // Animate each group with increasing delay
        for (groupIndex, group) in animationGroups.enumerated() {
            let delay = animationInitialDelay + (Double(groupIndex) * effectiveStaggerDelay)
            
            for index in group {
                let node = nodes[index]
                
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.easeOut(duration: self.animationDuration)) {
                        self.iconOpacities[node.id] = 1.0
                        self.iconScales[node.id] = 1.0
                        self.iconRotationOffsets[node.id] = 0
                    }
                }
            }
        }
        
        // Animate running indicators and badges after all icons are done
        let lastGroupDelay = animationInitialDelay + (Double(animationGroups.count - 1) * effectiveStaggerDelay)
        let indicatorDelay = lastGroupDelay + animationDuration
        
        for node in nodes {
            guard let metadata = node.metadata else { continue }
            
            // Check if this node is a running app
            if let isRunning = metadata["isRunning"] as? Bool, isRunning {
                DispatchQueue.main.asyncAfter(deadline: .now() + indicatorDelay) {
                    withAnimation(.easeIn(duration: 0.3)) {
                        self.runningIndicatorOpacities[node.id] = 1.0
                    }
                }
            }
            
            // Animate badge if present
            if let badge = metadata["badge"] as? String, !badge.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + indicatorDelay) {
                    withAnimation(.easeIn(duration: 0.3)) {
                        self.badgeOpacities[node.id] = 1.0
                    }
                }
            }
        }
    }
    
    // MARK: - Surgical Icon Animation

    func animateIconsSurgical(oldNodes: [FunctionNode], newNodes: [FunctionNode]) {
        let oldIds = Set(oldNodes.map { $0.id })
        let newIds = Set(newNodes.map { $0.id })
        
        let addedIds = newIds.subtracting(oldIds)
        let removedIds = oldIds.subtracting(newIds)
        let persistingIds = oldIds.intersection(newIds)
        
        print("      🔍 Surgical Animation Analysis:")
        print("         Old nodes: \(oldNodes.count), New nodes: \(newNodes.count)")
        print("         Added: \(addedIds.count), Removed: \(removedIds.count), Persisting: \(persistingIds.count)")
        if !addedIds.isEmpty {
            print("         ➕ Added IDs: \(Array(addedIds).joined(separator: ", "))")
        }
        if !removedIds.isEmpty {
            print("         ➖ Removed IDs: \(Array(removedIds).joined(separator: ", "))")
        }

        // Guard against empty old nodes (shouldn't happen, but just in case)
        if oldNodes.isEmpty && newNodes.count > 0 {
            print("      ⚠️ Old nodes empty - treating as first appearance, calling full animation")
            animateIconsIn()
            return
        }
        
        // 1. REMOVED ICONS: Fade out
        for id in removedIds {
            withAnimation(.easeIn(duration: 0.2)) {
                iconOpacities[id] = 0
                iconScales[id] = 0.8
                runningIndicatorOpacities[id] = 0
                badgeOpacities[id] = 0
            }
            
            // Clean up after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self.iconOpacities.removeValue(forKey: id)
                self.iconScales.removeValue(forKey: id)
                self.iconRotationOffsets.removeValue(forKey: id)
                self.runningIndicatorOpacities.removeValue(forKey: id)
                self.badgeOpacities.removeValue(forKey: id)
            }
        }
        
        // 2. PERSISTING ICONS: Ensure visible, no animation
        for id in persistingIds {
            // Just make sure they're visible (in case they weren't before)
            if iconOpacities[id] != 1.0 {
                iconOpacities[id] = 1.0
                iconScales[id] = 1.0
                iconRotationOffsets[id] = 0
            }
            
            // Update running indicator and badge if metadata changed
            if let node = newNodes.first(where: { $0.id == id }),
               let metadata = node.metadata {
                
                // Running indicator
                if let isRunning = metadata["isRunning"] as? Bool {
                    let currentOpacity = runningIndicatorOpacities[id] ?? 0
                    let targetOpacity = isRunning ? 1.0 : 0.0
                    if currentOpacity != targetOpacity {
                        withAnimation(.easeIn(duration: 0.3)) {
                            runningIndicatorOpacities[id] = targetOpacity
                        }
                    }
                }
                
                // Badge
                let badge = metadata["badge"] as? String
                let hasBadge = badge != nil && !badge!.isEmpty
                let currentBadgeOpacity = badgeOpacities[id] ?? 0
                let targetBadgeOpacity = hasBadge ? 1.0 : 0.0
                if currentBadgeOpacity != targetBadgeOpacity {
                    withAnimation(.easeIn(duration: 0.3)) {
                        badgeOpacities[id] = targetBadgeOpacity
                    }
                }
            }
        }
        
        // 3. ADDED ICONS: Fade in
        for id in addedIds {
            print("      ➕ Fading in new icon: \(id)")
            
            // Start invisible
            iconOpacities[id] = 0
            iconScales[id] = animationStartScale
            iconRotationOffsets[id] = 0
            runningIndicatorOpacities[id] = 0
            badgeOpacities[id] = 0
            
            // Fade in with slight delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeOut(duration: 0.25)) {
                    self.iconOpacities[id] = 1.0
                    self.iconScales[id] = 1.0
                }
                
                // Check if should show running indicator and badge
                if let node = newNodes.first(where: { $0.id == id }),
                   let metadata = node.metadata {
                    
                    // Running indicator
                    if let isRunning = metadata["isRunning"] as? Bool, isRunning {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            withAnimation(.easeIn(duration: 0.3)) {
                                self.runningIndicatorOpacities[id] = 1.0
                            }
                        }
                    }
                    
                    // Badge
                    if let badge = metadata["badge"] as? String, !badge.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            withAnimation(.easeIn(duration: 0.3)) {
                                self.badgeOpacities[id] = 1.0
                            }
                        }
                    }
                }
            }
        }
        
        // 4. SAFETY NET: Ensure ALL current nodes have animation states
        // This catches any nodes that might have been missed (e.g., due to truncation edge cases)
        var safetyNetTriggered = false
        for node in newNodes {
            if iconOpacities[node.id] == nil {
                print("      ⚠️ SAFETY NET: Initializing missing animation state for: \(node.id)")
                safetyNetTriggered = true
                iconOpacities[node.id] = 0
                iconScales[node.id] = animationStartScale
                iconRotationOffsets[node.id] = 0
                runningIndicatorOpacities[node.id] = 0
                badgeOpacities[node.id] = 0
                
                // Immediately fade in (this shouldn't normally happen)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        self.iconOpacities[node.id] = 1.0
                        self.iconScales[node.id] = 1.0
                    }
                    
                    // Running indicator if needed
                    if let metadata = node.metadata,
                       let isRunning = metadata["isRunning"] as? Bool,
                       isRunning {
                        self.runningIndicatorOpacities[node.id] = 1.0
                    }
                    
                    // Badge if needed
                    if let metadata = node.metadata,
                       let badge = metadata["badge"] as? String,
                       !badge.isEmpty {
                        self.badgeOpacities[node.id] = 1.0
                    }
                }
            }
        }
        
        if !safetyNetTriggered {
            print("      ✅ All \(newNodes.count) nodes have animation states")
        }
    }
}
