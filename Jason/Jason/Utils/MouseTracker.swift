//
//  MouseTracker.swift
//  Jason
//
//  Created by Timothy Velberg on 05/10/2025.
//

import Cocoa

class MouseTracker {
    
    private var trackingStartPoint: NSPoint?
    private var trackingTimer: Timer?
    private var lastFunctionIndex: Int?
    private var lastRingLevel: Int?  // Can be nil when outside all rings
    private var isPausedAfterScroll = false
    private var lastMouseLocation: NSPoint?
    
    var onPieHover: ((Int?) -> Void)?
    private var functionManager: FunctionManager

    var mouseAngleOffset: CGFloat = 0
    
    
    init(functionManager: FunctionManager) {
        self.functionManager = functionManager
    }
    
    func startTrackingMouse() {
        stopTrackingMouse()
        trackingStartPoint = NSEvent.mouseLocation
        print("Mouse tracking started at: \(String(describing: trackingStartPoint))")

        var hasMouseMoved = false

        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            guard let start = self.trackingStartPoint else { return }
            
            let current = NSEvent.mouseLocation
            let distance = hypot(current.x - start.x, current.y - start.y)

            if !hasMouseMoved, distance > 5 {
                hasMouseMoved = true
                print("Mouse moved, starting selection tracking.")
            }
            if hasMouseMoved {
                self.trackMousePosition(distance: distance)
            }
        }
    }
    
    func stopTrackingMouse() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        trackingStartPoint = nil
        lastFunctionIndex = nil
        lastRingLevel = nil
        print("Mouse tracking stopped")
    }
    
    func pauseAfterScroll() {
        isPausedAfterScroll = true
        lastMouseLocation = NSEvent.mouseLocation  // Remember current position
        print("⏸️ [MouseTracker] Paused tracking after scroll - waiting for mouse movement")
    }

    private func trackMousePosition(distance: CGFloat) {
        guard let start = trackingStartPoint else { return }

        let current = NSEvent.mouseLocation
        
        // Check if paused and if mouse moved enough to resume
        if isPausedAfterScroll {
            if let last = lastMouseLocation {
                let moved = abs(current.x - last.x) > 5 || abs(current.y - last.y) > 5  // Increased threshold
                if moved {
                    isPausedAfterScroll = false
                    print("▶️ [MouseTracker] Resumed tracking after mouse movement")
                    lastMouseLocation = current  // Update now that we resumed
                } else {
                    // Still paused, don't track and DON'T update lastMouseLocation
                    return
                }
            } else {
                // No last position stored, resume immediately
                isPausedAfterScroll = false
                lastMouseLocation = current
            }
        } else {
            // Update last position only when NOT paused
            lastMouseLocation = current
        }
        
        let angle = self.calculateAngle(from: start, to: current)
//        print("🔍 [Track] Distance: \(String(format: "%.1f", distance)), Angle: \(String(format: "%.1f", angle))°")
        
        // Determine which ring the mouse is in based on distance
        let ringLevel = determineRingLevel(distance: distance)
        
//        print("🔍 [Track] RingLevel: \(ringLevel?.description ?? "nil"), Active: \(functionManager.activeRingLevel)")
        
        // Handle boundary crossing between rings
        handleBoundaryCrossing(distance: distance, currentRingLevel: ringLevel, angle: angle)
        
        // Only track hover if we're inside a ring
        guard let ringLevel = ringLevel else {
            print("⚠️ [Track] No ring level - skipping hover")
            return
        }
        
        //Don't update hover for rings that aren't the active ring
        guard ringLevel == functionManager.activeRingLevel else {
            print("⏭️ Skipping hover update for ring \(ringLevel) (active ring is \(functionManager.activeRingLevel))")
            return
        }

        // Get nodes for the current ring level
        guard ringLevel < functionManager.rings.count else { return }
        let nodes = functionManager.rings[ringLevel].nodes
        guard !nodes.isEmpty else { return }
        
        // Get the slice configuration for this ring
        let configs = functionManager.ringConfigurations
        guard ringLevel < configs.count else { return }
        let sliceConfig = configs[ringLevel].sliceConfig
        
        // Check if angle is within the slice (for partial slices)
        if !sliceConfig.isFullCircle {
            if !isAngleInSlice(angle, sliceConfig: sliceConfig) {
                // Mouse is outside the slice - don't update hover
                return
            }
        }
        
        let pieIndex = angleToIndex(angle, sliceConfig: sliceConfig)
        
        // Update if index or ring level changed
        if pieIndex != lastFunctionIndex || ringLevel != lastRingLevel {
            functionManager.hoverNode(ringLevel: ringLevel, index: pieIndex)
            lastFunctionIndex = pieIndex
            lastRingLevel = ringLevel
            onPieHover?(pieIndex)
        }
    }
    
    private func determineRingLevel(distance: CGFloat) -> Int? {
        // Use actual ring configurations from FunctionManager
        let configs = functionManager.ringConfigurations
        
        // Check each ring's boundary
        for config in configs {
            let ringOuterRadius = config.startRadius + config.thickness
            
            if distance <= ringOuterRadius {
                return config.level
            }
        }
        
        // If beyond all rings, treat as being in the active (outermost) ring
        if functionManager.rings.count > 0 {
//            print("🎯 Beyond all rings at distance \(distance), treating as active ring \(functionManager.activeRingLevel)")
            return functionManager.activeRingLevel
        }
        
        return nil
    }
    
    private func handleBoundaryCrossing(distance: CGFloat, currentRingLevel: Int?, angle: CGFloat) {
        let activeRingLevel = functionManager.activeRingLevel
        
        // Calculate the outer boundary of the active ring using actual config
        let configs = functionManager.ringConfigurations
        guard activeRingLevel < configs.count else { return }
        
        let activeRingConfig = configs[activeRingLevel]
        let activeRingOuterRadius = activeRingConfig.startRadius + activeRingConfig.thickness
        
        // Check if we're beyond the active ring's boundary
        if let currentRingLevel = currentRingLevel,
           currentRingLevel == activeRingLevel,
           distance > activeRingOuterRadius {
            
            // Get the slice configuration for the active ring
            let configs = functionManager.ringConfigurations
            guard activeRingLevel < configs.count else { return }
            let sliceConfig = configs[activeRingLevel].sliceConfig
            
            // Check if the angle is within a valid slice
            if sliceConfig.isFullCircle || isAngleInSlice(angle, sliceConfig: sliceConfig) {
                // Calculate which item we're hovering over
                let pieIndex = angleToIndex(angle, sliceConfig: sliceConfig)
                
                if pieIndex >= 0 {
                    let nodes = functionManager.rings[activeRingLevel].nodes
                    
                    if nodes.indices.contains(pieIndex) {
                        let node = nodes[pieIndex]
                        
                        // USE EXPLICIT INTERACTION MODEL
                        switch node.onBoundaryCross {
                        case .expand:
//                            print("🔵 Beyond boundary (\(distance) > \(activeRingOuterRadius)) - expanding '\(node.name)'")
                            functionManager.expandCategory(ringLevel: activeRingLevel, index: pieIndex)
                            
                            lastFunctionIndex = pieIndex
                            lastRingLevel = activeRingLevel
                            return
                        
                        case .navigateInto:  // NEW: Handle folder navigation on boundary cross
                            print("📂 Beyond boundary (\(distance) > \(activeRingOuterRadius)) - navigating into '\(node.name)'")
                            functionManager.navigateIntoFolder(ringLevel: activeRingLevel, index: pieIndex)
                            
                            lastFunctionIndex = pieIndex
                            lastRingLevel = activeRingLevel
                            return
                            
                        case .doNothing:
                            print("⚠️ Beyond boundary hovering '\(node.name)' - no auto-expand (use right-click)")
                            
                        case .execute:
                            print("⚠️ Beyond boundary hovering '\(node.name)' - would execute action (unusual for boundary cross)")
                            
                        case .executeKeepOpen:
                            print("⚠️ Beyond boundary hovering '\(node.name)' - would execute and keep open (unusual for boundary cross)")
                            
                        case .drag:
                            // Drag doesn't make sense for boundary crossing
                            print("⚠️ Beyond boundary hovering '\(node.name)' - draggable item (no auto-expand)")
                        }
                    }
                }
            }
        }
        
        // Check if mouse crossed inward
        if let currentRingLevel = currentRingLevel, currentRingLevel < activeRingLevel {
            print("🔴 Boundary crossed inward - collapsing to ring \(currentRingLevel)")
            functionManager.collapseToRing(level: currentRingLevel)
            return
        }
        
        // Mouse moved to different category in the same active ring level
        if let currentRingLevel = currentRingLevel, currentRingLevel == activeRingLevel, lastRingLevel == activeRingLevel {
            if let hoveredIndex = lastFunctionIndex {
                guard activeRingLevel < functionManager.rings.count else { return }
                let nodes = functionManager.rings[activeRingLevel].nodes
                
                if nodes.indices.contains(hoveredIndex) {
                    let node = nodes[hoveredIndex]
                    let currentSelectedIndex = functionManager.rings[activeRingLevel].selectedIndex
                    
                    // If hovering over a different category and there's an expanded ring above
                    // Check if this node wants to auto-expand or auto-navigate
                    if hoveredIndex != currentSelectedIndex && functionManager.rings.count > activeRingLevel + 1 {
                        switch node.onBoundaryCross {
                        case .expand:
                            print("🔄 Switching to category '\(node.name)'")
                            functionManager.expandCategory(ringLevel: activeRingLevel, index: hoveredIndex)
                        case .navigateInto:  // NEW: Handle switching folders
                            print("📂 Switching to folder '\(node.name)'")
                            functionManager.navigateIntoFolder(ringLevel: activeRingLevel, index: hoveredIndex)
                        case .doNothing, .execute, .executeKeepOpen, .drag:
                            // Don't switch if node doesn't want auto-expansion/navigation
                            break
                        }
                    }
                }
            }
        }
    }
    
    private func calculateAngle(from start: NSPoint, to current: NSPoint) -> CGFloat {
        let dx = current.x - start.x
        let dy = current.y - start.y

        let radians = atan2(dy, dx)
        var degrees = radians * (180 / .pi)

        degrees -= 90

        if degrees < 0 { degrees += 360 }

        degrees = (360 - degrees).truncatingRemainder(dividingBy: 360)

        degrees += mouseAngleOffset

        if degrees < 0 { degrees += 360 }
        if degrees >= 360 { degrees -= 360 }

        return degrees
    }
    
    private func angleToIndex(_ angle: CGFloat, sliceConfig: PieSliceConfig) -> Int {
        let configs = functionManager.ringConfigurations
        let ringLevel = functionManager.activeRingLevel
        guard ringLevel < configs.count else { return -1 }
        
        let totalCount = configs[ringLevel].nodes.count
        guard totalCount > 0 else { return -1 }
        
        let itemAngle = CGFloat(sliceConfig.itemAngle)
        let sliceStart = CGFloat(sliceConfig.startAngle)
        let sliceEnd = CGFloat(sliceConfig.endAngle)
        
        if sliceConfig.isFullCircle {
            // Normalize angles to 0-360 range
            var adjustedAngle = angle
            while adjustedAngle < 0 { adjustedAngle += 360 }
            while adjustedAngle >= 360 { adjustedAngle -= 360 }
            
            var normalizedStart = sliceStart
            while normalizedStart >= 360 { normalizedStart -= 360 }
            while normalizedStart < 0 { normalizedStart += 360 }
            
            // Calculate relative angle from start
            var relativeAngle = adjustedAngle - normalizedStart
            if relativeAngle < 0 { relativeAngle += 360 }
            
            let index = Int(relativeAngle / itemAngle) % totalCount
            return index
            
        } else {
            // Partial slice
            
            // Normalize angle to 0-360
            var normalizedAngle = angle
            while normalizedAngle < 0 { normalizedAngle += 360 }
            while normalizedAngle >= 360 { normalizedAngle -= 360 }
            
            if sliceConfig.direction == .counterClockwise {
                // Counter-clockwise: Items positioned from END going backwards
                // Normalize end angle
                var normalizedEnd = sliceEnd
                while normalizedEnd >= 360 { normalizedEnd -= 360 }
                while normalizedEnd < 0 { normalizedEnd += 360 }
                
                // Calculate how far back from the end we are
                var relativeAngle = normalizedEnd - normalizedAngle
                if relativeAngle < 0 { relativeAngle += 360 }
                
                // Convert to index (item 0 is closest to end, item N is furthest)
                let index = Int(relativeAngle / itemAngle)
                
                if index >= 0 && index < totalCount {
                    return index
                }
                
            } else {
                // Clockwise: Items positioned from START going forwards
                // Normalize start angle
                var normalizedStart = sliceStart
                while normalizedStart >= 360 { normalizedStart -= 360 }
                while normalizedStart < 0 { normalizedStart += 360 }
                
                // Calculate relative angle from start
                var relativeAngle = normalizedAngle - normalizedStart
                if relativeAngle < 0 { relativeAngle += 360 }
                
                let index = Int(relativeAngle / itemAngle)
                
                if index >= 0 && index < totalCount {
                    return index
                }
            }
        }

        return -1
    }
    private func isAngleInSlice(_ angle: Double, sliceConfig: PieSliceConfig) -> Bool {
        // Normalize all angles to 0-360 range
        let normalizedAngle = angle.truncatingRemainder(dividingBy: 360)
        let normalizedStart = sliceConfig.startAngle.truncatingRemainder(dividingBy: 360)
        let normalizedEnd = sliceConfig.endAngle.truncatingRemainder(dividingBy: 360)
        
        // Handle wrapping (when slice crosses 0°)
        if normalizedStart <= normalizedEnd {
            // Normal case: start < end (e.g., 90° to 180°)
            return normalizedAngle >= normalizedStart && normalizedAngle <= normalizedEnd
        } else {
            // Wrapped case: crosses 0° (e.g., 350° to 10°)
            return normalizedAngle >= normalizedStart || normalizedAngle <= normalizedEnd
        }
    }
}
