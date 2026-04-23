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
            return [categoryNode(children: [noActionsNode()])]
        }

        let shortcuts = DatabaseManager.shared.fetchContextShortcuts(for: bundleID)
        let enabledShortcuts = shortcuts.filter { $0.enabled }
        
        let children: [FunctionNode] = enabledShortcuts.isEmpty
            ? [noActionsNode()]
            : enabledShortcuts.map { shortcut in
                makeShortcutNode(
                    id: "context-\(shortcut.id)",
                    name: shortcut.shortcutName,
                    icon: shortcut.iconName ?? "command",
                    keyCode: shortcut.keyCode,
                    modifierFlags: shortcut.modifierFlags
                )
            }

        return [categoryNode(children: children)]
    }

    func refresh() {
        print("[ContextProvider] refresh() called")
        NotificationCenter.default.postProviderUpdate(providerId: providerId)
    }

    func teardown() {
        print("[ContextProvider] teardown()")
        NotificationCenter.default.removeObserver(self)
        print("[ContextProvider] teardown complete")
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
            onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
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
    
    private func categoryNode(children: [FunctionNode]) -> FunctionNode {
        return FunctionNode(
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
    }

    // MARK: - Notifications

    @objc private func frontmostAppChanged() {
        guard let app = FrontmostAppMonitor.shared.frontmostApp,
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier else {
            return
        }
        print("[ContextProvider] Frontmost app changed — refreshing")
        DispatchQueue.main.async {
            NotificationCenter.default.postProviderUpdate(providerId: self.providerId)
        }
    }}
