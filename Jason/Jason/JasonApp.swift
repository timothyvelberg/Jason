//
//  JasonApp.swift
//  Jason
//
//  Created by Timothy Velberg on 31/07/2025.
//

import SwiftUI
import Sparkle

@main
struct JasonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Remove WindowGroup - we'll manage windows manually in AppDelegate
        Settings {
            EmptyView()
        }
    }
}

// App Delegate to handle keyboard events and menu bar
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var keyMonitor: Any?
    var statusItem: NSStatusItem?
    var contentWindow: NSWindow?
    var updaterController: SPUStandardUpdaterController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        
        ClipboardManager.shared.startMonitoring()
        
        // Run ALL database operations sequentially on main thread
        DatabaseManager.shared.setupSmartCacheTables()
        print("SmartCache: System initialized!")
        
        // Small delay between operations to prevent conflicts
        DispatchQueue.main.async {
            DatabaseManager.shared.createEnhancedCacheTables()
            
            // Start LiveDataCoordinator after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // Register streams with coordinator
                LiveDataCoordinator.shared.register(FolderWatcherManager.shared)
                
                // Start all live data monitoring (includes sleep/wake handling)
                LiveDataCoordinator.shared.startAll()
                print("LiveDataCoordinator: Started with sleep/wake handling!")
                
                let stats = DatabaseManager.shared.getEnhancedCacheStats()
                print("Cache stats: \(stats.folders) folders, \(stats.items) items, \(stats.thumbnails) thumbnails")
                
                let watchedFolders = FolderWatcherManager.shared.getWatchedFolders()
                if !watchedFolders.isEmpty {
                    print("Currently watching \(watchedFolders.count) folders:")
                    for folder in watchedFolders {
                        print("   \(folder)")
                    }
                }
            }
        }
        
        // Create the status bar item (menu bar icon)
        setupMenuBar()
        
        // Create the ContentWindow (hidden initially)
        setupContentWindow()
        
        // Initialize Sparkle for updates
        setupSparkle()
    }
    
    func setupMenuBar() {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            // Set the icon - using SF Symbol
            button.image = NSImage(systemSymbolName: "circle.circle", accessibilityDescription: "Jason App Switcher")
            button.action = #selector(toggleContentWindow)
            button.target = self
        }
        
        print("Menu bar item created")
    }
    
    func setupSparkle() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        print("✨ Sparkle updater initialized")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            print("🔍 Current version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "unknown")")
            print("🔍 Current build: \(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "unknown")")
            self.updaterController?.updater.checkForUpdates()
        }
    }
    
    func setupContentWindow() {
        let contentView = ContentSettingsView()
        
        // Create window with size appropriate for settings interface
        contentWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        contentWindow?.title = "Jason Settings"
        contentWindow?.contentView = NSHostingView(rootView: contentView)
        contentWindow?.isReleasedWhenClosed = false
        contentWindow?.delegate = self  // 👈 ADD THIS LINE
        
        // Set minimum size constraints
        contentWindow?.minSize = NSSize(width: 1024, height: 640)
        
        // Center on screen instead of anchoring to menu bar (better for settings)
        contentWindow?.center()
        
        // Normal level (not floating) for settings window
        contentWindow?.level = .normal
    }
    
    @objc func toggleContentWindow() {
        guard let window = contentWindow else { return }
        
        if window.isVisible {
            print("[Hiding Window] Switching to accessory mode")
            window.orderOut(nil)
            NSApp.setActivationPolicy(.accessory)  // 👈 Remove dock icon
        } else {
            print("[Show Window] Switching to regular mode")
            
            // Switch to regular app mode (shows dock icon & app switcher)
            NSApp.setActivationPolicy(.regular)  // 👈 Show dock icon
            
            // Center window on screen
            window.center()
            
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    // Prevent app from quitting when window closes
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        print("[Window Closing] Switching back to accessory mode")
        NSApp.setActivationPolicy(.accessory)  // 👈 Remove dock icon when user clicks X
    }
}
