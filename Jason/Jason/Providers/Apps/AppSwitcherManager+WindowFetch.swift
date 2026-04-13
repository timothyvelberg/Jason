//
//  AppSwitcherManager+WindowFetch.swift
//  Jason
//
//  Created by Timothy Velberg on 13/04/2026.
//

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
}
