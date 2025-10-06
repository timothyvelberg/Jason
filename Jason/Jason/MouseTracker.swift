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
                self.trackMousePosition(initial: false)
            }
        }
    }
    
    func stopTrackingMouse() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        trackingStartPoint = nil
        print("Mouse tracking stopped")
    }
    
    private var currentFunctions: [FunctionItem] {
        functionManager.currentFunctionList
    }

    private func trackMousePosition(initial: Bool) {
        guard let start = trackingStartPoint else { return }

        let current = NSEvent.mouseLocation
        let angle = self.calculateAngle(from: start, to: current)
        let pieIndex = self.angleToIndex(angle)
        
        if initial || pieIndex != lastFunctionIndex {
            functionManager.selectFunction(at: pieIndex)
            lastFunctionIndex = pieIndex
            if let pieIndex = lastFunctionIndex {
                onPieHover?(pieIndex)
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
    
    private var sliceSize: CGFloat {
        let total = currentFunctions.count
        return total > 0 ? 360.0 / CGFloat(total) : 0
    }
    
    private func angleToIndex(_ angle: CGFloat) -> Int {
        let totalFunctions = currentFunctions.count
        guard totalFunctions > 0 else { return -1 }
        let halfSlice = sliceSize / 2

        var adjustedAngle = angle.truncatingRemainder(dividingBy: 360)
        if adjustedAngle < 0 { adjustedAngle += 360 }

        // FIXED: Changed from "halfSlice + sliceSize" to just "halfSlice"
        // This removes the extra full-slice offset that was causing selection to be one slice ahead
        adjustedAngle += halfSlice
        if adjustedAngle >= 360 { adjustedAngle -= 360 }

        for index in 0..<totalFunctions {
            let startAngle = CGFloat(index) * sliceSize
            let endAngle = startAngle + sliceSize

            if adjustedAngle >= startAngle && adjustedAngle < endAngle {
                return index
            }
        }

        return -1
    }
}
