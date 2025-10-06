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
    private var lastRingLevel: Int?
    var onPieHover: ((Int?) -> Void)?
    private var functionManager: FunctionManager

    var mouseAngleOffset: CGFloat = 0
    
    // Ring configuration (must match CircularUIView)
    private let centerHoleRadius: CGFloat = 50
    private let ringThickness: CGFloat = 80
    private let ringMargin: CGFloat = 10
    
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
        
        // Handle boundary crossing based on distance
        handleBoundaryCrossing(distance: distance)
        
        // Always track the outermost visible ring
        let ringLevel = getOutermostVisibleRing()
        
        // Get the appropriate function list for this ring level
        let functions = functionsForRing(level: ringLevel)
        guard !functions.isEmpty else { return }
        
        let pieIndex = angleToIndex(angle, totalCount: functions.count)
        
        // Update if index or ring level changed
        if pieIndex != lastFunctionIndex || ringLevel != lastRingLevel {
            updateRingSelection(level: ringLevel, index: pieIndex)
            lastFunctionIndex = pieIndex
            lastRingLevel = ringLevel
            onPieHover?(pieIndex)
        }
    }
    
    private func handleBoundaryCrossing(distance: CGFloat) {
        let innerRingOuterRadius = centerHoleRadius + ringThickness
        
        let isOutsideInnerRing = distance > innerRingOuterRadius
        let isOuterRingVisible = functionManager.shouldShowOuterRing
        
        if isOutsideInnerRing && !isOuterRingVisible {
            // Mouse crossed outward - check if hovering over a category
            if let hoveredIndex = lastFunctionIndex {
                let innerNodes = functionManager.innerRingNodes
                if innerNodes.indices.contains(hoveredIndex) {
                    let node = innerNodes[hoveredIndex]
                    if node.isBranch {
                        // Expand to show this category's children
                        print("🔵 Boundary crossed outward over category '\(node.name)' - expanding")
                        functionManager.expandRing(at: hoveredIndex)
                    }
                }
            }
        } else if !isOutsideInnerRing && isOuterRingVisible {
            // Mouse crossed inward - collapse outer ring
            print("🔴 Boundary crossed inward - collapsing")
            functionManager.collapseRing()
        } else if isOutsideInnerRing && isOuterRingVisible {
            // Mouse is in outer ring area - check for category switching
            if let hoveredIndex = lastFunctionIndex, lastRingLevel == 0 {
                let innerNodes = functionManager.innerRingNodes
                if innerNodes.indices.contains(hoveredIndex) {
                    let node = innerNodes[hoveredIndex]
                    if node.isBranch && hoveredIndex != functionManager.selectedIndex {
                        // Different category - switch to it
                        print("🔄 Switching to category '\(node.name)'")
                        functionManager.expandRing(at: hoveredIndex)
                    }
                }
            }
        }
    }
    
    private func getOutermostVisibleRing() -> Int {
        // If outer ring is visible, track it (level 1)
        // Otherwise track inner ring (level 0)
        if functionManager.shouldShowOuterRing {
            return 1
        }
        return 0
    }
    
    private func functionsForRing(level: Int) -> [FunctionItem] {
        switch level {
        case 0:
            return functionManager.currentFunctionList
        case 1:
            return functionManager.outerRingNodes.map { node in
                FunctionItem(
                    id: node.id,
                    name: node.name,
                    icon: node.icon,
                    action: { node.action?() }
                )
            }
        default:
            return []
        }
    }
    
    private func updateRingSelection(level: Int, index: Int) {
        switch level {
        case 0:
            functionManager.selectFunction(at: index)
        case 1:
            functionManager.selectOuterFunction(at: index)
        default:
            break
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
