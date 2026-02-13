//
//  CalendarProvider.swift
//  Jason
//
//  Provides today's calendar events as FunctionNodes
//

import Foundation
import AppKit
import EventKit

class CalendarProvider: ObservableObject, FunctionProvider {
    
    // MARK: - Provider Info
    
    var providerId: String { "calendar" }
    var providerName: String { "Calendar" }
    var providerIcon: NSImage {
        return NSWorkspace.shared.icon(forFile: "/System/Applications/Calendar.app")
    }
    
    // MARK: - EventKit
    
    private let eventStore = EKEventStore()
    private var authorizationStatus: EKAuthorizationStatus {
        return EKEventStore.authorizationStatus(for: .event)
    }
    
    // MARK: - Cache
    
    private var cachedNodes: [FunctionNode]?
    private var lastFetchDate: Date?
    
    // MARK: - Initialization
    
    init() {
        // Listen for external calendar changes (user edits in Calendar.app, sync, etc.)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(calendarStoreChanged),
            name: .EKEventStoreChanged,
            object: eventStore
        )
        
        // Schedule midnight refresh so "today" rolls over
        scheduleMidnightRefresh()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - FunctionProvider Protocol
    
    func provideFunctions() -> [FunctionNode] {
        print("📅 [CalendarProvider] provideFunctions() called")
        
        switch authorizationStatus {
        case .authorized, .fullAccess:
            return buildEventNodes()
            
        case .notDetermined:
            // Return a prompt node — actual request happens on interaction
            return [createRequestAccessNode()]
            
        case .denied, .restricted:
            return [createAccessDeniedNode()]
            
        @unknown default:
            return [createAccessDeniedNode()]
        }
    }
    
    func refresh() {
        print("🔄 [CalendarProvider] refresh() called")
        cachedNodes = nil
        lastFetchDate = nil
    }
    
    func clearCache() {
        cachedNodes = nil
        lastFetchDate = nil
        print("🗑️ [CalendarProvider] Cache cleared")
    }
    
    // MARK: - Permission Handling
    
    /// Request calendar access. Call this once (e.g., from the "Grant Access" node action).
    func requestAccess(completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { granted, error in
                if let error = error {
                    print("❌ [CalendarProvider] Access request error: \(error.localizedDescription)")
                }
                print("📅 [CalendarProvider] Access granted: \(granted)")
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        } else {
            // Fallback for macOS 13 and earlier
            eventStore.requestAccess(to: .event) { granted, error in
                if let error = error {
                    print("❌ [CalendarProvider] Access request error: \(error.localizedDescription)")
                }
                print("📅 [CalendarProvider] Access granted: \(granted)")
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        }
    }
    
    // MARK: - Event Fetching
    
    private func buildEventNodes() -> [FunctionNode] {
        // Use cache if we already fetched today
        if let cached = cachedNodes,
           let fetchDate = lastFetchDate,
           Calendar.current.isDateInToday(fetchDate) {
            print("⚡ [CalendarProvider] Using cached nodes (\(cached.count) events)")
            return cached
        }
        
        let events = fetchTodaysEvents()
        
        if events.isEmpty {
            let nodes = [createNoEventsNode()]
            cachedNodes = nodes
            lastFetchDate = Date()
            return nodes
        }
        
        // Separate all-day events from timed events
        let allDayEvents = events.filter { $0.isAllDay }
        let timedEvents = events.filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
        
        var nodes: [FunctionNode] = []
        
        // All-day events first
        for event in allDayEvents {
            nodes.append(createEventNode(for: event))
        }
        
        // Then timed events in chronological order
        for event in timedEvents {
            nodes.append(createEventNode(for: event))
        }
        
        print("📅 [CalendarProvider] Built \(nodes.count) event nodes (\(allDayEvents.count) all-day, \(timedEvents.count) timed)")
        
        // Wrap in category node (applyDisplayMode will unwrap if displayMode == .direct)
        let categoryNode = FunctionNode(
            id: "calendar-today-section",
            name: "Today",
            type: .category,
            icon: providerIcon,
            children: nodes,
            childDisplayMode: .panel,
            providerId: providerId,
            onLeftClick: ModifierAwareInteraction(base: .doNothing),
            onRightClick: ModifierAwareInteraction(base: .doNothing),
            onBoundaryCross: ModifierAwareInteraction(base: .expand)
        )
        
        let result = [categoryNode]
        cachedNodes = result
        lastFetchDate = Date()
        return result
    }
    
    private func fetchTodaysEvents() -> [EKEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            print("❌ [CalendarProvider] Failed to calculate end of day")
            return []
        }
        
        // Only include actual user calendars — skip subscriptions (holidays) and birthdays
        let calendars = eventStore.calendars(for: .event).filter { calendar in
            calendar.type != .subscription && calendar.type != .birthday
        }
        
        let predicate = eventStore.predicateForEvents(
            withStart: startOfDay,
            end: endOfDay,
            calendars: calendars
        )
        
        let events = eventStore.events(matching: predicate)
        print("📅 [CalendarProvider] Fetched \(events.count) events for today")
        return events
    }
    
    // MARK: - Node Creation
    
    private func createEventNode(for event: EKEvent) -> FunctionNode {
        let timeString = formatEventTime(event)
        let displayName = event.isAllDay ? "🕐 \(event.title ?? "Untitled")" : "\(timeString)  \(event.title ?? "Untitled")"
        
        // Create a colored calendar dot icon
        let icon = createCalendarEventIcon(color: NSColor(cgColor: event.calendar.cgColor) ?? .systemBlue)
        
        let eventIdentifier = event.eventIdentifier ?? UUID().uuidString
        
        return FunctionNode(
            id: "calendar-event-\(eventIdentifier)",
            name: displayName,
            type: .action,
            icon: icon,
            preferredLayout: .partialSlice,
            showLabel: true,
            slicePositioning: .center,
            providerId: providerId,
            onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                self?.openEventInCalendar(event)
            }),
            onRightClick: ModifierAwareInteraction(base: .doNothing),
            onBoundaryCross: ModifierAwareInteraction(base: .execute { [weak self] in
                self?.openEventInCalendar(event)
            })
        )
    }
    
    private func createNoEventsNode() -> FunctionNode {
        return FunctionNode(
            id: "calendar-no-events",
            name: "No events today",
            type: .action,
            icon: providerIcon,
            showLabel: true,
            providerId: providerId,
            onLeftClick: ModifierAwareInteraction(base: .execute {
                NSWorkspace.shared.open(URL(string: "x-apple-calevent://")!)
            }),
            onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
        )
    }
    
    private func createRequestAccessNode() -> FunctionNode {
        return FunctionNode(
            id: "calendar-request-access",
            name: "Grant Calendar Access",
            type: .action,
            icon: providerIcon,
            showLabel: true,
            providerId: providerId,
            onLeftClick: ModifierAwareInteraction(base: .executeKeepOpen { [weak self] in
                self?.requestAccess { granted in
                    if granted {
                        print("✅ [CalendarProvider] Access granted — posting refresh")
                        NotificationCenter.default.post(name: .providerContentUpdated, object: nil)
                    }
                }
            }),
            onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
        )
    }
    
    private func createAccessDeniedNode() -> FunctionNode {
        return FunctionNode(
            id: "calendar-access-denied",
            name: "Calendar Access Denied — Open Settings",
            type: .action,
            icon: providerIcon,
            showLabel: true,
            providerId: providerId,
            onLeftClick: ModifierAwareInteraction(base: .execute {
                // Open System Settings > Privacy > Calendars
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                    NSWorkspace.shared.open(url)
                }
            }),
            onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
        )
    }
    
    // MARK: - Event Interaction
    
    private func openEventInCalendar(_ event: EKEvent) {
        // Open Calendar.app at the event's date
        // calshow: URL scheme opens Calendar at a specific timestamp
        let timestamp = event.startDate.timeIntervalSinceReferenceDate
        if let url = URL(string: "x-apple-calevent://calshow/\(timestamp)") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Icon Creation
    
    private func createCalendarEventIcon(color: NSColor, size: CGFloat = 64) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        let cornerRadius: CGFloat = size * 0.15
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        
        // Background — calendar color with slight transparency
        color.withAlphaComponent(0.85).setFill()
        path.fill()
        
        // Draw a simple calendar glyph (top bar + lines)
        let lineColor = NSColor.white.withAlphaComponent(0.9)
        lineColor.setFill()
        
        // Top bar (the calendar header strip)
        let topBar = NSRect(x: 0, y: size * 0.75, width: size, height: size * 0.25)
        let topPath = NSBezierPath(roundedRect: topBar, xRadius: cornerRadius, yRadius: cornerRadius)
        // Clip bottom corners of top bar
        let clipRect = NSRect(x: 0, y: size * 0.75, width: size, height: size * 0.15)
        topPath.append(NSBezierPath(rect: clipRect))
        NSColor.white.withAlphaComponent(0.3).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: size * 0.78, width: size, height: size * 0.22)).fill()
        
        // Two horizontal lines suggesting text/events
        NSColor.white.withAlphaComponent(0.5).setFill()
        NSBezierPath(rect: NSRect(x: size * 0.2, y: size * 0.50, width: size * 0.6, height: size * 0.06)).fill()
        NSBezierPath(rect: NSRect(x: size * 0.2, y: size * 0.32, width: size * 0.45, height: size * 0.06)).fill()
        
        image.unlockFocus()
        return image
    }
    
    // MARK: - Time Formatting
    
    private func formatEventTime(_ event: EKEvent) -> String {
        if event.isAllDay {
            return "All Day"
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: event.startDate)
    }
    
    // MARK: - Change Notifications
    
    @objc private func calendarStoreChanged() {
        print("📅 [CalendarProvider] Calendar store changed — invalidating cache")
        cachedNodes = nil
        lastFetchDate = nil
        
        // Notify the system that this provider's content has changed
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .providerContentUpdated, object: nil)
        }
    }
    
    // MARK: - Midnight Refresh
    
    private func scheduleMidnightRefresh() {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()),
              let midnight = calendar.date(bySettingHour: 0, minute: 0, second: 5, of: tomorrow) else {
            return
        }
        
        let timeInterval = midnight.timeIntervalSinceNow
        print("📅 [CalendarProvider] Midnight refresh scheduled in \(String(format: "%.0f", timeInterval))s")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + timeInterval) { [weak self] in
            guard let self = self else { return }
            print("🌅 [CalendarProvider] Midnight rollover — refreshing for new day")
            self.refresh()
            NotificationCenter.default.post(name: .providerContentUpdated, object: nil)
            
            // Schedule next midnight
            self.scheduleMidnightRefresh()
        }
    }
}
