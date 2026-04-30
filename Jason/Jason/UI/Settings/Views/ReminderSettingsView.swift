//
//  RemindersSettingsView.swift
//  Jason
//
//  Created by Timothy Velberg on 16/02/2026.
//

import SwiftUI
import EventKit

struct RemindersSettingsView: View {
    @State private var sources: [ReminderSource] = []
    @State private var enabledListIDs: Set<String> = []
    @State private var authorizationStatus: EKAuthorizationStatus = .notDetermined

    private var eventStore: EKEventStore { PermissionManager.shared.getEventStore() }

    static let enabledListsKey = "RemindersProvider.enabledListIDs"

    struct ReminderSource: Identifiable {
        let id: String
        let name: String
        let lists: [ReminderListEntry]
    }

    struct ReminderListEntry: Identifiable {
        let id: String
        let title: String
        let color: NSColor
        let typeName: String
    }

    private var permissionState: SettingsPermissionState {
        switch authorizationStatus {
        case .authorized, .fullAccess: return .authorized
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    var body: some View {
        SettingsListShell(
            title: "Reminders",
            emptyIcon: "checklist",
            emptyTitle: "No reminder lists found",
            primaryLabel: "Enable All",
            primaryIcon: nil,
            primaryAction: enableAll,
            secondaryLabel: "Disable All",
            secondaryAction: disableAll,
            permission: SettingsPermissionConfig(
                state: permissionState,
                icon: "checklist",
                notDeterminedMessage: "Grant access to manage which reminder lists appear in Jason.",
                deniedMessage: "Open System Settings to grant Jason reminders access.",
                onRequestAccess: requestAccess,
                onOpenSettings: {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                        NSWorkspace.shared.open(url)
                    }
                }
            ),
            isEmpty: sources.isEmpty
        ) {
            ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                // Header row
                VStack(spacing: 4) {
                    if index > 0 {
                        Divider()
                            .padding(.horizontal, -8)
                    }
                    Text(source.name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    Divider()
                        .padding(.horizontal, -8)
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())

                // Reminder list rows
                ForEach(source.lists) { list in
                    ReminderListToggleRow(
                        list: list,
                        isEnabled: enabledListIDs.contains(list.id),
                        onToggle: { toggleList(id: list.id, enabled: $0) }
                    )
                }
            }
        }
        .onAppear { checkAuthorizationAndLoad() }
        .onReceive(NotificationCenter.default.publisher(for: .remindersPermissionChanged)) { _ in
            checkAuthorizationAndLoad()
        }
    }

    // MARK: - Data Loading

    private func checkAuthorizationAndLoad() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
        if authorizationStatus == .authorized || authorizationStatus == .fullAccess {
            loadReminderLists()
        }
    }

    private func requestAccess() {
        PermissionManager.shared.requestRemindersAccess { _ in
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.title == "Jason Settings" })?.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func loadReminderLists() {
        enabledListIDs = Self.loadEnabledListIDs()
        var sourceDict: [String: (name: String, lists: [ReminderListEntry])] = [:]

        for list in eventStore.calendars(for: .reminder) {
            let sourceId = list.source?.sourceIdentifier ?? "unknown"
            let entry = ReminderListEntry(
                id: list.calendarIdentifier,
                title: list.title,
                color: NSColor(cgColor: list.cgColor) ?? .systemBlue,
                typeName: listTypeName(list.type)
            )
            if sourceDict[sourceId] == nil {
                sourceDict[sourceId] = (name: list.source?.title ?? "Unknown", lists: [])
            }
            sourceDict[sourceId]?.lists.append(entry)
        }

        sources = sourceDict
            .filter { !$0.value.lists.isEmpty }
            .map { ReminderSource(id: $0.key, name: $0.value.name, lists: $0.value.lists) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func listTypeName(_ type: EKCalendarType) -> String {
        switch type {
        case .local: return "Local"
        case .calDAV: return "CalDAV"
        case .exchange: return "Exchange"
        case .subscription: return "Subscription"
        @unknown default: return "Other"
        }
    }

    // MARK: - Toggle Actions

    private func toggleList(id: String, enabled: Bool) {
        if enabled { enabledListIDs.insert(id) } else { enabledListIDs.remove(id) }
        saveEnabledListIDs()
        notifyProvider()
    }

    private func enableAll() {
        enabledListIDs = Set(sources.flatMap(\.lists).map(\.id))
        saveEnabledListIDs()
        notifyProvider()
    }

    private func disableAll() {
        enabledListIDs.removeAll()
        saveEnabledListIDs()
        notifyProvider()
    }

    // MARK: - Persistence

    private func saveEnabledListIDs() {
        UserDefaults.standard.set(Array(enabledListIDs), forKey: Self.enabledListsKey)
    }

    static func loadEnabledListIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: enabledListsKey) ?? [])
    }

    private func notifyProvider() {
        NotificationCenter.default.post(name: .providerContentUpdated, object: nil)
    }
}

// MARK: - Reminder List Toggle Row

struct ReminderListToggleRow: View {
    let list: RemindersSettingsView.ReminderListEntry
    let isEnabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(nsColor: list.color))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(list.title)
                    .font(.body)
                    .fontWeight(.medium)
                Text(list.typeName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(get: { isEnabled }, set: { onToggle($0) }))
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.vertical, 2)
        .listRowSeparator(.hidden)
    }
}
