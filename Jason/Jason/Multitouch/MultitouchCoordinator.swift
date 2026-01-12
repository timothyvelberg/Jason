//
//  MultitouchCoordinator.swift
//  Jason
//
//  Coordinates multitouch source and gesture recognizers
//

import Foundation

/// Coordinates multitouch input and gesture recognition
class MultitouchCoordinator {
    
    // MARK: - Properties
    
    /// The touch data source
    private let source: MultitouchSourceProtocol
    
    /// Registered gesture recognizers
    private var recognizers: [GestureRecognizer] = []
    
    /// Unified callback for all gesture events
    var onGesture: ((GestureEvent) -> Void)?
    
    /// Whether the coordinator is active
    var isMonitoring: Bool { source.isMonitoring }
    
    var recognizerCount: Int { recognizers.count }
    // MARK: - Debug
    
    var debugLogging: Bool = false {
        didSet {
            // Propagate to recognizers that support it
            for recognizer in recognizers {
                if let circle = recognizer as? CircleRecognizer {
                    circle.debugLogging = debugLogging
                }
            }
        }
    }
    
    /// Called when circle calibration completes
    var onCircleCalibrationComplete: ((CircleRecognizer.Config) -> Void)?
    
    
    
    // MARK: - Initialization
    
    /// Create coordinator with specified source
    /// - Parameter source: The multitouch data source to use
    init(source: MultitouchSourceProtocol = PrivateFrameworkSource()) {
        self.source = source
        
        // Wire up source to feed recognizers
        source.onTouchFrame = { [weak self] frame in
            self?.processTouchFrame(frame)
        }
        
        print("🎛️ [MultitouchCoordinator] Initialized")
    }
    
    deinit {
        stopMonitoring()
        print("🎛️ [MultitouchCoordinator] Deallocated")
    }
    
    // MARK: - Recognizer Management
    
    /// Add a gesture recognizer
    func addRecognizer(_ recognizer: GestureRecognizer) {
        // Wire recognizer events to coordinator
        recognizer.onGesture = { [weak self] event in
            self?.handleGestureEvent(event, from: recognizer)
        }
    
        if let circleRecognizer = recognizer as? CircleRecognizer {
            circleRecognizer.onCalibrationComplete = { [weak self] config in
                self?.onCircleCalibrationComplete?(config)
            }
        }
        
        recognizers.append(recognizer)
        print("🎛️ [MultitouchCoordinator] Added recognizer: \(recognizer.identifier)")
    }
    
    /// Remove a gesture recognizer by identifier
    func removeRecognizer(identifier: String) {
        recognizers.removeAll { $0.identifier == identifier }
        print("🎛️ [MultitouchCoordinator] Removed recognizer: \(identifier)")
    }
    
    /// Get a recognizer by identifier
    func recognizer(identifier: String) -> GestureRecognizer? {
        return recognizers.first { $0.identifier == identifier }
    }
    
    // MARK: - Monitoring
    
    /// Start monitoring for gestures
    func startMonitoring() {
        print("🎛️ [MultitouchCoordinator] Starting with \(recognizers.count) recognizer(s)...")
        source.startMonitoring()
    }
    
    /// Stop monitoring
    func stopMonitoring() {
        source.stopMonitoring()
        resetAllRecognizers()
        print("🎛️ [MultitouchCoordinator] Stopped")
    }
    
    /// Prepare for system sleep
    func prepareForSleep() {
        source.prepareForSleep()
        resetAllRecognizers()
    }
    
    /// Restart after system wake
    func restartAfterWake() {
        source.restartAfterWake()
    }
    
    // MARK: - Private
    
    private func processTouchFrame(_ frame: TouchFrame) {
        // Feed frame to all enabled recognizers
        for recognizer in recognizers where recognizer.isEnabled {
            recognizer.processTouchFrame(frame)
        }
    }
    
    private func handleGestureEvent(_ event: GestureEvent, from recognizer: GestureRecognizer) {
        if debugLogging {
            print("🎛️ [MultitouchCoordinator] Gesture from \(recognizer.identifier): \(event.description)")
        }
        
        // Forward to unified callback
        onGesture?(event)
    }
    
    private func resetAllRecognizers() {
        for recognizer in recognizers {
            recognizer.reset()
        }
    }
    
    // MARK: - Calibration
    
    /// Start circle calibration mode
    func startCircleCalibration() {
        if let circleRecognizer = recognizer(identifier: "circle") as? CircleRecognizer {
            circleRecognizer.startCalibration()
        } else {
            print("⚠️ [MultitouchCoordinator] No circle recognizer found for calibration")
        }
    }
    
    /// Cancel circle calibration
    func cancelCircleCalibration() {
        if let circleRecognizer = recognizer(identifier: "circle") as? CircleRecognizer {
            circleRecognizer.cancelCalibration()
        }
    }
    
    /// Check if currently calibrating
    var isCalibrating: Bool {
        if let circleRecognizer = recognizer(identifier: "circle") as? CircleRecognizer {
            return circleRecognizer.calibrating
        }
        return false
    }
}

// MARK: - Convenience Factory

extension MultitouchCoordinator {
    
    /// Create a coordinator with circle recognition enabled
    static func withCircleRecognition(debugLogging: Bool = false) -> MultitouchCoordinator {
        let coordinator = MultitouchCoordinator()
        coordinator.debugLogging = debugLogging
        
        let circleRecognizer = CircleRecognizer()
        circleRecognizer.debugLogging = debugLogging
        coordinator.addRecognizer(circleRecognizer)
        
        return coordinator
    }
}

// MARK: - LiveDataStream Conformance

extension MultitouchCoordinator: LiveDataStream {
    var streamId: String { "circle-gesture" }
    
    func restartMonitoring() {
        print("🔄 [MultitouchCoordinator] Restarting after wake...")
        source.stopMonitoring()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.source.startMonitoring()
        }
    }
}
