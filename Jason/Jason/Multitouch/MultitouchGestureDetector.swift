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
class MultitouchGestureDetector: LiveDataStream {
    
    // MARK: - LiveDataStream Protocol
    
    var streamId: String { "multitouch-gestures" }
    
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
        case addLeft, addRight  // New: finger added on left/right side
        
        var string: String {
            switch self {
            case .up: return "up"
            case .down: return "down"
            case .left: return "left"
            case .right: return "right"
            case .tap: return "tap"
            case .addLeft: return "addLeft"
            case .addRight: return "addRight"
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
    
    // Zero-finger tracking for gesture validation
    /// Timestamp when we last had 0 fingers on trackpad
    /// Used to validate "fresh tap" gestures (0→3 within threshold)
    private var lastZeroTimestamp: Double? = nil
    
    /// Time window for valid 0→3 gesture (seconds)
    /// If 3 fingers detected within this time after 0 fingers, accept gesture
    private let zeroToThreeThreshold: Double = 0.5
    
    // MARK: - Finger Position Tracking (for left/right detection)
    
    /// Anchor position when at stable finger count
    private var anchorPosition: (id: Int, x: Float, y: Float)? = nil
    
    /// Last stable finger count
    private var stableFingerCount: Int = 0
    
    /// Whether we've already fired an addLeft/addRight gesture for this touch sequence
    /// Prevents firing multiple times as finger count fluctuates
    private var hasFiredAddGesture: Bool = false
    
    // MARK: - Callbacks
    
    /// Delegate for swipe gesture notifications
    weak var delegate: MultitouchGestureDelegate?
    
    /// Called when a swipe gesture is detected
    var onSwipeDetected: ((SwipeDirection, Int) -> Void)?
    
    // MARK: - Device Management
    
    private var devices: [MTDeviceRef] = []
    private(set) var isMonitoring: Bool = false
    
    /// Lock to protect device operations during sleep/wake transitions
    private let deviceLock = NSLock()
    
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
        deviceLock.lock()
        defer { deviceLock.unlock() }
        
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
            MultitouchGestureDetector.setShared(self)
            print("✅ [MultitouchGestureDetector] Monitoring started successfully")
        }
    }
    
    /// Stop monitoring for multitouch gestures
    func stopMonitoring() {
        deviceLock.lock()
        defer { deviceLock.unlock() }
        
        guard isMonitoring else {
            print("⚠️ [MultitouchGestureDetector] Not currently monitoring")
            return
        }
        
        print("🛑 [MultitouchGestureDetector] Stopping multitouch monitoring...")
        
        for device in devices {
            // CRITICAL: Unregister the callback BEFORE stopping the device
            // This prevents callbacks from firing into freed memory
            MTUnregisterContactFrameCallback(device, touchCallback)
            MTDeviceStop(device)
        }
        
        devices.removeAll()
        isMonitoring = false
        
        // Reset gesture tracking state
        resetGestureState()
        
        print("✅ [MultitouchGestureDetector] Monitoring stopped")
    }
    
    /// Prepare for system sleep - properly unregisters all callbacks
    func prepareForSleep() {
        print("💤 [MultitouchGestureDetector] Preparing for sleep - unregistering callbacks...")
        stopMonitoring()
    }
    
    /// Restart monitoring after wake - gets fresh device references
    func restartMonitoring() {
        print("🔄 [\(streamId)] Restarting monitoring...")
        
        deviceLock.lock()
        
        // Clear shared instance FIRST - makes any pending callbacks no-ops
        MultitouchGestureDetector.sharedInstance = nil
        
        // Don't try to unregister from old devices - they may be invalid after sleep
        // Just clear our state
        devices.removeAll()
        isMonitoring = false
        resetGestureState()
        
        deviceLock.unlock()
        
        print("🧹 [MultitouchGestureDetector] Cleared state for fresh start")
        
        // Now start fresh with new device references
        startMonitoring()
    }
    
    /// Reset gesture tracking state (call after stop or on wake)
    private func resetGestureState() {
        activeTouches.removeAll()
        touchStartPositions.removeAll()
        currentFingerCount = 0
        gestureStartTime = 0
        gestureFingerCount = 0
        isTrackingGesture = false
        lastFingerCount = 0
        lastZeroTimestamp = nil
        primaryStartPosition = (0, 0)
        primaryCurrentPosition = (0, 0)
        anchorPosition = nil
        stableFingerCount = 0
        hasFiredAddGesture = false
    }
    
    // MARK: - Touch Processing
    
    /// Process touch frame data
    fileprivate func processTouches(_ touches: UnsafeMutablePointer<MTTouch>?, count: Int, timestamp: Double) {
        // Safety check: ignore callbacks if we're not supposed to be monitoring
        guard isMonitoring else { return }
        
        let activeCount = count
        
        // Update finger count FIRST so we can handle 0-finger case
        let previousCount = currentFingerCount
        currentFingerCount = activeCount
        
        // Detect finger additions and check for left/right
        if currentFingerCount > lastFingerCount && currentFingerCount >= 2 {
            guard let touches = touches else { return }
            let touch = touches[0]
            let newId = Int(touch.identifier)
            let newX = touch.normalizedX
            
            // Check if we have an anchor to compare against and haven't fired yet
            if let anchor = anchorPosition, !hasFiredAddGesture {
                if newId != anchor.id {
                    // Different identifier = this is the NEW finger
                    let direction: SwipeDirection = newX < anchor.x ? .addLeft : .addRight
                    let fingerCount = currentFingerCount
                    
                    print("✅ [Gesture] \(direction.string.uppercased()) detected: \(lastFingerCount)→\(currentFingerCount) fingers")
                    
                    // Mark that we've fired to prevent duplicates
                    hasFiredAddGesture = true
                    
                    // Fire callback
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.didDetectSwipe(direction: direction, fingerCount: fingerCount)
                        self.onSwipeDetected?(direction, fingerCount)
                    }
                }
            }
            
            // Update anchor to current touch for next transition
            anchorPosition = (id: newId, x: newX, y: touch.normalizedY)
            stableFingerCount = currentFingerCount
        }
        
        // Track timestamp when at 0 fingers
        // Update continuously while at 0 so we always have a fresh reference point
        if currentFingerCount == 0 {
            lastZeroTimestamp = timestamp
            anchorPosition = nil
            stableFingerCount = 0
            hasFiredAddGesture = false  // Reset for next gesture sequence
            
            if previousCount > 0 {
                print("👆 [Touch] Fingers lifted")
            }
            // Reset tracking state when all fingers lifted
            if isTrackingGesture {
                analyzeGesture(endTime: timestamp)
                isTrackingGesture = false
                gestureFingerCount = 0
                touchStartPositions.removeAll()
                activeTouches.removeAll()
            }
            lastFingerCount = currentFingerCount
            return  // No touches to process
        }
        
        // Beyond this point, we have active touches
        guard let touches = touches else {
            return
        }
        
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
        
        // Set anchor for first finger (0→1 transition)
        if currentFingerCount == 1 && lastFingerCount == 0 {
            anchorPosition = (id: Int(firstTouch.identifier), x: firstTouch.normalizedX, y: firstTouch.normalizedY)
            stableFingerCount = 1
        }
        
        // Detect gesture start (fingers just touched down)
        // Handle both 3-finger and 4-finger gestures with "came from 0" validation
        if !isTrackingGesture && currentFingerCount >= 3 && previousCount < currentFingerCount {
            // VALIDATE: Check if we recently came from 0 fingers (fresh gesture)
            var shouldAccept = false
            
            if let zeroTime = lastZeroTimestamp {
                let timeSinceZero = timestamp - zeroTime
                
                if timeSinceZero <= zeroToThreeThreshold {
                    // Recently came from 0 - accept as fresh gesture
                    shouldAccept = true
                } else {
                    // Too long since 0 - likely adding fingers to existing touch
                    // This is handled by the addLeft/addRight logic above
                    lastFingerCount = currentFingerCount
                    return
                }
            } else {
                // No timestamp yet (first gesture after app launch) - accept it
                shouldAccept = true
            }
            
            // Only proceed if validation passed
            if shouldAccept {
                isTrackingGesture = true
                gestureStartTime = timestamp
                gestureFingerCount = currentFingerCount
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
            analyzeGesture(endTime: timestamp)
            
            // Reset state
            isTrackingGesture = false
            gestureFingerCount = 0
            touchStartPositions.removeAll()
            activeTouches.removeAll()
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
            print("✅ [Gesture] TAP with \(capturedFingerCount) fingers")
            
            // Dispatch callbacks to main thread for UI updates
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.didDetectSwipe(direction: .tap, fingerCount: capturedFingerCount)
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
        
        print("✅ [Gesture] SWIPE \(direction.string.uppercased()) with \(capturedFingerCount) fingers")
        
        // Dispatch callbacks to main thread for UI updates
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.didDetectSwipe(direction: direction, fingerCount: capturedFingerCount)
            self.onSwipeDetected?(direction, capturedFingerCount)
        }
    }
}

// MARK: - C Callback

/// Callback function that bridges to Swift
private func touchCallback(
    device: MTDeviceRef?,
    touches: UnsafeMutablePointer<MTTouch>?,
    numTouches: Int32,
    timestamp: Double,
    frame: Int32,
    refcon: UnsafeMutableRawPointer?
) {
    // Bail immediately if no instance - prevents crashes during sleep/wake transitions
    guard let detector = MultitouchGestureDetector.sharedInstance else { return }
    detector.processTouches(touches, count: Int(numTouches), timestamp: timestamp)
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
