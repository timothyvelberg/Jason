//
//  MultitouchGestureDetector.swift
//  Jason
//
//  Detects swipe gestures using the private MultitouchSupport framework
//

import Foundation

/// Protocol for receiving swipe gesture notifications
protocol MultitouchGestureDelegate: AnyObject {
    func didDetectSwipe(direction: MultitouchGestureDetector.SwipeDirection, fingerCount: Int)
}

/// Detects multitouch gestures (particularly swipes) using raw trackpad data
class MultitouchGestureDetector {
    
    // MARK: - Types
    
    struct Touch {
        let identifier: Int
        let x: Float
        let y: Float
        let timestamp: Double
        
        func distance(to other: Touch) -> Float {
            let dx = x - other.x
            let dy = y - other.y
            return sqrt(dx * dx + dy * dy)
        }
    }
    
    enum SwipeDirection {
        case up, down, left, right, tap
        
        var string: String {
            switch self {
            case .up: return "up"
            case .down: return "down"
            case .left: return "left"
            case .right: return "right"
            case .tap: return "tap"
            }
        }
    }
    
    // MARK: - Configuration
    
    /// Minimum distance to consider a swipe (normalized coordinates 0-1)
    private let minSwipeDistance: Float = 0.15
    
    /// Maximum time for a swipe gesture (seconds)
    private let maxSwipeDuration: Double = 0.5
    
    /// Minimum velocity to be considered a swipe (distance/second)
    private let minSwipeVelocity: Float = 0.3
    
    // Tap detection thresholds
    /// Maximum distance for a tap (if movement is less than this, it's a tap not a swipe)
    private let maxTapDistance: Float = 0.03
    
    /// Maximum duration for a tap (seconds)
    private let maxTapDuration: Double = 0.6
    
    // 🆕 Finger timing validation
    /// Maximum time spread between first and last finger touching (seconds)
    /// All fingers must touch within this window to be considered a valid gesture
    /// TUNING: Increase if legitimate gestures are rejected, decrease if accidental triggers occur
    private let maxFingerSpreadTime: Double = 3.0
    
    // MARK: - State Tracking
    
    /// Tracks active touches by their identifier
    private var activeTouches: [Int: Touch] = [:]
    
    /// Tracks the starting position of each touch
    private var touchStartPositions: [Int: Touch] = [:]
    
    /// Number of fingers currently touching
    private var currentFingerCount: Int = 0
    
    /// Timestamp when the gesture started
    private var gestureStartTime: Double = 0
    
    /// Number of fingers when the gesture started
    private var gestureFingerCount: Int = 0
    
    /// Whether we're currently tracking a potential swipe
    private var isTrackingGesture: Bool = false
    
    /// Last reported finger count to detect changes
    private var lastFingerCount: Int = 0
    
    // 🆕 Finger timing tracking
    /// Timestamp when the first finger touched (to validate gesture timing)
    private var firstFingerTimestamp: Double? = nil
    
    // MARK: - Callbacks
    
    /// Delegate for swipe gesture notifications
    weak var delegate: MultitouchGestureDelegate?
    
    /// Called when a swipe gesture is detected
    var onSwipeDetected: ((SwipeDirection, Int) -> Void)?
    
    // MARK: - Device Management
    
    private var devices: [MTDeviceRef] = []
    private var isMonitoring: Bool = false
    
    // MARK: - Initialization
    
    init() {
        print("🎯 [MultitouchGestureDetector] Initialized")
    }
    
    deinit {
        stopMonitoring()
        print("🎯 [MultitouchGestureDetector] Deallocated")
    }
    
    // MARK: - Public Interface
    
    /// Start monitoring for multitouch gestures
    func startMonitoring() {
        guard !isMonitoring else {
            print("⚠️ [MultitouchGestureDetector] Already monitoring")
            return
        }
        
        print("🚀 [MultitouchGestureDetector] Starting multitouch monitoring...")
        
        // Get list of multitouch devices
        guard let deviceList = MTDeviceCreateList() else {
            print("❌ [MultitouchGestureDetector] Failed to get device list")
            return
        }
        
        let deviceArray = deviceList.takeRetainedValue()
        let count = CFArrayGetCount(deviceArray)
        print("   Found \(count) multitouch device(s)")
        
        // Register callback for each device
        for i in 0..<count {
            // Get device pointer from CFArray
            let devicePtr = CFArrayGetValueAtIndex(deviceArray, i)
            let device = unsafeBitCast(devicePtr, to: MTDeviceRef.self)
            
            // Check if it's the built-in trackpad
            let isBuiltIn = MTDeviceIsBuiltIn(device)
            let deviceType = isBuiltIn ? "built-in" : "external"
            print("   Device \(i): \(deviceType)")
            
            // Register callback for ALL devices (built-in and external)
            print("   🔧 Registering callback for \(deviceType) device...")
            MTRegisterContactFrameCallback(device, touchCallback)
            
            // Start receiving events
            MTDeviceStart(device, 0)
            
            devices.append(device)
            print("   ✅ Registered \(deviceType) trackpad")
        }
        
        if devices.isEmpty {
            print("❌ [MultitouchGestureDetector] No suitable devices found")
        } else {
            isMonitoring = true
            print("✅ [MultitouchGestureDetector] Monitoring started successfully")
        }
    }
    
    /// Stop monitoring for multitouch gestures
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        print("🛑 [MultitouchGestureDetector] Stopping multitouch monitoring...")
        
        for device in devices {
            MTDeviceStop(device)
        }
        
        devices.removeAll()
        isMonitoring = false
        
        print("✅ [MultitouchGestureDetector] Monitoring stopped")
    }
    
    // MARK: - Touch Processing
    
    /// Process touch frame data
    fileprivate func processTouches(_ touches: UnsafeMutablePointer<MTTouch>?, count: Int, timestamp: Double) {
        guard let touches = touches, count > 0 else {
            return
        }
        
        // Use the count from the callback - it's reliable
        // The framework reports accurate finger count but only fills first touch structure
        let activeCount = count
        
        // Get position from first touch (the only one with valid data)
        let firstTouch = touches[0]
        
        // Only process if first touch has valid state
        guard firstTouch.state >= 1 && firstTouch.state <= 7 else {
            return
        }
        
        // Build touch data for the primary touch
        var currentTouches: [Int: Touch] = [:]
        if firstTouch.state == MTTouchStateTouching.rawValue ||
           firstTouch.state == MTTouchStateMakeTouch.rawValue ||
           firstTouch.state == MTTouchStateBreakTouch.rawValue {
            
            let touchData = Touch(
                identifier: Int(firstTouch.identifier),
                x: firstTouch.normalizedX,
                y: firstTouch.normalizedY,
                timestamp: timestamp
            )
            currentTouches[Int(firstTouch.identifier)] = touchData
        }
        
        // Update finger count
        let previousCount = currentFingerCount
        currentFingerCount = activeCount
        
        // 🆕 Track when ANY fingers first touch (to validate gesture timing later)
        // Only set timestamp when going from 0 to any number
        if currentFingerCount > 0 && previousCount == 0 {
            firstFingerTimestamp = timestamp
            print("👆 [Timing] First touch detected (\(currentFingerCount) finger(s)) at \(timestamp)")
        }
        
        // 🆕 Reset timing ONLY when ALL fingers lifted (back to 0)
        // Do NOT reset on individual finger lifts - that causes issues
        if currentFingerCount == 0 {
            firstFingerTimestamp = nil
            print("👆 [Timing] All fingers lifted - reset timestamp")
        }
        
        // Detect gesture start (fingers just touched down)
        // Handle both 3-finger and 4-finger gestures with timing validation
        if !isTrackingGesture && currentFingerCount >= 3 && previousCount < currentFingerCount {
            // 🆕 VALIDATE TIMING: Check if all fingers touched within acceptable time window
            var shouldAccept = false
            
            if let firstTime = firstFingerTimestamp {
                let fingerSpread = timestamp - firstTime
                
                if fingerSpread <= maxFingerSpreadTime {
                    // Fingers touched close enough together - accept
                    shouldAccept = true
                    print("✅ [Timing] Accepted \(currentFingerCount)-finger gesture: finger spread \(String(format: "%.3f", fingerSpread))s ≤ \(maxFingerSpreadTime)s threshold")
                } else {
                    // Fingers touched too far apart - reject
                    let fingerDesc = currentFingerCount == 3 ? "third" : "fourth"
                    print("⚠️ [Timing] Rejected \(currentFingerCount)-finger gesture: finger spread \(String(format: "%.3f", fingerSpread))s > \(maxFingerSpreadTime)s threshold")
                    print("   Likely accidental \(fingerDesc) finger added to \(previousCount)-finger gesture")
                    
                    // Reset timestamp to current time for next attempt
                    // This allows immediate retry without lifting all fingers
                    firstFingerTimestamp = timestamp
                    print("   🔄 Reset timestamp to current touch")
                    
                    // Don't start tracking
                    return
                }
            } else {
                // No timestamp - this shouldn't happen, but if it does, reject
                print("⚠️ [Timing] Rejected \(currentFingerCount)-finger gesture: no first touch timestamp")
                
                // Set timestamp to current time so next attempt works
                firstFingerTimestamp = timestamp
                return
            }
            
            // Only proceed if validation passed
            if shouldAccept {
                print("👆 [Gesture] Started tracking - \(currentFingerCount) fingers")
                isTrackingGesture = true
                gestureStartTime = timestamp
                gestureFingerCount = currentFingerCount  // LOCK IN THE FINGER COUNT
                // Store the primary touch start position directly from firstTouch
                touchStartPositions = currentTouches
                primaryStartPosition = (firstTouch.normalizedX, firstTouch.normalizedY)
            }
        }
        
        // Track gesture progression - store latest position
        if isTrackingGesture && currentFingerCount >= 3 {
            activeTouches = currentTouches
            primaryCurrentPosition = (firstTouch.normalizedX, firstTouch.normalizedY)
        }
        
        // Detect gesture end (fingers lifted)
        if isTrackingGesture && currentFingerCount < 3 {
            print("👆 [Gesture] Ended - analyzing movement")
            analyzeGesture(endTime: timestamp)
            
            // Reset state
            isTrackingGesture = false
            gestureFingerCount = 0
            touchStartPositions.removeAll()
            activeTouches.removeAll()
            
            // 🆕 IMPORTANT: Reset timestamp after gesture ends
            // This gives a fresh start for the next gesture attempt
            firstFingerTimestamp = timestamp
            print("   🔄 Reset timestamp after gesture ended")
        }
        
        lastFingerCount = currentFingerCount
    }
    
    // Track primary touch position
    private var primaryStartPosition: (x: Float, y: Float) = (0, 0)
    private var primaryCurrentPosition: (x: Float, y: Float) = (0, 0)
    
    /// Analyze the gesture to determine if it's a tap or swipe
    private func analyzeGesture(endTime: Double) {
        let duration = endTime - gestureStartTime
        
        // Calculate movement of primary touch
        let dx = primaryCurrentPosition.x - primaryStartPosition.x
        let dy = primaryCurrentPosition.y - primaryStartPosition.y
        let distance = sqrt(dx * dx + dy * dy)
        
        // Capture finger count BEFORE async dispatch (it gets reset to 0 immediately after this method returns)
        let capturedFingerCount = gestureFingerCount
        
        // CHECK FOR TAP: Short duration + minimal movement
        if duration <= maxTapDuration && distance < maxTapDistance {
            print("✅ [Gesture] TAP DETECTED with \(capturedFingerCount) fingers (distance: \(String(format: "%.2f", distance)), duration: \(String(format: "%.2f", duration))s)")
            
            // Dispatch callbacks to main thread for UI updates
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // Notify delegate - use captured value
                self.delegate?.didDetectSwipe(direction: .tap, fingerCount: capturedFingerCount)
                
                // Fire callback - use captured value
                self.onSwipeDetected?(.tap, capturedFingerCount)
            }
            return
        }
        
        // CHECK FOR SWIPE: Sufficient distance and velocity
        guard duration <= maxSwipeDuration else {
            return
        }
        
        guard distance >= minSwipeDistance else {
            return
        }
        
        // Calculate velocity
        let velocity = distance / Float(duration)
        
        guard velocity >= minSwipeVelocity else {
            return
        }
        
        // Determine direction (Y is inverted on trackpad)
        let direction: SwipeDirection
        if abs(dy) > abs(dx) {
            direction = dy < 0 ? .up : .down  // Negative dy = swipe up
        } else {
            direction = dx > 0 ? .right : .left
        }
        
        print("✅ [Gesture] SWIPE DETECTED: \(direction.string) with \(capturedFingerCount) fingers (distance: \(String(format: "%.2f", distance)), velocity: \(String(format: "%.2f", velocity)), duration: \(String(format: "%.2f", duration))s)")
        
        // Dispatch callbacks to main thread for UI updates
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Notify delegate - use captured value
            self.delegate?.didDetectSwipe(direction: direction, fingerCount: capturedFingerCount)
            
            // Fire callback - use captured value
            self.onSwipeDetected?(direction, capturedFingerCount)
        }
    }
}

// MARK: - C Callback

/// C callback function that bridges to Swift
private func touchCallback(
    device: MTDeviceRef?,
    touches: UnsafeMutablePointer<MTTouch>?,
    numTouches: Int32,
    timestamp: Double,
    frame: Int32,
    refcon: UnsafeMutableRawPointer?
) {
    // Use the shared instance to process touches
    MultitouchGestureDetector.sharedInstance?.processTouches(touches, count: Int(numTouches), timestamp: timestamp)
}

// MARK: - Singleton for C Callback Access

extension MultitouchGestureDetector {
    fileprivate static var sharedInstance: MultitouchGestureDetector?
    
    static func setShared(_ detector: MultitouchGestureDetector?) {
        sharedInstance = detector
        if detector != nil {
            print("✅ [MultitouchGestureDetector] Shared instance SET for C callback")
        } else {
            print("❌ [MultitouchGestureDetector] Shared instance CLEARED")
        }
    }
}
