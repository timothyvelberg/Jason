//
//  MenuItemExecutor.swift
//  Jason
//
//  Created by Timothy Velberg on 28/04/2026.
//  Executes macOS menu bar items via the Accessibility API.
//

import Foundation
import AppKit

struct MenuItemExecutor {

    /// Execute a menu item by path in the target app.
    /// Use this for normal (non-keep-open) execution — the UI has already
    /// dismissed and the target app will be frontmost naturally.
    /// - Parameters:
    ///   - menuPath: Semicolon-separated path string, e.g. "File;Export;Export as PNG"
    ///   - pid: Process ID of the target application
    static func execute(menuPath: String, pid: pid_t) {
        DispatchQueue.global(qos: .userInitiated).async {
            Thread.sleep(forTimeInterval: 0.15)
            performExecution(menuPath: menuPath, pid: pid)
        }
    }

    /// Execute a menu item while keeping Jason's UI alive (CMD+click).
    /// Briefly activates the target app, presses the menu item via AX,
    /// then reactivates Jason — mirroring ShortcutExecutor.postViaFocusSwitch.
    /// - Parameters:
    ///   - menuPath: Semicolon-separated path string, e.g. "File;Export;Export as PNG"
    ///   - pid: Process ID of the target application
    static func executeKeepOpen(menuPath: String, pid: pid_t) {
        guard let targetApp = NSRunningApplication(processIdentifier: pid),
              let jasonApp = NSRunningApplication(processIdentifier: ProcessInfo.processInfo.processIdentifier) else {
            print("❌ [MenuItemExecutor] Could not resolve apps for keep-open execution")
            return
        }

        ShortcutExecutor.isSwitchingFocus = true
        AppSwitcherManager.shared.activeUIManager?.ignoreFocusChangesTemporarily(duration: 0.6)

        targetApp.activate()

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1) {
            performExecution(menuPath: menuPath, pid: pid)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                jasonApp.activate()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    ShortcutExecutor.isSwitchingFocus = false
                }
            }
        }
    }

    // MARK: - Core Execution

    private static func performExecution(menuPath: String, pid: pid_t) {
        let components = menuPath
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !components.isEmpty else {
            print("[MenuItemExecutor] Empty menu path")
            return
        }

        let appElement = AXUIElementCreateApplication(pid)

        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBar = menuBarRef else {
            print("[MenuItemExecutor] Could not access menu bar for PID \(pid)")
            return
        }

        guard let topLevelItem = findMenuBarItem(in: menuBar as! AXUIElement, named: components[0]) else {
            print("[MenuItemExecutor] Could not find top-level menu: '\(components[0])'")
            return
        }

        if components.count == 1 {
            AXUIElementPerformAction(topLevelItem, kAXPressAction as CFString)
            print("[MenuItemExecutor] Executed menu path: \(menuPath)")
            return
        }

        var current: AXUIElement = topLevelItem
        let remainingComponents = Array(components.dropFirst())

        for (index, component) in remainingComponents.enumerated() {
            guard let submenu = getSubmenu(of: current),
                  let match = findMenuItem(in: submenu, named: component) else {
                print("[MenuItemExecutor] Could not find menu item: '\(component)'")
                return
            }
            current = match

            if index == remainingComponents.count - 1 {
                AXUIElementPerformAction(current, kAXPressAction as CFString)
                print("[MenuItemExecutor] Executed menu path: \(menuPath)")
            }
        }
    }

    // MARK: - Private Helpers

    private static func findMenuBarItem(in menuBar: AXUIElement, named title: String) -> AXUIElement? {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }
        return children.first { titleOf($0)?.lowercased() == title.lowercased() }
    }

    private static func getSubmenu(of element: AXUIElement) -> AXUIElement? {
        var submenuRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &submenuRef) == .success,
              let children = submenuRef as? [AXUIElement],
              let submenu = children.first else {
            return nil
        }
        return submenu
    }

    private static func findMenuItem(in menu: AXUIElement, named title: String) -> AXUIElement? {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menu, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }
        return children.first { titleOf($0)?.lowercased() == title.lowercased() }
    }

    private static func titleOf(_ element: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String else {
            return nil
        }
        return title
    }
}
