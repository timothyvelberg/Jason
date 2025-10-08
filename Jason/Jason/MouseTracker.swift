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
    var onPieHover: ((Int?) -> Void)?
    private var functionManager: FunctionManager

    var mouseAngleOffset: CGFloat = 0
    
    // Ring configuration (must match CircularUIView and FunctionManager)
    private let centerHoleRadius: CGFloat = 50
    private let ringThickness: CGFloat = 80
    private let ringMargin: CGFloat = 2
    
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

    private func trackMousePosition(distance: CGFloat) {
        guard let start = trackingStartPoint else { return }

        let current = NSEvent.mouseLocation
        let angle = self.calculateAngle(from: start, to: current)
        
        // Determine which ring the mouse is in based on distance
        let ringLevel = determineRingLevel(distance: distance)
        
        // Debug: Print distance and detected ring level
        if ringLevel == nil {
            print("📏 Distance: \(distance), Ring Level: nil (OUTSIDE)")
        }
        
        // Handle boundary crossing between rings
        handleBoundaryCrossing(distance: distance, currentRingLevel: ringLevel)
        
        // Only track hover if we're inside a ring
        guard let ringLevel = ringLevel else { return }
        
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
        var currentRadius = centerHoleRadius
        
        for ringLevel in 0..<functionManager.rings.count {
            let ringOuterRadius = currentRadius + ringThickness
            
            if distance <= ringOuterRadius {
                return ringLevel
            }
            
            currentRadius = ringOuterRadius + ringMargin
        }
        
        // If beyond all rings, return nil to indicate we're outside
        // For ring 0: boundary is at 50 + 80 = 130 pixels
        let ring0Boundary = centerHoleRadius + ringThickness
        print("🎯 Mouse distance \(distance) > ring 0 boundary \(ring0Boundary) - OUTSIDE ALL RINGS")
        return nil
    }
    
    private func handleBoundaryCrossing(distance: CGFloat, currentRingLevel: Int?) {
        let activeRingLevel = functionManager.activeRingLevel
        
        // Calculate the outer boundary of the active ring
        var activeRingOuterRadius = centerHoleRadius
        for i in 0...activeRingLevel {
            activeRingOuterRadius += ringThickness
            if i < activeRingLevel {
                activeRingOuterRadius += ringMargin
            }
        }
        
        // Debug: Print boundary info
        if currentRingLevel == nil && distance > activeRingOuterRadius {
            print("🔍 Outside all rings: distance=\(distance), boundary=\(activeRingOuterRadius), lastIndex=\(String(describing: lastFunctionIndex)), lastLevel=\(String(describing: lastRingLevel))")
        }
        
        // Check if mouse crossed outward beyond the active ring
        if currentRingLevel == nil && distance > activeRingOuterRadius {
            // Mouse is outside all rings - check if we should expand
            if let hoveredIndex = lastFunctionIndex, let lastLevel = lastRingLevel, lastLevel == activeRingLevel {
                guard activeRingLevel < functionManager.rings.count else { return }
                let nodes = functionManager.rings[activeRingLevel].nodes
                
                if nodes.indices.contains(hoveredIndex) {
                    let node = nodes[hoveredIndex]
                    if node.isBranch {
                        print("🔵 Boundary crossed outward over category '\(node.name)' - expanding")
                        functionManager.expandCategory(ringLevel: activeRingLevel, index: hoveredIndex)
                        return
                    } else {
                        print("⚠️ Hovering over leaf node '\(node.name)', not expanding")
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
                    if node.isBranch && hoveredIndex != currentSelectedIndex && functionManager.rings.count > activeRingLevel + 1 {
                        print("🔄 Switching to category '\(node.name)'")
                        functionManager.expandCategory(ringLevel: activeRingLevel, index: hoveredIndex)
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
        
        if sliceConfig.isFullCircle {
            // Full circle: items centered at 22.5°, 67.5°, etc.
            // Zones should be: [0° to 45°], [45° to 90°], etc.
            
            var adjustedAngle = angle
            if adjustedAngle < 0 { adjustedAngle += 360 }
            
            // Don't add any offset - zones start at 0° boundaries
            let index = Int(adjustedAngle / itemAngle) % totalCount
            return index
        } else {
            // Partial slice: items centered in their slices
            let sliceStart = CGFloat(sliceConfig.startAngle)
            
            var normalizedAngle = angle
            if normalizedAngle < 0 { normalizedAngle += 360 }
            
            var relativeAngle = normalizedAngle - sliceStart
            if relativeAngle < 0 { relativeAngle += 360 }
            if relativeAngle >= 360 { relativeAngle -= 360 }
            
            let index = Int(relativeAngle / itemAngle)
            
            if index >= 0 && index < totalCount {
                return index
            }
        }

        return -1
    }
    
    private func isAngleInSlice(_ angle: CGFloat, sliceConfig: PieSliceConfig) -> Bool {
        if sliceConfig.isFullCircle {
            return true  // Full circle always contains any angle
        }
        
        let sliceStart = CGFloat(sliceConfig.startAngle)
        let sliceEnd = CGFloat(sliceConfig.endAngle)
        let totalAngle = CGFloat(sliceConfig.totalAngle)
        
        // Normalize angle to 0-360
        var normalizedAngle = angle
        while normalizedAngle < 0 { normalizedAngle += 360 }
        while normalizedAngle >= 360 { normalizedAngle -= 360 }
        
        // Handle wrap-around case (e.g., slice from 350° to 10°)
        if sliceEnd < sliceStart {
            // Slice wraps around 0°
            return normalizedAngle >= sliceStart || normalizedAngle <= sliceEnd
        } else {
            // Normal case
            return normalizedAngle >= sliceStart && normalizedAngle <= sliceEnd
        }
    }
}
