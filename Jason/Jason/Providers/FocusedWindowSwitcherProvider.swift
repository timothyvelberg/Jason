//
//  FocusedWindowSwitcherProvider.swift
//  Jason
//
//  Created by Timothy Velberg on 15/04/2026.
//

import Foundation
import AppKit

class FocusedWindowSwitcherProvider: ObservableObject, FunctionProvider {

    // MARK: - FunctionProvider Protocol

    var providerId: String { "focused-window-switcher" }
    var providerName: String { "Window Switcher" }
    var providerIcon: NSImage {
        NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: nil) ?? NSImage()
    }

    // MARK: - Cache

    private var cachedNodes: [FunctionNode]?
    private var cachedForBundleID: String?
    private var lastFetchDate: Date?
    private let cacheTimeout: TimeInterval = 60

    private var isCacheValid: Bool {
        guard let cachedForBundleID,
              let lastFetchDate,
              let frontmost = NSWorkspace.shared.frontmostApplication,
              let currentBundleID = frontmost.bundleIdentifier else {
            return false
        }
        let notExpired = Date().timeIntervalSince(lastFetchDate) < cacheTimeout
        let sameApp = cachedForBundleID == currentBundleID
        return notExpired && sameApp
    }

    // MARK: - Init / Teardown

    init() {
        print("[FocusedWindowSwitcher] Initialized")
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostAppChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func teardown() {
        print("[FocusedWindowSwitcher] teardown()")
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        invalidateCache()
        print("[FocusedWindowSwitcher] teardown complete")
    }

    func refresh() {
        print("[FocusedWindowSwitcher] refresh() called")
        invalidateCache()
    }

    func clearCache() {
        invalidateCache()
        print("[FocusedWindowSwitcher] Cache cleared")
    }

    // MARK: - Cache Helpers

    private func invalidateCache() {
        cachedNodes = nil
        cachedForBundleID = nil
        lastFetchDate = nil
    }

    // MARK: - Observation

    @objc private func frontmostAppChanged() {
        print("[FocusedWindowSwitcher] Frontmost app changed — invalidating cache")
        invalidateCache()
    }

    // MARK: - FunctionProvider

    func provideFunctions() -> [FunctionNode] {
        if isCacheValid, let cached = cachedNodes {
            print("[FocusedWindowSwitcher] Returning cached nodes (\(cached.count) windows)")
            return cached
        }

        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            return [createNoWindowsNode(message: "No active app")]
        }

        let windows = AppSwitcherManager.shared.fetchWindows(for: frontmost)
        print("[FocusedWindowSwitcher] Fetched \(windows.count) window(s) for \(frontmost.localizedName ?? "unknown")")

        if windows.isEmpty {
            return [createNoWindowsNode(message: "No windows open")]
        }

        let nodes = windows.map { window in
            FunctionNode(
                id: "focused-window-\(window.windowID)",
                name: window.title.isEmpty ? "Untitled Window" : window.title,
                type: .action,
                icon: frontmost.icon ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil) ?? NSImage(),
                preferredLayout: .partialSlice,
                showLabel: true,
                slicePositioning: .center,
                providerId: providerId,
                onLeftClick: ModifierAwareInteraction(base: .execute {
                    AppSwitcherManager.shared.focusWindow(window)
                }),
                onRightClick: ModifierAwareInteraction(base: .doNothing),
                onBoundaryCross: ModifierAwareInteraction(base: .execute {
                    AppSwitcherManager.shared.focusWindow(window)
                })
            )
        }

        cachedNodes = nodes
        cachedForBundleID = frontmost.bundleIdentifier
        lastFetchDate = Date()

        return nodes
    }

    // MARK: - Empty State

    private func createNoWindowsNode(message: String) -> FunctionNode {
        FunctionNode(
            id: "focused-window-empty",
            name: message,
            type: .action,
            icon: NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil) ?? NSImage(),
            preferredLayout: .partialSlice,
            showLabel: true,
            slicePositioning: .center,
            providerId: providerId,
            onLeftClick: ModifierAwareInteraction(base: .doNothing),
            onRightClick: ModifierAwareInteraction(base: .doNothing),
            onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
        )
    }
}
