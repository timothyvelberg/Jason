//
//  AppSwitcherManager+WindowFetch.swift
//  Jason
//
//  Created by Timothy Velberg on 13/04/2026.

import AppKit

// MARK: - WindowInfo Model

struct WindowInfo {
    let windowID: CGWindowID
    let title: String
    let appBundleID: String
}

// MARK: - Window Fetching

extension AppSwitcherManager {
    
    func fetchWindows(for app: NSRunningApplication) -> [WindowInfo] {
        guard hasAccessibilityPermission else {
            print("[WindowFetch] Accessibility permission denied - cannot fetch windows")
            return []
        }
        
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            print("[WindowFetch] Could not retrieve windows for \(app.localizedName ?? "unknown")")
            return []
        }
        
        print("[WindowFetch] Found \(windows.count) window(s) for \(app.localizedName ?? "unknown")")
        
        return windows.compactMap { window in
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            let title = (titleRef as? String) ?? "Untitled"
            
            var windowID: CGWindowID = 0
            _AXUIElementGetWindow(window, &windowID)
            
            print("[WindowFetch] Window: '\(title)' (id: \(windowID))")
            
            return WindowInfo(
                windowID: windowID,
                title: title,
                appBundleID: app.bundleIdentifier ?? ""
            )
        }
    }
    
    // MARK: - Window Focusing
    
    func focusWindow(_ window: WindowInfo) {
        print("[AppSwitcherManager] Focusing window: '\(window.title)' (id: \(window.windowID))")

        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: window.appBundleID)
        guard let app = runningApps.first else {
            print("[AppSwitcherManager] App not found for bundle: \(window.appBundleID)")
            return
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else {
            print("[AppSwitcherManager] Could not get AX windows for \(window.appBundleID)")
            activeUIManager?.hideAndSwitchTo(app: app)
            return
        }

        for axWindow in axWindows {
            var windowIDRef: CGWindowID = 0
            _AXUIElementGetWindow(axWindow, &windowIDRef)
            if windowIDRef == window.windowID {
                // Hide the Jason UI without activating any app —
                // we own the full activation sequence from here
                
                // Suppress focus restore, then hide and own activation ourselves
                activeUIManager?.ignoreFocusChangesTemporarily(duration: 0.5)
                activeUIManager?.hide()

                let targetWindow = axWindow
                let targetTitle = window.title
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)
                    AXUIElementSetAttributeValue(targetWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
                    app.activate()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)
                        print("🪟 [AppSwitcherManager] Raised window '\(targetTitle)'")
                    }
                }
                return
            }
        }

        print("[AppSwitcherManager] Could not match window ID \(window.windowID) — falling back")
        activeUIManager?.hideAndSwitchTo(app: app)
    }
}
