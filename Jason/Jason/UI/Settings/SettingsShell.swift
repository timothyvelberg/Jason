//
//  SettingsShell.swift
//  Jason
//
//  Shared structural components for settings list views.
//  Provides a consistent layout shell and row template used by
//  Apps, Folders, Snippets, and Instances settings views.
//

import SwiftUI
import AppKit

// MARK: - Settings List Shell

/// Outer frame shared by all settings list views.
/// Handles the page title, empty state, the list body, divider, and bottom toolbar.
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
    
    // Toolbar
    let primaryLabel: String
    let primaryAction: () -> Void
    let secondaryLabel: String?
    let secondaryAction: (() -> Void)?
    
    // isEmpty must come before the @ViewBuilder rows closure
    // so Swift can use rows as a trailing closure at the call site
    let isEmpty: Bool
    
    @ViewBuilder let rows: () -> RowContent
    
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
            
            if isEmpty {
                emptyState
            } else {
                List {
                    rows()
                }
                .listStyle(.inset)
            }
            
            Divider()
            
            bottomToolbar
        }
    }
    
    // MARK: - Subviews
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: emptyIcon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(emptyTitle)
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text(emptySubtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var bottomToolbar: some View {
        HStack(spacing: 8) {
            Button(action: primaryAction) {
                Label(primaryLabel, systemImage: "plus.circle.fill")
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
    /// Conditionally applies a transform to a view.
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}


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

/// Icon type for a settings row.
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
            
            actionButtons
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
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
