//
//  PermissionManager.swift
//  Jason
//
//  Created by Timothy Velberg on 16/01/2026.
//  Handles permission requests for protected resources
//

import Foundation
import AppKit
import EventKit

// MARK: - Permission Status Enum

enum PermissionStatus {
    case notDetermined
    case denied
    case restricted
    case granted
}

// MARK: - Permission Manager

class PermissionManager {
    
    static let shared = PermissionManager()
    
    // MARK: - EventKit
    
    private let eventStore = EKEventStore()
    
    private init() {}
    
    // MARK: - Calendar Permission Status
    
    var hasCalendarAccess: Bool {
        if #available(macOS 14.0, *) {
            let status = EKEventStore.authorizationStatus(for: .event)
            return status == .fullAccess || status == .writeOnly
        } else {
            let status = EKEventStore.authorizationStatus(for: .event)
            return status == .authorized
        }
    }
    
    func calendarStatus() -> PermissionStatus {
        if #available(macOS 14.0, *) {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .notDetermined:
                return .notDetermined
            case .restricted:
                return .restricted
            case .denied:
                return .denied
            case .fullAccess, .writeOnly:
                return .granted
            case .authorized:
                return .granted
            @unknown default:
                return .denied
            }
        } else {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .notDetermined:
                return .notDetermined
            case .restricted:
                return .restricted
            case .denied:
                return .denied
            case .authorized:
                return .granted
            case .fullAccess, .writeOnly:
                return .granted
            @unknown default:
                return .denied
            }
        }
    }

    func remindersStatus() -> PermissionStatus {
        if #available(macOS 14.0, *) {
            switch EKEventStore.authorizationStatus(for: .reminder) {
            case .notDetermined:
                return .notDetermined
            case .restricted:
                return .restricted
            case .denied:
                return .denied
            case .fullAccess, .writeOnly:
                return .granted
            case .authorized:
                return .granted
            @unknown default:
                return .denied
            }
        } else {
            switch EKEventStore.authorizationStatus(for: .reminder) {
            case .notDetermined:
                return .notDetermined
            case .restricted:
                return .restricted
            case .denied:
                return .denied
            case .authorized:
                return .granted
            case .fullAccess, .writeOnly:
                return .granted
            @unknown default:
                return .denied
            }
        }
    }
    
    var hasRemindersAccess: Bool {
        if #available(macOS 14.0, *) {
            let status = EKEventStore.authorizationStatus(for: .reminder)
            return status == .fullAccess || status == .writeOnly
        } else {
            let status = EKEventStore.authorizationStatus(for: .reminder)
            return status == .authorized
        }
    }
    
    // MARK: - Request Calendar Access
    
    func requestCalendarAccess(completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { [weak self] granted, error in
                if let error = error {
                    print("❌ [PermissionManager] Calendar access error: \(error.localizedDescription)")
                }
                print("📅 [PermissionManager] Calendar access: \(granted)")
                DispatchQueue.main.async {
                    completion(granted)
                    if granted {
                        self?.notifyPermissionChanged(type: .calendar)
                    }
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { [weak self] granted, error in
                if let error = error {
                    print("❌ [PermissionManager] Calendar access error: \(error.localizedDescription)")
                }
                print("📅 [PermissionManager] Calendar access: \(granted)")
                DispatchQueue.main.async {
                    completion(granted)
                    if granted {
                        self?.notifyPermissionChanged(type: .calendar)
                    }
                }
            }
        }
    }
    
    // MARK: - Request Reminders Access
    
    func requestRemindersAccess(completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToReminders { [weak self] granted, error in
                if let error = error {
                    print("❌ [PermissionManager] Reminders access error: \(error.localizedDescription)")
                }
                print("✅ [PermissionManager] Reminders access: \(granted)")
                DispatchQueue.main.async {
                    completion(granted)
                    if granted {
                        self?.notifyPermissionChanged(type: .reminders)
                    }
                }
            }
        } else {
            eventStore.requestAccess(to: .reminder) { [weak self] granted, error in
                if let error = error {
                    print("❌ [PermissionManager] Reminders access error: \(error.localizedDescription)")
                }
                print("✅ [PermissionManager] Reminders access: \(granted)")
                DispatchQueue.main.async {
                    completion(granted)
                    if granted {
                        self?.notifyPermissionChanged(type: .reminders)
                    }
                }
            }
        }
    }
    
    // MARK: - Shared EventStore Access
    
    func getEventStore() -> EKEventStore {
        return eventStore
    }
    
    // MARK: - Notifications
    
    // MARK: - Unified Permission Alerts

    enum PermissionType {
        case calendar
        case reminders
        case accessibility
    }

    func showPermissionAlert(for type: PermissionType) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            
            switch type {
            case .calendar:
                alert.messageText = "Calendar Access Required"
                alert.informativeText = "Jason needs access to your Calendar. Please configure permissions in Settings."
            case .reminders:
                alert.messageText = "Reminders Access Required"
                alert.informativeText = "Jason needs access to your Reminders. Please configure permissions in Settings."
            case .accessibility:
                alert.messageText = "Accessibility Access Required"
                alert.informativeText = "Jason needs Accessibility permissions for advanced features like app switching and gesture detection. Please enable in System Settings > Privacy & Security > Accessibility."
            }
            
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
            
            if alert.runModal() == .alertFirstButtonReturn {
                switch type {
                case .calendar, .reminders:
                    // Open Jason Settings window
                    NotificationCenter.default.post(name: .openSettingsWindow, object: nil)
                case .accessibility:
                    // Open System Settings
                    self.openAccessibilityPreferences()
                }
            }
        }
    }
    
    private func notifyPermissionChanged(type: PermissionType) {
        let name: Notification.Name = type == .calendar ? .calendarPermissionChanged : .remindersPermissionChanged
        NotificationCenter.default.post(name: name, object: nil)
    }
    
    // MARK: - File Permissions (Existing)
    
    /// Call this early at app launch, before any UI
    func requestAccessToFavoriteFolders() {
        print("🔐 [Permissions] Checking folder access...")
        
        // Get favorite folders from database
        let favoriteFolders = DatabaseManager.shared.getFavoriteFolders()
        let folderPaths = favoriteFolders.map { $0.folder.path }
        
        // Also add common system folders that might be used
        var allPaths = folderPaths
        
        if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            allPaths.append(desktop.path)
        }
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            allPaths.append(downloads.path)
        }
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            allPaths.append(documents.path)
        }
        
        // Remove duplicates
        let uniquePaths = Array(Set(allPaths))
        
        print("🔐 [Permissions] Requesting access to \(uniquePaths.count) folders")
        
        for path in uniquePaths {
            requestAccess(to: path)
        }
        
        print("🔐 [Permissions] Folder access check complete")
    }
    
    private func requestAccess(to path: String) {
        let url = URL(fileURLWithPath: path)
        
        do {
            // This triggers the permission dialog if needed
            _ = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            print("   ✅ Access granted: \(url.lastPathComponent)")
        } catch {
            print("   ❌ Access denied or error: \(url.lastPathComponent) - \(error.localizedDescription)")
        }
    }

    // MARK: - Accessibility Permission Status

    var hasAccessibilityAccess: Bool {
        return AXIsProcessTrusted()
    }

    func accessibilityStatus() -> PermissionStatus {
        return AXIsProcessTrusted() ? .granted : .denied
    }

    // MARK: - Request Accessibility Access

    func requestAccessibilityAccess() {
        // Accessibility can't be requested programmatically like Calendar/Reminders
        // We need to open System Settings
        openAccessibilityPreferences()
    }

    func openAccessibilityPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
// MARK: - Notification Names

extension Notification.Name {
    static let calendarPermissionChanged = Notification.Name("calendarPermissionChanged")
    static let remindersPermissionChanged = Notification.Name("remindersPermissionChanged")
}
