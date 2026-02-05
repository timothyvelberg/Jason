//
//  UIManagerProtocol.swift
//  Jason
//
//  Created by Timothy Velberg on 29/01/2026.
//  Protocol defining common interface for UI managers (ring and panel).
//

import Foundation
import AppKit

/// Protocol for UI managers that can be shown/hidden via triggers
protocol UIManager: AnyObject {
    /// Configuration ID this manager is associated with
    var configId: Int { get }
    
    /// Whether the UI is currently visible
    var isVisible: Bool { get }
    
    /// Whether the UI is in hold mode (key held down)
    var isInHoldMode: Bool { get set }
    
    /// The trigger that activated this UI (for hold mode behavior)
    var activeTrigger: TriggerConfiguration? { get set }
    
    /// The list panel manager (both ring and panel modes have this)
    var listPanelManager: ListPanelManager? { get }
    
    /// Setup the manager (create windows, wire callbacks)
    func setup()
    
    /// Show the UI
    func show(triggerDirection: RotationDirection?)
    
    /// Hide the UI
    func hide()
    
    /// Temporarily ignore focus changes
    func ignoreFocusChangesTemporarily(duration: TimeInterval)
}

// MARK: - Default Implementations

extension UIManager {
    /// Convenience show without trigger direction
    func show() {
        show(triggerDirection: nil)
    }
}
