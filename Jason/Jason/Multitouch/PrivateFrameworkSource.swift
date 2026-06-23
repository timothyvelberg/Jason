//
//  PrivateFrameworkSource.swift
//  Jason
//
//  Created by Timothy Velberg on 10/01/2026.
//  Multitouch source using Apple's private MultitouchSupport.framework
//

import Foundation
import AppKit

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

    /// Set when the system is about to sleep. The current MTDeviceRefs become
    /// invalid across a sleep/wake cycle, so afterwards we must NOT call any
    /// MultitouchSupport function on them (even unregister) — doing so crashes.
    /// Guarded by `deviceLock`.
    private var devicesAreStale = false

    /// Token for the workspace sleep observer (block-based; removed in deinit).
    private var sleepObserver: NSObjectProtocol?

    // MARK: - Singleton for C Callback
    
    fileprivate static var shared: PrivateFrameworkSource?
    
    // MARK: - Lifecycle
    
    init() {
        // The MTDeviceRefs we create become invalid across sleep/wake; observe
        // sleep so we can avoid calling framework functions on stale handles.
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.markDevicesStale()
        }
        print("[PrivateFrameworkSource] Initialized")
    }

    deinit {
        if let sleepObserver = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
        }
        stopMonitoring()
        print("[PrivateFrameworkSource] Deallocated")
    }

    private func markDevicesStale() {
        deviceLock.lock()
        devicesAreStale = true
        deviceLock.unlock()
        print("[PrivateFrameworkSource] System will sleep — devices marked stale")
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
            devicesAreStale = false  // handles came from a fresh MTDeviceCreateList
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

        if devicesAreStale {
            // After sleep the MTDeviceRefs are invalid; calling ANY MultitouchSupport
            // function on them (even unregister) can crash. Just drop the handles and
            // let startMonitoring() build a fresh list.
            print("[PrivateFrameworkSource] Devices stale (post-sleep) — discarding without framework calls")
        } else {
            // Normal teardown: stop the device and unregister our callback. Do NOT
            // call MTDeviceRelease — the device pointers come from MTDeviceCreateList's
            // array by the Get Rule (borrowed; owned by the framework, not us), so
            // releasing them over-releases and crashes inside CFRelease. Stopping
            // pairs with MTDeviceStart so a later restart doesn't double-start.
            for device in devices {
                MTDeviceStop(device)
                MTUnregisterContactFrameCallback(device, privateFrameworkTouchCallback)
            }
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
        
        // After wake, device references are stale/invalid
        // Just clear state and start fresh - don't try to stop dead devices
        devices.removeAll()
        isMonitoring = false
        PrivateFrameworkSource.shared = nil
        
        deviceLock.unlock()
        
        // Now safe to restart with fresh device list
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
