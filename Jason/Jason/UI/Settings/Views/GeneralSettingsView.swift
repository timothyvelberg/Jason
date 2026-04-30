//
//  GeneralSettingsView.swift
//  Jason
//
//  Created by Timothy Velberg on 25/02/2026.
//

import SwiftUI
import ApplicationServices

struct GeneralSettingsView: View {

    @State private var permissionManager = AccessibilityPermissionManager.shared
    @State private var showRestartAlert: Bool = false

    var body: some View {
        VStack(spacing: 0) {

            // Header
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    Text("Permissions")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)

                    accessibilityCard

                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            let previous = permissionManager.state
            permissionManager.update()
            if previous == .notGranted && permissionManager.state == .grantedPendingRestart {
                showRestartAlert = true
            }
        }
        .alert("Restart Required", isPresented: $showRestartAlert) {
            Button("Restart Now") {
                NSApplication.shared.relaunch()
            }
        } message: {
            Text("Accessibility access has been granted. Jason needs to restart to activate hotkey monitoring.")
        }
        .onAppear {
            permissionManager.update()
        }
    }

    // MARK: - Accessibility Card

    private var accessibilityCard: some View {
        HStack(spacing: 16) {

            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(cardIconBackground)
                    .frame(width: 48, height: 48)

                Image(systemName: "accessibility")
                    .font(.system(size: 22))
                    .foregroundColor(cardIconColor)
            }

            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text("Accessibility")
                    .font(.body)
                    .fontWeight(.medium)

                Text(cardMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            // Action
            switch permissionManager.state {
            case .notGranted:
                Button("Open Settings") {
                    openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)

            case .grantedPendingRestart:
                Button("Restart Now") {
                    NSApplication.shared.relaunch()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

            case .active:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.green)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(cardBorderColor, lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private var cardMessage: String {
        switch permissionManager.state {
        case .notGranted:
            return "Required for hotkey monitoring and window event handling. Jason cannot function without this."
        case .grantedPendingRestart:
            return "Access granted. Restart Jason to activate hotkey monitoring."
        case .active:
            return "Access granted. Hotkeys and event monitoring are active."
        }
    }

    private var cardIconColor: Color {
        switch permissionManager.state {
        case .notGranted: return .red
        case .grantedPendingRestart: return .orange
        case .active: return .green
        }
    }

    private var cardIconBackground: Color {
        switch permissionManager.state {
        case .notGranted: return .red.opacity(0.12)
        case .grantedPendingRestart: return .orange.opacity(0.12)
        case .active: return .green.opacity(0.12)
        }
    }

    private var cardBorderColor: Color {
        switch permissionManager.state {
        case .notGranted: return .red.opacity(0.25)
        case .grantedPendingRestart: return .orange.opacity(0.25)
        case .active: return .green.opacity(0.25)
        }
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
