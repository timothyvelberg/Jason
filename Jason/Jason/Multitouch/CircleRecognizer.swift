//
//  CircleRecognizer.swift
//  Jason
//
//  Recognizes circular gestures on the trackpad
//

import Foundation

/// Recognizes single-finger circular gestures
class CircleRecognizer: GestureRecognizer {
    
    // MARK: - Protocol Properties
    
    let identifier = "circle"
    var isEnabled: Bool = true
    var onGesture: ((GestureEvent) -> Void)?
    
    // MARK: - Configuration
    
    struct Config {
        /// Minimum points needed to analyze a path
        var minPoints: Int = 10
        
        /// Maximum radius variance to be considered circular (lower = stricter)
        var maxRadiusVariance: Float = 0.01
        
        /// Minimum angle traveled (in full circles, e.g., 0.75 = 270°)
        var minCircles: Float = 0.75
        
        /// Maximum closure gap as ratio of radius (lower = must end near start)
        var maxClosureRatio: Float = 0.5
        
        /// Minimum radius to filter out tiny accidental circles
        var minRadius: Float = 0.03
        
        /// Maximum duration for a circle gesture (seconds)
        var maxDuration: Double = 2.0
    }
    
    /// Called when calibration completes with the new config
    var onCalibrationComplete: ((Config) -> Void)?
    
    var config = Config()
    
    // MARK: - Path Tracking
    
    private struct PathPoint {
        let x: Float
        let y: Float
        let timestamp: Double
        
        func angle(from center: (x: Float, y: Float)) -> Float {
            return atan2(y - center.y, x - center.x)
        }
    }
    
    /// Points collected during current finger movement
    private var currentPath: [PathPoint] = []
    
    /// Whether we're currently tracking a finger
    private var isTracking: Bool = false
    
    /// The finger identifier we're tracking
    private var trackedFingerId: Int? = nil
    
    /// Timestamp when tracking started
    private var trackingStartTime: Double = 0
    
    // MARK: - Debug Logging
    
    var debugLogging: Bool = false
    
    // MARK: - Calibration
    
    private var isCalibrating: Bool = false
    private var calibrationSamples: [CalibrationSample] = []
    private let calibrationSampleCount: Int = 5
    
    struct CalibrationSample {
        let radiusVariance: Float
        let fullCircles: Float
        let avgRadius: Float
        let duration: Double
        let closureDistance: Float
    }
    
    /// Start calibration mode - next 5 circles will be captured as samples
    func startCalibration() {
        isCalibrating = true
        calibrationSamples.removeAll()
        print("")
        print("🎯 ═══════════════════════════════════════════════════════════")
        print("🎯 CIRCLE CALIBRATION STARTED")
        print("🎯 Draw \(calibrationSampleCount) circles. Progress: 0/\(calibrationSampleCount)")
        print("🎯 ═══════════════════════════════════════════════════════════")
        print("")
    }
    
    /// Cancel calibration
    func cancelCalibration() {
        isCalibrating = false
        calibrationSamples.removeAll()
        print("🎯 Calibration cancelled")
    }
    
    /// Check if currently calibrating
    var calibrating: Bool { isCalibrating }
    
    // MARK: - Protocol Methods
    
    func processTouchFrame(_ frame: TouchFrame) {
        guard isEnabled else { return }
        
        let activeTouches = frame.touches.filter { $0.state.isActive }
        
        // No fingers - end tracking if we were tracking
        if activeTouches.isEmpty {
            if isTracking {
                endTracking()
            }
            return
        }
        
        // Only track single finger gestures
        if activeTouches.count == 1 {
            let touch = activeTouches[0]
            
            // Finger down - start tracking
            if touch.state == .makeTouch || (!isTracking && touch.state == .touching) {
                startTracking(touch: touch)
            }
            // Finger moving - accumulate points
            else if touch.state == .touching && isTracking && trackedFingerId == touch.identifier {
                addPoint(touch: touch)
                
                // Check for timeout
                if frame.timestamp - trackingStartTime > config.maxDuration {
                    if debugLogging {
                        print("🔵 [CircleRecognizer] Timeout - path too slow")
                    }
                    reset()
                }
            }
            // Finger lifting - end tracking
            else if touch.state == .breakTouch && isTracking && trackedFingerId == touch.identifier {
                addPoint(touch: touch)
                endTracking()
            }
        }
        // Multiple fingers - abort circle tracking
        else if activeTouches.count > 1 && isTracking {
            if debugLogging {
                print("🔵 [CircleRecognizer] Multiple fingers - aborting")
            }
            reset()
        }
    }
    
    func reset() {
        isTracking = false
        trackedFingerId = nil
        currentPath.removeAll()
        trackingStartTime = 0
    }
    
    // MARK: - Tracking
    
    private func startTracking(touch: TouchPoint) {
        isTracking = true
        trackedFingerId = touch.identifier
        trackingStartTime = touch.timestamp
        currentPath.removeAll()
        currentPath.append(PathPoint(
            x: Float(touch.position.x),
            y: Float(touch.position.y),
            timestamp: touch.timestamp
        ))
        
        if debugLogging {
            print("🔵 [CircleRecognizer] Started tracking finger \(touch.identifier)")
        }
    }
    
    private func addPoint(touch: TouchPoint) {
        currentPath.append(PathPoint(
            x: Float(touch.position.x),
            y: Float(touch.position.y),
            timestamp: touch.timestamp
        ))
    }
    
    private func endTracking() {
        guard isTracking else { return }
        
        isTracking = false
        trackedFingerId = nil
        
        analyzePath()
        currentPath.removeAll()
    }
    
    // MARK: - Path Analysis
    
    private func analyzePath() {
        guard currentPath.count >= config.minPoints else {
            if debugLogging {
                print("🔵 [CircleRecognizer] Path too short (\(currentPath.count) points)")
            }
            return
        }
        
        // Calculate metrics
        let center = calculateCenter()
        let avgRadius = calculateAverageRadius(from: center)
        let radiusVariance = calculateRadiusVariance(from: center, avgRadius: avgRadius)
        let totalAngle = calculateTotalAngleTraveled(from: center)
        let closureDistance = calculateClosureDistance()
        let duration = currentPath.last!.timestamp - currentPath.first!.timestamp
        
        let isClockwise = totalAngle < 0
        let fullCircles = abs(totalAngle) / (2 * Float.pi)
        
        // CALIBRATION MODE: Capture sample and return (don't fire gesture)
        if isCalibrating {
            let sample = CalibrationSample(
                radiusVariance: radiusVariance,
                fullCircles: fullCircles,
                avgRadius: avgRadius,
                duration: duration,
                closureDistance: closureDistance
            )
            calibrationSamples.append(sample)
            
            print("")
            print("🎯 ───────────────────────────────────────────────────────────")
            print("🎯 CALIBRATION SAMPLE \(calibrationSamples.count)/\(calibrationSampleCount)")
            print("🎯 ───────────────────────────────────────────────────────────")
            print("   Radius variance:  \(String(format: "%.4f", radiusVariance))")
            print("   Full circles:     \(String(format: "%.2f", fullCircles))")
            print("   Avg radius:       \(String(format: "%.3f", avgRadius))")
            print("   Duration:         \(String(format: "%.3f", duration))s")
            print("   Closure distance: \(String(format: "%.3f", closureDistance))")
            
            if calibrationSamples.count >= calibrationSampleCount {
                finishCalibration()
            } else {
                print("🎯 Draw \(calibrationSampleCount - calibrationSamples.count) more circle(s)...")
            }
            return
        }
        
        // Check criteria
        let isCircular = radiusVariance < config.maxRadiusVariance
        let hasEnoughRotation = fullCircles >= config.minCircles
        let isLargeEnough = avgRadius >= config.minRadius
        let isClosed = closureDistance < avgRadius * config.maxClosureRatio
//        
//        if debugLogging {
//            print("")
//            print("═══════════════════════════════════════════════════════════")
//            print("🔵 [CircleRecognizer] PATH ANALYSIS")
//            print("═══════════════════════════════════════════════════════════")
//            print("   Points:           \(currentPath.count)")
//            print("   Duration:         \(String(format: "%.3f", duration))s")
//            print("   Radius:           \(String(format: "%.3f", avgRadius)) (min: \(config.minRadius))")
//            print("   Radius variance:  \(String(format: "%.4f", radiusVariance)) (max: \(config.maxRadiusVariance))")
//            print("   Angle:            \(String(format: "%.1f", abs(totalAngle) * 180 / Float.pi))°")
//            print("   Full circles:     \(String(format: "%.2f", fullCircles)) (min: \(config.minCircles))")
//            print("   Closure gap:      \(String(format: "%.3f", closureDistance))")
//            print("───────────────────────────────────────────────────────────")
//            print("   Circular:         \(isCircular ? "✅" : "❌")")
//            print("   Enough rotation:  \(hasEnoughRotation ? "✅" : "❌")")
//            print("   Large enough:     \(isLargeEnough ? "✅" : "❌")")
//            print("   Closed:           \(isClosed ? "✅" : "❌") (optional)")
//            print("═══════════════════════════════════════════════════════════")
//        }
        
        // Fire event if it's a valid circle (closure is optional for now)
        if isCircular && hasEnoughRotation && isLargeEnough {
            let direction: RotationDirection = isClockwise ? .clockwise : .counterClockwise
            let event = GestureEvent.circle(direction: direction, fingerCount: 1)
            
            if debugLogging {
                print("   🎉 CIRCLE DETECTED: \(direction)")
            }
            
            onGesture?(event)
        }
    }
    
    // MARK: - Calibration Completion
    
    private func finishCalibration() {
        isCalibrating = false
        
        // Calculate statistics
        let variances = calibrationSamples.map { $0.radiusVariance }
        let circles = calibrationSamples.map { $0.fullCircles }
        let radii = calibrationSamples.map { $0.avgRadius }
        let durations = calibrationSamples.map { $0.duration }
        let closures = calibrationSamples.map { $0.closureDistance }
        
        let meanVariance = variances.reduce(0, +) / Float(variances.count)
        let meanCircles = circles.reduce(0, +) / Float(circles.count)
        let meanRadius = radii.reduce(0, +) / Float(radii.count)
        let meanDuration = durations.reduce(0, +) / Double(durations.count)
        let meanClosure = closures.reduce(0, +) / Float(closures.count)
        
        let maxVariance = variances.max() ?? 0
        let minCircles = circles.min() ?? 0
        let minRadius = radii.min() ?? 0
        let maxDuration = durations.max() ?? 0
        
        // Calculate standard deviations
        let varianceStdDev = standardDeviation(variances)
        let circlesStdDev = standardDeviation(circles)
        
        // Suggested thresholds (mean + 1.5 std dev for variance, mean - 1 std dev for circles)
        let suggestedMaxVariance = meanVariance + (varianceStdDev * 1.5)
        let suggestedMinCircles = max(0.5, meanCircles - circlesStdDev)
        let suggestedMinRadius = minRadius * 0.8
        
        print("")
        print("🎯 ═══════════════════════════════════════════════════════════")
        print("🎯 CALIBRATION COMPLETE!")
        print("🎯 ═══════════════════════════════════════════════════════════")
        print("")
        print("📊 SAMPLE STATISTICS (\(calibrationSamples.count) samples):")
        print("   ┌─────────────────┬──────────┬──────────┬──────────┐")
        print("   │ Metric          │   Mean   │   Min    │   Max    │")
        print("   ├─────────────────┼──────────┼──────────┼──────────┤")
        print("   │ Radius Variance │ \(String(format: "%8.4f", meanVariance)) │ \(String(format: "%8.4f", variances.min() ?? 0)) │ \(String(format: "%8.4f", maxVariance)) │")
        print("   │ Full Circles    │ \(String(format: "%8.2f", meanCircles)) │ \(String(format: "%8.2f", minCircles)) │ \(String(format: "%8.2f", circles.max() ?? 0)) │")
        print("   │ Avg Radius      │ \(String(format: "%8.3f", meanRadius)) │ \(String(format: "%8.3f", minRadius)) │ \(String(format: "%8.3f", radii.max() ?? 0)) │")
        print("   │ Duration (s)    │ \(String(format: "%8.3f", meanDuration)) │ \(String(format: "%8.3f", durations.min() ?? 0)) │ \(String(format: "%8.3f", maxDuration)) │")
        print("   │ Closure Gap     │ \(String(format: "%8.3f", meanClosure)) │ \(String(format: "%8.3f", closures.min() ?? 0)) │ \(String(format: "%8.3f", closures.max() ?? 0)) │")
        print("   └─────────────────┴──────────┴──────────┴──────────┘")
        print("")
        print("📐 CURRENT CONFIG:")
        print("   maxRadiusVariance: \(config.maxRadiusVariance)")
        print("   minCircles:        \(config.minCircles)")
        print("   minRadius:         \(config.minRadius)")
        print("")
        print("💡 SUGGESTED CONFIG (based on your samples):")
        print("   maxRadiusVariance: \(String(format: "%.4f", suggestedMaxVariance))")
        print("   minCircles:        \(String(format: "%.2f", suggestedMinCircles))")
        print("   minRadius:         \(String(format: "%.3f", suggestedMinRadius))")
        print("")
        print("🎯 ═══════════════════════════════════════════════════════════")
        print("")
        
        // Auto-apply suggested config
        config.maxRadiusVariance = suggestedMaxVariance
        config.minCircles = suggestedMinCircles
        config.minRadius = suggestedMinRadius
        
        print("✅ Suggested config AUTO-APPLIED!")
        print("   Try drawing circles now to test the new thresholds.")
        print("")
        
        // Notify listener
        onCalibrationComplete?(config)
    }
    
    private func standardDeviation(_ values: [Float]) -> Float {
        let count = Float(values.count)
        guard count > 1 else { return 0 }
        let mean = values.reduce(0, +) / count
        let sumSquaredDiffs = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return sqrtf(sumSquaredDiffs / (count - 1))
    }
    
    // MARK: - Math Helpers
    
    private func calculateCenter() -> (x: Float, y: Float) {
        let sumX = currentPath.reduce(Float(0)) { $0 + $1.x }
        let sumY = currentPath.reduce(Float(0)) { $0 + $1.y }
        let count = Float(currentPath.count)
        return (sumX / count, sumY / count)
    }
    
    private func calculateAverageRadius(from center: (x: Float, y: Float)) -> Float {
        let sumRadius = currentPath.reduce(Float(0)) { sum, point in
            let dx = point.x - center.x
            let dy = point.y - center.y
            return sum + sqrtf(dx * dx + dy * dy)
        }
        return sumRadius / Float(currentPath.count)
    }
    
    private func calculateRadiusVariance(from center: (x: Float, y: Float), avgRadius: Float) -> Float {
        let sumSquaredDiff = currentPath.reduce(Float(0)) { sum, point in
            let dx = point.x - center.x
            let dy = point.y - center.y
            let radius = sqrtf(dx * dx + dy * dy)
            let diff = radius - avgRadius
            return sum + diff * diff
        }
        return sumSquaredDiff / Float(currentPath.count)
    }
    
    private func calculateTotalAngleTraveled(from center: (x: Float, y: Float)) -> Float {
        guard currentPath.count >= 2 else { return 0 }
        
        var totalAngle: Float = 0
        
        for i in 1..<currentPath.count {
            let prevAngle = currentPath[i-1].angle(from: center)
            let currAngle = currentPath[i].angle(from: center)
            
            var delta = currAngle - prevAngle
            
            // Handle wrap-around at ±π
            if delta > Float.pi {
                delta -= 2 * Float.pi
            } else if delta < -Float.pi {
                delta += 2 * Float.pi
            }
            
            totalAngle += delta
        }
        
        return totalAngle
    }
    
    private func calculateClosureDistance() -> Float {
        guard let first = currentPath.first, let last = currentPath.last else { return 0 }
        let dx = last.x - first.x
        let dy = last.y - first.y
        return sqrtf(dx * dx + dy * dy)
    }
}
