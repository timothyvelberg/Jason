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
    private var isPausedUntilMovement = false
    private var lastMouseLocation: NSPoint?
    internal var ringLevelAtPause: Int?
    private var lastExecutedNodeId: String?
    private var wasOutsideBoundary: Bool = false
    
    weak var inputCoordinator: InputCoordinator?
    weak var circularUIManager: CircularUIManager?
    
    var onPieHover: ((Int?) -> Void)?
    var onCollapse: (() -> Void)?
    var onReturnedInsideBoundary: (() -> Void)?
    var onExecuteAction: (() -> Void)?
    var isMouseInPanel: (() -> Bool)?
    private var functionManager: FunctionManager

    var mouseAngleOffset: CGFloat = 0
    var onExpandToPanel: ((_ node: FunctionNode, _ angle: Double, _ ringCenter: CGPoint, _ ringOuterRadius: CGFloat) -> Void)?

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
        isPausedForDrag = false
        print("Mouse tracking stopped")
    }
    
    func pauseUntilMovement() {
        isPausedUntilMovement = true
        lastMouseLocation = NSEvent.mouseLocation
        ringLevelAtPause = lastRingLevel  // Remember which ring we clicked in
        print("⏸️ [MouseTracker] Paused tracking - clicked in ring level: \(ringLevelAtPause ?? -1)")
    }
    
    private var isPausedForDrag = false

    func pauseForDrag() {
        isPausedForDrag = true
        print("⏸️ [MouseTracker] Paused for drag operation")
    }

    func resumeFromDrag() {
        guard isPausedForDrag else { return }
        isPausedForDrag = false
        print("▶️ [MouseTracker] Resumed from drag")
    }
    
    func resumeTracking() {
        isPausedUntilMovement = false
        lastMouseLocation = NSEvent.mouseLocation
        print("▶️ [MouseTracker] Resumed tracking")
    }

    private func trackMousePosition(distance: CGFloat) {
        
        guard let start = trackingStartPoint else { return }

        let current = NSEvent.mouseLocation
        
        // Report movement to InputCoordinator (may switch from keyboard to mouse mode)
        if let coordinator = inputCoordinator {
            coordinator.handleMouseMoved(to: current)
            
            // If still in keyboard mode after reporting, don't process
            if !coordinator.isMouseTrackingEnabled() {
                return
            }
        }
        
        // Skip ALL tracking if mouse is inside a panel
        if let inPanel = isMouseInPanel, inPanel() {
            return
        }
        
        //Check if paused for drag FIRST (don't auto-resume)
        if isPausedForDrag {
            return  // Stay paused until explicitly resumed
        }
        
        // Check if paused and if mouse moved enough to resume
        if isPausedUntilMovement {
            if let last = lastMouseLocation {
                let moved = abs(current.x - last.x) > 5 || abs(current.y - last.y) > 5  // Increased threshold
                if moved {
                    isPausedUntilMovement = false
                    print("▶️ [MouseTracker] Resumed tracking after mouse movement")
                    lastMouseLocation = current  // Update now that we resumed
                } else {
                    // Still paused, don't track and DON'T update lastMouseLocation
                    return
                }
            } else {
                // No last position stored, resume immediately
                isPausedUntilMovement = false
                lastMouseLocation = current
            }
        } else {
                    // Update last position only when NOT paused
                    lastMouseLocation = current
                }
                
                // Check if mouse is in close zone (center of donut)
                if distance < FunctionManager.closeZoneRadius {
                    // Only show close button if we've left the zone at least once
                    if let circularUI = circularUIManager, circularUI.hasLeftCloseZone {
                        circularUI.isInCloseZone = true
                    }
                    
                    // Clear selection when in close zone
                    if lastFunctionIndex != nil || lastRingLevel != nil {
                        print("🎯 [Track] In close zone (distance: \(String(format: "%.1f", distance))) - clearing selection")
                        lastFunctionIndex = nil
                        lastRingLevel = nil
                        onPieHover?(nil)
                    }
                    return
                } else {
                    // Outside close zone - mark that we've left and update state
                    if let circularUI = circularUIManager {
                        circularUI.hasLeftCloseZone = true
                        circularUI.isInCloseZone = false
                    }
                }
                
                let angle = self.calculateAngle(from: start, to: current)
        
        // Determine which ring the mouse is in based on distance
        let ringLevel = determineRingLevel(distance: distance)
    
        // Handle boundary crossing between rings
        handleBoundaryCrossing(distance: distance, currentRingLevel: ringLevel, angle: angle)
        
        // Only track hover if we're inside a ring
        guard let ringLevel = ringLevel else {
            print("⚠️ [Track] No ring level - skipping hover")
            return
        }
        
        //Don't update hover for rings that aren't the active ring
        guard ringLevel == functionManager.activeRingLevel else {
            print("Skipping hover update for ring \(ringLevel) (active ring is \(functionManager.activeRingLevel))")
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
        
        
        // Track boundary crossing for panel dismissal
        let isOutside = distance > activeRingOuterRadius
        if wasOutsideBoundary && !isOutside {
            // Just crossed back inside
            onReturnedInsideBoundary?()
        }
        wasOutsideBoundary = isOutside
        
        if let currentRingLevel = currentRingLevel,
           currentRingLevel == activeRingLevel,
           distance <= activeRingOuterRadius {
            lastExecutedNodeId = nil
        }
        
        // Check if active ring was opened by click
        let activeRingOpenedByClick = functionManager.rings[activeRingLevel].openedByClick
        
        
        // Check if mouse moved FORWARD into the click-opened ring
        // Once you move into it, apply regular boundary rules from then on
        if activeRingOpenedByClick, let pauseLevel = ringLevelAtPause {
            if let currentRingLevel = currentRingLevel, currentRingLevel == activeRingLevel, activeRingLevel > pauseLevel {
                // Moved forward from ring 2 into ring 3 - clear click protection
                print("➡️ Moved forward from ring \(pauseLevel) into ring \(currentRingLevel) - enabling regular boundary rules")
                ringLevelAtPause = nil
                // Note: Don't return, let the rest of the boundary logic handle it
            }
        }
        
        // Check if we're beyond the active ring's boundary
        if let currentRingLevel = currentRingLevel,
           currentRingLevel == activeRingLevel,
           distance > activeRingOuterRadius {
            
            // Only auto-expand if the ring was NOT opened by click OR we've moved into it
            if !activeRingOpenedByClick || ringLevelAtPause == nil {
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
                            switch node.onBoundaryCross.base {
                                
                            case .expand:
                                // Check display mode preference
                                if node.childDisplayMode == .panel {
                                    // Debounce: only trigger once per node
                                    if lastExecutedNodeId != node.id {
                                        if let center = trackingStartPoint {
                                            print("📋 Beyond boundary - expanding '\(node.name)' to panel")
                                            onExpandToPanel?(node, Double(angle), center, activeRingOuterRadius)
                                        }
                                        lastExecutedNodeId = node.id
                                    }
                                    
                                    // Always update ring hover state (keeps highlight in sync with mouse angle)
                                    if pieIndex != lastFunctionIndex || activeRingLevel != lastRingLevel {
                                        functionManager.hoverNode(ringLevel: activeRingLevel, index: pieIndex)
                                        onPieHover?(pieIndex)
                                    }
                                    
                                    lastFunctionIndex = pieIndex
                                    lastRingLevel = activeRingLevel
                                    return
                                }
                                
                                // Default: expand as ring
                                functionManager.expandCategory(ringLevel: activeRingLevel, index: pieIndex)
                                lastFunctionIndex = pieIndex
                                lastRingLevel = activeRingLevel
                                return

                            case .navigateInto:
                                // Check display mode preference
                                if node.childDisplayMode == .panel {
                                    // Debounce: only trigger once per node
                                    if lastExecutedNodeId != node.id {
                                        if let center = trackingStartPoint {
                                            print("📋 Beyond boundary - navigating '\(node.name)' to panel")
                                            onExpandToPanel?(node, Double(angle), center, activeRingOuterRadius)
                                        }
                                        lastExecutedNodeId = node.id
                                    }
                                    
                                    // Always update ring hover state (keeps highlight in sync with mouse angle)
                                    if pieIndex != lastFunctionIndex || activeRingLevel != lastRingLevel {
                                        functionManager.hoverNode(ringLevel: activeRingLevel, index: pieIndex)
                                        onPieHover?(pieIndex)
                                    }
                                    
                                    lastFunctionIndex = pieIndex
                                    lastRingLevel = activeRingLevel
                                    return
                                }
                                
                                // Default: navigate in ring
                                print("📂 Beyond boundary - navigating into '\(node.name)'")
                                functionManager.navigateIntoFolder(ringLevel: activeRingLevel, index: pieIndex)
                                lastFunctionIndex = pieIndex
                                lastRingLevel = activeRingLevel
                                return
                                
                            case .launchRing(let configId):
                                print("🎯 [BoundaryCross] Launching ring config \(configId)")
                                DispatchQueue.main.async {
                                    CircularUIInstanceManager.shared.show(configId: configId)
                                }
                                return
                                
                            case .doNothing:
                                return
//                                print("⚠️ Beyond boundary hovering '\(node.name)' - no auto-expand (use right-click)")

                            case .execute(let action):
                                // Only execute once per node (debounce)
                                if lastExecutedNodeId != node.id {
                                    print("🎯 Beyond boundary - executing '\(node.name)'")
                                    action()
                                    lastExecutedNodeId = node.id
                                    lastFunctionIndex = pieIndex
                                    lastRingLevel = activeRingLevel
                                    
                                    onExecuteAction?()
                                }
                                return
                                
                            case .executeKeepOpen(let action):
                                // Only execute once per node (debounce)
                                if lastExecutedNodeId != node.id {
                                    print("🎯 Beyond boundary - executing '\(node.name)' (keeping UI open)")
                                    action()
                                    lastExecutedNodeId = node.id
                                    lastFunctionIndex = pieIndex
                                    lastRingLevel = activeRingLevel
                                }
                            case .drag:
                                print("⚠️ Beyond boundary hovering '\(node.name)' - draggable item (no auto-expand)")
                            }
                        }
                    }
                }
            } else {
                print("🔒 Active ring was opened by click - not auto-expanding beyond boundary")
            }
        }
        
        // Check if mouse crossed inward to a parent ring
        if let currentRingLevel = currentRingLevel, currentRingLevel < activeRingLevel {
            // If active ring was opened by click
            if activeRingOpenedByClick {
                if let pauseLevel = ringLevelAtPause {
                    if currentRingLevel < pauseLevel {
                        // Moved backward past where we clicked - collapse
                        print("🔴 Click-opened ring - moved backward from ring \(pauseLevel) to ring \(currentRingLevel) - collapsing")
                        functionManager.collapseToRing(level: currentRingLevel)
                        onCollapse?()
                        ringLevelAtPause = nil  // Reset
                        return
                    } else if currentRingLevel == pauseLevel {
                        // Still in the ring where we clicked - keep open
                        print("✅ Click-opened ring - staying in ring \(currentRingLevel) (clicked at \(pauseLevel)) - keeping open")
                        return
                    } else {
                        // currentRingLevel > pauseLevel - shouldn't happen here but handle it
                        print("⚠️ Unexpected: current ring \(currentRingLevel) > pause level \(pauseLevel) in inward check")
                        return
                    }
                } else {
                    // No pause level recorded - apply regular boundary rules
                    print("🔴 Click-opened ring (no pause level) - collapsing to ring \(currentRingLevel)")
                    functionManager.collapseToRing(level: currentRingLevel)
                    onCollapse?()
                    return
                }
            } else {
                // Not click-opened - normal boundary crossing behavior
                print("🔴 Boundary crossed inward - collapsing to ring \(currentRingLevel)")
                functionManager.collapseToRing(level: currentRingLevel)
                onCollapse?()
                return
            }
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
                        switch node.onBoundaryCross.base {
                        
                        case .expand:
                            print("🔄 Switching to category '\(node.name)'")
                            functionManager.expandCategory(ringLevel: activeRingLevel, index: hoveredIndex)
                        
                        case .launchRing(let configId):
                            print("🎯 [BoundaryCross-Category] Launching ring config \(configId)")
                            DispatchQueue.main.async {
                                CircularUIInstanceManager.shared.show(configId: configId)
                            }
                            
                        case .navigateInto:
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
        
        // Check if we have variable angles
        if let perItemAngles = sliceConfig.perItemAngles, perItemAngles.count == totalCount {
            // VARIABLE ANGLES: Check cumulative ranges
            return angleToIndexVariable(angle, sliceConfig: sliceConfig, perItemAngles: perItemAngles, totalCount: totalCount)
        } else {
            // UNIFORM ANGLES: Use existing logic
            return angleToIndexUniform(angle, sliceConfig: sliceConfig, totalCount: totalCount)
        }
    }

    /// Handle variable angle selection (new logic)
    private func angleToIndexVariable(_ angle: CGFloat, sliceConfig: PieSliceConfig, perItemAngles: [Double], totalCount: Int) -> Int {
        // Normalize angle to 0-360 range
        var normalizedAngle = angle
        while normalizedAngle < 0 { normalizedAngle += 360 }
        while normalizedAngle >= 360 { normalizedAngle -= 360 }
        
        let sliceStart = CGFloat(sliceConfig.startAngle)
        let sliceEnd = CGFloat(sliceConfig.endAngle)
        
        if sliceConfig.isFullCircle {
            // Full circle with variable angles
            var normalizedStart = sliceStart
            while normalizedStart >= 360 { normalizedStart -= 360 }
            while normalizedStart < 0 { normalizedStart += 360 }
            
            // Calculate relative angle from start
            var relativeAngle = normalizedAngle - normalizedStart
            if relativeAngle < 0 { relativeAngle += 360 }
            
            // Find which item this angle falls within
            var cumulativeAngle: CGFloat = 0
            for (index, itemAngle) in perItemAngles.enumerated() {
                let itemEnd = cumulativeAngle + CGFloat(itemAngle)
                if relativeAngle >= cumulativeAngle && relativeAngle < itemEnd {
                    return index
                }
                cumulativeAngle = itemEnd
            }
            
            // Edge case: very close to 360°, return last item
            return totalCount - 1
            
        } else {
            // Partial slice with variable angles
            if sliceConfig.direction == .counterClockwise {
                // Counter-clockwise: Items positioned from END going backwards
                var normalizedEnd = sliceEnd
                while normalizedEnd >= 360 { normalizedEnd -= 360 }
                while normalizedEnd < 0 { normalizedEnd += 360 }
                
                // Calculate how far back from the end we are
                var relativeAngle = normalizedEnd - normalizedAngle
                if relativeAngle < 0 { relativeAngle += 360 }
                
                // Find which item this angle falls within
                var cumulativeAngle: CGFloat = 0
                for (index, itemAngle) in perItemAngles.enumerated() {
                    let itemEnd = cumulativeAngle + CGFloat(itemAngle)
                    if relativeAngle >= cumulativeAngle && relativeAngle < itemEnd {
                        return index
                    }
                    cumulativeAngle = itemEnd
                }
                
            } else {
                // Clockwise: Items positioned from START going forwards
                var normalizedStart = sliceStart
                while normalizedStart >= 360 { normalizedStart -= 360 }
                while normalizedStart < 0 { normalizedStart += 360 }
                
                // Calculate relative angle from start
                var relativeAngle = normalizedAngle - normalizedStart
                if relativeAngle < 0 { relativeAngle += 360 }
                
                // Find which item this angle falls within
                var cumulativeAngle: CGFloat = 0
                for (index, itemAngle) in perItemAngles.enumerated() {
                    let itemEnd = cumulativeAngle + CGFloat(itemAngle)
                    if relativeAngle >= cumulativeAngle && relativeAngle < itemEnd {
                        return index
                    }
                    cumulativeAngle = itemEnd
                }
            }
        }
        
        return -1
    }

    /// Handle uniform angle selection (existing logic)
    private func angleToIndexUniform(_ angle: CGFloat, sliceConfig: PieSliceConfig, totalCount: Int) -> Int {
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
                var normalizedEnd = sliceEnd
                while normalizedEnd >= 360 { normalizedEnd -= 360 }
                while normalizedEnd < 0 { normalizedEnd += 360 }
                
                // Calculate how far back from the end we are
                var relativeAngle = normalizedEnd - normalizedAngle
                if relativeAngle < 0 { relativeAngle += 360 }
                
                // Convert to index
                let index = Int(relativeAngle / itemAngle)
                
                if index >= 0 && index < totalCount {
                    return index
                }
                
            } else {
                // Clockwise: Items positioned from START going forwards
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
        // Normalize all angles to 0-360 range (handle negatives properly!)
        var normalizedAngle = angle.truncatingRemainder(dividingBy: 360)
        if normalizedAngle < 0 { normalizedAngle += 360 }
        
        var normalizedStart = sliceConfig.startAngle.truncatingRemainder(dividingBy: 360)
        if normalizedStart < 0 { normalizedStart += 360 }
        
        var normalizedEnd = sliceConfig.endAngle.truncatingRemainder(dividingBy: 360)
        if normalizedEnd < 0 { normalizedEnd += 360 }
        
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
