//
//  LiveDataStream.swift
//  Jason
//
//  Created by Timothy Velberg on 27/11/2025.

//  Protocol defining the interface for live data streams
//  (running apps, trackpad gestures, folder watchers, etc.)

import Foundation

/// Protocol for components that monitor external data sources in real-time
protocol LiveDataStream: AnyObject {
    
    /// Unique identifier for this stream (for logging/debugging)
    var streamId: String { get }
    
    /// Whether the stream is currently monitoring
    var isMonitoring: Bool { get }
    
    /// Start monitoring for changes
    func startMonitoring()
    
    /// Stop monitoring
    func stopMonitoring()
    
    /// Restart monitoring (convenience - stops then starts)
    func restartMonitoring()
}

// MARK: - Default Implementation

extension LiveDataStream {
    
    /// Default restart implementation
    func restartMonitoring() {
        print("🔄 [\(streamId)] Restarting monitoring...")
        stopMonitoring()
        startMonitoring()
    }
}
