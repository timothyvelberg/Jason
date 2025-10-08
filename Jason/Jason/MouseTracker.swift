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
        
        let pieIndex = angleToIndex(angle, totalCount: nodes.count)
        
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
    
    private func angleToIndex(_ angle: CGFloat, totalCount: Int) -> Int {
        guard totalCount > 0 else { return -1 }
        
        let sliceSize = 360.0 / CGFloat(totalCount)
        let halfSlice = sliceSize / 2

        var adjustedAngle = angle.truncatingRemainder(dividingBy: 360)
        if adjustedAngle < 0 { adjustedAngle += 360 }

        // Shift forward by half a slice for proper alignment
        adjustedAngle += sliceSize - halfSlice
        if adjustedAngle >= 360 { adjustedAngle -= 360 }
        
        for index in 0..<totalCount {
            let startAngle = CGFloat(index) * sliceSize
            let endAngle = startAngle + sliceSize

            if adjustedAngle >= startAngle && adjustedAngle < endAngle {
                return index
            }
        }

        return -1
    }
}
