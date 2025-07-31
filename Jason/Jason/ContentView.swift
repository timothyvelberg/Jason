//
//  ContentView.swift
//  Jason
//
//  Created by Timothy Velberg on 31/07/2025.
//

//
//  ContentView.swift
//  Jason
//
//  Created by Timothy Velberg on 31/07/2025.
//

//
//  ContentView.swift
//  Jason
//
//  Created by Timothy Velberg on 31/07/2025.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @State private var runningApps: [NSRunningApplication] = []
    @State private var refreshTimer: Timer?
    @State private var isVisible: Bool = false
    @State private var hasAccessibilityPermission: Bool = false
    
    var body: some View {
        Group {
            if !hasAccessibilityPermission {
                // Show permission request UI
                permissionRequestView
            } else if isVisible {
                // Show the app switcher UI
                appSwitcherView
            } else {
                // Show a minimal hidden state
                Text("Jason App Switcher")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 200, height: 50)
            }
        }
        .onAppear {
            print("🚀 ContentView appeared")
            checkAccessibilityPermission()
            if hasAccessibilityPermission {
                setupServices()
            }
        }
        .onDisappear {
            print("👋 ContentView disappeared - stopping services")
            stopAutoRefresh()
        }
    }
    
    var permissionRequestView: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            
            Text("Accessibility Permission Required")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Jason needs Accessibility permission to detect global keyboard shortcuts (Ctrl+2) and function as an app switcher.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(spacing: 10) {
                Text("To grant permission:")
                    .fontWeight(.medium)
                
                Text("1. Click 'Open System Preferences' below")
                Text("2. Find 'Jason' in the list")
                Text("3. Check the box next to 'Jason'")
                Text("4. Come back and click 'Check Again'")
            }
            .font(.system(size: 14))
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            HStack(spacing: 15) {
                Button("Open System Preferences") {
                    openAccessibilityPreferences()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Check Again") {
                    checkAccessibilityPermission()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(30)
        .frame(maxWidth: 500)
    }
    
    var appSwitcherView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Running Applications")
                    .font(.title)
                
                Spacer()
                
                Button("Hide") {
                    hideAppSwitcher()
                }
                .buttonStyle(.bordered)
                
                Text("\(runningApps.count) apps")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 10)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(runningApps, id: \.processIdentifier) { app in
                        HStack {
                            // App icon
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                            } else {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.localizedName ?? "Unknown")
                                    .font(.headline)
                                
                                Text(app.bundleIdentifier ?? "Unknown ID")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            // Status indicators
                            if app.isActive {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                            }
                            
                            if app.isHidden {
                                Image(systemName: "eye.slash")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(app.isActive ? Color.blue.opacity(0.1) : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            switchToApp(app)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                .opacity(app.isActive ? 1 : 0)
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 10)
    }
    
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
    
    func setupServices() {
        print("🎹 Setting up services")
        setupGlobalHotkeys()
        startAutoRefresh()
        loadRunningApplications()
    }
    
    func setupGlobalHotkeys() {
        print("🎹 Setting up global hotkeys")
        
        // Listen for global key events (requires Accessibility permission)
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { event in
            handleGlobalKeyDown(event)
        }
        
        // Also listen for local events (when our app has focus)
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleLocalKeyDown(event)
            return event
        }
        
        print("✅ Global hotkey monitoring started")
    }
    
    func handleGlobalKeyDown(_ event: NSEvent) {
        // Check for Ctrl+2 combination
        let isCtrlPressed = event.modifierFlags.contains(.control)
        let isKey2 = event.keyCode == 19  // Key code for "2"
        
        if isCtrlPressed && isKey2 {
            print("🔥 Global Ctrl+2 detected!")
            showAppSwitcher()
        }
    }
    
    func handleLocalKeyDown(_ event: NSEvent) {
        // Check for Ctrl+2 combination
        let isCtrlPressed = event.modifierFlags.contains(.control)
        let isKey2 = event.keyCode == 19  // Key code for "2"
        
        if isCtrlPressed && isKey2 {
            print("🔥 Local Ctrl+2 detected!")
            showAppSwitcher()
        }
        
        // Check for Escape to hide
        if event.keyCode == 53 { // Escape key
            print("⌨️  Escape pressed - hiding app switcher")
            hideAppSwitcher()
        }
    }
    
    func showAppSwitcher() {
        print("👁️  Showing app switcher")
        isVisible = true
        loadRunningApplications()
        
        // Bring Jason window to the front
        bringJasonToFront()
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
    
    func hideAppSwitcher() {
        print("🙈 Hiding app switcher")
        isVisible = false
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
            loadRunningApplications()
        }
    }
    
    func startAutoRefresh() {
        // Stop any existing timer
        stopAutoRefresh()
        
        // Start a timer that checks for changes every 1 second
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            loadRunningApplications()
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
}
