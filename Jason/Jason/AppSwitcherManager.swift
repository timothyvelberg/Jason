//
//  AppSwitcherManager.swift
//  Jason
//
//  Created by Timothy Velberg on 31/07/2025.
//

import Foundation
import AppKit
import SwiftUI

class AppSwitcherManager: ObservableObject {
    @Published var runningApps: [NSRunningApplication] = []
    @Published var isVisible: Bool = false
    @Published var selectedAppIndex: Int = 0
    @Published var hasAccessibilityPermission: Bool = false
    
    private var refreshTimer: Timer?
    internal var isCtrlPressed: Bool = false
    
    init() {
        checkAccessibilityPermission()
    }
    
    // MARK: - Permission Management
    
    func checkAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        hasAccessibilityPermission = trusted
        
        print("🔐 Accessibility permission check: \(trusted ? "✅ GRANTED" : "❌ DENIED")")
        
        if trusted {
            setupServices()
        }
    }
    
    func openAccessibilityPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
    
    // MARK: - Service Setup
    
    func setupServices() {
        print("🎹 Setting up services")
        setupGlobalHotkeys()
        startAutoRefresh()
        loadRunningApplications()
    }
    
    func setupGlobalHotkeys() {
        print("🎹 Setting up global hotkeys")
        
        // Listen for global key events (requires Accessibility permission)
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            self.handleGlobalKeyEvent(event)
        }
        
        // Also listen for local events (when our app has focus)
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            self.handleLocalKeyEvent(event)
            return event
        }
        
        print("✅ Global hotkey monitoring started")
    }
    
    // MARK: - App Management
    
    func startAutoRefresh() {
        // Stop any existing timer
        stopAutoRefresh()
        
        // Start a timer that checks for changes every 1 second
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.loadRunningApplications()
        }
        
        print("✅ Auto-refresh timer started (1 second interval)")
    }
    
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        print("🛑 Auto-refresh timer stopped")
    }
    
    func loadRunningApplications() {
        let allApps = NSWorkspace.shared.runningApplications
        
        // Filter to only show regular applications (not background processes) and exclude our own app
        let newApps = allApps.filter { app in
            app.activationPolicy == .regular &&
            app.bundleIdentifier != Bundle.main.bundleIdentifier  // Exclude our own app (Jason)
        }
        
        // Sort by name for better organization
        let sortedApps = newApps.sorted { app1, app2 in
            let name1 = app1.localizedName ?? ""
            let name2 = app2.localizedName ?? ""
            return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
        }
        
        // Only update if there's actually a change (to reduce unnecessary UI updates)
        let oldAppIDs = Set(runningApps.map { $0.processIdentifier })
        let newAppIDs = Set(sortedApps.map { $0.processIdentifier })
        
        if oldAppIDs != newAppIDs {
            let oldCount = runningApps.count
            let newCount = sortedApps.count
            
            // Log what changed BEFORE updating the state
            let added = newAppIDs.subtracting(oldAppIDs)
            let removed = oldAppIDs.subtracting(newAppIDs)
            
            if !added.isEmpty {
                let addedApps = sortedApps.filter { added.contains($0.processIdentifier) }
                print("   ➕ Added: \(addedApps.map { $0.localizedName ?? "Unknown" }.joined(separator: ", "))")
            }
            
            if !removed.isEmpty {
                let removedApps = runningApps.filter { removed.contains($0.processIdentifier) }
                print("   ➖ Removed: \(removedApps.map { $0.localizedName ?? "Unknown" }.joined(separator: ", "))")
            }
            
            // Update the state AFTER logging
            runningApps = sortedApps
            
            print("📊 Applications changed: \(oldCount) → \(newCount)")
        }
    }
    
    // MARK: - App Switcher Control
    
    func showAppSwitcher() {
        print("👁️  Showing app switcher")
        isVisible = true
        selectedAppIndex = 0
        isCtrlPressed = true
        loadRunningApplications()
        
        // Bring Jason window to the front
        bringJasonToFront()
    }
    
    func hideAppSwitcher() {
        print("🙈 Hiding app switcher")
        isVisible = false
        selectedAppIndex = 0
        isCtrlPressed = false
    }
    
    func bringJasonToFront() {
        print("🔝 Bringing Jason to front")
        
        // Activate our own application
        NSApp.activate(ignoringOtherApps: true)
        
        // Bring all our windows to the front
        for window in NSApp.windows {
            window.orderFrontRegardless()
        }
    }
    
    // MARK: - Navigation
    
    func navigateNext() {
        if !runningApps.isEmpty {
            selectedAppIndex = (selectedAppIndex + 1) % runningApps.count
            print("➡️  Selected: \(runningApps[selectedAppIndex].localizedName ?? "Unknown") (\(selectedAppIndex + 1)/\(runningApps.count))")
        }
    }
    
    func navigatePrevious() {
        if !runningApps.isEmpty {
            selectedAppIndex = selectedAppIndex > 0 ? selectedAppIndex - 1 : runningApps.count - 1
            print("⬅️  Selected: \(runningApps[selectedAppIndex].localizedName ?? "Unknown") (\(selectedAppIndex + 1)/\(runningApps.count))")
        }
    }
    
    func selectCurrentApp() {
        if !runningApps.isEmpty && selectedAppIndex < runningApps.count {
            let selectedApp = runningApps[selectedAppIndex]
            switchToApp(selectedApp)
        }
    }
    
    func switchToApp(_ app: NSRunningApplication) {
        print("🔄 Switching to app: \(app.localizedName ?? "Unknown")")
        
        // First hide our app switcher
        hideAppSwitcher()
        
        // Then activate the selected app and bring it to front
        app.activate()
        
        // Give the system a moment to process the activation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Try to bring the app's windows to front
            if let appWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] {
                let targetPID = app.processIdentifier
                for windowInfo in appWindows {
                    if let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
                       ownerPID == targetPID {
                        // Found a window belonging to the target app
                        print("🪟 Found window for \(app.localizedName ?? "Unknown")")
                        break
                    }
                }
            }
        }
        
        print("✅ Successfully switched to \(app.localizedName ?? "Unknown")")
        
        // Force a refresh to update the active state indicators
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.loadRunningApplications()
        }
    }
}
