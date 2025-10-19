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
    
    weak var circularUIManager: CircularUIManager?
    
    private var refreshTimer: Timer?
    internal var isCtrlPressed: Bool = false
    
    // MARK: - MRU (Most Recently Used) Tracking
    private var appUsageHistory: [pid_t] = [] // Track PIDs in MRU order
    
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
        
        // Initialize MRU history with currently active app
        initializeMRUHistory()
    }
    
    private func initializeMRUHistory() {
        // Find the currently active app and put it at the top of MRU history
        if let activeApp = NSWorkspace.shared.frontmostApplication,
           activeApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            print("🎯 Initializing MRU with active app: \(activeApp.localizedName ?? "Unknown")")
            recordAppUsage(activeApp)
        }
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
        
        // Only update if there's actually a change (to reduce unnecessary UI updates)
        let oldAppIDs = Set(runningApps.map { $0.processIdentifier })
        let newAppIDs = Set(newApps.map { $0.processIdentifier })
        
        if oldAppIDs != newAppIDs {
            // Only do expensive sorting when the app list actually changes
            let sortedApps = sortAppsByMRU(newApps)
            
            let oldCount = runningApps.count
            let newCount = sortedApps.count
            
            // Log what changed BEFORE updating the state
            let added = newAppIDs.subtracting(oldAppIDs)
            let removed = oldAppIDs.subtracting(newAppIDs)
            
            if !added.isEmpty {
                let addedApps = sortedApps.filter { added.contains($0.processIdentifier) }
                print("   ➕ Added: \(addedApps.map { $0.localizedName ?? "Unknown" }.joined(separator: ", "))")
                
                // Add new apps to the end of usage history
                for app in addedApps {
                    addToUsageHistory(app.processIdentifier)
                }
            }
            
            if !removed.isEmpty {
                let removedApps = runningApps.filter { removed.contains($0.processIdentifier) }
                print("   ➖ Removed: \(removedApps.map { $0.localizedName ?? "Unknown" }.joined(separator: ", "))")
                
                // Remove apps from usage history
                for app in removedApps {
                    removeFromUsageHistory(app.processIdentifier)
                }
            }
            
            // Update the state AFTER logging
            runningApps = sortedApps
            
            print("📊 Applications changed: \(oldCount) → \(newCount)")
            print("🏆 MRU Order: \(runningApps.prefix(5).map { $0.localizedName ?? "Unknown" }.joined(separator: " → "))")
        }
        // If no apps changed, don't do anything - this prevents spam
    }
    
    // MARK: - MRU Management
    
    private func sortAppsByMRU(_ apps: [NSRunningApplication]) -> [NSRunningApplication] {
        print("🔍 Sorting apps by MRU. Usage history: \(appUsageHistory)")
        
        // Create a dictionary for quick lookup
        let appDict = Dictionary(uniqueKeysWithValues: apps.map { ($0.processIdentifier, $0) })
        
        var sortedApps: [NSRunningApplication] = []
        
        // First, add apps in MRU order (if they still exist)
        for pid in appUsageHistory {
            if let app = appDict[pid] {
                sortedApps.append(app)
            }
        }
        
        // Then add any new apps that aren't in our history yet (alphabetically)
        let appsInHistory = Set(sortedApps.map { $0.processIdentifier })
        let newApps = apps.filter { !appsInHistory.contains($0.processIdentifier) }
            .sorted { app1, app2 in
                let name1 = app1.localizedName ?? ""
                let name2 = app2.localizedName ?? ""
                return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
            }
        
        for app in newApps {
//            print("  🆕 Added new app: \(app.localizedName ?? "Unknown") (PID: \(app.processIdentifier))")
        }
        
        sortedApps.append(contentsOf: newApps)
        
        print("🏁 Final sorted order: \(sortedApps.map { $0.localizedName ?? "Unknown" }.joined(separator: " → "))")
        
        return sortedApps
    }
    
    private func addToUsageHistory(_ pid: pid_t) {
//        print("➕ Adding PID \(pid) to usage history")
        // Remove if already exists
        appUsageHistory.removeAll { $0 == pid }
        // Add to front (most recent)
        appUsageHistory.insert(pid, at: 0)
        
        // Keep history reasonable size (max 50 apps)
        if appUsageHistory.count > 50 {
            appUsageHistory = Array(appUsageHistory.prefix(50))
        }
        
//        print("📚 Updated usage history: \(appUsageHistory.prefix(5))")
    }
    
    private func removeFromUsageHistory(_ pid: pid_t) {
        appUsageHistory.removeAll { $0 == pid }
    }
    
    func recordAppUsage(_ app: NSRunningApplication) {
        print("📝 Recording usage for: \(app.localizedName ?? "Unknown") (PID: \(app.processIdentifier))")
        addToUsageHistory(app.processIdentifier)
        
        // Force immediate re-sort without waiting for app list changes
        DispatchQueue.main.async {
            self.forceResortApps()
        }
    }
    
    private func forceResortApps() {
        print("🔄 Force resorting apps by MRU")
        let allApps = NSWorkspace.shared.runningApplications
        
        let newApps = allApps.filter { app in
            app.activationPolicy == .regular &&
            app.bundleIdentifier != Bundle.main.bundleIdentifier
        }
        
        let sortedApps = sortAppsByMRU(newApps)
        runningApps = sortedApps
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
        
        // Record this app usage BEFORE hiding the switcher
        recordAppUsage(app)
        
        // Update app switcher state
        hideAppSwitcher()
        
        // 🆕 ADD THIS LOG:
        if circularUIManager == nil {
            print("❌ circularUIManager is NIL!")
        } else {
            print("✅ Calling hideAndSwitchTo...")
        }
        
        // Hide the circular UI and activate the selected app
        // This uses the special hideAndSwitchTo which doesn't restore previous app
        circularUIManager?.hideAndSwitchTo(app: app)
        
        print("✅ Successfully switched to \(app.localizedName ?? "Unknown")")
        
        // Force a refresh to update the active state indicators and MRU order
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.loadRunningApplications()
        }
    }
}

// MARK: - App Actions (for context menu)

extension AppSwitcherManager {
    
    /// Quit an application
    func quitApp(_ app: NSRunningApplication) {
        print("🚪 Quitting app: \(app.localizedName ?? "Unknown")")
        app.terminate()
    }
    
    /// Hide an application
    func hideApp(_ app: NSRunningApplication) {
        print("👁️ Hiding app: \(app.localizedName ?? "Unknown")")
        app.hide()
    }
    
    /// Unhide an application (show it)
    func unhideApp(_ app: NSRunningApplication) {
        print("👀 Unhiding app: \(app.localizedName ?? "Unknown")")
        app.unhide()
    }
    
    /// Force quit an application (future)
    func forceQuitApp(_ app: NSRunningApplication) {
        print("⚠️ Force quitting app: \(app.localizedName ?? "Unknown")")
        app.forceTerminate()
    }
}

extension AppSwitcherManager: FunctionProvider {
    var providerId: String {
        return "app-switcher"
    }
    
    var providerName: String {
        return "Applications"
    }
    
    var providerIcon: NSImage {
        return NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: nil) ?? NSImage()
    }
    
    func provideFunctions() -> [FunctionNode] {
        // Convert running apps to FunctionNodes with context actions
        let appNodes = runningApps.map { app in
            // Create context actions for each app using StandardContextActions
            let contextActions = [
                StandardContextActions.quitApp(app, manager: self),
                StandardContextActions.bringToFront(app, manager: self),
                StandardContextActions.hideApp(app, manager: self)
            ]
            
            return FunctionNode(
                id: "app-\(app.processIdentifier)",
                name: app.localizedName ?? "Unknown",
                icon: app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!,
                contextActions: contextActions,
                preferredLayout: .partialSlice,
                itemAngleSize: 12,
                // EXPLICIT INTERACTION MODEL:
                onLeftClick: .execute { [weak self] in
                    // Primary action: switch to app and close UI
                    self?.switchToApp(app)
                },
                onRightClick: .expand,  // Right-click: Show context menu
                onMiddleClick: .executeKeepOpen { [weak self] in
                    // Middle-click: Switch to app but keep UI open
                    self?.switchToApp(app)
                },
                onBoundaryCross: .doNothing,  // Don't auto-expand context menus
                onHover: {
                    // Optional: Could preview app windows here
                    print("Hovering over \(app.localizedName ?? "Unknown")")
                },
                onHoverExit: {
                    // Optional: Clean up preview
                    print("Left \(app.localizedName ?? "Unknown")")
                }
            )
        }
        
        // Return as a single category node
        return [
            FunctionNode(
                id: providerId,
                name: providerName,
                icon: providerIcon,
                children: appNodes,
                maxDisplayedChildren: 12,  // Limit to 12 apps in the pie slice
                preferredLayout: .fullCircle,  // Use full circle for many apps
                // EXPLICIT INTERACTION MODEL:
                onLeftClick: .expand,           // Click to expand applications
                onRightClick: .execute { [weak self] in
                    // Right-click: Open Applications folder
                    print("📂 Opening Applications folder")
                    self?.openApplicationsFolder()
                },
                onMiddleClick: .expand,         // Middle-click: Expand
                onBoundaryCross: .expand,       // Auto-expand on boundary cross
                onHover: {
                    print("📱 Hovering over Applications category")
                },
                onHoverExit: {
                    print("📱 Left Applications category")
                }
            )
        ]
    }
    
    func refresh() {
        // Force reload of running applications
        loadRunningApplications()
    }
    
    // Helper method to open Applications folder
    private func openApplicationsFolder() {
        let applicationsURL = URL(fileURLWithPath: "/Applications")
        NSWorkspace.shared.open(applicationsURL)
    }
}
