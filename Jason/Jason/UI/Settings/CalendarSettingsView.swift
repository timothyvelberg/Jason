//
//  CalendarSettingsView.swift
//  Jason
//
//  Created by Timothy Velberg on 13/02/2026.
//

import SwiftUI
import EventKit

struct CalendarSettingsView: View {
    @State private var sources: [CalendarSource] = []
    @State private var enabledCalendarIDs: Set<String> = []
    @State private var authorizationStatus: EKAuthorizationStatus = .notDetermined

    private var eventStore: EKEventStore { PermissionManager.shared.getEventStore() }

    static let enabledCalendarsKey = "CalendarProvider.enabledCalendarIDs"

    struct CalendarSource: Identifiable {
        let id: String
        let name: String
        let calendars: [CalendarEntry]
    }

    struct CalendarEntry: Identifiable {
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
            title: "Calendar",
            emptyIcon: "calendar.badge.exclamationmark",
            emptyTitle: "No calendars found",
            primaryLabel: "Enable All",
            primaryIcon: nil,
            primaryAction: enableAll,
            secondaryLabel: "Disable All",
            secondaryAction: disableAll,
            permission: SettingsPermissionConfig(
                state: permissionState,
                icon: "calendar.badge.plus",
                notDeterminedMessage: "Grant access to manage which calendars appear in Jason.",
                deniedMessage: "Open System Settings to grant Jason calendar access.",
                onRequestAccess: requestAccess,
                onOpenSettings: {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
            ),
            isEmpty: sources.isEmpty
        ) {
            ForEach(sources) { source in
                Section(header: Text(source.name)) {
                    ForEach(source.calendars) { calendar in
                        CalendarToggleRow(
                            calendar: calendar,
                            isEnabled: enabledCalendarIDs.contains(calendar.id),
                            onToggle: { toggleCalendar(id: calendar.id, enabled: $0) }
                        )
                    }
                }
            }
        }
        .onAppear { checkAuthorizationAndLoad() }
        .onReceive(NotificationCenter.default.publisher(for: .calendarPermissionChanged)) { _ in
            checkAuthorizationAndLoad()
        }
    }

    // MARK: - Data Loading

    private func checkAuthorizationAndLoad() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        if authorizationStatus == .authorized || authorizationStatus == .fullAccess {
            loadCalendars()
        }
    }

    private func requestAccess() {
        PermissionManager.shared.requestCalendarAccess { _ in
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.title == "Jason" })?.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func loadCalendars() {
        enabledCalendarIDs = Self.loadEnabledCalendarIDs()
        var sourceDict: [String: (name: String, calendars: [CalendarEntry])] = [:]

        for cal in eventStore.calendars(for: .event) {
            let sourceId = cal.source?.sourceIdentifier ?? "unknown"
            let entry = CalendarEntry(
                id: cal.calendarIdentifier,
                title: cal.title,
                color: NSColor(cgColor: cal.cgColor) ?? .systemBlue,
                typeName: calendarTypeName(cal.type)
            )
            if sourceDict[sourceId] == nil {
                sourceDict[sourceId] = (name: cal.source?.title ?? "Unknown", calendars: [])
            }
            sourceDict[sourceId]?.calendars.append(entry)
        }

        sources = sourceDict
            .filter { !$0.value.calendars.isEmpty }
            .map { CalendarSource(id: $0.key, name: $0.value.name, calendars: $0.value.calendars) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func calendarTypeName(_ type: EKCalendarType) -> String {
        switch type {
        case .local: return "Local"
        case .calDAV: return "CalDAV"
        case .exchange: return "Exchange"
        case .subscription: return "Subscription"
        case .birthday: return "Birthday"
        @unknown default: return "Other"
        }
    }

    // MARK: - Toggle Actions

    private func toggleCalendar(id: String, enabled: Bool) {
        if enabled { enabledCalendarIDs.insert(id) } else { enabledCalendarIDs.remove(id) }
        saveEnabledCalendarIDs()
        notifyProvider()
    }

    private func enableAll() {
        enabledCalendarIDs = Set(sources.flatMap(\.calendars).map(\.id))
        saveEnabledCalendarIDs()
        notifyProvider()
    }

    private func disableAll() {
        enabledCalendarIDs.removeAll()
        saveEnabledCalendarIDs()
        notifyProvider()
    }

    // MARK: - Persistence

    private func saveEnabledCalendarIDs() {
        UserDefaults.standard.set(Array(enabledCalendarIDs), forKey: Self.enabledCalendarsKey)
    }

    static func loadEnabledCalendarIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: enabledCalendarsKey) ?? [])
    }

    private func notifyProvider() {
        NotificationCenter.default.post(name: .providerContentUpdated, object: nil)
    }
}

// MARK: - Calendar Toggle Row

struct CalendarToggleRow: View {
    let calendar: CalendarSettingsView.CalendarEntry
    let isEnabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(nsColor: calendar.color))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(calendar.title)
                    .font(.body)
                    .fontWeight(.medium)
                Text(calendar.typeName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(get: { isEnabled }, set: { onToggle($0) }))
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}
