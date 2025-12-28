//
//  RingView+Geometry.swift
//  Jason
//
//  Created by Timothy Velberg on 04/12/2025.
//

import SwiftUI

// MARK: - Geometry & Angle Calculations

extension RingView {
    
    func updateSlice(for index: Int, totalCount: Int) {
        print("🔧 [updateSlice] Called with index=\(index), totalCount=\(totalCount)")
        print("   Previous state: previousIndex=\(previousIndex?.description ?? "nil"), rotationIndex=\(rotationIndex), previousTotalCount=\(previousTotalCount)")
        
        guard totalCount > 0 else {
            angleOffset = 0
            startAngle = .degrees(0)
            endAngle = .degrees(0)
            print("   ⚠️ totalCount is 0, resetting angles")
            return
        }
        
        let itemAngle = angleForItem(at: index)
        print("   📏 itemAngle for index \(index): \(itemAngle)°")
        
        if previousIndex == nil {
            // First selection - calculate center angle for this item
            let centerAngle = calculateCenterAngle(for: index)
            angleOffset = centerAngle
            startAngle = Angle(degrees: centerAngle - itemAngle / 2 - 90)
            endAngle = Angle(degrees: centerAngle + itemAngle / 2 - 90)
            
            print("   🆕 FIRST SELECTION:")
            print("      centerAngle=\(centerAngle)°")
            print("      angleOffset=\(angleOffset)°")
            print("      startAngle=\(startAngle.degrees)°, endAngle=\(endAngle.degrees)°")
            
            previousIndex = index
            previousTotalCount = totalCount
            rotationIndex = index
            return
        }
        
        // Also check if totalCount changed
        guard let prevIndex = previousIndex,
              index != prevIndex || totalCount != previousTotalCount else {
            print("   ⏭️ SKIPPING: index and totalCount unchanged (index=\(index), totalCount=\(totalCount))")
            return
        }
        
        // Check if totalCount changed even though index stayed the same
        if index == prevIndex && totalCount != previousTotalCount {
            print("   🔄 TOTALCOUNT CHANGED: Same index (\(index)) but count changed from \(previousTotalCount) to \(totalCount)")
            print("      Need to recalculate angles for new layout!")
        } else {
            print("   🔄 UPDATING SELECTION: from \(prevIndex) to \(index)")
        }
        
        var newRotationIndex: Int
        
        if sliceConfig.isFullCircle {
            let forwardSteps = (index - prevIndex + totalCount) % totalCount
            let backwardSteps = (prevIndex - index + totalCount) % totalCount
            
            if forwardSteps <= backwardSteps {
                newRotationIndex = rotationIndex + forwardSteps
                print("      Moving FORWARD: \(forwardSteps) steps, newRotationIndex=\(newRotationIndex)")
            } else {
                newRotationIndex = rotationIndex - backwardSteps
                print("      Moving BACKWARD: \(backwardSteps) steps, newRotationIndex=\(newRotationIndex)")
            }
        } else {
            newRotationIndex = index
            print("      Partial slice: newRotationIndex=\(newRotationIndex)")
        }
        
        // Calculate angle offset using rotationIndex for smooth wraparound animation
        let newAngleOffset: Double
        if sliceConfig.direction == .counterClockwise {
            let baseAngle = sliceConfig.endAngle
            newAngleOffset = cumulativeAngleAtRotationIndex(newRotationIndex, baseAngle: baseAngle, clockwise: false)
            print("      CCW: baseAngle=\(baseAngle)°, newAngleOffset=\(newAngleOffset)°")
        } else {
            let baseAngle = sliceConfig.startAngle
            newAngleOffset = cumulativeAngleAtRotationIndex(newRotationIndex, baseAngle: baseAngle, clockwise: true)
            print("      CW: baseAngle=\(baseAngle)°, newAngleOffset=\(newAngleOffset)°")
        }
        
        let newStartAngle = newAngleOffset - itemAngle / 2 - 90
        let newEndAngle = newAngleOffset + itemAngle / 2 - 90
        
        withAnimation(.easeOut(duration: 0.2)) {
            angleOffset = newAngleOffset
            startAngle = Angle(degrees: newStartAngle)
            endAngle = Angle(degrees: newEndAngle)
        }
        
        previousIndex = index
        previousTotalCount = totalCount
        rotationIndex = newRotationIndex
        
        print("   ✅ Update complete: previousIndex=\(previousIndex?.description ?? "nil"), previousTotalCount=\(previousTotalCount), rotationIndex=\(rotationIndex)")
    }

    /// Calculate the angle at a given rotationIndex (which can be negative or > totalCount for wraparound animation)
    func cumulativeAngleAtRotationIndex(_ rotIndex: Int, baseAngle: Double, clockwise: Bool) -> Double {
        let totalCount = nodes.count
        guard totalCount > 0 else { return baseAngle }
        
        // Check if we have variable angles
        guard let perItemAngles = sliceConfig.perItemAngles, perItemAngles.count == totalCount else {
            // Fallback to uniform angle calculation
            let itemAngle = sliceConfig.itemAngle
            if clockwise {
                return baseAngle + (Double(rotIndex) * itemAngle) + (itemAngle / 2)
            } else {
                return baseAngle - (Double(rotIndex) * itemAngle) - (itemAngle / 2)
            }
        }
        
        // Variable angles: need to calculate cumulative
        let actualIndex = ((rotIndex % totalCount) + totalCount) % totalCount
        let fullRotations = rotIndex >= 0 ? rotIndex / totalCount : (rotIndex - totalCount + 1) / totalCount
        
        // Calculate cumulative angle to actualIndex
        var cumulative: Double = 0
        for i in 0..<actualIndex {
            cumulative += perItemAngles[i]
        }
        
        // Add center offset for this item
        let itemAngle = perItemAngles[actualIndex]
        let centerOffset = cumulative + (itemAngle / 2)
        
        if clockwise {
            return baseAngle + centerOffset + (Double(fullRotations) * 360.0)
        } else {
            return baseAngle - centerOffset - (Double(fullRotations) * 360.0)
        }
    }
    
    func iconPosition(for index: Int) -> CGPoint {
        guard nodes.count > 0 else {
            return CGPoint(x: totalDiameter / 2, y: totalDiameter / 2)
        }
        
        // Use helper to get center angle (handles variable angles)
        let iconAngle = calculateCenterAngle(for: index)
        
        // Apply rotation offset for animation
        let node = nodes[index]
        let rotationOffset = iconRotationOffsets[node.id] ?? 0
        let finalAngle = iconAngle + rotationOffset
        
        let angleInRadians = (finalAngle - 90) * (.pi / 180)
        
        let center = CGPoint(x: totalDiameter / 2, y: totalDiameter / 2)
        let x = center.x + middleRadius * cos(angleInRadians)
        let y = center.y + middleRadius * sin(angleInRadians)
        
        return CGPoint(x: x, y: y)
    }
    
    func calculateCenterAngle(for index: Int) -> Double {
        guard nodes.count > 0 else { return 0 }
        
        let startAngle = cumulativeStartAngle(for: index)
        let itemAngle = angleForItem(at: index)
        
        // Return the center of this item's slice
        if sliceConfig.direction == .counterClockwise {
            return startAngle - (itemAngle / 2)
        } else {
            return startAngle + (itemAngle / 2)
        }
    }
    
    // MARK: - Variable Angle Helpers

    /// Get the angle size for a specific item (supports variable angles)
    func angleForItem(at index: Int) -> Double {
        if let perItemAngles = sliceConfig.perItemAngles,
           index < perItemAngles.count {
            let angle = perItemAngles[index]
            return angle
        }
        let fallback = sliceConfig.itemAngle
        return fallback
    }

    /// Calculate the cumulative start angle for an item (where its slice begins)
    func cumulativeStartAngle(for index: Int) -> Double {
        let baseAngle = sliceConfig.direction == .counterClockwise
            ? sliceConfig.endAngle
            : sliceConfig.startAngle
        
        guard let perItemAngles = sliceConfig.perItemAngles else {
            // Uniform angles: simple multiplication
            let offset = sliceConfig.itemAngle * Double(index)
            return sliceConfig.direction == .counterClockwise
                ? baseAngle - offset
                : baseAngle + offset
        }
        
        // Variable angles: sum all previous angles
        var cumulativeAngle: Double = 0
        for i in 0..<index {
            if i < perItemAngles.count {
                cumulativeAngle += perItemAngles[i]
            }
        }
        
        return sliceConfig.direction == .counterClockwise
            ? baseAngle - cumulativeAngle
            : baseAngle + cumulativeAngle
    }
}
