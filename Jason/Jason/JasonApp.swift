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
        print("🚀 AppDelegate: Setting up menu bar app")
        
        // Initialize databases
        DatabaseManager.shared.setupSmartCacheTables()
        print("⚡ SmartCache: System initialized!")
        
        DatabaseManager.shared.createEnhancedCacheTables()
        print("⚡ EnhancedCache: System initialized!")
        
        // Start watching (after a small delay to let everything initialize)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            FolderWatcherManager.shared.startWatchingFavorites()
            print("👀 FSEvents: Folder watching started!")
            
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
        
        // Run cleanup later (30 minutes after launch)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1800) {
            DatabaseManager.shared.cleanupInactiveHeavyFolders(inactiveDays: 30)
            DatabaseManager.shared.cleanupOldAccessRecords(keepDays: 90)
            DatabaseManager.shared.cleanupOldEnhancedCache()
            print("🧹 SmartCache: Cleanup completed")
        }
    
        
        // ✅ Optional: Print cache stats
        let stats = DatabaseManager.shared.getEnhancedCacheStats()
        print("📊 Cache stats: \(stats.folders) folders, \(stats.items) items, \(stats.thumbnails) thumbnails")
        
        // Create the status bar item (menu bar icon)
        setupMenuBar()
        
        // Create the ContentView window (hidden initially)
        setupContentWindow()
        
        // Add local monitor to consume Ctrl+Shift+K in main window
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isCtrlPressed = event.modifierFlags.contains(.control)
            let isShiftPressed = event.modifierFlags.contains(.shift)
            let isKKey = event.keyCode == 40  // K key
            
            // If this is our shortcut, consume it (prevent beep)
            if isCtrlPressed && isShiftPressed && isKKey {
                print("🎯 [AppDelegate] Consuming Ctrl+Shift+K in main window (no beep)")
                return nil  // Consume event - prevents beep!
            }
            
            // Let other keys through
            return event
        }
        
        print("✅ AppDelegate: Menu bar app ready")
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
        
        // Create window
        contentWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        contentWindow?.title = "Jason"
        contentWindow?.contentView = NSHostingView(rootView: contentView)
        contentWindow?.isReleasedWhenClosed = false
        contentWindow?.level = .floating
        
        print("🪟 Content window created (hidden)")
    }
    
    @objc func toggleContentWindow() {
        guard let window = contentWindow else { return }
        
        if window.isVisible {
            print("🙈 Hiding content window")
            window.orderOut(nil)
        } else {
            print("👁️ Showing content window")
            
            // Position window near menu bar icon
            if let button = statusItem?.button {
                let buttonFrame = button.window?.convertToScreen(button.frame) ?? .zero
                
                // Position below the menu bar icon
                let windowX = buttonFrame.origin.x - (window.frame.width / 2) + (buttonFrame.width / 2)
                let windowY = buttonFrame.origin.y - window.frame.height - 5
                
                window.setFrameOrigin(NSPoint(x: windowX, y: windowY))
            }
            
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
