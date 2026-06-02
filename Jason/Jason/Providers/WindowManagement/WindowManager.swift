//
//  WindowManager.swift
//  Jason
//
//  Created by Timothy Velberg on 09/05/2026.
//

import Foundation
import AppKit
import ApplicationServices

class WindowManager {

    // MARK: - Accessibility Permissions

    static func checkAccessibilityPermissions() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)

        if !accessEnabled {
            print("[WindowManager] Accessibility permissions not granted")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission Required"
                alert.informativeText = "Jason needs Accessibility permissions to manage windows. Please grant access in System Settings > Privacy & Security > Accessibility, then restart Jason."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Cancel")

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }

        return accessEnabled
    }

    // MARK: - Accessibility API

    static func getFrontmostWindow(targetApp: NSRunningApplication? = nil) -> AXUIElement? {
        let app = targetApp ?? NSWorkspace.shared.frontmostApplication

        guard let app = app else {
            print("[WindowManager] No target application")
            return nil
        }

        print("[WindowManager] Target app: \(app.localizedName ?? "Unknown") (PID: \(app.processIdentifier))")

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: AnyObject?

        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value)

        if result == .success, let window = value {
            print("[WindowManager] Got focused window")
            return (window as! AXUIElement)
        }

        print("[WindowManager] Could not get focused window (error: \(result.rawValue)) — trying first window")

        var windowsValue: AnyObject?
        let windowsResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)

        if windowsResult == .success,
           let windows = windowsValue as? [AXUIElement],
           let firstWindow = windows.first {
            print("[WindowManager] Using first available window")
            return firstWindow
        }

        return nil
    }

    
    
    static func setWindowFrame(_ window: AXUIElement, frame: CGRect) {
        guard let primaryScreen = NSScreen.screens.first else {
            print("[WindowManager] No screens available")
            return
        }

        // AX API uses CG space (Y=0 at top of primary screen); AppKit uses Y=0 at bottom.
        // Inverse of the conversion in getScreenForWindow.
        let cgY = primaryScreen.frame.height - (frame.origin.y + frame.height)
        let convertedFrame = CGRect(x: frame.origin.x, y: cgY, width: frame.width, height: frame.height)

        print("[WindowManager] Setting frame: origin(\(convertedFrame.origin.x), \(convertedFrame.origin.y)) size(\(convertedFrame.width)x\(convertedFrame.height))")

        // Apply twice — first pass moves the window, second pass corrects size
        // after the app adjusts it in response to the position change
        for _ in 0..<2 {
            var size = convertedFrame.size
            let sizeValue = AXValueCreate(.cgSize, &size)!
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)

            var origin = convertedFrame.origin
            let positionValue = AXValueCreate(.cgPoint, &origin)!
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        }
    }
}
