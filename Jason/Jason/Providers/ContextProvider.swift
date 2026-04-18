//
//  ContextProvider.swift
//  Jason
//
//  Created by Timothy Velberg on 16/04/2026.
//
//  Surfaces app-specific shortcut nodes based on the frontmost application.
//

import Foundation
import AppKit

class ContextProvider: ObservableObject, FunctionProvider {

    // MARK: - FunctionProvider Protocol

    var providerId: String { "context" }
    var providerName: String { "Context" }
    var providerIcon: NSImage {
        NSImage(systemSymbolName: "contextualmenu.and.cursorarrow", accessibilityDescription: nil) ?? NSImage()
    }

    // MARK: - Initialization

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(frontmostAppChanged),
            name: .frontmostAppChanged,
            object: nil
        )
        print("🎯 [ContextProvider] Initialized")
    }

    // MARK: - FunctionProvider Protocol

    func provideFunctions() -> [FunctionNode] {
        guard let app = FrontmostAppMonitor.shared.frontmostApp,
              let bundleID = app.bundleIdentifier else {
            return [noActionsNode()]
        }

        let children = nodesForApp(bundleID: bundleID)

        return [
            FunctionNode(
                id: "context-category",
                name: "Context",
                type: .category,
                icon: providerIcon,
                children: children,
                childDisplayMode: .panel,
                preferredLayout: .partialSlice,
                slicePositioning: .center,
                providerId: providerId,
                onLeftClick: ModifierAwareInteraction(base: .doNothing),
                onRightClick: ModifierAwareInteraction(base: .doNothing),
                onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                onBoundaryCross: ModifierAwareInteraction(base: .expand)
            )
        ]
    }

    func refresh() {
        print("🎯 [ContextProvider] refresh() called")
        NotificationCenter.default.post(name: .providerContentUpdated, object: nil)
    }

    func teardown() {
        print("🎯 [ContextProvider] teardown()")
        NotificationCenter.default.removeObserver(self)
        print("🎯 [ContextProvider] teardown complete")
    }

    // MARK: - App Routing

    private func nodesForApp(bundleID: String) -> [FunctionNode] {
        switch bundleID {
        case "com.apple.finder":
            return finderNodes()
        case "com.vivaldi.Vivaldi":
            return vivaldiNodes()
        default:
            return [noActionsNode()]
        }
    }

    // MARK: - Finder Nodes

    private func finderNodes() -> [FunctionNode] {
        return [
            makeShortcutNode(
                id: "context-finder-new-window",
                name: "New Window",
                icon: "plus.rectangle",
                keyCode: 45,  // N
                modifierFlags: NSEvent.ModifierFlags.command.rawValue
            ),
            makeShortcutNode(
                id: "context-finder-close-window",
                name: "Close Window",
                icon: "xmark.rectangle",
                keyCode: 13,  // W
                modifierFlags: NSEvent.ModifierFlags.command.rawValue
            ),
            makeShortcutNode(
                id: "context-finder-search-window",
                name: "Search Window",
                icon: "xmark.rectangle",
                keyCode: 3,  // W
                modifierFlags:  NSEvent.ModifierFlags([.command, .option]).rawValue
            )
        ]
    }
    
    private func vivaldiNodes() -> [FunctionNode] {
        return [
            makeShortcutNode(
                id: "context-vivaldi-new-window",
                name: "New Window",
                icon: "macwindow",
                keyCode: 45,  // N
                modifierFlags: NSEvent.ModifierFlags.command.rawValue
            ),
            makeShortcutNode(
                id: "context-vivaldi-new-tab",
                name: "New Tab",
                icon: "plus.square",
                keyCode: 17,  // T
                modifierFlags: NSEvent.ModifierFlags.command.rawValue
            ),
            makeShortcutNode(
                id: "context-vivaldi-close-tab",
                name: "Close Tab",
                icon: "xmark.circle",
                keyCode: 13,
                modifierFlags: NSEvent.ModifierFlags.command.rawValue
            ),
            makeShortcutNode(
                id: "context-vivaldi-alfred",
                name: "Context Search",
                icon: "magnifyingglass",
                keyCode: 57,
                modifierFlags: NSEvent.ModifierFlags.control.rawValue
            )
        ]
    }

    // MARK: - Node Helpers

    private func makeShortcutNode(
        id: String,
        name: String,
        icon: String,
        keyCode: UInt16,
        modifierFlags: UInt
    ) -> FunctionNode {
        let iconImage = NSImage(systemSymbolName: icon, accessibilityDescription: nil) ?? NSImage()

        return FunctionNode(
            id: id,
            name: name,
            type: .action,
            icon: iconImage,
            preferredLayout: nil,
            showLabel: true,
            providerId: providerId,
            onLeftClick: ModifierAwareInteraction(base: .execute {
                print("🎯 [ContextProvider] Executing: \(name)")
                ShortcutExecutor.execute(keyCode: keyCode, modifierFlags: modifierFlags)
            }),
            onRightClick: ModifierAwareInteraction(base: .doNothing),
            onMiddleClick: ModifierAwareInteraction(base: .doNothing),
            onBoundaryCross: ModifierAwareInteraction(base: .execute {
                print("🎯 [ContextProvider] Executing via boundary: \(name)")
                ShortcutExecutor.execute(keyCode: keyCode, modifierFlags: modifierFlags)
            })
        )
    }

    private func noActionsNode() -> FunctionNode {
        return FunctionNode(
            id: "context-no-actions",
            name: "No actions for this app",
            type: .action,
            icon: NSImage(systemSymbolName: "slash.circle", accessibilityDescription: nil) ?? NSImage(),
            preferredLayout: nil,
            showLabel: true,
            providerId: providerId,
            onLeftClick: ModifierAwareInteraction(base: .doNothing),
            onRightClick: ModifierAwareInteraction(base: .doNothing),
            onMiddleClick: ModifierAwareInteraction(base: .doNothing),
            onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
        )
    }

    // MARK: - Notifications

    @objc private func frontmostAppChanged() {
        print("🎯 [ContextProvider] Frontmost app changed — refreshing")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .providerContentUpdated, object: nil)
        }
    }
}
