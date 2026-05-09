//
//  WindowManagementProvider.swift
//  Jason
//
//  Provider for window management with directional positioning
//
//

import Foundation
import AppKit
import ApplicationServices

class WindowManagementProvider: ObservableObject, FunctionProvider {

    // MARK: - FunctionProvider Protocol

    var providerId: String { "window-management" }
    var providerName: String { "Window Management" }
    var providerIcon: NSImage {
        NSImage(systemSymbolName: "uiwindow.split.2x1", accessibilityDescription: nil) ?? NSImage()
    }

    // MARK: - Dependencies

    weak var circularUIManager: CircularUIManager?

    // MARK: - Initialization

    init() {
        print("🪟 WindowManagementProvider initialized")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDisplayChange),
            name: .displayConfigurationDidChange,
            object: nil
        )
    }

    @objc private func handleDisplayChange() {
        print("🪟 [WindowManagementProvider] Display configuration changed - rebuilding")
        NotificationCenter.default.postProviderUpdate(providerId: providerId)
    }

    func teardown() {
        NotificationCenter.default.removeObserver(self, name: .displayConfigurationDidChange, object: nil)
    }

    func refresh() {
        print("🪟 [WindowManagementProvider] Refresh called (no-op)")
    }

    // MARK: - FunctionProvider Methods

    func provideFunctions() -> [FunctionNode] {
        let targetApp = circularUIManager?.previousApp
        let currentScreen = WindowManager.currentScreen(for: targetApp)
        let neighbours = DisplayMonitor.shared.neighbours(of: currentScreen)
        let leftScreen  = neighbours.first { $0.direction == .left }?.screen
        let rightScreen = neighbours.first { $0.direction == .right }?.screen

        let items: [FunctionNode] = [
            makeTopNode(),
            makeQuarterNode(id: "window-top-right",    name: "Top Right",    imageName: "window_manager_top_right",    action: WindowManager.positionTopRight),
            makeDirectionalHalfNode(direction: .right, neighbourScreen: rightScreen),
            makeQuarterNode(id: "window-bottom-right", name: "Bottom Right", imageName: "window_manager_bottom_right", action: WindowManager.positionBottomRight),
            makeBottomNode(),
            makeQuarterNode(id: "window-bottom-left",  name: "Bottom Left",  imageName: "window_manager_bottom_left",  action: WindowManager.positionBottomLeft),
            makeDirectionalHalfNode(direction: .left,  neighbourScreen: leftScreen),
            makeQuarterNode(id: "window-top-left",     name: "Top Left",     imageName: "window_manager_top_left",     action: WindowManager.positionTopLeft),
        ]

        return [
            FunctionNode(
                id: "window-management",
                name: "Window Management",
                type: .category,
                icon: NSImage(systemSymbolName: "uiwindow.split.2x1", accessibilityDescription: nil) ?? NSImage(),
                children: items,
                preferredLayout: .partialSlice,
                slicePositioning: .center,
                onLeftClick: ModifierAwareInteraction(base: .doNothing),
                onRightClick: ModifierAwareInteraction(base: .doNothing),
                onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                onBoundaryCross: ModifierAwareInteraction(base: .expand)
            )
        ]
    }

    // MARK: - Node Builders

    private func makeTopNode() -> FunctionNode {
        FunctionNode(
            id: "window-top",
            name: "Top",
            type: .category,
            icon: NSImage(named: "window_manager_fullscreen") ?? NSImage(),
            children: [
                FunctionNode(
                    id: "window-fullscreen",
                    name: "Fullscreen",
                    type: .action,
                    icon: NSImage(named: "window_manager_fullscreen") ?? NSImage(),
                    showLabel: true,
                    onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                        WindowManager.fullscreen(targetApp: self?.circularUIManager?.previousApp)
                    }),
                    onRightClick: ModifierAwareInteraction(base: .doNothing),
                    onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                    onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
                ),
                FunctionNode(
                    id: "window-top-half",
                    name: "Top Half",
                    type: .action,
                    icon: NSImage(named: "window_manager_top_half") ?? NSImage(),
                    showLabel: true,
                    onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                        WindowManager.positionTopHalf(targetApp: self?.circularUIManager?.previousApp)
                    }),
                    onRightClick: ModifierAwareInteraction(base: .doNothing),
                    onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                    onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
                )
            ],
            preferredLayout: .partialSlice,
            slicePositioning: .center,
            onLeftClick: ModifierAwareInteraction(base: .doNothing),
            onRightClick: ModifierAwareInteraction(base: .doNothing),
            onMiddleClick: ModifierAwareInteraction(base: .doNothing),
            onBoundaryCross: ModifierAwareInteraction(base: .expand)
        )
    }

    private func makeBottomNode() -> FunctionNode {
        FunctionNode(
            id: "window-bottom",
            name: "Bottom",
            type: .category,
            icon: NSImage(named: "window_manager_hide") ?? NSImage(),
            children: [
                FunctionNode(
                    id: "window-bottom-half",
                    name: "Bottom Half",
                    type: .action,
                    icon: NSImage(named: "window_manager_bottom_half") ?? NSImage(),
                    showLabel: true,
                    onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                        WindowManager.positionBottomHalf(targetApp: self?.circularUIManager?.previousApp)
                    }),
                    onRightClick: ModifierAwareInteraction(base: .doNothing),
                    onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                    onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
                ),
                FunctionNode(
                    id: "window-hide",
                    name: "Hide",
                    type: .action,
                    icon: NSImage(named: "window_manager_hide") ?? NSImage(),
                    showLabel: true,
                    onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                        WindowManager.hideWindow(targetApp: self?.circularUIManager?.previousApp)
                    }),
                    onRightClick: ModifierAwareInteraction(base: .doNothing),
                    onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                    onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
                )
            ],
            preferredLayout: .partialSlice,
            slicePositioning: .center,
            onLeftClick: ModifierAwareInteraction(base: .doNothing),
            onRightClick: ModifierAwareInteraction(base: .doNothing),
            onMiddleClick: ModifierAwareInteraction(base: .doNothing),
            onBoundaryCross: ModifierAwareInteraction(base: .expand)
        )
    }

    /// Builds a simple quarter-position action node.
    private func makeQuarterNode(
        id: String,
        name: String,
        imageName: String,
        action: @escaping (NSRunningApplication?) -> Void
    ) -> FunctionNode {
        FunctionNode(
            id: id,
            name: name,
            type: .action,
            icon: NSImage(named: imageName) ?? NSImage(),
            preferredLayout: nil,
            showLabel: true,
            onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                action(self?.circularUIManager?.previousApp)
            }),
            onRightClick: ModifierAwareInteraction(base: .doNothing),
            onMiddleClick: ModifierAwareInteraction(base: .doNothing),
            onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
        )
    }

    /// Builds a left or right half node — category with child ring if a
    /// neighbouring screen exists in that direction, direct action otherwise.
    private func makeDirectionalHalfNode(
        direction: ScreenDirection,
        neighbourScreen: NSScreen?
    ) -> FunctionNode {
        let isRight      = direction == .right
        let id           = isRight ? "window-right-half"                  : "window-left-half"
        let halfName     = isRight ? "Right Half"                         : "Left Half"
        let halfImage    = isRight ? "window_manager_right_half"          : "window_manager_left_half"
        let moveId       = isRight ? "window-move-right-screen"           : "window-move-left-screen"
        let moveName     = isRight ? "Move to Right Display"              : "Move to Left Display"
        let moveImage    = isRight ? "window_manager_switch_monitor_right" : "window_manager_switch_monitor_left"
        let halfAction   = isRight ? WindowManager.positionRightHalf      : WindowManager.positionLeftHalf

        guard let screen = neighbourScreen else {
            return FunctionNode(
                id: id,
                name: halfName,
                type: .action,
                icon: NSImage(named: halfImage) ?? NSImage(),
                preferredLayout: nil,
                showLabel: true,
                onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                    halfAction(self?.circularUIManager?.previousApp)
                }),
                onRightClick: ModifierAwareInteraction(base: .doNothing),
                onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
            )
        }

        let halfChild = FunctionNode(
            id: "\(id)-action",
            name: halfName,
            type: .action,
            icon: NSImage(named: halfImage) ?? NSImage(),
            showLabel: true,
            onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                halfAction(self?.circularUIManager?.previousApp)
            }),
            onRightClick: ModifierAwareInteraction(base: .doNothing),
            onMiddleClick: ModifierAwareInteraction(base: .doNothing),
            onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
        )

        let moveChild = FunctionNode(
            id: moveId,
            name: moveName,
            type: .action,
            icon: NSImage(named: moveImage) ?? NSImage(),
            showLabel: true,
            onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                WindowManager.moveToScreen(screen, targetApp: self?.circularUIManager?.previousApp)
            }),
            onRightClick: ModifierAwareInteraction(base: .doNothing),
            onMiddleClick: ModifierAwareInteraction(base: .doNothing),
            onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
        )

        return FunctionNode(
            id: id,
            name: isRight ? "Right" : "Left",
            type: .category,
            icon: NSImage(named: halfImage) ?? NSImage(),
            children: [halfChild, moveChild],
            preferredLayout: .partialSlice,
            slicePositioning: .center,
            onLeftClick: ModifierAwareInteraction(base: .doNothing),
            onRightClick: ModifierAwareInteraction(base: .doNothing),
            onMiddleClick: ModifierAwareInteraction(base: .doNothing),
            onBoundaryCross: ModifierAwareInteraction(base: .expand)
        )
    }
}
