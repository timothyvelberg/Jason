//
//  PrivateFrameworkSource.swift
//  Jason
//
//  Created by Timothy Velberg on 10/01/2026.
//  Multitouch source using Apple's private MultitouchSupport.framework
//

import Foundation

/// Multitouch source using the private MultitouchSupport framework
class PrivateFrameworkSource: MultitouchSourceProtocol {
    
    // MARK: - Protocol Properties
    
    var onTouchFrame: ((TouchFrame) -> Void)?
    
    // Thread-safe monitoring state (accessed from callback thread and main thread)
    private var _isMonitoring: Bool = false
    private let monitoringLock = NSLock()
    
    var isMonitoring: Bool {
        get {
            monitoringLock.lock()
            defer { monitoringLock.unlock() }
            return _isMonitoring
        }
        set {
            monitoringLock.lock()
            _isMonitoring = newValue
            monitoringLock.unlock()
        }
    }
    
    // MARK: - Device Management
    
    private var devices: [MTDeviceRef] = []
    private let deviceLock = NSLock()
    
    // MARK: - Singleton for C Callback
    
    fileprivate static var shared: PrivateFrameworkSource?
    
    // MARK: - Lifecycle
    
    init() {
        print("[PrivateFrameworkSource] Initialized")
    }
    
    deinit {
        stopMonitoring()
        print("[PrivateFrameworkSource] Deallocated")
    }
    
    // MARK: - Protocol Methods
    
    func startMonitoring() {
        deviceLock.lock()
        defer { deviceLock.unlock() }
        
        guard !isMonitoring else {
            print("[PrivateFrameworkSource] Already monitoring")
            return
        }
        
        print("[PrivateFrameworkSource] Starting...")
        
        guard let deviceList = MTDeviceCreateList() else {
            print("[PrivateFrameworkSource] Failed to get device list")
            return
        }
        
        let deviceArray = deviceList.takeRetainedValue()
        let count = CFArrayGetCount(deviceArray)
        print("   Found \(count) multitouch device(s)")
        
        for i in 0..<count {
            let devicePtr = CFArrayGetValueAtIndex(deviceArray, i)
            let device = unsafeBitCast(devicePtr, to: MTDeviceRef.self)
            
            let isBuiltIn = MTDeviceIsBuiltIn(device)
            let deviceType = isBuiltIn ? "built-in" : "external"
            print("   Device \(i): \(deviceType)")
            
            MTRegisterContactFrameCallback(device, privateFrameworkTouchCallback)
            MTDeviceStart(device, 0)
            
            devices.append(device)
            print("   Registered \(deviceType) trackpad")
        }
        
        if devices.isEmpty {
            print("[PrivateFrameworkSource] No devices found")
        } else {
            isMonitoring = true
            PrivateFrameworkSource.shared = self
            print("[PrivateFrameworkSource] Monitoring started")
        }
    }
    
    func stopMonitoring() {
        deviceLock.lock()
        defer { deviceLock.unlock() }
        
        guard isMonitoring else { return }
        
        print("[PrivateFrameworkSource] Stopping...")
        
        // Clear state FIRST to stop accepting callbacks
        isMonitoring = false
        PrivateFrameworkSource.shared = nil
        
        // THEN unregister (callbacks may still fire but will be ignored)
        for device in devices {
            MTUnregisterContactFrameCallback(device, privateFrameworkTouchCallback)
            MTDeviceStop(device)
        }
        
        devices.removeAll()
        
        print("[PrivateFrameworkSource] Stopped")
    }
    
    func prepareForSleep() {
        print("[PrivateFrameworkSource] Preparing for sleep...")
        stopMonitoring()
    }
    
    func restartAfterWake() {
        print("[PrivateFrameworkSource] Restarting after wake...")
        
        deviceLock.lock()
        
        // Clear everything BEFORE unregistering to prevent race
        let oldDevices = devices
        devices.removeAll()
        isMonitoring = false
        PrivateFrameworkSource.shared = nil
        
        deviceLock.unlock()
        
        // Unregister callbacks (they may still fire but will be ignored by guard)
        for device in oldDevices {
            MTUnregisterContactFrameCallback(device, privateFrameworkTouchCallback)
            MTDeviceStop(device)
        }
        
        // Now safe to restart - callback guard handles any spurious events
        startMonitoring()
    }
    
    // MARK: - Touch Processing
    
    fileprivate func processTouches(_ rawTouches: UnsafeMutablePointer<MTTouch>?, count: Int, timestamp: Double) {
        guard isMonitoring else { return }
        
        var touches: [TouchPoint] = []
        
        if let rawTouches = rawTouches {
            for i in 0..<count {
                let mt = rawTouches[i]
                
                // Try to get state, default to .touching if invalid (position may still be valid)
                let state = TouchState(rawValue: Int(mt.state)) ?? .touching
                
                let touch = TouchPoint(
                    identifier: Int(mt.identifier),
                    x: mt.normalizedX,
                    y: mt.normalizedY,
                    state: state,
                    timestamp: timestamp
                )
                touches.append(touch)
            }
        }
        
        // Pass raw count - crucial for multi-finger detection
        let frame = TouchFrame(touches: touches, timestamp: timestamp, rawFingerCount: count)
        onTouchFrame?(frame)
    }
}

// MARK: - C Callback

private func privateFrameworkTouchCallback(
    device: MTDeviceRef?,
    touches: UnsafeMutablePointer<MTTouch>?,
    numTouches: Int32,
    timestamp: Double,
    frame: Int32,
    refcon: UnsafeMutableRawPointer?
) {
    // CRITICAL: Guard against callbacks firing during/after cleanup
    // The device pointer may be stale/invalid during wake cycles
    guard let source = PrivateFrameworkSource.shared,
          source.isMonitoring else {
        #if DEBUG
        // Log spurious callbacks in debug builds to track wake behavior
        // (Comment out if too noisy)
        // print("⚠️ [MTCallback] Ignored spurious callback (not monitoring)")
        #endif
        return
    }
    
    source.processTouches(touches, count: Int(numTouches), timestamp: timestamp)
}
