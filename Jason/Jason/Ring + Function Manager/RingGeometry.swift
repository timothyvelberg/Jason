//
//  RingGeometry.swift
//  Jason
//
//  Created by Timothy Velberg on 29/11/2025.
//

import Foundation

/// Geometry utilities for ring hit testing and angle calculations
enum RingGeometry {
    
    /// Calculate distance from center to position
    static func calculateDistance(from center: CGPoint, to position: CGPoint) -> CGFloat {
        let dx = position.x - center.x
        let dy = position.y - center.y
        return hypot(dx, dy)
    }
    
    /// Calculate angle from center to position (in degrees, 0° = top, clockwise)
    static func calculateAngle(from center: CGPoint, to position: CGPoint) -> Double {
        let dx = position.x - center.x
        let dy = position.y - center.y
        
        let radians = atan2(dy, dx)
        var degrees = radians * (180 / .pi)
        
        // Adjust so 0° is at top (not right)
        degrees -= 90
        
        // Normalize to 0-360 range
        if degrees < 0 { degrees += 360 }
        
        // Flip direction (screen coordinates are flipped)
        degrees = (360 - degrees).truncatingRemainder(dividingBy: 360)
        
        return degrees
    }
    
    /// Check if angle is within a slice configuration
    static func isAngleInSlice(_ angle: Double, sliceConfig: PieSliceConfig) -> Bool {
        // Normalize all angles to 0-360 range
        var normalizedAngle = angle.truncatingRemainder(dividingBy: 360)
        if normalizedAngle < 0 { normalizedAngle += 360 }
        
        var normalizedStart = sliceConfig.startAngle.truncatingRemainder(dividingBy: 360)
        if normalizedStart < 0 { normalizedStart += 360 }
        
        var normalizedEnd = sliceConfig.endAngle.truncatingRemainder(dividingBy: 360)
        if normalizedEnd < 0 { normalizedEnd += 360 }
        
        // Handle wrapping (when slice crosses 0°)
        if normalizedStart <= normalizedEnd {
            // Normal case: start < end
            return normalizedAngle >= normalizedStart && normalizedAngle <= normalizedEnd
        } else {
            // Wrapped case: crosses 0°
            return normalizedAngle >= normalizedStart || normalizedAngle <= normalizedEnd
        }
    }
    
    /// Calculate which item index an angle corresponds to within a slice
    static func getItemIndex(for angle: Double, sliceConfig: PieSliceConfig, itemCount: Int) -> Int {
        guard itemCount > 0 else { return -1 }
        
        let itemAngle = sliceConfig.itemAngle
        let sliceStart = sliceConfig.startAngle
        let sliceEnd = sliceConfig.endAngle
        
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
            
            let index = Int(relativeAngle / itemAngle) % itemCount
            return index
            
        } else {
            // Partial slice
            var normalizedAngle = angle
            while normalizedAngle < 0 { normalizedAngle += 360 }
            while normalizedAngle >= 360 { normalizedAngle -= 360 }
            
            if sliceConfig.direction == .counterClockwise {
                // Counter-clockwise: Items positioned from END going backwards
                var normalizedEnd = sliceEnd
                while normalizedEnd >= 360 { normalizedEnd -= 360 }
                while normalizedEnd < 0 { normalizedEnd += 360 }
                
                var relativeAngle = normalizedEnd - normalizedAngle
                if relativeAngle < 0 { relativeAngle += 360 }
                
                let index = Int(relativeAngle / itemAngle)
                
                if index >= 0 && index < itemCount {
                    return index
                }
                
            } else {
                // Clockwise: Items positioned from START going forwards
                var normalizedStart = sliceStart
                while normalizedStart >= 360 { normalizedStart -= 360 }
                while normalizedStart < 0 { normalizedStart += 360 }
                
                var relativeAngle = normalizedAngle - normalizedStart
                if relativeAngle < 0 { relativeAngle += 360 }
                
                let index = Int(relativeAngle / itemAngle)
                
                if index >= 0 && index < itemCount {
                    return index
                }
            }
        }
        
        return -1
    }
}
