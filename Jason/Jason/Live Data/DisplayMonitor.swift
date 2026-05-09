//
//  DisplayMonitor.swift
//  Jason
//
//  Created by Timothy Velberg on 08/05/2026.
//  Monitors display configuration changes and exposes
//  spatial relationships between screens.
//

import Foundation
import AppKit

// MARK: - Supporting Types

enum ScreenDirection {
    case left, right, above, below
}

struct ScreenNeighbour {
    let screen: NSScreen
    let direction: ScreenDirection
}

// MARK: - DisplayMonitor

class DisplayMonitor: LiveDataStream {
    
    // MARK: - Singleton
    
    static let shared = DisplayMonitor()
    
    // MARK: - LiveDataStream
    
    var streamId: String { "display-monitor" }
    private(set) var isMonitoring: Bool = false
    
    // MARK: - State
    
    private(set) var screens: [NSScreen] = NSScreen.screens
    
    var screenCount: Int { screens.count }
    var hasMultipleScreens: Bool { screens.count > 1 }
    
    // MARK: - Init
    
    private init() {
        print("[DisplayMonitor] Initialized with \(NSScreen.screens.count) screen(s)")
    }
    
    // MARK: - LiveDataStream
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        isMonitoring = true
        print("[DisplayMonitor] Started monitoring")
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        isMonitoring = false
        print("[DisplayMonitor] Stopped monitoring")
    }
    
    // MARK: - Screen Change Handler
    
    @objc private func handleScreenChange() {
        let oldCount = screens.count
        screens = NSScreen.screens
        print("[DisplayMonitor] Configuration changed: \(oldCount) → \(screens.count) screen(s)")
        NotificationCenter.default.post(name: .displayConfigurationDidChange, object: nil)
    }
    
    // MARK: - Neighbour API
    
    /// Returns all screens adjacent to the given screen, with their cardinal direction
    func neighbours(of screen: NSScreen) -> [ScreenNeighbour] {
        screens.compactMap { candidate in
            guard candidate != screen,
                  let dir = direction(from: screen, to: candidate) else { return nil }
            return ScreenNeighbour(screen: candidate, direction: dir)
        }
    }
    
    /// Determines the cardinal direction from source to target if they are adjacent.
    /// Two screens are considered adjacent when their edges are within `tolerance` points
    /// of each other AND they overlap by at least `minOverlap` points on the perpendicular axis.
    private func direction(from source: NSScreen, to target: NSScreen) -> ScreenDirection? {
        let s = source.frame
        let t = target.frame
        let tolerance: CGFloat = 20
        let minOverlap: CGFloat = 100
        
        // Right: target's left edge aligns with source's right edge
        if abs(t.minX - s.maxX) <= tolerance {
            let overlap = min(s.maxY, t.maxY) - max(s.minY, t.minY)
            if overlap >= minOverlap { return .right }
        }
        
        // Left: target's right edge aligns with source's left edge
        if abs(t.maxX - s.minX) <= tolerance {
            let overlap = min(s.maxY, t.maxY) - max(s.minY, t.minY)
            if overlap >= minOverlap { return .left }
        }
        
        // Above: target's bottom edge aligns with source's top edge
        if abs(t.minY - s.maxY) <= tolerance {
            let overlap = min(s.maxX, t.maxX) - max(s.minX, t.minX)
            if overlap >= minOverlap { return .above }
        }
        
        // Below: target's top edge aligns with source's bottom edge
        if abs(t.maxY - s.minY) <= tolerance {
            let overlap = min(s.maxX, t.maxX) - max(s.minX, t.minX)
            if overlap >= minOverlap { return .below }
        }
        
        return nil
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let displayConfigurationDidChange = Notification.Name("jason.displayConfigurationDidChange")
}
