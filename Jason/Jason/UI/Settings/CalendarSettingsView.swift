//
//  CalendarSettingsView.swift
//  Jason
//
//  Created by Timothy Velberg on 13/02/2026.
//  Settings view for selecting which calendars appear in the CalendarProvider

import SwiftUI
import EventKit

struct CalendarSettingsView: View {
    @State private var sources: [CalendarSource] = []
    @State private var enabledCalendarIDs: Set<String> = []
    @State private var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @State private var isLoading = true
    
    // Use shared eventStore from PermissionManager
    private var eventStore: EKEventStore {
        PermissionManager.shared.getEventStore()
    }
    
    // UserDefaults key for storing enabled calendar IDs
    static let enabledCalendarsKey = "CalendarProvider.enabledCalendarIDs"
    
    struct CalendarSource: Identifiable {
        let id: String
        let name: String
        let calendars: [CalendarEntry]
    }
    
    struct CalendarEntry: Identifiable {
        let id: String  // calendarIdentifier
        let title: String
        let color: NSColor
        let typeName: String
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if authorizationStatus == .authorized || authorizationStatus == .fullAccess {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading calendars...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if sources.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("No calendars found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(sources) { source in
                            Section(header: Text(source.name)) {
                                ForEach(source.calendars) { calendar in
                                    CalendarToggleRow(
                                        calendar: calendar,
                                        isEnabled: enabledCalendarIDs.contains(calendar.id),
                                        onToggle: { enabled in
                                            toggleCalendar(id: calendar.id, enabled: enabled)
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            } else if authorizationStatus == .notDetermined {
                VStack(spacing: 16) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("Calendar access required")
                        .font(.headline)
                    
                    Text("Grant access to manage which calendars appear in Jason.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Grant Access") {
                        requestAccess()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundColor(.red)
                    
                    Text("Calendar access denied")
                        .font(.headline)
                    
                    Text("Open System Settings to grant Jason calendar access.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Open Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            Divider()
            
            HStack {
                let totalCount = sources.flatMap(\.calendars).count
                Text("\(enabledCalendarIDs.count) of \(totalCount) calendar\(totalCount == 1 ? "" : "s") enabled")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Enable All") {
                    enableAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button("Disable All") {
                    disableAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()
        }
        .onAppear {
            checkAuthorizationAndLoad()
            // Listen for permission changes
            NotificationCenter.default.addObserver(
                forName: .calendarPermissionChanged,
                object: nil,
                queue: .main
            ) { _ in
                checkAuthorizationAndLoad()
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func checkAuthorizationAndLoad() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        
        if authorizationStatus == .authorized || authorizationStatus == .fullAccess {
            loadCalendars()
        } else {
            isLoading = false
        }
    }
    
    private func requestAccess() {
        // Use PermissionManager instead of local request
        PermissionManager.shared.requestCalendarAccess { granted in
            // The notification will trigger checkAuthorizationAndLoad()
            // Bring the settings window back to front
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.title == "Jason" })?.makeKeyAndOrderFront(nil)
            }
        }
    }
    
    private func loadCalendars() {
        // Load saved enabled IDs
        enabledCalendarIDs = Self.loadEnabledCalendarIDs()
        
        // Build source → calendar hierarchy
        let allCalendars = eventStore.calendars(for: .event)
        
        // Group by source
        var sourceDict: [String: (name: String, calendars: [CalendarEntry])] = [:]
        
        for cal in allCalendars {
            let sourceName = cal.source?.title ?? "Unknown"
            let sourceId = cal.source?.sourceIdentifier ?? "unknown"
            
            let entry = CalendarEntry(
                id: cal.calendarIdentifier,
                title: cal.title,
                color: NSColor(cgColor: cal.cgColor) ?? .systemBlue,
                typeName: calendarTypeName(cal.type)
            )
            
            if sourceDict[sourceId] == nil {
                sourceDict[sourceId] = (name: sourceName, calendars: [])
            }
            sourceDict[sourceId]?.calendars.append(entry)
        }
        
        // Convert to sorted array, skip empty sources
        sources = sourceDict
            .filter { !$0.value.calendars.isEmpty }
            .map { CalendarSource(id: $0.key, name: $0.value.name, calendars: $0.value.calendars) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        
        // If no saved preferences exist yet, enable nothing (user picks explicitly)
        // OR if you prefer all-on by default, uncomment the block below:
        // if enabledCalendarIDs.isEmpty {
        //     enabledCalendarIDs = Set(allCalendars.map { $0.calendarIdentifier })
        //     saveEnabledCalendarIDs()
        // }
        
        isLoading = false
        print("📅 [CalendarSettings] Loaded \(sources.count) sources, \(enabledCalendarIDs.count) enabled calendars")
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
        if enabled {
            enabledCalendarIDs.insert(id)
        } else {
            enabledCalendarIDs.remove(id)
        }
        saveEnabledCalendarIDs()
        notifyProvider()
    }
    
    private func enableAll() {
        let allIDs = sources.flatMap(\.calendars).map(\.id)
        enabledCalendarIDs = Set(allIDs)
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
        let array = Array(enabledCalendarIDs)
        UserDefaults.standard.set(array, forKey: Self.enabledCalendarsKey)
        print("💾 [CalendarSettings] Saved \(array.count) enabled calendar IDs")
    }
    
    static func loadEnabledCalendarIDs() -> Set<String> {
        guard let array = UserDefaults.standard.stringArray(forKey: enabledCalendarsKey) else {
            return []
        }
        return Set(array)
    }
    
    // MARK: - Provider Notification
    
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
            // Calendar color dot
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
            
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}
