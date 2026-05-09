//
//  WindowManager+Screen..swift
//  Jason
//
//  Created by Timothy Velberg on 09/05/2026.
//
//  Screen detection, current screen resolution, and move-to-screen
//

import Foundation
import AppKit
import ApplicationServices

extension WindowManager {

    // MARK: - Screen Detection

    static func getScreenForWindow(_ window: AXUIElement) -> NSScreen? {
        var positionValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue)

        guard result == .success,
              let axValue = positionValue,
              AXValueGetType(axValue as! AXValue) == .cgPoint else {
            print("[WindowManager] Could not get window position, using main screen")
            return NSScreen.main
        }

        var position = CGPoint.zero
        AXValueGetValue(axValue as! AXValue, .cgPoint, &position)

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(position) }) {
            return screen
        }

        // Fallback: closest screen by center distance
        return NSScreen.screens.min(by: { a, b in
            let da = hypot(a.frame.midX - position.x, a.frame.midY - position.y)
            let db = hypot(b.frame.midX - position.x, b.frame.midY - position.y)
            return da < db
        }) ?? NSScreen.main
    }

    /// Gets the screen the target app's window is currently on.
    /// Falls back to the screen under the mouse cursor if AX is unavailable.
    static func currentScreen(for app: NSRunningApplication?) -> NSScreen {
        if let window = getFrontmostWindow(targetApp: app),
           let screen = getScreenForWindow(window) {
            return screen
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    // MARK: - Move to Screen1

    /// Moves a window to the target screen, preserving its relative position and size.
    static func moveToScreen(_ targetScreen: NSScreen, targetApp: NSRunningApplication? = nil) {
        guard checkAccessibilityPermissions() else { return }
        guard let window = getFrontmostWindow(targetApp: targetApp) else {
            print("[WindowManager] No frontmost window found")
            return
        }
        guard let currentScreen = getScreenForWindow(window) else {
            print("[WindowManager] Could not determine current screen")
            return
        }

        var posValue: AnyObject?
        var sizeValue: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue)

        var position = CGPoint.zero
        var size = CGSize.zero
        if let p = posValue { AXValueGetValue(p as! AXValue, .cgPoint, &position) }
        if let s = sizeValue { AXValueGetValue(s as! AXValue, .cgSize, &size) }

        let src = currentScreen.visibleFrame
        let dst = targetScreen.visibleFrame

        let newFrame = CGRect(
            x: dst.origin.x + ((position.x - src.origin.x) / src.width) * dst.width,
            y: dst.origin.y + ((position.y - src.origin.y) / src.height) * dst.height,
            width: (size.width / src.width) * dst.width,
            height: (size.height / src.height) * dst.height
        )

        setWindowFrame(window, frame: newFrame)
        print("[WindowManager] Moved window to screen: \(targetScreen.localizedName ?? "unknown")")
    }
}
