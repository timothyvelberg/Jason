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
    
    static weak var shared: AppDelegate?

    private var pendingSettingsTab: SettingsTab?
    var keyMonitor: Any?
    var statusItem: NSStatusItem?
    var contentWindow: NSWindow?
    var updaterController: SPUStandardUpdaterController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        
        AppDelegate.shared = self
        

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
            button.image = NSImage(named: "icon_menu_bar") ?? NSImage()
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
            print("Current version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "unknown")")
            print("Current build: \(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "unknown")")
            self.updaterController?.updater.checkForUpdatesInBackground()
        }
    }
    
    func setupContentWindow() {
        let contentView = ContentSettingsView()
        
        // Create window with size appropriate for settings interface
        contentWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        contentWindow?.title = "Jason"
        contentWindow?.contentView = NSHostingView(rootView: contentView)
        contentWindow?.isReleasedWhenClosed = false
        contentWindow?.delegate = self
        
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
            NSApp.setActivationPolicy(.accessory)
        } else {
            print("[Show Window] Switching to regular mode")
            
            // Activate the app first so the window becomes properly key
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            
            // Then bring the window forward
            window.center()
            window.makeKeyAndOrderFront(nil)
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
        NSApp.setActivationPolicy(.accessory)
    }
    
    func openSettings(tab: SettingsTab) {
        DispatchQueue.main.async {
            if !(self.contentWindow?.isVisible ?? false) {
                self.pendingSettingsTab = tab
                self.toggleContentWindow()
            } else {
                Notification.openSettings(tab: tab)
            }
        }
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        if let tab = pendingSettingsTab {
            pendingSettingsTab = nil
            DispatchQueue.main.async {
                Notification.openSettings(tab: tab)
            }
        }
    }
}
