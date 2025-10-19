//
//  SystemActions.swift
//  Jason
//
//  SOLUTION FOUND: BetterTouchTool uses CoreDockSendNotification!
//

import Foundation
import AppKit
import CoreGraphics

class SystemActions {
    
    /// Trigger Mission Control
    static func showMissionControl() {
        print("🚀 [SystemActions] Triggering Mission Control")
        
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-a", "Mission Control"]
        
        do {
            try task.run()
            print("✅ [SystemActions] Launched Mission Control")
        } catch {
            print("❌ [SystemActions] Failed to launch Mission Control: \(error)")
        }
    }
    
    /// Show Desktop
    static func showDesktop() {
        typealias CoreDockSendNotificationFunc = @convention(c) (CFString, Int) -> Void
        
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CoreDockSendNotification") else {
            print("Function not found")
            return
        }
        
        let coreDockSendNotification = unsafeBitCast(symbol, to: CoreDockSendNotificationFunc.self)
        coreDockSendNotification("com.apple.showdesktop.awake" as CFString, 1)
    }
}
