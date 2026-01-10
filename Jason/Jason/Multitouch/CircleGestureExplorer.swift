//
//  CircleGestureExplorer.swift
//  Jason
//
//  Experimental class for exploring circle gesture detection on trackpad
//

import Foundation

/// Explores single-finger circular gesture detection using raw trackpad data
class CircleGestureExplorer {
    
    // MARK: - Types
    
    struct PathPoint {
        let x: Float
        let y: Float
        let timestamp: Double
        
        /// Angle from center point (radians, 0 = right, counter-clockwise positive)
        func angle(from center: (x: Float, y: Float)) -> Float {
            return atan2(y - center.y, x - center.x)
        }
    }
    
    // MARK: - State
    
    /// Points collected during current finger movement
    private var currentPath: [PathPoint] = []
    
    /// Whether we're currently tracking a finger
    private var isTracking: Bool = false
    
    /// The finger identifier we're tracking
    private var trackedFingerId: Int? = nil
    
    /// Minimum points needed to analyze a path
    private let minPointsForAnalysis: Int = 10
    
    // MARK: - Device Management
    
    private var devices: [MTDeviceRef] = []
    private(set) var isMonitoring: Bool = false
    
    // MARK: - Singleton for C Callback
    
    fileprivate static var shared: CircleGestureExplorer?
    
    // MARK: - Lifecycle
    
    init() {
        print("🔵 [CircleExplorer] Initialized")
    }
    
    deinit {
        stopMonitoring()
        print("🔵 [CircleExplorer] Deallocated")
    }
    
    // MARK: - Monitoring
    
    func startMonitoring() {
        guard !isMonitoring else {
            print("⚠️ [CircleExplorer] Already monitoring")
            return
        }
        
        print("🚀 [CircleExplorer] Starting monitoring...")
        
        guard let deviceList = MTDeviceCreateList() else {
            print("❌ [CircleExplorer] Failed to get device list")
            return
        }
        
        let deviceArray = deviceList.takeRetainedValue()
        let count = CFArrayGetCount(deviceArray)
        print("   Found \(count) multitouch device(s)")
        
        for i in 0..<count {
            let devicePtr = CFArrayGetValueAtIndex(deviceArray, i)
            let device = unsafeBitCast(devicePtr, to: MTDeviceRef.self)
            
            MTRegisterContactFrameCallback(device, circleExplorerCallback)
            MTDeviceStart(device, 0)
            devices.append(device)
        }
        
        if !devices.isEmpty {
            isMonitoring = true
            CircleGestureExplorer.shared = self
            print("✅ [CircleExplorer] Monitoring started - draw circles on trackpad!")
        }
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        print("🛑 [CircleExplorer] Stopping monitoring...")
        
        for device in devices {
            MTUnregisterContactFrameCallback(device, circleExplorerCallback)
            MTDeviceStop(device)
        }
        
        devices.removeAll()
        isMonitoring = false
        CircleGestureExplorer.shared = nil
        
        print("✅ [CircleExplorer] Stopped")
    }
    
    // MARK: - Touch Processing
    
    fileprivate func processTouches(_ touches: UnsafeMutablePointer<MTTouch>?, count: Int, timestamp: Double) {
        
        // No fingers - end tracking if we were tracking
        if count == 0 {
            if isTracking {
                endTracking()
            }
            return
        }
        
        guard let touches = touches else { return }
        
        // Only track single finger gestures for now
        if count == 1 {
            let touch = touches[0]
            let touchId = Int(touch.identifier)
            let state = touch.state
            
            // Finger down - start tracking
            if state == MTTouchStateMakeTouch.rawValue ||
               (state == MTTouchStateTouching.rawValue && !isTracking) {
                startTracking(fingerId: touchId, x: touch.normalizedX, y: touch.normalizedY, timestamp: timestamp)
            }
            // Finger moving - accumulate points
            else if state == MTTouchStateTouching.rawValue && isTracking && trackedFingerId == touchId {
                addPoint(x: touch.normalizedX, y: touch.normalizedY, timestamp: timestamp)
            }
            // Finger lifting - end tracking
            else if state == MTTouchStateBreakTouch.rawValue && isTracking {
                addPoint(x: touch.normalizedX, y: touch.normalizedY, timestamp: timestamp)
                endTracking()
            }
        }
        // Multiple fingers - abort circle tracking
        else if count > 1 && isTracking {
            print("🔵 [CircleExplorer] Multiple fingers detected - aborting circle tracking")
            isTracking = false
            trackedFingerId = nil
            currentPath.removeAll()
        }
    }
    
    // MARK: - Tracking
    
    private func startTracking(fingerId: Int, x: Float, y: Float, timestamp: Double) {
        isTracking = true
        trackedFingerId = fingerId
        currentPath.removeAll()
        currentPath.append(PathPoint(x: x, y: y, timestamp: timestamp))
        print("🔵 [CircleExplorer] Started tracking finger \(fingerId) at (\(String(format: "%.3f", x)), \(String(format: "%.3f", y)))")
    }
    
    private func addPoint(x: Float, y: Float, timestamp: Double) {
        currentPath.append(PathPoint(x: x, y: y, timestamp: timestamp))
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
        let pointCount = currentPath.count
        
        guard pointCount >= minPointsForAnalysis else {
            print("🔵 [CircleExplorer] Path too short (\(pointCount) points) - ignoring")
            return
        }
        
        // Calculate basic metrics
        let duration = currentPath.last!.timestamp - currentPath.first!.timestamp
        let center = calculateCenter()
        let avgRadius = calculateAverageRadius(from: center)
        let radiusVariance = calculateRadiusVariance(from: center, avgRadius: avgRadius)
        let totalAngle = calculateTotalAngleTraveled(from: center)
        let isClockwise = totalAngle < 0
        let closureDistance = calculateClosureDistance()
        
        // Print analysis
        print("")
        print("═══════════════════════════════════════════════════════════")
        print("🔵 [CircleExplorer] PATH ANALYSIS")
        print("═══════════════════════════════════════════════════════════")
        print("   Points collected:    \(pointCount)")
        print("   Duration:            \(String(format: "%.3f", duration))s")
        print("   Center estimate:     (\(String(format: "%.3f", center.x)), \(String(format: "%.3f", center.y)))")
        print("   Average radius:      \(String(format: "%.3f", avgRadius))")
        print("   Radius variance:     \(String(format: "%.4f", radiusVariance)) (lower = more circular)")
        print("   Total angle:         \(String(format: "%.1f", abs(totalAngle) * 180 / Float.pi))° \(isClockwise ? "clockwise" : "counter-clockwise")")
        print("   Closure distance:    \(String(format: "%.3f", closureDistance)) (start→end gap)")
        print("───────────────────────────────────────────────────────────")
        
        // Circle quality assessment
        let fullCircles = abs(totalAngle) / (2 * Float.pi)
        let isCircular = radiusVariance < 0.01 && fullCircles >= 0.7
        let isClosed = closureDistance < avgRadius * 0.5
        
        print("   Full circles:        \(String(format: "%.2f", fullCircles))")
        print("   Appears circular:    \(isCircular ? "✅ YES" : "❌ NO")")
        print("   Path closes:         \(isClosed ? "✅ YES" : "❌ NO")")
        
        if isCircular && fullCircles >= 0.75 {
            print("")
            print("   🎉 CIRCLE DETECTED!")
        }
        
        print("═══════════════════════════════════════════════════════════")
        print("")
        
        // Also print raw path for detailed inspection
        printRawPath()
    }
    
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
    
    private func printRawPath() {
        print("🔵 [CircleExplorer] Raw path data (sampled):")
        
        // Sample every Nth point to keep output manageable
        let sampleRate = max(1, currentPath.count / 20)
        
        for (index, point) in currentPath.enumerated() {
            if index % sampleRate == 0 || index == currentPath.count - 1 {
                let relativeTime = point.timestamp - currentPath.first!.timestamp
                print("   [\(String(format: "%3d", index))] t=\(String(format: "%.3f", relativeTime))s  x=\(String(format: "%.3f", point.x))  y=\(String(format: "%.3f", point.y))")
            }
        }
    }
}

// MARK: - C Callback

private func circleExplorerCallback(
    device: MTDeviceRef?,
    touches: UnsafeMutablePointer<MTTouch>?,
    numTouches: Int32,
    timestamp: Double,
    frame: Int32,
    refcon: UnsafeMutableRawPointer?
) {
    guard let explorer = CircleGestureExplorer.shared else { return }
    explorer.processTouches(touches, count: Int(numTouches), timestamp: timestamp)
}
