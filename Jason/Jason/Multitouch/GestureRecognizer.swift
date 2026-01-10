//
//  GestureRecognizer.swift
//  Jason
//
//  Created by Timothy Velberg on 10/01/2026.
//  Protocol for gesture recognizers
//

import Foundation

/// Protocol for gesture recognizers that analyze touch frames
protocol GestureRecognizer: AnyObject {
    
    /// Unique identifier for this recognizer
    var identifier: String { get }
    
    /// Whether the recognizer is currently enabled
    var isEnabled: Bool { get set }
    
    /// Callback when a gesture is recognized
    var onGesture: ((GestureEvent) -> Void)? { get set }
    
    /// Process a touch frame
    /// - Parameter frame: The touch data to analyze
    func processTouchFrame(_ frame: TouchFrame)
    
    /// Reset the recognizer state (e.g., when gesture tracking is cancelled)
    func reset()
}
