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
    /// - Parameters:
    ///   - menuPath: Semicolon-separated path string, e.g. "File;Export;Export as PNG"
    ///   - pid: Process ID of the target application
    static func execute(menuPath: String, pid: pid_t) {
        let components = menuPath
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !components.isEmpty else {
            print("[MenuItemExecutor] Empty menu path")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            Thread.sleep(forTimeInterval: 0.15)
            let appElement = AXUIElementCreateApplication(pid)

            var menuBarRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
                  let menuBar = menuBarRef else {
                print("[MenuItemExecutor] Could not access menu bar for PID \(pid)")
                return
            }

            // Find the top-level menu bar item without pressing it
            guard let topLevelItem = findMenuBarItem(in: menuBar as! AXUIElement, named: components[0]) else {
                print("[MenuItemExecutor] Could not find top-level menu: '\(components[0])'")
                return
            }

            // If only one component, press it directly
            if components.count == 1 {
                AXUIElementPerformAction(topLevelItem, kAXPressAction as CFString)
                print("[MenuItemExecutor] Executed menu path: \(menuPath)")
                return
            }

            // Traverse remaining components purely by reading children — no actions on intermediate items
            var current: AXUIElement = topLevelItem
            let remainingComponents = Array(components.dropFirst())

            for (index, component) in remainingComponents.enumerated() {
                guard let submenu = getSubmenu(of: current),
                      let match = findMenuItem(in: submenu, named: component) else {
                    print("[MenuItemExecutor] Could not find menu item: '\(component)'")
                    return
                }
                current = match

                // Only press the final item
                if index == remainingComponents.count - 1 {
                    AXUIElementPerformAction(current, kAXPressAction as CFString)
                    print("[MenuItemExecutor] Executed menu path: \(menuPath)")
                }
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

        return children.first { element in
            titleOf(element)?.lowercased() == title.lowercased()
        }
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

        return children.first { element in
            titleOf(element)?.lowercased() == title.lowercased()
        }
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
