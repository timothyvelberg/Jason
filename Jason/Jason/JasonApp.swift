//
//  JasonApp.swift
//  Jason
//
//  Created by Timothy Velberg on 31/07/2025.
//

import SwiftUI

@main
struct JasonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// App Delegate to handle keyboard events at app level
class AppDelegate: NSObject, NSApplicationDelegate {
    var keyMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 AppDelegate: Setting up main window keyboard handling")
        
        // Add local monitor to consume Ctrl+Shift+K in main window
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isCtrlPressed = event.modifierFlags.contains(.control)
            let isShiftPressed = event.modifierFlags.contains(.shift)
            let isKKey = event.keyCode == 40  // K key
            
            // If this is our shortcut, consume it (prevent beep)
            if isCtrlPressed && isShiftPressed && isKKey {
                print("🎯 [AppDelegate] Consuming Ctrl+Shift+K in main window (no beep)")
                return nil  // Consume event - prevents beep!
            }
            
            // Let other keys through
            return event
        }
        
        print("✅ AppDelegate: Main window keyboard handling ready")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
