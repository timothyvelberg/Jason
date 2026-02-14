import Foundation
import AppKit
import SwiftUI
import EventKit

class TodoListProvider: FunctionProvider, MutableListProvider {

    var providerId: String { "todo-list" }
    var providerName: String { "Todo List" }
    var providerIcon: NSImage { NSImage(systemSymbolName: "checklist", accessibilityDescription: "Todo List") ?? NSImage() }
    var defaultTypingMode: TypingMode { .input }
    var panelConfig: PanelConfig { PanelConfig(lineLimit: 3, panelWidth: 320, maxVisibleItems: 24) }
    var onItemsChanged: (() -> Void)?
    
    // MARK: - EventKit
    
    private let eventStore = EKEventStore()
    private var reminders: [EKReminder] = []
    private var hasAccess = false
    
    // MARK: - Init
    
    init() {
        requestAccess()
        
        // Listen for external changes (Reminders app, other devices via iCloud)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeChanged),
            name: .EKEventStoreChanged,
            object: eventStore
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Permissions
    
    private func requestAccess() {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToReminders { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.handleAccessResult(granted: granted, error: error)
                }
            }
        } else {
            eventStore.requestAccess(to: .reminder) { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.handleAccessResult(granted: granted, error: error)
                }
            }
        }
    }
    
    private func handleAccessResult(granted: Bool, error: Error?) {
        if let error = error {
            print("❌ [TodoListProvider] Reminders access error: \(error.localizedDescription)")
        }
        hasAccess = granted
        if granted {
            print("✅ [TodoListProvider] Reminders access granted")
            fetchReminders()
        } else {
            print("⚠️ [TodoListProvider] Reminders access denied")
        }
    }
    
    // MARK: - Fetching
    
    private func fetchReminders() {
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil
        )
        
        eventStore.fetchReminders(matching: predicate) { [weak self] fetched in
            guard let self = self else { return }
            
            // Also fetch recently completed (last 24h) so toggles feel responsive
            let completedPredicate = self.eventStore.predicateForCompletedReminders(
                withCompletionDateStarting: Calendar.current.date(byAdding: .day, value: -1, to: Date()),
                ending: Date(),
                calendars: nil
            )
            
            self.eventStore.fetchReminders(matching: completedPredicate) { [weak self] completedFetched in
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
                    print("📋 [TodoListProvider] Loaded \(incomplete.count) incomplete + \(completed.count) recently completed reminders")
                    self.onItemsChanged?()
                }
            }
        }
    }
    
    @objc private func storeChanged() {
        print("🔄 [TodoListProvider] Reminders store changed - refreshing")
        fetchReminders()
    }
    
    // MARK: - FunctionProvider
    
    func provideFunctions() -> [FunctionNode] {
        let items = buildTodoNodes()
        return [
            FunctionNode(
                id: "todo-list",
                name: "Todo List",
                type: .category,
                icon: NSImage(named: "parent-todo") ?? NSImage(),
                children: items,
                childDisplayMode: .panel,
                providerId: "todo-list",
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
        guard hasAccess else {
            return [
                FunctionNode(
                    id: "todo-no-access",
                    name: "Grant Reminders access in System Settings",
                    type: .action,
                    icon: NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil) ?? NSImage(),
                    showLabel: true,
                    providerId: providerId,
                    onLeftClick: ModifierAwareInteraction(base: .execute {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!)
                    })
                )
            ]
        }
        
        if reminders.isEmpty {
            return [
                FunctionNode(
                    id: "todo-empty",
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
            if index > 0 {
                nodes.append(spacerNode(after: "before-\(listName)"))
            }
            
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
            nodes.append(spacerNode(after: "after-\(listName)"))
            
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
        if !listOrder.isEmpty {
            nodes.append(spacerNode(after: "end"))
        }
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
        guard hasAccess else {
            print("⚠️ [TodoListProvider] Cannot add - no Reminders access")
            return
        }
        
        let (listName, cleanTitle) = parseInput(title)
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = cleanTitle
        reminder.calendar = findOrDefaultList(named: listName)
        
        do {
            try eventStore.save(reminder, commit: true)
            reminders.insert(reminder, at: 0)
            print("✅ [TodoListProvider] Added: '\(cleanTitle)' to list '\(reminder.calendar.title)'")
            onItemsChanged?()
        } catch {
            print("❌ [TodoListProvider] Failed to save reminder: \(error.localizedDescription)")
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
                print("✅ [TodoListProvider] Created new Reminders list: '\(newList.title)'")
                return newList
            } catch {
                print("❌ [TodoListProvider] Failed to create list '\(name)': \(error.localizedDescription)")
            }
        }
        
        return eventStore.defaultCalendarForNewReminders() ?? eventStore.calendars(for: .reminder).first!
    }
    
    // MARK: - Actions
    
    private func toggleReminder(id: String) {
        guard let reminder = reminders.first(where: { $0.calendarItemIdentifier == id }) else { return }
        
        reminder.isCompleted.toggle()
        
        do {
            try eventStore.save(reminder, commit: true)
            print("✅ [TodoListProvider] Toggled: '\(reminder.title ?? "")' → \(reminder.isCompleted ? "done" : "undone")")
            onItemsChanged?()
        } catch {
            // Revert on failure
            reminder.isCompleted.toggle()
            print("❌ [TodoListProvider] Failed to toggle: \(error.localizedDescription)")
        }
    }
    
    private func deleteReminder(id: String) {
        guard let index = reminders.firstIndex(where: { $0.calendarItemIdentifier == id }) else { return }
        let reminder = reminders[index]
        let title = reminder.title ?? "Untitled"
        
        do {
            try eventStore.remove(reminder, commit: true)
            reminders.remove(at: index)
            print("🗑️ [TodoListProvider] Deleted: '\(title)' (\(reminders.count) remaining)")
            onItemsChanged?()
        } catch {
            print("❌ [TodoListProvider] Failed to delete: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Context Actions
    
    private func deleteAction(for reminder: EKReminder) -> FunctionNode {
        let reminderId = reminder.calendarItemIdentifier
        return FunctionNode(
            id: "delete-todo-\(reminderId)",
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
        print("🔄 [TodoListProvider] Manual refresh requested")
        fetchReminders()
    }
    
    func clearCache() {
        reminders.removeAll()
        print("🗑️ [TodoListProvider] Cache cleared")
    }
}
