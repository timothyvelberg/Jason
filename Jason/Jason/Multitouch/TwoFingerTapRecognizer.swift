//
//  TwoFingerTapRecognizer.swift
//  Jason
//
//  Recognizes two-finger taps with left/right detection
//  based on whether the second finger lands left or right of the first
//

import Foundation

/// Recognizes two-finger tap gestures with positional awareness
class TwoFingerTapRecognizer: GestureRecognizer {
    
    // MARK: - Protocol Properties
    
    let identifier = "two-finger-tap"
    var isEnabled: Bool = true
    var onGesture: ((GestureEvent) -> Void)?
    
    // MARK: - Configuration
    
    struct Config {
        /// Minimum delay before second finger can land (seconds)
        var minSecondFingerDelay: Double = 0.05
        
        /// Maximum delay for second finger to land (seconds)
        var maxSecondFingerDelay: Double = 0.5
        
        /// Maximum movement allowed for anchor finger (normalized, 0-1)
        var maxAnchorMovement: CGFloat = 0.05
        
        /// Maximum movement allowed for second finger (normalized, 0-1)
        var maxSecondFingerMovement: CGFloat = 0.05
        
        /// Maximum duration for the entire tap gesture (seconds)
        var maxTapDuration: Double = 0.8
        
        /// Minimum X distance between fingers to determine side (normalized)
        /// Prevents ambiguous "center" taps from firing
        var minXDifference: CGFloat = 0.02
        
        /// Grace period for second finger to lift after first (seconds)
        var liftGracePeriod: Double = 0.15
    }
    
    var config = Config()
    var debugLogging: Bool = false
    
    // MARK: - State
    
    private enum State {
        case idle
        case trackingFirstFinger(finger: TrackedFinger)
        case trackingBothFingers(first: TrackedFinger, second: TrackedFinger, side: TapSide)
        case waitingForSecondLift(side: TapSide, firstLiftTime: Double)
    }
    
    private struct TrackedFinger {
        let identifier: Int
        let startPosition: CGPoint
        var currentPosition: CGPoint
        let startTime: Double
    }
    
    private var state: State = .idle
    
    // MARK: - Protocol Methods
    
    func processTouchFrame(_ frame: TouchFrame) {
        guard isEnabled else { return }
        
        let activeTouches = frame.touches.filter { $0.state.isActive }
        let newTouches = frame.touches.filter { $0.state == .makeTouch }
        let liftingTouches = frame.touches.filter { $0.state == .breakTouch }
        
        switch state {
        case .idle:
            handleIdleState(frame: frame, newTouches: newTouches)
            
        case .trackingFirstFinger(let first):
            handleTrackingFirstFinger(
                frame: frame,
                first: first,
                activeTouches: activeTouches,
                newTouches: newTouches,
                liftingTouches: liftingTouches
            )
            
        case .trackingBothFingers(let first, let second, let side):
            handleTrackingBothFingers(
                frame: frame,
                first: first,
                second: second,
                side: side,
                activeTouches: activeTouches,
                liftingTouches: liftingTouches
            )
            
        case .waitingForSecondLift(let side, let firstLiftTime):
            handleWaitingForSecondLift(
                frame: frame,
                side: side,
                firstLiftTime: firstLiftTime,
                activeTouches: activeTouches
            )
        }
    }
    
    func reset() {
        state = .idle
    }
    
    // MARK: - State Handlers
    
    private func handleIdleState(frame: TouchFrame, newTouches: [TouchPoint]) {
        // Look for first finger landing
        guard let firstTouch = newTouches.first else { return }
        
        let finger = TrackedFinger(
            identifier: firstTouch.identifier,
            startPosition: firstTouch.position,
            currentPosition: firstTouch.position,
            startTime: frame.timestamp
        )
        
        state = .trackingFirstFinger(finger: finger)
        
        if debugLogging {
            print("👆 [TwoFingerTap] First finger down at x=\(String(format: "%.3f", firstTouch.position.x))")
        }
    }
    
    private func handleTrackingFirstFinger(
        frame: TouchFrame,
        first: TrackedFinger,
        activeTouches: [TouchPoint],
        newTouches: [TouchPoint],
        liftingTouches: [TouchPoint]
    ) {
        let elapsed = frame.timestamp - first.startTime
        
        // Check for timeout
        if elapsed > config.maxTapDuration {
            if debugLogging {
                print("👆 [TwoFingerTap] Timeout waiting for second finger")
            }
            reset()
            return
        }
        
        // Check if first finger lifted (single finger tap, not our gesture)
        if liftingTouches.contains(where: { $0.identifier == first.identifier }) {
            reset()
            return
        }
        
        // Update first finger position
        var updatedFirst = first
        if let currentFirst = activeTouches.first(where: { $0.identifier == first.identifier }) {
            updatedFirst.currentPosition = currentFirst.position
            
            // Check if first finger moved too much
            let movement = distance(from: first.startPosition, to: currentFirst.position)
            if movement > config.maxAnchorMovement {
                if debugLogging {
                    print("👆 [TwoFingerTap] First finger moved too much: \(String(format: "%.3f", movement))")
                }
                reset()
                return
            }
        }
        
        // Look for second finger landing
        if let secondTouch = newTouches.first(where: { $0.identifier != first.identifier }) {
            // Check timing window
            if elapsed < config.minSecondFingerDelay {
                if debugLogging {
                    print("👆 [TwoFingerTap] Second finger too fast: \(String(format: "%.0f", elapsed * 1000))ms")
                }
                reset()
                return
            }
            
            if elapsed > config.maxSecondFingerDelay {
                if debugLogging {
                    print("👆 [TwoFingerTap] Second finger too slow: \(String(format: "%.0f", elapsed * 1000))ms")
                }
                reset()
                return
            }
            
            // Determine side based on X position
            let xDiff = secondTouch.position.x - updatedFirst.currentPosition.x
            
            if abs(xDiff) < config.minXDifference {
                if debugLogging {
                    print("👆 [TwoFingerTap] Fingers too close horizontally: \(String(format: "%.3f", abs(xDiff)))")
                }
                reset()
                return
            }
            
            let side: TapSide = xDiff < 0 ? .left : .right
            
            let secondFinger = TrackedFinger(
                identifier: secondTouch.identifier,
                startPosition: secondTouch.position,
                currentPosition: secondTouch.position,
                startTime: frame.timestamp
            )
            
            state = .trackingBothFingers(first: updatedFirst, second: secondFinger, side: side)
            
            if debugLogging {
                print("👆 [TwoFingerTap] Second finger down at x=\(String(format: "%.3f", secondTouch.position.x)) → \(side.rawValue.uppercased())")
            }
        } else {
            // Just update state with new position
            state = .trackingFirstFinger(finger: updatedFirst)
        }
    }
    
    private func handleTrackingBothFingers(
        frame: TouchFrame,
        first: TrackedFinger,
        second: TrackedFinger,
        side: TapSide,
        activeTouches: [TouchPoint],
        liftingTouches: [TouchPoint]
    ) {
        let elapsed = frame.timestamp - first.startTime
        
        // Check for timeout
        if elapsed > config.maxTapDuration {
            if debugLogging {
                print("👆 [TwoFingerTap] Gesture timeout")
            }
            reset()
            return
        }
        
        // Check movement for both fingers
        if let currentFirst = activeTouches.first(where: { $0.identifier == first.identifier }) {
            let movement = distance(from: first.startPosition, to: currentFirst.position)
            if movement > config.maxAnchorMovement {
                if debugLogging {
                    print("👆 [TwoFingerTap] First finger moved too much during tap")
                }
                reset()
                return
            }
        }
        
        if let currentSecond = activeTouches.first(where: { $0.identifier == second.identifier }) {
            let movement = distance(from: second.startPosition, to: currentSecond.position)
            if movement > config.maxSecondFingerMovement {
                if debugLogging {
                    print("👆 [TwoFingerTap] Second finger moved too much during tap")
                }
                reset()
                return
            }
        }
        
        // Check if fingers have lifted
        let firstLifted = liftingTouches.contains(where: { $0.identifier == first.identifier }) ||
                          !activeTouches.contains(where: { $0.identifier == first.identifier })
        let secondLifted = liftingTouches.contains(where: { $0.identifier == second.identifier }) ||
                           !activeTouches.contains(where: { $0.identifier == second.identifier })
        
        if firstLifted && secondLifted {
            // Success! Fire the event
            if debugLogging {
                print("👆 [TwoFingerTap] ✅ Detected: \(side.rawValue.uppercased())")
            }
            
            let event = GestureEvent.twoFingerTap(side: side)
            onGesture?(event)
            reset()
        } else if firstLifted || secondLifted {
            // One finger lifted - enter grace period
            state = .waitingForSecondLift(side: side, firstLiftTime: frame.timestamp)
        }
    }
    
    private func handleWaitingForSecondLift(
        frame: TouchFrame,
        side: TapSide,
        firstLiftTime: Double,
        activeTouches: [TouchPoint]
    ) {
        let elapsed = frame.timestamp - firstLiftTime
        
        // Check grace period timeout
        if elapsed > config.liftGracePeriod {
            if debugLogging {
                print("👆 [TwoFingerTap] Second finger didn't lift in time")
            }
            reset()
            return
        }
        
        // Check if all fingers are now lifted
        if activeTouches.isEmpty {
            if debugLogging {
                print("👆 [TwoFingerTap] ✅ Detected: \(side.rawValue.uppercased())")
            }
            
            let event = GestureEvent.twoFingerTap(side: side)
            onGesture?(event)
            reset()
        }
    }
    
    // MARK: - Helpers
    
    private func distance(from p1: CGPoint, to p2: CGPoint) -> CGFloat {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        return sqrt(dx * dx + dy * dy)
    }
}
