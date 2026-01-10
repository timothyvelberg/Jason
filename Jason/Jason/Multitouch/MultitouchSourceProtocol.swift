//
//  MultitouchSourceProtocol.swift
//  Jason
//
//  Created by Timothy Velberg on 10/01/2026.
//  Protocol defining what a multitouch data source provides
//

import Foundation

/// Protocol for multitouch data sources
/// Implementations can use private frameworks, OpenMultitouchSupport, or other backends
protocol MultitouchSourceProtocol: AnyObject {
    
    /// Callback invoked for each touch frame
    var onTouchFrame: ((TouchFrame) -> Void)? { get set }
    
    /// Whether the source is currently monitoring
    var isMonitoring: Bool { get }
    
    /// Start receiving touch data
    func startMonitoring()
    
    /// Stop receiving touch data
    func stopMonitoring()
    
    /// Prepare for system sleep (unregister callbacks)
    func prepareForSleep()
    
    /// Restart after system wake
    func restartAfterWake()
}
