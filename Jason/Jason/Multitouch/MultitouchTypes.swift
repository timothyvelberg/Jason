//
//  MultitouchTypes.swift
//  Jason
//
//  Shared types for the multitouch gesture system
//

import Foundation

// MARK: - Touch Data

/// State of a touch point
enum TouchState: Int {
    case notTracking = 0
    case startInRange = 1
    case hoverInRange = 2
    case makeTouch = 3      // Finger just landed
    case touching = 4       // Finger is down and moving
    case breakTouch = 5     // Finger lifting
    case lingerInRange = 6
    case outOfRange = 7
    
    var isActive: Bool {
        return self == .makeTouch || self == .touching || self == .breakTouch
    }
    
    var isDown: Bool {
        return self == .makeTouch || self == .touching
    }
}

/// A single touch point with optional rich data
struct TouchPoint {
    let identifier: Int
    let position: CGPoint       // Normalized 0-1
    let state: TouchState
    let timestamp: Double
    
    // Optional rich data (OpenMT may provide, private framework may not)
    let ellipseMajor: Float?
    let ellipseMinor: Float?
    let ellipseAngle: Float?
    let pressure: Float?
    let handId: Int?
    
    /// Basic initializer for private framework data
    init(
        identifier: Int,
        x: Float,
        y: Float,
        state: TouchState,
        timestamp: Double
    ) {
        self.identifier = identifier
        self.position = CGPoint(x: CGFloat(x), y: CGFloat(y))
        self.state = state
        self.timestamp = timestamp
        self.ellipseMajor = nil
        self.ellipseMinor = nil
        self.ellipseAngle = nil
        self.pressure = nil
        self.handId = nil
    }
    
    /// Full initializer with rich data
    init(
        identifier: Int,
        position: CGPoint,
        state: TouchState,
        timestamp: Double,
        ellipseMajor: Float? = nil,
        ellipseMinor: Float? = nil,
        ellipseAngle: Float? = nil,
        pressure: Float? = nil,
        handId: Int? = nil
    ) {
        self.identifier = identifier
        self.position = position
        self.state = state
        self.timestamp = timestamp
        self.ellipseMajor = ellipseMajor
        self.ellipseMinor = ellipseMinor
        self.ellipseAngle = ellipseAngle
        self.pressure = pressure
        self.handId = handId
    }
}

/// A frame of touch data from the trackpad
struct TouchFrame {
    let touches: [TouchPoint]
    let timestamp: Double
    
    var fingerCount: Int { touches.filter { $0.state.isActive }.count }
}

// MARK: - Gesture Events

/// Direction of a swipe gesture (prefixed to avoid conflict with MultitouchGestureDetector)
enum MTSwipeDirection: String {
    case up, down, left, right
}

/// Rotation direction for circle gestures
enum RotationDirection {
    case clockwise
    case counterClockwise
}

/// Events that gesture recognizers can emit
enum GestureEvent {
    case swipe(direction: MTSwipeDirection, fingerCount: Int)
    case tap(fingerCount: Int)
    case circle(direction: RotationDirection, fingerCount: Int)
    case fingerAdd(fromCount: Int, toCount: Int)
    
    var description: String {
        switch self {
        case .swipe(let dir, let count):
            return "\(count)-finger swipe \(dir.rawValue)"
        case .tap(let count):
            return "\(count)-finger tap"
        case .circle(let dir, let count):
            let dirStr = dir == .clockwise ? "clockwise" : "counter-clockwise"
            return "\(count)-finger \(dirStr) circle"
        case .fingerAdd(let from, let to):
            return "finger add \(from)→\(to)"
        }
    }
}
