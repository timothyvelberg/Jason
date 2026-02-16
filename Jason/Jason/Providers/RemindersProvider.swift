//
//  RemindersProvider.swift
//  Jason
//
//  Created by Timothy Velberg on 14/02/2026.
//

import Foundation
import AppKit
import SwiftUI
import EventKit

class RemindersProvider: FunctionProvider, MutableListProvider {

    var providerId: String { "reminders" }
    var providerName: String { "Todo List" }
    var providerIcon: NSImage { NSImage(systemSymbolName: "checklist", accessibilityDescription: "Todo List") ?? NSImage() }
    var defaultTypingMode: TypingMode { .input }
    var panelConfig: PanelConfig { PanelConfig(lineLimit: 1, panelWidth: 320) }
    var onItemsChanged: (() -> Void)?
    
    // MARK: - Data
    
    private var reminders: [EKReminder] = []
    
    // MARK: - Init
    
    init() {
        // Listen for external changes (Reminders app, other devices via iCloud)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeChanged),
            name: .EKEventStoreChanged,
            object: PermissionManager.shared.getEventStore()
        )
        
        // Listen for permission changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(permissionGranted),
            name: .remindersPermissionChanged,
            object: nil
        )
        
        // Fetch reminders if we already have access
        if PermissionManager.shared.hasRemindersAccess {
            fetchReminders()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Permission Handling
    
    private func showPermissionAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Reminders Access Required"
            alert.informativeText = "Jason needs access to your Reminders. Please configure permissions in Settings."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
            
            if alert.runModal() == .alertFirstButtonReturn {
                // Open Jason Settings window
                NotificationCenter.default.post(name: .openSettingsWindow, object: nil)
            }
        }
    }
    
    @objc private func permissionGranted() {
        print("[RemindersProvider] Permission granted - fetching reminders")
        fetchReminders()
    }
    
    // MARK: - Fetching
    
    private func fetchReminders() {
        let eventStore = PermissionManager.shared.getEventStore()
        
        // Filter to only user-enabled lists from Settings
        let enabledIDs = RemindersSettingsView.loadEnabledListIDs()
        
        // If no lists are enabled, don't fetch anything
        if enabledIDs.isEmpty {
            print("[RemindersProvider] No reminder lists enabled — configure in Settings > Reminders")
            DispatchQueue.main.async {
                self.reminders = []
                self.onItemsChanged?()
            }
            return  // Exit early, don't fetch
        }
        
        let calendars = eventStore.calendars(for: .reminder).filter { list in
            enabledIDs.contains(list.calendarIdentifier)
        }
        
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: calendars
        )
        
        eventStore.fetchReminders(matching: predicate) { [weak self] fetched in
            guard let self = self else { return }
            
            // Also fetch recently completed (last 24h) so toggles feel responsive
            let completedPredicate = eventStore.predicateForCompletedReminders(
                withCompletionDateStarting: Calendar.current.date(byAdding: .day, value: -1, to: Date()),
                ending: Date(),
                calendars: calendars
            )
            
            eventStore.fetchReminders(matching: completedPredicate) { [weak self] completedFetched in
                guard let self = self else { return }
                
                let incomplete = fetched ?? []
                let completed = completedFetched ?? []
                
                // Merge, deduplicating by calendarItemIdentifier
                var seen = Set<String>()
                var merged: [EKReminder] = []
                for r in incomplete + completed {
                    if seen.insert(r.calendarItemIdentifier).inserted {
                        merged.append(r)
                    }
                }
                
                DispatchQueue.main.async {
                    self.reminders = merged
                    print("[RemindersProvider] Loaded \(incomplete.count) incomplete + \(completed.count) recently completed reminders")
                    self.onItemsChanged?()
                }
            }
        }
    }
    
    @objc private func storeChanged() {
        print("[RemindersProvider] Reminders store changed - refreshing")
        fetchReminders()
    }
    
    // MARK: - FunctionProvider
    
    func provideFunctions() -> [FunctionNode] {
        guard PermissionManager.shared.hasRemindersAccess else {
            // Show alert to configure in Settings
            showPermissionAlert()
            return []
        }
        
        let items = buildTodoNodes()
        return [
            FunctionNode(
                id: "reminders-list",
                name: "Todo List",
                type: .category,
                icon: NSImage(named: "parent-todo") ?? NSImage(),
                children: items,
                childDisplayMode: .panel,
                providerId: providerId,
                onLeftClick: ModifierAwareInteraction(base: .doNothing),
                onRightClick: ModifierAwareInteraction(base: .doNothing),
                onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                onBoundaryCross: ModifierAwareInteraction(base: .expand)
            )
        ]
    }
    
    private func spacerNode(after listName: String) -> FunctionNode {
        FunctionNode(
            id: "spacer-\(listName)",
            name: "",
            type: .sectionHeader(style: .spacer),
            icon: NSImage(),
            providerId: providerId
        )
    }
    
    private func buildTodoNodes() -> [FunctionNode] {
        if reminders.isEmpty {
            return [
                FunctionNode(
                    id: "reminders-empty",
                    name: "No reminders",
                    type: .action,
                    icon: NSImage(systemSymbolName: "checklist", accessibilityDescription: nil) ?? NSImage(),
                    showLabel: true,
                    providerId: providerId,
                    onLeftClick: ModifierAwareInteraction(base: .doNothing),
                    onRightClick: ModifierAwareInteraction(base: .doNothing),
                    onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                    onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
                )
            ]
        }
        
        // Group by Reminders list (calendar)
        var grouped: [String: [EKReminder]] = [:]

        for reminder in reminders {
            let listName = reminder.calendar.title
            grouped[listName, default: []].append(reminder)
        }

        // Sort lists by most recently modified reminder (newest on top)
        let listOrder = grouped.keys.sorted { a, b in
            let aLatest = grouped[a]?.compactMap({ $0.lastModifiedDate ?? $0.creationDate }).max() ?? .distantPast
            let bLatest = grouped[b]?.compactMap({ $0.lastModifiedDate ?? $0.creationDate }).max() ?? .distantPast
            return aLatest > bLatest
        }
        
        var nodes: [FunctionNode] = []
        
        for (index, listName) in listOrder.enumerated() {
            guard let listReminders = grouped[listName] else { continue }
            
            let incomplete = listReminders.filter { !$0.isCompleted }
            let completed = listReminders.filter { $0.isCompleted }
            
            // Spacer before header (not before first)
//            if index > 0 {
//                nodes.append(spacerNode(after: "before-\(listName)"))
//            }
            
            // List header with Reminders color
            let listColor = Color(cgColor: listReminders.first!.calendar.cgColor)

            nodes.append(FunctionNode(
                id: "group-\(listName)",
                name: listName,
                type: .sectionHeader(style: .category.withTopLine(index > 0).withTextColor(listColor)),
                icon: NSImage(),
                providerId: providerId
            ))
            
            // Spacer after header
//            nodes.append(spacerNode(after: "after-\(listName)"))
            
            // Incomplete first
            let sortedIncomplete = incomplete.sorted { a, b in
                if a.priority != b.priority {
                    return a.priority < b.priority
                }
                return (a.creationDate ?? Date.distantPast) > (b.creationDate ?? Date.distantPast)
            }
            nodes.append(contentsOf: sortedIncomplete.map { makeReminderNode($0) })
            
            // Completed after
            nodes.append(contentsOf: completed.map { makeReminderNode($0) })
        }
//        if !listOrder.isEmpty {
//            nodes.append(spacerNode(after: "end"))
//        }
        return nodes
    }
    
    func loadChildren(for node: FunctionNode) async -> [FunctionNode] {
        return buildTodoNodes()
    }
    
    // MARK: - Node Creation
    
    private func makeReminderNode(_ reminder: EKReminder) -> FunctionNode {
        let icon: NSImage
        if reminder.isCompleted {
            icon = NSImage(named: "icon_done") ?? NSImage()
        } else {
            icon = NSImage(named: "icon_todo") ?? NSImage()
        }
        
        // Build subtitle with due date if present
        var name = reminder.title ?? "Untitled"
        if let dueDate = reminder.dueDateComponents?.date {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            name += " · \(formatter.string(from: dueDate))"
        }
        
        let reminderId = reminder.calendarItemIdentifier
        
        return FunctionNode(
            id: reminderId,
            name: name,
            type: .file,
            icon: icon,
            contextActions: [deleteAction(for: reminder)],
            onLeftClick: ModifierAwareInteraction(
                base: .execute { [weak self] in
                    self?.toggleReminder(id: reminderId)
                },
                command: .executeKeepOpen { [weak self] in
                    self?.toggleReminder(id: reminderId)
                }
            )
        )
    }
    
    // MARK: - MutableListProvider
    
    func addItem(title: String) {
        guard PermissionManager.shared.hasRemindersAccess else {
            print("[RemindersProvider] Cannot add - no Reminders access")
            showPermissionAlert()
            return
        }
        
        let eventStore = PermissionManager.shared.getEventStore()
        let (listName, cleanTitle) = parseInput(title)
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = cleanTitle
        reminder.calendar = findOrDefaultList(named: listName)
        
        do {
            try eventStore.save(reminder, commit: true)
            reminders.insert(reminder, at: 0)
            print("[RemindersProvider] Added: '\(cleanTitle)' to list '\(reminder.calendar.title)'")
            onItemsChanged?()
        } catch {
            print("[RemindersProvider] Failed to save reminder: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Input Parsing
    
    private func parseInput(_ raw: String) -> (listName: String, title: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        
        // Match <list> prefix — maps to Reminders list
        if let range = trimmed.range(of: #"^<([^>]+)>\s*"#, options: .regularExpression) {
            let listName = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 1)..<trimmed.firstIndex(of: ">")!])
                .trimmingCharacters(in: .whitespaces)
            let title = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            
            if !title.isEmpty {
                return (listName, title)
            }
        }
        
        return ("", trimmed)  // Empty string = use default list
    }
    
    // MARK: - List Lookup
    
    /// Find a Reminders list by name, or return the default list
    private func findOrDefaultList(named name: String) -> EKCalendar {
        let eventStore = PermissionManager.shared.getEventStore()
        
        if !name.isEmpty {
            let calendars = eventStore.calendars(for: .reminder)
            
            // Try case-insensitive match on existing lists
            if let match = calendars.first(where: { $0.title.lowercased() == name.lowercased() }) {
                return match
            }
            
            // List doesn't exist — create it
            let newList = EKCalendar(for: .reminder, eventStore: eventStore)
            newList.title = name.capitalized
            
            // Use the default source (iCloud or local)
            if let defaultCalendar = eventStore.defaultCalendarForNewReminders(),
               let source = defaultCalendar.source {
                newList.source = source
            }
            
            do {
                try eventStore.saveCalendar(newList, commit: true)
                print("[RemindersProvider] Created new Reminders list: '\(newList.title)'")
                return newList
            } catch {
                print("[RemindersProvider] Failed to create list '\(name)': \(error.localizedDescription)")
            }
        }
        
        return eventStore.defaultCalendarForNewReminders() ?? eventStore.calendars(for: .reminder).first!
    }
    
    // MARK: - Actions
    
    private func toggleReminder(id: String) {
        guard let reminder = reminders.first(where: { $0.calendarItemIdentifier == id }) else { return }
        
        let eventStore = PermissionManager.shared.getEventStore()
        reminder.isCompleted.toggle()
        
        do {
            try eventStore.save(reminder, commit: true)
            print("[RemindersProvider] Toggled: '\(reminder.title ?? "")' → \(reminder.isCompleted ? "done" : "undone")")
            onItemsChanged?()
        } catch {
            // Revert on failure
            reminder.isCompleted.toggle()
            print("[RemindersProvider] Failed to toggle: \(error.localizedDescription)")
        }
    }
    
    private func deleteReminder(id: String) {
        guard let index = reminders.firstIndex(where: { $0.calendarItemIdentifier == id }) else { return }
        let reminder = reminders[index]
        let title = reminder.title ?? "Untitled"
        
        let eventStore = PermissionManager.shared.getEventStore()
        
        do {
            try eventStore.remove(reminder, commit: true)
            reminders.remove(at: index)
            print("[RemindersProvider] Deleted: '\(title)' (\(reminders.count) remaining)")
            onItemsChanged?()
        } catch {
            print("[RemindersProvider] Failed to delete: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Context Actions
    
    private func deleteAction(for reminder: EKReminder) -> FunctionNode {
        let reminderId = reminder.calendarItemIdentifier
        return FunctionNode(
            id: "delete-reminder-\(reminderId)",
            name: "Delete",
            type: .action,
            icon: NSImage(named: "context_actions_delete") ?? NSImage(),
            onLeftClick: ModifierAwareInteraction(
                base: .execute { [weak self] in
                    self?.deleteReminder(id: reminderId)
                },
                command: .executeKeepOpen { [weak self] in
                    self?.deleteReminder(id: reminderId)
                }
            ),
            onMiddleClick: ModifierAwareInteraction(base: .doNothing)
        )
    }
    
    // MARK: - Refresh
    
    func refresh() {
        print("[RemindersProvider] Manual refresh requested")
        fetchReminders()
    }
    
    func clearCache() {
        reminders.removeAll()
        print("[RemindersProvider] Cache cleared")
    }
}
