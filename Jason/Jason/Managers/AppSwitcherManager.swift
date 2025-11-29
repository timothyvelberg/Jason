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
    // MARK: - Singleton
    
    /// Shared singleton instance
    static let shared = AppSwitcherManager()
    
    // MARK: - Published Properties
    
    @Published var runningApps: [NSRunningApplication] = []
    @Published var isVisible: Bool = false
    @Published var selectedAppIndex: Int = 0
    @Published var hasAccessibilityPermission: Bool = false
    
    // MARK: - Instance Management
    
    /// Reference to the currently active CircularUIManager instance
    /// This gets set when a CircularUIManager shows, and unset when it hides
    weak var activeCircularUIManager: CircularUIManager?
    
    private var refreshTimer: Timer?
    internal var isCtrlPressed: Bool = false
    
    // Prevent race conditions during updates
    private var isUpdating: Bool = false
    
    // MARK: - MRU (Most Recently Used) Tracking
    private var appUsageHistory: [pid_t] = [] // Track PIDs in MRU order
    
    private init() {
        print("🔧 [AppSwitcherManager] Initializing SHARED instance")
        checkAccessibilityPermission()
        setupServices()
        
        // 🆕 ADDED: Listen to NSWorkspace notifications for instant app change detection
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
        
        print("✅ [AppSwitcherManager] Monitoring NSWorkspace for app changes")
        
        // 🆕 ADDED: Start polling as backup (detects changes if notifications miss anything)
        startAutoRefresh()
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
        loadRunningApplications()
        
        // Only initialize MRU if we have permission
        if hasAccessibilityPermission {
            initializeMRUHistory()
        } else {
            print("MRU tracking disabled (no accessibility permission)")
        }
    }
    
    private func initializeMRUHistory() {
        // Find the currently active app and put it at the top of MRU history
        if let activeApp = NSWorkspace.shared.frontmostApplication,
           activeApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            print("🎯 Initializing MRU with active app: \(activeApp.localizedName ?? "Unknown")")
            recordAppUsage(activeApp)
        }
    }
    
    // MARK: - App Management
    
    public func startAutoRefresh() {
        // Stop any existing timer
        stopAutoRefresh()
        
        // Start a timer that checks for changes every 5 seconds (backup to NSWorkspace notifications)
        // Note: NSWorkspace provides instant detection, timer just catches edge cases
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            // Logging controlled by UI visibility (see loadRunningApplications)
            self?.loadRunningApplications()
        }
        
        print("✅ Auto-refresh timer started (5 second backup polling)")
    }
    
    public func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        print("🛑 Auto-refresh timer stopped")
    }
    
    func loadRunningApplications() {
        // Prevent re-entrant updates (race condition protection)
        guard !isUpdating else {
            print("⏭️ [AppSwitcher] Update already in progress - skipping")
            return
        }
        
        isUpdating = true
        defer { isUpdating = false }
        
        let allApps = NSWorkspace.shared.runningApplications
        
        // Filter to only show regular applications (not background processes) and exclude our own app
        let filteredApps = allApps.filter { app in
            app.activationPolicy == .regular &&
            app.bundleIdentifier != Bundle.main.bundleIdentifier
        }
        
        // Quick deduplication by bundle ID (without sorting - cheap!)
        var seenBundleIds = Set<String>()
        var deduplicatedApps: [NSRunningApplication] = []
        
        for app in filteredApps where app.processIdentifier > 0 {
            guard let bundleId = app.bundleIdentifier else { continue }
            if !seenBundleIds.contains(bundleId) {
                seenBundleIds.insert(bundleId)
                deduplicatedApps.append(app)
            }
        }
        
        // Compare bundle IDs (cheap comparison)
        let oldAppBundleIDs = Set(runningApps.compactMap { $0.bundleIdentifier })
        let newAppBundleIDs = seenBundleIds  // Already a Set!
        
        // Only log when UI is visible (when user is actively using it)
        let isUIVisible = activeCircularUIManager?.isVisible ?? false
        
        if isUIVisible {
            // Verbose logging when UI is open - user can see changes happening
            print("[AppSwitcher] Checking apps: current=\(runningApps.count), new=\(deduplicatedApps.count)")
        }
        
        // Only sort and update if there's an actual change
        if oldAppBundleIDs != newAppBundleIDs {
            print("[AppSwitcher] CHANGE DETECTED!")
            
            // NOW do the expensive MRU sorting
            let sortedApps = sortAppsByMRU(deduplicatedApps)
            
            let oldCount = runningApps.count
            let newCount = sortedApps.count
            
            // Log what changed BEFORE updating the state (using bundle IDs)
            let added = newAppBundleIDs.subtracting(oldAppBundleIDs)
            let removed = oldAppBundleIDs.subtracting(newAppBundleIDs)
            
            if !added.isEmpty {
                let addedApps = sortedApps.filter { app in
                    guard let bundleId = app.bundleIdentifier else { return false }
                    return added.contains(bundleId)
                }
                print("   Added: \(addedApps.map { $0.localizedName ?? "Unknown" }.joined(separator: ", "))")
                
                // Add new apps to the end of usage history
                for app in addedApps {
                    addToUsageHistory(app.processIdentifier)
                }
            }
            
            if !removed.isEmpty {
                let removedApps = runningApps.filter { app in
                    guard let bundleId = app.bundleIdentifier else { return false }
                    return removed.contains(bundleId)
                }
                print("   Removed: \(removedApps.map { $0.localizedName ?? "Unknown" }.joined(separator: ", "))")
                
                // Remove apps from usage history
                for app in removedApps {
                    removeFromUsageHistory(app.processIdentifier)
                }
            }
            
            // Update the state AFTER logging
            runningApps = sortedApps
            
            // Post notifications for both AppSwitcher and CombinedApps providers
            DispatchQueue.main.async {
                NotificationCenter.default.postProviderUpdate(providerId: "app-switcher")
                print("📢 Posted update notification for app-switcher")
                
                NotificationCenter.default.postProviderUpdate(providerId: "combined-apps")
                print("📢 Posted update notification for combined-apps")
            }
            print("Applications changed: \(oldCount) → \(newCount)")
            print("MRU Order: \(runningApps.prefix(5).map { $0.localizedName ?? "Unknown" }.joined(separator: " → "))")
        }
    }
    
    // MARK: - NSWorkspace Notification Handlers
    
    @objc private func handleAppLaunched(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.activationPolicy == .regular,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }
        
        print("🚀 [AppSwitcherManager] App launched: \(app.localizedName ?? "Unknown")")
        
        // 🆕 Refresh badge cache (new app might have badges)
        DockBadgeReader.shared.forceRefresh()
        
        // Trigger immediate refresh instead of waiting for timer
        loadRunningApplications()
    }
    
    @objc private func handleAppTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        
        print("🛑 [AppSwitcherManager] App terminated: \(app.localizedName ?? "Unknown")")
        
        // 🆕 Refresh badge cache (removes terminated app's badge)
        DockBadgeReader.shared.forceRefresh()
        
        // Trigger immediate refresh instead of waiting for timer
        loadRunningApplications()
    }
    
    // MARK: - MRU Management
    
    private func sortAppsByMRU(_ apps: [NSRunningApplication]) -> [NSRunningApplication] {
        // Note: This function now only gets called when there's an actual change
        // So logging here is appropriate (won't spam console)
        print("Sorting apps by MRU. Usage history: \(appUsageHistory)")
        
        // Apps are already deduplicated by caller, but we still filter invalid PIDs
        let validApps = apps.filter { $0.processIdentifier > 0 }
        
        // Create dictionary from valid apps by PID for MRU lookup
        let appDict = Dictionary(uniqueKeysWithValues: validApps.map {
            ($0.processIdentifier, $0)
        })
        
        var sortedApps: [NSRunningApplication] = []
        
        // First, add apps in MRU order (if they still exist)
        for pid in appUsageHistory {
            if let app = appDict[pid] {
                sortedApps.append(app)
            }
        }
        
        // Then add any new apps that aren't in our history yet (alphabetically)
        let appsInHistory = Set(sortedApps.map { $0.processIdentifier })
        let newApps = validApps.filter { !appsInHistory.contains($0.processIdentifier) }
            .sorted { app1, app2 in
                let name1 = app1.localizedName ?? ""
                let name2 = app2.localizedName ?? ""
                return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
            }
        
        sortedApps.append(contentsOf: newApps)
        
        print("🏁 Final sorted order: \(sortedApps.map { $0.localizedName ?? "Unknown" }.joined(separator: " → "))")
        
        return sortedApps
    }
    
    private func addToUsageHistory(_ pid: pid_t) {
        // Don't track invalid PIDs (safety check)
        guard pid > 0 else {
            print("⚠️ Ignoring invalid PID in usage history")
            return
        }
        // Remove if already exists
        appUsageHistory.removeAll { $0 == pid }
        // Add to front (most recent)
        appUsageHistory.insert(pid, at: 0)
        
        // Keep history reasonable size (max 50 apps)
        if appUsageHistory.count > 50 {
            appUsageHistory = Array(appUsageHistory.prefix(50))
        }
    }
    
    private func removeFromUsageHistory(_ pid: pid_t) {
        appUsageHistory.removeAll { $0 == pid }
    }
    
    func recordAppUsage(_ app: NSRunningApplication) {
        print("Recording usage for: \(app.localizedName ?? "Unknown") (PID: \(app.processIdentifier))")
        
        // Don't record apps with invalid process IDs
        guard app.processIdentifier > 0 else {
            print("⚠️ Skipping usage record for app with invalid PID")
            return
        }
        
        addToUsageHistory(app.processIdentifier)
        
        // Force immediate re-sort without waiting for app list changes
        DispatchQueue.main.async {
            self.forceResortApps()
        }
    }
    
    private func forceResortApps() {
        print("Force resorting apps by MRU")
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
        print("Showing app switcher")
        isVisible = true
        selectedAppIndex = 0
        isCtrlPressed = true
        loadRunningApplications()
        
        // Bring Jason window to the front
        bringJasonToFront()
    }
    
    func hideAppSwitcher() {
        print("Hiding app switcher")
        isVisible = false
        selectedAppIndex = 0
        isCtrlPressed = false
    }
    
    func bringJasonToFront() {
        print("Bringing Jason to front")
        
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
            print("Selected: \(runningApps[selectedAppIndex].localizedName ?? "Unknown") (\(selectedAppIndex + 1)/\(runningApps.count))")
        }
    }
    
    func navigatePrevious() {
        if !runningApps.isEmpty {
            selectedAppIndex = selectedAppIndex > 0 ? selectedAppIndex - 1 : runningApps.count - 1
            print("Selected: \(runningApps[selectedAppIndex].localizedName ?? "Unknown") (\(selectedAppIndex + 1)/\(runningApps.count))")
        }
    }
    
    func selectCurrentApp() {
        if !runningApps.isEmpty && selectedAppIndex < runningApps.count {
            let selectedApp = runningApps[selectedAppIndex]
            switchToApp(selectedApp)
        }
    }
    
    func switchToApp(_ app: NSRunningApplication) {
        print("Switching to app: \(app.localizedName ?? "Unknown")")
        
        // Record this app usage BEFORE hiding the switcher
        recordAppUsage(app)
        
        // Update app switcher state
        hideAppSwitcher()
        
        // Check if we have an active UI manager
        if activeCircularUIManager == nil {
            print("⚠️ activeCircularUIManager is NIL! Cannot hide UI properly")
        } else {
            print("✅ Calling hideAndSwitchTo on active instance...")
        }
        
        // Hide the circular UI and activate the selected app
        // This uses the special hideAndSwitchTo which doesn't restore previous app
        activeCircularUIManager?.hideAndSwitchTo(app: app)
        
        print("Successfully switched to \(app.localizedName ?? "Unknown")")
        
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
        
        // Ignore focus changes for 500ms to prevent UI from hiding when app window closes
        activeCircularUIManager?.ignoreFocusChangesTemporarily(duration: 0.5)
        
        app.terminate()
    }
    
    /// Hide an application
    func hideApp(_ app: NSRunningApplication) {
        print("Hiding app: \(app.localizedName ?? "Unknown")")
        app.hide()
    }
    
    /// Unhide an application (show it)
    func unhideApp(_ app: NSRunningApplication) {
        print("Unhiding app: \(app.localizedName ?? "Unknown")")
        app.unhide()
    }
    
    /// Force quit an application (future)
    func forceQuitApp(_ app: NSRunningApplication) {
        print("Force quitting app: \(app.localizedName ?? "Unknown")")
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
                StandardContextActions.bringToFront(app, manager: self),
                StandardContextActions.quitApp(app, manager: self),
                StandardContextActions.hideApp(app, manager: self)
            ]
            
            return FunctionNode(
                id: "app-\(app.processIdentifier)",
                name: app.localizedName ?? "Unknown",
                type: .app,
                icon: app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!,
                contextActions: contextActions,
                slicePositioning: .center,
                // EXPLICIT INTERACTION MODEL:
                onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                    // Primary action: switch to app and close UI
                    self?.switchToApp(app)
                }),
                onRightClick: ModifierAwareInteraction(base: .expand),  // Right-click: Show context menu
                onMiddleClick: ModifierAwareInteraction(base: .executeKeepOpen { [weak self] in
                    // Middle-click: Switch to app but keep UI open
                    self?.switchToApp(app)
                })
            )
        }
        
        // Return as a single category node
        return [
            FunctionNode(
                id: providerId,
                name: providerName,
                type: .category,
                icon: providerIcon,
                children: appNodes,
                preferredLayout: .partialSlice,  // Use full circle for many apps
                slicePositioning: .center,
                providerId: self.providerId,
                // EXPLICIT INTERACTION MODEL:
                onLeftClick: ModifierAwareInteraction(base: .expand),           // Click to expand applications
                onRightClick: ModifierAwareInteraction(base: .execute { [weak self] in
                   // Right-click: Open Applications folder
                   print("Opening Applications folder")
                   self?.openApplicationsFolder()
                }),
                onMiddleClick: ModifierAwareInteraction(base: .expand),         // Middle-click: Expand
                onBoundaryCross: ModifierAwareInteraction(base: .expand),       // Auto-expand on boundary cross
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
