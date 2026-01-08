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
        case add  // Generic finger add (1→2 or 2→3)
        
        var string: String {
            switch self {
            case .up: return "up"
            case .down: return "down"
            case .left: return "left"
            case .right: return "right"
            case .tap: return "tap"
            case .add: return "add"
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
    
    // Add gesture timing thresholds
    /// Minimum time finger must be held before adding second finger (seconds)
    private let addGestureMinDelay: Double = 0.2
    
    /// Maximum time to add second finger after first (seconds)
    private let addGestureMaxDelay: Double = 0.8
    
    /// Maximum movement allowed for anchor finger before add gesture is invalidated
    private let addGestureMaxMovement: Float = 0.03
    
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
    private var lastZeroTimestamp: Double? = nil
    
    /// Time window for valid 0→3 gesture (seconds)
    private let zeroToThreeThreshold: Double = 0.5
    
    // MARK: - Finger Position Tracking (for add detection)
    
    /// Anchor position when at stable finger count
    private var anchorPosition: (id: Int, x: Float, y: Float)? = nil
    
    /// Timestamp when anchor was set
    private var anchorTimestamp: Double = 0
    
    /// Original position when anchor was set (for movement detection)
    private var anchorStartPosition: (x: Float, y: Float) = (0, 0)
    
    /// Whether the anchor finger is still eligible for add gesture
    private var isEligibleForAdd: Bool = false
    
    /// Last stable finger count
    private var stableFingerCount: Int = 0
    
    /// Whether we've already fired an add gesture for this touch sequence
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
            let devicePtr = CFArrayGetValueAtIndex(deviceArray, i)
            let device = unsafeBitCast(devicePtr, to: MTDeviceRef.self)
            
            let isBuiltIn = MTDeviceIsBuiltIn(device)
            let deviceType = isBuiltIn ? "built-in" : "external"
            print("   Device \(i): \(deviceType)")
            print("   🔧 Registering callbacks for \(deviceType) device...")
            
            MTRegisterContactFrameCallback(device, touchCallback)
            MTRegisterPathCallback(device, pathCallback)
            
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
            MTUnregisterContactFrameCallback(device, touchCallback)
            MTUnregisterPathCallback(device, pathCallback)
            MTDeviceStop(device)
        }
        
        devices.removeAll()
        isMonitoring = false
        
        resetGestureState()
        
        print("✅ [MultitouchGestureDetector] Monitoring stopped")
    }
    
    /// Prepare for system sleep
    func prepareForSleep() {
        print("💤 [MultitouchGestureDetector] Preparing for sleep - unregistering callbacks...")
        stopMonitoring()
    }
    
    /// Restart monitoring after wake
    func restartMonitoring() {
        print("🔄 [\(streamId)] Restarting monitoring...")
        
        deviceLock.lock()
        
        MultitouchGestureDetector.sharedInstance = nil
        
        devices.removeAll()
        isMonitoring = false
        resetGestureState()
        
        deviceLock.unlock()
        
        print("🧹 [MultitouchGestureDetector] Cleared state for fresh start")
        
        startMonitoring()
    }
    
    /// Reset gesture tracking state
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
        anchorTimestamp = 0
        anchorStartPosition = (0, 0)
        isEligibleForAdd = false
        stableFingerCount = 0
        hasFiredAddGesture = false
        lastTouchdownPathID = nil
        pathTouchdownPositions.removeAll()
        activePathIDs.removeAll()
        pendingAddGesture = nil
    }
    
    // MARK: - Touch Processing
    
    /// Process touch frame data
    fileprivate func processTouches(_ touches: UnsafeMutablePointer<MTTouch>?, count: Int, timestamp: Double) {
        guard isMonitoring else { return }
        
        let activeCount = count
        let previousCount = currentFingerCount
        currentFingerCount = activeCount
        
        // Track timestamp when at 0 fingers
        if currentFingerCount == 0 {
            lastZeroTimestamp = timestamp
            anchorPosition = nil
            anchorTimestamp = 0
            anchorStartPosition = (0, 0)
            isEligibleForAdd = false
            stableFingerCount = 0
            hasFiredAddGesture = false
            lastTouchdownPathID = nil
            pathTouchdownPositions.removeAll()
            activePathIDs.removeAll()
            pendingAddGesture = nil
            
            if previousCount > 0 {
                print("👆 [Touch] Fingers lifted")
            }
            if isTrackingGesture {
                analyzeGesture(endTime: timestamp)
                isTrackingGesture = false
                gestureFingerCount = 0
                touchStartPositions.removeAll()
                activeTouches.removeAll()
            }
            lastFingerCount = currentFingerCount
            return
        }
        
        guard let touches = touches else {
            return
        }
        
        let firstTouch = touches[0]
        
        guard firstTouch.state >= 1 && firstTouch.state <= 7 else {
            return
        }
        
        // Track this finger's position for later lookup (first time we see each ID)
        if pathTouchdownPositions[Int(firstTouch.identifier)] == nil {
            pathTouchdownPositions[Int(firstTouch.identifier)] = firstTouch.normalizedX
            print("📍 [Track] First sighting of id=\(firstTouch.identifier) at x=\(String(format: "%.3f", firstTouch.normalizedX))")
        }
        
        // Set anchor for first finger (0→1 transition)
        if currentFingerCount == 1 && lastFingerCount == 0 {
            anchorPosition = (id: Int(firstTouch.identifier), x: firstTouch.normalizedX, y: firstTouch.normalizedY)
            anchorTimestamp = timestamp
            anchorStartPosition = (firstTouch.normalizedX, firstTouch.normalizedY)
            isEligibleForAdd = true
            stableFingerCount = 1
        }
        
        // Check for anchor movement while at 1 finger
        if currentFingerCount == 1 && isEligibleForAdd {
            if let anchor = anchorPosition, Int(firstTouch.identifier) == anchor.id {
                let dx = firstTouch.normalizedX - anchorStartPosition.x
                let dy = firstTouch.normalizedY - anchorStartPosition.y
                let movement = sqrt(dx * dx + dy * dy)
                
                if movement > addGestureMaxMovement {
                    isEligibleForAdd = false
                }
            }
        }
        
        // Detect finger additions (1→2 or 2→3)
        if currentFingerCount > lastFingerCount && currentFingerCount >= 2 && currentFingerCount <= 3 {
            let frameID = Int(firstTouch.identifier)
            let frameX = firstTouch.normalizedX
            
            if let anchor = anchorPosition, !hasFiredAddGesture {
                let timeSinceAnchor = timestamp - anchorTimestamp
                let isInTimeWindow = timeSinceAnchor >= addGestureMinDelay && timeSinceAnchor <= addGestureMaxDelay
                
                // Determine new finger position
                var newFingerX: Float? = nil
                var newFingerID: Int? = nil
                
                if frameID != anchor.id {
                    // Frame shows the NEW finger directly
                    newFingerX = frameX
                    newFingerID = frameID
                    print("🔍 [Add] Frame shows NEW finger (id=\(frameID)) at x=\(String(format: "%.3f", frameX))")
                } else if let pathID = lastTouchdownPathID, pathID != anchor.id {
                    // Frame shows anchor, but path told us which ID is new
                    if let trackedX = pathTouchdownPositions[pathID] {
                        newFingerX = trackedX
                        newFingerID = pathID
                        print("🔍 [Add] Path says new finger is id=\(pathID), tracked at x=\(String(format: "%.3f", trackedX))")
                    } else {
                        print("🔍 [Add] Path says new finger is id=\(pathID), but no position tracked yet")
                    }
                } else {
                    // Frame shows anchor, try to find new finger from active paths
                    for pathID in activePathIDs where pathID != anchor.id {
                        if let trackedX = pathTouchdownPositions[pathID] {
                            newFingerX = trackedX
                            newFingerID = pathID
                            print("🔍 [Add] Found new finger from active paths: id=\(pathID) at x=\(String(format: "%.3f", trackedX))")
                            break
                        }
                    }
                    if newFingerX == nil {
                        print("🔍 [Add] Cannot determine new finger (frameID=\(frameID), anchor=\(anchor.id), active=\(activePathIDs.sorted()))")
                    }
                }
                
                var detectedDirection: String? = nil
                if let newX = newFingerX {
                    detectedDirection = newX > anchor.x ? "RIGHT" : "LEFT"
                    print("   📍 Anchor x=\(String(format: "%.3f", anchor.x)), New x=\(String(format: "%.3f", newX)) → \(detectedDirection!)")
                }
                
                if isEligibleForAdd && isInTimeWindow {
                    let fingerCount = currentFingerCount
                    
                    if let dir = detectedDirection {
                        // We have direction, fire immediately
                        print("✅ [Gesture] ADD detected: \(lastFingerCount)→\(currentFingerCount) fingers (delay: \(String(format: "%.0f", timeSinceAnchor * 1000))ms)")
                        print("   Direction: \(dir)")
                        
                        hasFiredAddGesture = true
                        
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            self.delegate?.didDetectSwipe(direction: .add, fingerCount: fingerCount)
                            self.onSwipeDetected?(.add, fingerCount)
                        }
                    } else {
                        // Direction unknown, defer until path callback arrives
                        print("⏳ [Gesture] ADD pending: \(lastFingerCount)→\(currentFingerCount) fingers, waiting for new finger path...")
                        pendingAddGesture = (anchorX: anchor.x, fingerCount: fingerCount, anchorID: anchor.id)
                        hasFiredAddGesture = true  // Prevent duplicate detection
                    }
                }
            }
            
            // Update anchor for next transition
            anchorPosition = (id: frameID, x: frameX, y: firstTouch.normalizedY)
            anchorTimestamp = timestamp
            anchorStartPosition = (frameX, firstTouch.normalizedY)
            isEligibleForAdd = true
            stableFingerCount = currentFingerCount
        }
        
        // Check for anchor movement while at 2 fingers
        if currentFingerCount == 2 && isEligibleForAdd && stableFingerCount == 2 {
            if let anchor = anchorPosition, Int(firstTouch.identifier) == anchor.id {
                let dx = firstTouch.normalizedX - anchorStartPosition.x
                let dy = firstTouch.normalizedY - anchorStartPosition.y
                let movement = sqrt(dx * dx + dy * dy)
                
                if movement > addGestureMaxMovement {
                    isEligibleForAdd = false
                }
            }
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
        
        // Detect gesture start (3+ fingers landed together)
        if !isTrackingGesture && currentFingerCount >= 3 && previousCount < currentFingerCount {
            var shouldAccept = false
            
            if let zeroTime = lastZeroTimestamp {
                let timeSinceZero = timestamp - zeroTime
                
                if timeSinceZero <= zeroToThreeThreshold {
                    shouldAccept = true
                } else {
                    lastFingerCount = currentFingerCount
                    return
                }
            } else {
                shouldAccept = true
            }
            
            if shouldAccept {
                isTrackingGesture = true
                gestureStartTime = timestamp
                gestureFingerCount = currentFingerCount
                touchStartPositions = currentTouches
                primaryStartPosition = (firstTouch.normalizedX, firstTouch.normalizedY)
            }
        }
        
        // Track gesture progression
        if isTrackingGesture && currentFingerCount >= 3 {
            activeTouches = currentTouches
            primaryCurrentPosition = (firstTouch.normalizedX, firstTouch.normalizedY)
        }
        
        // Detect gesture end
        if isTrackingGesture && currentFingerCount < 3 {
            analyzeGesture(endTime: timestamp)
            
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
        
        let dx = primaryCurrentPosition.x - primaryStartPosition.x
        let dy = primaryCurrentPosition.y - primaryStartPosition.y
        let distance = sqrt(dx * dx + dy * dy)
        
        let capturedFingerCount = gestureFingerCount
        
        // CHECK FOR TAP
        if duration <= maxTapDuration && distance < maxTapDistance {
            print("✅ [Gesture] TAP with \(capturedFingerCount) fingers")
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.didDetectSwipe(direction: .tap, fingerCount: capturedFingerCount)
                self.onSwipeDetected?(.tap, capturedFingerCount)
            }
            return
        }
        
        // CHECK FOR SWIPE
        guard duration <= maxSwipeDuration else {
            return
        }
        
        guard distance >= minSwipeDistance else {
            return
        }
        
        let velocity = distance / Float(duration)
        
        guard velocity >= minSwipeVelocity else {
            return
        }
        
        let direction: SwipeDirection
        if abs(dy) > abs(dx) {
            direction = dy < 0 ? .up : .down
        } else {
            direction = dx > 0 ? .right : .left
        }
        
        print("✅ [Gesture] SWIPE \(direction.string.uppercased()) with \(capturedFingerCount) fingers")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.didDetectSwipe(direction: direction, fingerCount: capturedFingerCount)
            self.onSwipeDetected?(direction, capturedFingerCount)
        }
    }
}

// MARK: - C Callback

private func touchCallback(
    device: MTDeviceRef?,
    touches: UnsafeMutablePointer<MTTouch>?,
    numTouches: Int32,
    timestamp: Double,
    frame: Int32,
    refcon: UnsafeMutableRawPointer?
) {
    guard let detector = MultitouchGestureDetector.sharedInstance else { return }
    detector.processTouches(touches, count: Int(numTouches), timestamp: timestamp)
}

// MARK: - Path API Callback

private var lastTouchdownPathID: Int? = nil
private var pathTouchdownPositions: [Int: Float] = [:]
private var activePathIDs: Set<Int> = []
private var pendingAddGesture: (anchorX: Float, fingerCount: Int, anchorID: Int)? = nil

private func pathCallback(
    device: MTDeviceRef?,
    pathID: Int,
    state: Int32,
    path: MTPathRef?
) {
    if state == 3 {  // MakeTouch / touchdown
        lastTouchdownPathID = pathID
        activePathIDs.insert(pathID)
        print("🔬 [Path] TOUCHDOWN pathID=\(pathID), active=\(activePathIDs.sorted())")
        
        // Check if we have a pending add gesture waiting for this finger
        if let pending = pendingAddGesture, pathID != pending.anchorID {
            // This is the new finger we were waiting for
            if let newX = pathTouchdownPositions[pathID] {
                let direction = newX > pending.anchorX ? "RIGHT" : "LEFT"
                print("🔍 [Add] Deferred detection: new finger id=\(pathID) at x=\(String(format: "%.3f", newX)) → \(direction)")
                print("✅ [Gesture] ADD detected (deferred): \(pending.fingerCount) fingers")
                print("   Direction: \(direction)")
                
                DispatchQueue.main.async {
                    guard let detector = MultitouchGestureDetector.sharedInstance else { return }
                    detector.delegate?.didDetectSwipe(direction: .add, fingerCount: pending.fingerCount)
                    detector.onSwipeDetected?(.add, pending.fingerCount)
                }
            }
            pendingAddGesture = nil
        }
    } else if state == 0 || state == 7 {  // NotTracking or OutOfRange
        activePathIDs.remove(pathID)
        print("🔬 [Path] LIFTOFF pathID=\(pathID), active=\(activePathIDs.sorted())")
    }
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
