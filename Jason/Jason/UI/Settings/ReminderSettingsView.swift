//
//  RemindersSettingsView.swift
//  Jason
//
//  Created by Timothy Velberg on 16/02/2026.
//  Settings view for selecting which reminder lists appear in the TodoListProvider
//

import SwiftUI
import EventKit

struct RemindersSettingsView: View {
    @State private var sources: [ReminderSource] = []
    @State private var enabledListIDs: Set<String> = []
    @State private var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @State private var isLoading = true
    
    // Use shared eventStore from PermissionManager
    private var eventStore: EKEventStore {
        PermissionManager.shared.getEventStore()
    }
    
    // UserDefaults key for storing enabled reminder list IDs
    static let enabledListsKey = "RemindersProvider.enabledListIDs"
    
    struct ReminderSource: Identifiable {
        let id: String
        let name: String
        let lists: [ReminderListEntry]
    }
    
    struct ReminderListEntry: Identifiable {
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
                        Text("Loading reminder lists...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if sources.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checklist")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("No reminder lists found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(sources) { source in
                            Section(header: Text(source.name)) {
                                ForEach(source.lists) { list in
                                    ReminderListToggleRow(
                                        list: list,
                                        isEnabled: enabledListIDs.contains(list.id),
                                        onToggle: { enabled in
                                            toggleList(id: list.id, enabled: enabled)
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
                    Image(systemName: "checklist")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("Reminders access required")
                        .font(.headline)
                    
                    Text("Grant access to manage which reminder lists appear in Jason.")
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
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.red)
                    
                    Text("Reminders access denied")
                        .font(.headline)
                    
                    Text("Open System Settings to grant Jason reminders access.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Open Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            Divider()
            
            HStack {
                let totalCount = sources.flatMap(\.lists).count
                Text("\(enabledListIDs.count) of \(totalCount) list\(totalCount == 1 ? "" : "s") enabled")
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
                forName: .remindersPermissionChanged,
                object: nil,
                queue: .main
            ) { _ in
                checkAuthorizationAndLoad()
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func checkAuthorizationAndLoad() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
        
        if authorizationStatus == .authorized || authorizationStatus == .fullAccess {
            loadReminderLists()
        } else {
            isLoading = false
        }
    }
    private func requestAccess() {
        // Use PermissionManager instead of local request
        PermissionManager.shared.requestRemindersAccess { granted in
            // The notification will trigger checkAuthorizationAndLoad()
            // Bring the settings window back to front
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.title == "Jason Settings" })?.makeKeyAndOrderFront(nil)
            }
        }
    }
    private func loadReminderLists() {
        // Load saved enabled IDs
        enabledListIDs = Self.loadEnabledListIDs()
        
        // Build source → list hierarchy
        let allLists = eventStore.calendars(for: .reminder)
        
        // Group by source
        var sourceDict: [String: (name: String, lists: [ReminderListEntry])] = [:]
        
        for list in allLists {
            let sourceName = list.source?.title ?? "Unknown"
            let sourceId = list.source?.sourceIdentifier ?? "unknown"
            
            let entry = ReminderListEntry(
                id: list.calendarIdentifier,
                title: list.title,
                color: NSColor(cgColor: list.cgColor) ?? .systemBlue,
                typeName: listTypeName(list.type)
            )
            
            if sourceDict[sourceId] == nil {
                sourceDict[sourceId] = (name: sourceName, lists: [])
            }
            sourceDict[sourceId]?.lists.append(entry)
        }
        
        // Convert to sorted array, skip empty sources
        sources = sourceDict
            .filter { !$0.value.lists.isEmpty }
            .map { ReminderSource(id: $0.key, name: $0.value.name, lists: $0.value.lists) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        
        isLoading = false
        print("✅ [RemindersSettings] Loaded \(sources.count) sources, \(enabledListIDs.count) enabled lists")
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
        if enabled {
            enabledListIDs.insert(id)
        } else {
            enabledListIDs.remove(id)
        }
        saveEnabledListIDs()
        notifyProvider()
    }
    
    private func enableAll() {
        let allIDs = sources.flatMap(\.lists).map(\.id)
        enabledListIDs = Set(allIDs)
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
        let array = Array(enabledListIDs)
        UserDefaults.standard.set(array, forKey: Self.enabledListsKey)
        print("💾 [RemindersSettings] Saved \(array.count) enabled list IDs")
    }
    
    static func loadEnabledListIDs() -> Set<String> {
        guard let array = UserDefaults.standard.stringArray(forKey: enabledListsKey) else {
            return []
        }
        return Set(array)
    }
    
    // MARK: - Provider Notification
    
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
            // List color dot
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
