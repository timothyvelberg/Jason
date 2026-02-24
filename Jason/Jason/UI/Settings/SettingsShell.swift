//
//  SettingsShell.swift
//  Jason
//
//  Shared structural components for settings list views.
//  Provides a consistent layout shell and row template used by
//  Apps, Folders, Files, Snippets, Instances, Calendar, and Reminders.
//

import SwiftUI
import AppKit

// MARK: - Permission Support

enum SettingsPermissionState {
    case notDetermined
    case authorized
    case denied
}

struct SettingsPermissionConfig {
    let state: SettingsPermissionState
    let icon: String
    let notDeterminedMessage: String
    let deniedMessage: String
    let onRequestAccess: () -> Void
    let onOpenSettings: () -> Void
}

// MARK: - Settings List Shell

/// Outer frame shared by all settings list views.
/// Handles the page title, optional permission gating, empty state,
/// list body, divider, and bottom toolbar.
///
/// Permission: pass a `SettingsPermissionConfig` for views that require
/// system access (Calendar, Reminders). When nil, no permission layer is shown.
///
/// Note: reordering (.onMove) is handled inside the caller's ForEach, not here,
/// since .onMove can only be applied to ForEach — not to a generic View.
struct SettingsListShell<RowContent: View>: View {

    // Page title — mirrors the active sidebar item label
    let title: String

    // Empty state
    let emptyIcon: String
    let emptyTitle: String
    let emptySubtitle: String

    // Toolbar — primaryIcon is optional (nil renders plain text button)
    let primaryLabel: String
    let primaryIcon: String?
    let primaryAction: () -> Void
    let secondaryLabel: String?
    let secondaryAction: (() -> Void)?

    // Optional permission gating
    let permission: SettingsPermissionConfig?

    // isEmpty must come before the @ViewBuilder rows closure
    let isEmpty: Bool

    @ViewBuilder let rows: () -> RowContent

    init(
        title: String,
        emptyIcon: String,
        emptyTitle: String,
        emptySubtitle: String = "",
        primaryLabel: String,
        primaryIcon: String? = "plus.circle.fill",
        primaryAction: @escaping () -> Void,
        secondaryLabel: String? = nil,
        secondaryAction: (() -> Void)? = nil,
        permission: SettingsPermissionConfig? = nil,
        isEmpty: Bool,
        @ViewBuilder rows: @escaping () -> RowContent
    ) {
        self.title = title
        self.emptyIcon = emptyIcon
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
        self.primaryLabel = primaryLabel
        self.primaryIcon = primaryIcon
        self.primaryAction = primaryAction
        self.secondaryLabel = secondaryLabel
        self.secondaryAction = secondaryAction
        self.permission = permission
        self.isEmpty = isEmpty
        self.rows = rows
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            // Content area
            if let permission, permission.state != .authorized {
                permissionView(permission)
            } else if isEmpty {
                emptyState
            } else {
                List { rows() }
                    .listStyle(.inset)
            }

            Divider()

            // Footer — hidden when permission not yet granted
            if permission == nil || permission?.state == .authorized {
                bottomToolbar
            }
        }
    }

    // MARK: - Subviews

    private func permissionView(_ config: SettingsPermissionConfig) -> some View {
        VStack(spacing: 16) {
            switch config.state {
            case .notDetermined:
                Image(systemName: config.icon)
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text(config.notDeterminedMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Button("Grant Access", action: config.onRequestAccess)
                    .buttonStyle(.borderedProminent)

            case .denied:
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundColor(.red)
                Text(config.deniedMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Button("Open Settings", action: config.onOpenSettings)
                    .buttonStyle(.borderedProminent)

            case .authorized:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: emptyIcon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(emptyTitle)
                .font(.headline)
                .foregroundColor(.secondary)
            if !emptySubtitle.isEmpty {
                Text(emptySubtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bottomToolbar: some View {
        HStack(spacing: 8) {
            Button(action: primaryAction) {
                if let icon = primaryIcon {
                    Label(primaryLabel, systemImage: icon)
                } else {
                    Text(primaryLabel)
                }
            }
            .buttonStyle(.borderedProminent)

            if let secondaryLabel, let secondaryAction {
                Button(action: secondaryAction) {
                    Text(secondaryLabel)
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - View Helpers

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Shared Models

/// Shared model used by EditRingView and settings views to represent a content provider.
struct ProviderConfig: Identifiable {
    let id = UUID()
    let type: String
    let name: String
    let description: String
    var isEnabled: Bool
    var displayMode: ProviderDisplayMode
}

// MARK: - Settings Row Icon

enum SettingsRowIcon {
    case nsImage(NSImage)
    case systemSymbol(String, Color)
    case asset(String)
}

// MARK: - Settings Row

/// Standard row used across Apps, Folders, Snippets, and Instances.
///
/// - `showDragHandle`: shows the reorder gripper (disable for Instances)
/// - `metadata`: labelled view slot for badges, counts, etc.
/// - `onTap`: optional — used by Instances for tap-to-test
struct SettingsRow<Metadata: View>: View {

    let icon: SettingsRowIcon
    let title: String
    let subtitle: String
    let showDragHandle: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onTap: (() -> Void)?
    let metadata: () -> Metadata

    @State private var isHovered = false

    init(
        icon: SettingsRowIcon,
        title: String,
        subtitle: String,
        showDragHandle: Bool = true,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onTap: (() -> Void)? = nil,
        @ViewBuilder metadata: @escaping () -> Metadata = { EmptyView() }
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.showDragHandle = showDragHandle
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onTap = onTap
        self.metadata = metadata
    }

    var body: some View {
        HStack(spacing: 12) {

            if showDragHandle {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary.opacity(0.5))
                    .help("Drag to reorder")
            }

            rowIcon
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            metadata()

            if isHovered {
                actionButtons
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .if(onTap != nil) { view in
            view.onTapGesture { onTap?() }
        }
    }

    @ViewBuilder
    private var rowIcon: some View {
        switch icon {
        case .nsImage(let image):
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        case .systemSymbol(let name, let color):
            Image(systemName: name)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
        case .asset(let name):
            Image(name)
                .resizable()
                .scaledToFit()
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button(action: onEdit) {
                Image("context_actions_edit")
            }
            .buttonStyle(.borderless)
            .help("Edit")
            
            Button(action: onDelete) {
                Image("context_actions_delete")
            }
            .buttonStyle(.borderless)
            .help("Delete")
        }
    }
}
