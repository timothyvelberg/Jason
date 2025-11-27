//
//  JasonApp.swift
//  Jason
//
//  Created by Timothy Velberg on 31/07/2025.
//

import SwiftUI

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
class AppDelegate: NSObject, NSApplicationDelegate {
    var keyMonitor: Any?
    var statusItem: NSStatusItem?
    var contentWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        
        // Run ALL database operations sequentially on main thread
        DatabaseManager.shared.setupSmartCacheTables()
        print("⚡ SmartCache: System initialized!")
        
        // Small delay between operations to prevent conflicts
        DispatchQueue.main.async {
            DatabaseManager.shared.createEnhancedCacheTables()
            print("⚡ EnhancedCache: System initialized!")
            
            // Start LiveDataCoordinator after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // Register streams with coordinator
                LiveDataCoordinator.shared.register(FolderWatcherManager.shared)
                
                // Start all live data monitoring (includes sleep/wake handling)
                LiveDataCoordinator.shared.startAll()
                print("🎛️ LiveDataCoordinator: Started with sleep/wake handling!")
                
                let stats = DatabaseManager.shared.getEnhancedCacheStats()
                print("📊 Cache stats: \(stats.folders) folders, \(stats.items) items, \(stats.thumbnails) thumbnails")
                
                let watchedFolders = FolderWatcherManager.shared.getWatchedFolders()
                if !watchedFolders.isEmpty {
                    print("👀 Currently watching \(watchedFolders.count) folders:")
                    for folder in watchedFolders {
                        print("   📁 \(folder)")
                    }
                }
            }
        }
        
        // Create the status bar item (menu bar icon)
        setupMenuBar()
        
        // Create the ContentView window (hidden initially)
        setupContentWindow()
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
        
        print("📍 Menu bar item created")
    }
    
    func setupContentWindow() {
        // Create ContentView - it will create its own AppSwitcherManager and CircularUIManager
        let contentView = ContentView()
        
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
            print("🙈 Hiding settings window")
            window.orderOut(nil)
        } else {
            print("👁️ Showing settings window")
            
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
}
