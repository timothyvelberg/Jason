//
//  HotkeyManager+Circles.swift
//  Jason
//
//  Created by Timothy Velberg on 14/03/2026.

import AppKit

extension HotkeyManager {
    
    // MARK: - Registration
    
    func registerCircle(
        direction: RotationDirection,
        fingerCount: Int,
        modifierFlags: UInt,
        bundleId: String? = nil,
        forConfigId configId: Int,
        callback: @escaping (RotationDirection) -> Void
    ) {
        let display = formatCircleGesture(direction: direction, fingerCount: fingerCount, modifiers: modifierFlags)
        print("[HotkeyManager] Registering circle gesture for config \(configId): \(display)")
        
        // Only unregister if same combo AND same scope
        for (existingId, existing) in registeredCircles {
            if existing.direction == direction &&
               existing.fingerCount == fingerCount &&
               existing.modifierFlags == modifierFlags {
                
                let sameScope: Bool
                switch (bundleId, existing.bundleId) {
                case (nil, nil):                        sameScope = true   // both global
                case (let a?, let b?) where a == b:     sameScope = true   // same app
                case (nil, _), (_, nil):                sameScope = true   // global vs app-scoped — conflict
                default:                                sameScope = false  // different apps — no conflict
                }
                
                if sameScope {
                    unregisterCircle(forConfigId: existingId)
                    break
                }
            }
        }
        
        registeredCircles[configId] = (direction, fingerCount, modifierFlags, bundleId, callback)
    }
    
    func unregisterCircle(forConfigId configId: Int) {
        if let _ = registeredCircles.removeValue(forKey: configId) {
            print("[HotkeyManager] Unregistered circle for config \(configId)")
        }
    }
    
    func unregisterAllCircles() {
        let count = registeredCircles.count
        registeredCircles.removeAll()
        print("[HotkeyManager] Unregistered all \(count) circle gesture(s)")
    }
    
    // MARK: - Monitoring
    
    func startCircleMonitoring() {
        guard multitouchCoordinator == nil else {
            print("[HotkeyManager] Multitouch coordinator already exists")
            return
        }
        
        print("[HotkeyManager] Starting unified multitouch monitoring...")
        
        let coordinator = MultitouchCoordinator()
        coordinator.debugLogging = false
        
        coordinator.addRecognizer(CircleRecognizer())
        coordinator.addRecognizer(TwoFingerTapRecognizer())
        
        let multiFingerRecognizer = MultiFingerGestureRecognizer()
        multiFingerRecognizer.debugLogging = true
        coordinator.addRecognizer(multiFingerRecognizer)
        
        coordinator.onGesture = { [weak self] event in
            self?.handleGestureEvent(event)
        }
        
        if let saved = DatabaseManager.shared.loadCircleCalibration() {
            if let circleRec = coordinator.recognizer(identifier: "circle") as? CircleRecognizer {
                circleRec.config.maxRadiusVariance = saved.maxRadiusVariance
                circleRec.config.minCircles = saved.minCircles
                circleRec.config.minRadius = saved.minRadius
                print("   Applied calibration to recognizer")
            }
        } else {
            print("[HotkeyManager] No saved calibration found - using defaults")
        }
        
        coordinator.onCircleCalibrationComplete = { config in
            print("[HotkeyManager] Calibration complete - saving to database")
            let entry = CircleCalibrationEntry(
                maxRadiusVariance: config.maxRadiusVariance,
                minCircles: config.minCircles,
                minRadius: config.minRadius,
                calibratedAt: Date()
            )
            DatabaseManager.shared.saveCircleCalibration(entry)
        }
        
        coordinator.startMonitoring()
        LiveDataCoordinator.shared.register(coordinator)
        multitouchCoordinator = coordinator
        
        print("[HotkeyManager] Multitouch coordinator started with \(coordinator.recognizerCount) recognizer(s)")
    }
    
    func stopCircleMonitoring() {
        guard let coordinator = multitouchCoordinator else { return }
        LiveDataCoordinator.shared.unregister(coordinator)
        coordinator.stopMonitoring()
        multitouchCoordinator = nil
        print("[HotkeyManager] Multitouch coordinator stopped")
    }
    
    // MARK: - Calibration
    
    func startCircleCalibration() {
        multitouchCoordinator?.startCircleCalibration()
    }
    
    func cancelCircleCalibration() {
        multitouchCoordinator?.cancelCircleCalibration()
    }
    
    var isCircleCalibrating: Bool {
        multitouchCoordinator?.isCalibrating ?? false
    }
}
