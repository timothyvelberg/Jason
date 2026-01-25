//
//  LiveDataCoordinator.swift
//  Jason
//
//  Created by Timothy Velberg on 27/11/2025.
//
//  Coordinates all live data streams (running apps, gestures, folder watchers)
//  Handles sleep/wake cycles to restart monitoring after system resume
//

import Foundation
import AppKit

/// Coordinates all live data monitoring streams
/// Single point of control for starting, stopping, and restarting live data sources
class LiveDataCoordinator {
    
    // MARK: - Singleton
    
    static let shared = LiveDataCoordinator()
    
    // MARK: - Streams
    
    /// All registered live data streams
    private var streams: [LiveDataStream] = []
    
    /// Whether the coordinator has been started
    private(set) var isRunning: Bool = false
    
    // MARK: - Configuration
    
    /// Delay after wake before restarting streams (allows hardware to reinitialize)
    private let wakeRestartDelay: TimeInterval = 0.5
    
    // MARK: - Initialization
    
    private init() {
        print("[LiveDataCoordinator] Initialized")
        setupSystemObservers()
    }
    
    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        print("[LiveDataCoordinator] Deallocated")
    }
    
    // MARK: - Stream Registration
    
    /// Register a live data stream to be managed by the coordinator
    func register(_ stream: LiveDataStream) {
        // Avoid duplicate registration
        guard !streams.contains(where: { $0.streamId == stream.streamId }) else {
            print("[LiveDataCoordinator] Stream '\(stream.streamId)' already registered")
            return
        }
        
        streams.append(stream)
        print("[LiveDataCoordinator] Registered stream: \(stream.streamId)")
        
        // If coordinator is already running, start this stream immediately
        if isRunning && !stream.isMonitoring {
            print("   Auto-starting (coordinator already running)")
            stream.startMonitoring()
        }
    }
    
    /// Unregister a stream
    func unregister(_ stream: LiveDataStream) {
        streams.removeAll { $0.streamId == stream.streamId }
        print("[LiveDataCoordinator] Unregistered stream: \(stream.streamId)")
    }
    
    // MARK: - Lifecycle Control
    
    /// Start all registered streams
    func startAll() {
        guard !isRunning else {
            print("[LiveDataCoordinator] Already running")
            return
        }
        
        print("[LiveDataCoordinator] Starting all streams...")
        isRunning = true
        
        for stream in streams {
            if !stream.isMonitoring {
                stream.startMonitoring()
            } else {
                print("   \(stream.streamId) already monitoring")
            }
        }
        
        printStatus()
    }
    
    /// Stop all registered streams
    func stopAll() {
        guard isRunning else {
            print("[LiveDataCoordinator] Not running")
            return
        }
        
        print("[LiveDataCoordinator] Stopping all streams...")
        isRunning = false
        
        for stream in streams {
            if stream.isMonitoring {
                stream.stopMonitoring()
            }
        }
        
        printStatus()
    }
    
    /// Restart all streams (used after sleep/wake)
    func restartAll() {
        print("[LiveDataCoordinator] Restarting all streams...")
        
        for stream in streams {
            stream.restartMonitoring()
        }
        
        printStatus()
    }
    
    // MARK: - System Observers
    
    private func setupSystemObservers() {
        let workspaceNC = NSWorkspace.shared.notificationCenter
        
        // Sleep notification
        workspaceNC.addObserver(
            self,
            selector: #selector(handleSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        
        // Wake notification
        workspaceNC.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        
        print("[LiveDataCoordinator] Sleep/wake observers registered")
    }
    
    @objc private func handleSleep() {
        print("[LiveDataCoordinator] System going to sleep...")
        
        // Log which streams are currently active
        let activeStreams = streams.filter { $0.isMonitoring }
        if !activeStreams.isEmpty {
            print("   Active streams that will need restart:")
            for stream in activeStreams {
                print("   • \(stream.streamId)")
            }
        }
        
        // Note: We don't stop streams here - the system handles suspension
        // Some streams (like NSWorkspace notifications) survive sleep fine
        // Others (like MultitouchSupport) need restart after wake
    }
    
    @objc private func handleWake() {
        print("[LiveDataCoordinator] System woke up")
        
        guard isRunning else {
            print("   Coordinator not running - skipping restart")
            return
        }
        
        // Delay restart to allow hardware to reinitialize
        print("   Waiting \(wakeRestartDelay)s for hardware to reinitialize...")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + wakeRestartDelay) { [weak self] in
            guard let self = self else { return }
            
            print("[LiveDataCoordinator] Restarting streams after wake...")
            self.restartAll()
        }
    }
    
    // MARK: - Status & Debugging
    
    /// Print current status of all streams
    func printStatus() {
        print("[LiveDataCoordinator] Status:")
        print("   Running: \(isRunning)")
        print("   Registered streams: \(streams.count)")
        
        for stream in streams {
            let status = stream.isMonitoring ? "monitoring" : "stopped"
            print("   \(stream.streamId): \(status)")
        }
    }
    
    /// Get list of registered stream IDs
    var registeredStreamIds: [String] {
        return streams.map { $0.streamId }
    }
    
    /// Get count of active (monitoring) streams
    var activeStreamCount: Int {
        return streams.filter { $0.isMonitoring }.count
    }
}
