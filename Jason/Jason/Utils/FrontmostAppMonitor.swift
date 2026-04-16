//
//  FrontmostAppMonitor.swift
//  Jason
//
//  Created by Timothy Velberg on 16/04/2026.
//

import Foundation
import AppKit

extension Notification.Name {
    static let frontmostAppChanged = Notification.Name("jason.frontmostAppChanged")
}

class FrontmostAppMonitor: ObservableObject {

    // MARK: - Singleton

    static let shared = FrontmostAppMonitor()

    // MARK: - Published State

    @Published private(set) var frontmostApp: NSRunningApplication? = NSWorkspace.shared.frontmostApplication

    var frontmostBundleID: String? {
        frontmostApp?.bundleIdentifier
    }

    // MARK: - Init

    private init() {
        print("🔭 [FrontmostAppMonitor] Initialized")
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Observation

    @objc private func handleAppActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        print("🔭 [FrontmostAppMonitor] Frontmost app changed: \(app.localizedName ?? "unknown") (\(app.bundleIdentifier ?? "?"))")

        DispatchQueue.main.async {
            self.frontmostApp = app
            NotificationCenter.default.post(
                name: .frontmostAppChanged,
                object: app
            )
        }
    }
}
