//
//  WindowManager+Positioning.swift
//  Jason
//
//  Created by Timothy Velberg on 09/05/2026.
//
//  All window positioning actions
//

import Foundation
import AppKit
import ApplicationServices

extension WindowManager {

    static func fullscreen(targetApp: NSRunningApplication? = nil) {
        guard checkAccessibilityPermissions(),
              let window = getFrontmostWindow(targetApp: targetApp),
              let screen = getScreenForWindow(window) else { return }
        setWindowFrame(window, frame: screen.visibleFrame)
        print("[WindowManager] Fullscreen")
    }

    static func hideWindow(targetApp: NSRunningApplication? = nil) {
        guard let app = targetApp ?? NSWorkspace.shared.frontmostApplication else {
            print("[WindowManager] No frontmost application found")
            return
        }
        app.hide()
        print("[WindowManager] Hid application: \(app.localizedName ?? "unknown")")
    }

    static func positionLeftHalf(targetApp: NSRunningApplication? = nil) {
        guard checkAccessibilityPermissions(),
              let window = getFrontmostWindow(targetApp: targetApp),
              let screen = getScreenForWindow(window) else { return }
        let f = screen.visibleFrame
        setWindowFrame(window, frame: CGRect(x: f.minX, y: f.minY, width: f.width / 2, height: f.height))
        print("[WindowManager] Left half")
    }

    static func positionRightHalf(targetApp: NSRunningApplication? = nil) {
        guard checkAccessibilityPermissions(),
              let window = getFrontmostWindow(targetApp: targetApp),
              let screen = getScreenForWindow(window) else { return }
        let f = screen.visibleFrame
        setWindowFrame(window, frame: CGRect(x: f.midX, y: f.minY, width: f.width / 2, height: f.height))
        print("[WindowManager] Right half")
    }

    static func positionTopHalf(targetApp: NSRunningApplication? = nil) {
        guard checkAccessibilityPermissions(),
              let window = getFrontmostWindow(targetApp: targetApp),
              let screen = getScreenForWindow(window) else { return }
        let f = screen.visibleFrame
        setWindowFrame(window, frame: CGRect(x: f.minX, y: f.midY, width: f.width, height: f.height / 2))
        print("[WindowManager] Top half")
    }

    static func positionBottomHalf(targetApp: NSRunningApplication? = nil) {
        guard checkAccessibilityPermissions(),
              let window = getFrontmostWindow(targetApp: targetApp),
              let screen = getScreenForWindow(window) else { return }
        let f = screen.visibleFrame
        setWindowFrame(window, frame: CGRect(x: f.minX, y: f.minY, width: f.width, height: f.height / 2))
        print("[WindowManager] Bottom half")
    }

    static func positionTopLeft(targetApp: NSRunningApplication? = nil) {
        guard checkAccessibilityPermissions(),
              let window = getFrontmostWindow(targetApp: targetApp),
              let screen = getScreenForWindow(window) else { return }
        let f = screen.visibleFrame
        setWindowFrame(window, frame: CGRect(x: f.minX, y: f.midY, width: f.width / 2, height: f.height / 2))
        print("[WindowManager] Top left")
    }

    static func positionTopRight(targetApp: NSRunningApplication? = nil) {
        guard checkAccessibilityPermissions(),
              let window = getFrontmostWindow(targetApp: targetApp),
              let screen = getScreenForWindow(window) else { return }
        let f = screen.visibleFrame
        setWindowFrame(window, frame: CGRect(x: f.midX, y: f.midY, width: f.width / 2, height: f.height / 2))
        print("[WindowManager] Top right")
    }

    static func positionBottomLeft(targetApp: NSRunningApplication? = nil) {
        guard checkAccessibilityPermissions(),
              let window = getFrontmostWindow(targetApp: targetApp),
              let screen = getScreenForWindow(window) else { return }
        let f = screen.visibleFrame
        setWindowFrame(window, frame: CGRect(x: f.minX, y: f.minY, width: f.width / 2, height: f.height / 2))
        print("[WindowManager] Bottom left")
    }

    static func positionBottomRight(targetApp: NSRunningApplication? = nil) {
        guard checkAccessibilityPermissions(),
              let window = getFrontmostWindow(targetApp: targetApp),
              let screen = getScreenForWindow(window) else { return }
        let f = screen.visibleFrame
        setWindowFrame(window, frame: CGRect(x: f.midX, y: f.minY, width: f.width / 2, height: f.height / 2))
        print("[WindowManager] Bottom right")
    }
}
