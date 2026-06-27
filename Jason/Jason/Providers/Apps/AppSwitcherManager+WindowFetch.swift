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
        // Bound AX messaging so an unresponsive target app can't hang the main thread;
        // the call returns an error after the timeout instead of blocking indefinitely.
        AXUIElementSetMessagingTimeout(axApp, 0.5)
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
        // Bound AX messaging so an unresponsive target app can't hang the main thread;
        // the call returns an error after the timeout instead of blocking indefinitely.
        AXUIElementSetMessagingTimeout(axApp, 0.5)
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
                let targetWindow = axWindow
                let targetTitle = window.title

                // Hide without activating anything — we own the full sequence.
                // hideOverlay() orders our window out synchronously, so the target
                // app's window can be raised immediately without a settle delay.
                activeUIManager?.hideSkippingRestore()

                raiseAndActivate(window: targetWindow, app: app, title: targetTitle)
                return
            }
        }

        print("[AppSwitcherManager] Could not match window ID \(window.windowID) — falling back")
        activeUIManager?.hideAndSwitchTo(app: app)
    }

    /// Raise `window` and bring its app frontmost, then re-raise once the app has
    /// actually become active.
    ///
    /// macOS performs activation — and the window reordering it triggers —
    /// asynchronously with no completion callback. Rather than guessing fixed
    /// delays, we poll `app.isActive` (a real, observable signal) on a bounded
    /// 50 ms schedule and re-raise the target window until it wins, giving up
    /// after ~1 s so a stuck app can never spin forever.
    private func raiseAndActivate(window: AXUIElement,
                                  app: NSRunningApplication,
                                  title: String,
                                  attempt: Int = 0) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)

        if app.isActive {
            // App is frontmost; re-raise once more so our window wins any reorder
            // that activation caused, then we're done.
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            print("[AppSwitcherManager] Raised window '\(title)'")
            return
        }

        // Kick off activation once, then wait for it to take effect.
        if attempt == 0 {
            app.activate()
        }

        guard attempt < 20 else {   // ~1 s ceiling at 50 ms per tick
            print("[AppSwitcherManager] Gave up waiting for '\(title)' to activate")
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.raiseAndActivate(window: window, app: app, title: title, attempt: attempt + 1)
        }
    }
}
