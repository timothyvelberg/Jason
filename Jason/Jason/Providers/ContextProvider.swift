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
    
    // MARK: - Properties
    
    private let ringId: Int     // NEW
    
    // MARK: - Initialization
    
    init(ringId: Int) {         // NEW
        self.ringId = ringId
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(frontmostAppChanged),
            name: .frontmostAppChanged,
            object: nil
        )
        print("🎯 [ContextProvider] Initialized for ring \(ringId)")
    }
    
    // MARK: - FunctionProvider Protocol
    
    func provideFunctions() -> [FunctionNode] {
        let shortcuts = DatabaseManager.shared.fetchContextShortcuts(for: ringId)
        let enabledShortcuts = shortcuts.filter { $0.enabled }
        let groups = DatabaseManager.shared.fetchContextShortcutGroups(for: ringId)

        // If no groups exist, fall back to flat list (original behaviour)
        if groups.isEmpty {
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

        // Build top-level children sorted by sort_order (groups and ungrouped shortcuts interleaved)
        var topLevel: [(sortOrder: Int, node: FunctionNode)] = []

        for group in groups {
            let groupShortcuts = enabledShortcuts
                .filter { $0.groupId == group.id }
                .map { shortcut in
                    makeShortcutNode(
                        id: "context-\(shortcut.id)",
                        name: shortcut.shortcutName,
                        icon: shortcut.iconName ?? "command",
                        keyCode: shortcut.keyCode,
                        modifierFlags: shortcut.modifierFlags
                    )
                }
            topLevel.append((sortOrder: group.sortOrder, node: makeGroupNode(group: group, children: groupShortcuts)))
        }

        for shortcut in enabledShortcuts.filter({ $0.groupId == nil }) {
            let node = makeShortcutNode(
                id: "context-\(shortcut.id)",
                name: shortcut.shortcutName,
                icon: shortcut.iconName ?? "command",
                keyCode: shortcut.keyCode,
                modifierFlags: shortcut.modifierFlags
            )
            topLevel.append((sortOrder: shortcut.sortOrder, node: node))
        }

        var topLevelChildren = topLevel.sorted { $0.sortOrder < $1.sortOrder }.map { $0.node }

        if topLevelChildren.isEmpty {
            topLevelChildren = [noActionsNode()]
        }

        return [categoryNode(children: topLevelChildren)]
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
            onLeftClick: ModifierAwareInteraction(
                base: .execute {
                    print("🎯 [ContextProvider] Executing: \(name)")
                    ShortcutExecutor.execute(keyCode: keyCode, modifierFlags: modifierFlags)
                },
                command: .executeKeepOpen {
                    print("🎯 [ContextProvider] Executing (keep open): \(name)")
                    let pid = AppSwitcherManager.shared.activeUIManager?.previousApp?.processIdentifier
                    ShortcutExecutor.execute(keyCode: keyCode, modifierFlags: modifierFlags, pid: pid)
                }
            ),
            onRightClick: ModifierAwareInteraction(base: .doNothing),
            onMiddleClick: ModifierAwareInteraction(base: .doNothing),
            onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
        )
    }
    
    private func makeGroupNode(group: ContextShortcutGroup, children: [FunctionNode]) -> FunctionNode {
        let iconImage = group.iconName.flatMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil)
        } ?? NSImage(systemSymbolName: "folder", accessibilityDescription: nil) ?? NSImage()

        return FunctionNode(
            id: "context-group-\(group.id)",
            name: group.name,
            type: .category,
            icon: iconImage,
            children: children.isEmpty ? [noActionsNode()] : children,
//            childDisplayMode: .panel,
            preferredLayout: .partialSlice,
            slicePositioning: .center,
            providerId: providerId,
            onLeftClick: ModifierAwareInteraction(base: .doNothing),
            onRightClick: ModifierAwareInteraction(base: .doNothing),
            onMiddleClick: ModifierAwareInteraction(base: .doNothing),
            onBoundaryCross: ModifierAwareInteraction(base: .expand)
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
//            childDisplayMode: .panel,
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
        DispatchQueue.main.async {
            NotificationCenter.default.postProviderUpdate(providerId: self.providerId)
        }
    }
}
