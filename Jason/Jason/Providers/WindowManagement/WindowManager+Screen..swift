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

        var cgPosition = CGPoint.zero
        AXValueGetValue(axValue as! AXValue, .cgPoint, &cgPosition)

        // AX API returns positions in CG space (Y=0 at top of primary screen).
        // NSScreen.frame is in AppKit space (Y=0 at bottom of primary screen).
        // Convert before matching.
        guard let primaryScreen = NSScreen.screens.first else { return NSScreen.main }
        let appKitPosition = CGPoint(
            x: cgPosition.x,
            y: primaryScreen.frame.height - cgPosition.y
        )

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(appKitPosition) }) {
            return screen
        }

        // Fallback: closest screen by center distance (using converted AppKit position)
        return NSScreen.screens.min(by: { a, b in
            let da = hypot(a.frame.midX - appKitPosition.x, a.frame.midY - appKitPosition.y)
            let db = hypot(b.frame.midX - appKitPosition.x, b.frame.midY - appKitPosition.y)
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

        var cgPosition = CGPoint.zero
        var size = CGSize.zero
        if let p = posValue { AXValueGetValue(p as! AXValue, .cgPoint, &cgPosition) }
        if let s = sizeValue { AXValueGetValue(s as! AXValue, .cgSize, &size) }

        // AX position is in CG space; convert to AppKit space before relative arithmetic.
        // Inverse of the conversion in getScreenForWindow.
        guard let primaryScreen = NSScreen.screens.first else { return }
        let appKitTopLeft = CGPoint(
            x: cgPosition.x,
            y: primaryScreen.frame.height - cgPosition.y
        )

        let src = currentScreen.visibleFrame
        let dst = targetScreen.visibleFrame

        // Compute relative position using the window's top-left corner.
        // AppKit Y increases upward, so the top of the screen is src.maxY.
        let relX = (appKitTopLeft.x - src.origin.x) / src.width
        let relY = (src.maxY - appKitTopLeft.y) / src.height  // 0 = top of screen, 1 = bottom

        // Scale size proportionally between screens.
        let newWidth  = (size.width  / src.width)  * dst.width
        let newHeight = (size.height / src.height) * dst.height

        // Reconstruct the top-left corner on the destination screen,
        // then convert to bottom-left (AppKit origin) by subtracting newHeight.
        let newTopLeftY = dst.maxY - relY * dst.height
        let newY = newTopLeftY - newHeight

        let newFrame = CGRect(
            x: dst.origin.x + relX * dst.width,
            y: newY,
            width: newWidth,
            height: newHeight
        )

        print("🪟 [moveToScreen] appKitTopLeft: \(appKitTopLeft)")
        print("🪟 [moveToScreen] relX: \(relX), relY: \(relY)")
        print("🪟 [moveToScreen] src: \(src), dst: \(dst)")
        print("🪟 [moveToScreen] newFrame: \(newFrame)")

        setWindowFrame(window, frame: newFrame)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
}
