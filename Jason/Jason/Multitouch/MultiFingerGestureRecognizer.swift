//
//  MultiFingerGestureRecognizer.swift
//  Jason
//
//  Created by Timothy Velberg on 12/01/2026.
//
//  Recognizes multi-finger gestures: swipes, taps, and finger-add gestures
//  Consolidates logic from the old MultitouchGestureDetector
//

import Foundation

/// Recognizes multi-finger gestures (3+ finger swipes/taps, finger-add gestures)
class MultiFingerGestureRecognizer: GestureRecognizer {
    
    // MARK: - Protocol Properties
    
    let identifier = "multi-finger"
    var isEnabled: Bool = true
    var onGesture: ((GestureEvent) -> Void)?
    
    // MARK: - Configuration
    
    struct Config {
        // Swipe thresholds
        var minSwipeDistance: Float = 0.15      // Normalized coordinates 0-1
        var maxSwipeDuration: Double = 0.5      // Seconds
        var minSwipeVelocity: Float = 0.3       // Distance per second
        
        // Tap thresholds
        var maxTapDistance: Float = 0.03        // Max movement for tap
        var maxTapDuration: Double = 0.6        // Seconds
        
        // Add gesture thresholds
        var addGestureMinDelay: Double = 0.2    // Min time before adding finger
        var addGestureMaxDelay: Double = 0.8    // Max time to add finger
        var addGestureMaxMovement: Float = 0.03 // Max anchor movement
        
        // Gesture start validation
        var maxTimeToReachTargetFingers: Double = 0.3  // Time allowed to go from first touch to 3 fingers
    }
    
    var config = Config()
    var debugLogging: Bool = false
    
    // MARK: - State Tracking
    
    private enum GesturePhase {
        case idle
        case buildingUp          // Fingers landing, not yet at target count
        case tracking            // At 3+ fingers, tracking movement
        case completed           // Gesture analyzed, waiting for lift
    }
    
    private var phase: GesturePhase = .idle
    
    /// Timestamp when first finger landed (for build-up timing)
    private var firstTouchTimestamp: Double = 0
    
    /// Timestamp when we reached 3+ fingers
    private var gestureStartTimestamp: Double = 0
    
    /// Finger count when gesture tracking started
    private var gestureFingerCount: Int = 0
    
    /// Starting position of primary touch (for swipe/tap detection)
    private var startPosition: CGPoint = .zero
    
    /// Current position of primary touch
    private var currentPosition: CGPoint = .zero
    
    /// Previous frame's finger count
    private var lastFingerCount: Int = 0
    
    // MARK: - Add Gesture State
    
    /// Anchor finger info for add detection
    private var anchorInfo: (id: Int, position: CGPoint, timestamp: Double)?
    
    /// Whether anchor is eligible for add gesture
    private var isAnchorEligible: Bool = false
    
    /// Whether we've fired an add gesture this touch sequence
    private var hasFiredAddGesture: Bool = false
    
    /// Stable finger count for add gesture tracking
    private var stableFingerCount: Int = 0
    
    // MARK: - Protocol Methods
    
    func processTouchFrame(_ frame: TouchFrame) {
        if debugLogging && frame.touches.count > 0 {
            let activeCount = frame.touches.filter { $0.state.isActive }.count
        }
        
        guard isEnabled else { return }
        
        // Use raw count for finger detection (struct layout issues affect state parsing)
        let currentCount = frame.rawFingerCount
        let activeTouches = frame.touches  // Keep all touches for position data
        let timestamp = frame.timestamp

        
        defer { lastFingerCount = currentCount }
        
        // === ALL FINGERS LIFTED ===
        if currentCount == 0 {
            if phase == .tracking {
                analyzeGesture(endTime: timestamp)
            }
            resetState()
            return
        }
        
        // Get primary touch (first in array)
        guard let primaryTouch = activeTouches.first else { return }
        
        // === FIRST FINGER DOWN (0 → 1+) ===
        if lastFingerCount == 0 && currentCount > 0 {
            firstTouchTimestamp = timestamp
            phase = .buildingUp
            
            // Set anchor for potential add gesture
            anchorInfo = (primaryTouch.identifier, primaryTouch.position, timestamp)
            isAnchorEligible = true
            stableFingerCount = currentCount
            hasFiredAddGesture = false
            
            if debugLogging {
                print("🖐️ [MultiFingerGesture] First touch - starting build-up")
            }
        }
        
        // === FINGER COUNT INCREASED ===
        if currentCount > lastFingerCount {
            handleFingerAdded(
                newCount: currentCount,
                oldCount: lastFingerCount,
                primaryTouch: primaryTouch,
                timestamp: timestamp
            )
        }
        
        // === REACHED 3+ FINGERS ===
        if currentCount >= 3 && phase == .buildingUp {
            let buildUpTime = timestamp - firstTouchTimestamp
            
            // Validate build-up time
            if buildUpTime <= config.maxTimeToReachTargetFingers {
                phase = .tracking
                gestureStartTimestamp = timestamp
                gestureFingerCount = currentCount
                startPosition = primaryTouch.position
                currentPosition = primaryTouch.position
                
                if debugLogging {
                    print("🖐️ [MultiFingerGesture] Started tracking \(currentCount)-finger gesture (build-up: \(String(format: "%.0f", buildUpTime * 1000))ms)")
                }
            } else {
                // Took too long to get fingers down - not a deliberate gesture
                phase = .completed
                if debugLogging {
                    print("🖐️ [MultiFingerGesture] Build-up too slow (\(String(format: "%.0f", buildUpTime * 1000))ms) - ignoring")
                }
            }
        }
        
        // === TRACKING MOVEMENT ===
        if phase == .tracking && currentCount >= 3 {
            currentPosition = primaryTouch.position
        }
        
        // === FINGER COUNT DECREASED BELOW 3 ===
        if currentCount < 3 && phase == .tracking {
            analyzeGesture(endTime: timestamp)
            phase = .completed
        }
        
        // === UPDATE ANCHOR FOR ADD GESTURE ===
        updateAnchorTracking(activeTouches: activeTouches, timestamp: timestamp)
    }
    
    func reset() {
        resetState()
    }
    
    // MARK: - Private Methods
    
    private func resetState() {
        phase = .idle
        firstTouchTimestamp = 0
        gestureStartTimestamp = 0
        gestureFingerCount = 0
        startPosition = .zero
        currentPosition = .zero
        lastFingerCount = 0
        anchorInfo = nil
        isAnchorEligible = false
        hasFiredAddGesture = false
        stableFingerCount = 0
    }
    
    private func handleFingerAdded(
        newCount: Int,
        oldCount: Int,
        primaryTouch: TouchPoint,
        timestamp: Double
    ) {
        // Check for add gesture (1→2 or 2→3)
        if newCount >= 2 && newCount <= 3 && !hasFiredAddGesture {
            if let anchor = anchorInfo, isAnchorEligible {
                let timeSinceAnchor = timestamp - anchor.timestamp
                let isInTimeWindow = timeSinceAnchor >= config.addGestureMinDelay &&
                                     timeSinceAnchor <= config.addGestureMaxDelay
                
                if isInTimeWindow {
                    if debugLogging {
                        print("✅ [MultiFingerGesture] ADD detected: \(oldCount)→\(newCount) fingers (delay: \(String(format: "%.0f", timeSinceAnchor * 1000))ms)")
                    }
                    
                    hasFiredAddGesture = true
                    let event = GestureEvent.fingerAdd(fromCount: oldCount, toCount: newCount)
                    
                    DispatchQueue.main.async { [weak self] in
                        self?.onGesture?(event)
                    }
                }
            }
        }
        
        // Update anchor for next potential add
        anchorInfo = (primaryTouch.identifier, primaryTouch.position, timestamp)
        isAnchorEligible = true
        stableFingerCount = newCount
    }
    
    private func updateAnchorTracking(activeTouches: [TouchPoint], timestamp: Double) {
        guard isAnchorEligible, let anchor = anchorInfo else { return }
        
        // Find the anchor finger in current touches
        if let anchorTouch = activeTouches.first(where: { $0.identifier == anchor.id }) {
            let dx = Float(anchorTouch.position.x - anchor.position.x)
            let dy = Float(anchorTouch.position.y - anchor.position.y)
            let movement = sqrt(dx * dx + dy * dy)
            
            if movement > config.addGestureMaxMovement {
                isAnchorEligible = false
            }
        }
    }
    
    private func analyzeGesture(endTime: Double) {
        let duration = endTime - gestureStartTimestamp
        
        let dx = Float(currentPosition.x - startPosition.x)
        let dy = Float(currentPosition.y - startPosition.y)
        let distance = sqrt(dx * dx + dy * dy)
        
        let fingerCount = gestureFingerCount
        
        if debugLogging {
            print("🖐️ [MultiFingerGesture] Analyzing: fingers=\(fingerCount), duration=\(String(format: "%.3f", duration))s, distance=\(String(format: "%.3f", distance))")
        }
        
        // === CHECK FOR TAP ===
        if duration <= config.maxTapDuration && distance < config.maxTapDistance {
            if debugLogging {
                print("✅ [MultiFingerGesture] TAP with \(fingerCount) fingers")
            }
            
            let event = GestureEvent.tap(fingerCount: fingerCount)
            DispatchQueue.main.async { [weak self] in
                self?.onGesture?(event)
            }
            return
        }
        
        // === CHECK FOR SWIPE ===
        guard duration <= config.maxSwipeDuration else {
            if debugLogging {
                print("🖐️ [MultiFingerGesture] Duration too long for swipe")
            }
            return
        }
        
        guard distance >= config.minSwipeDistance else {
            if debugLogging {
                print("🖐️ [MultiFingerGesture] Distance too short for swipe")
            }
            return
        }
        
        let velocity = distance / Float(duration)
        guard velocity >= config.minSwipeVelocity else {
            if debugLogging {
                print("🖐️ [MultiFingerGesture] Velocity too low for swipe")
            }
            return
        }
        
        // Determine direction
        let direction: MTSwipeDirection
        if abs(dy) > abs(dx) {
            // Note: Y is inverted in normalized coordinates (0 = bottom, 1 = top)
            direction = dy < 0 ? .down : .up
        } else {
            direction = dx > 0 ? .right : .left
        }
        
        if debugLogging {
            print("✅ [MultiFingerGesture] SWIPE \(direction.rawValue.uppercased()) with \(fingerCount) fingers")
        }
        
        let event = GestureEvent.swipe(direction: direction, fingerCount: fingerCount)
        DispatchQueue.main.async { [weak self] in
            self?.onGesture?(event)
        }
    }
}
