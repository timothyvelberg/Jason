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

            
            // 🧪 TEST: WhatsApp badge debug
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                print("🧪 [Dock A11y] Checking all dock items for badges...")
                
                guard let dockApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dock" }) else {
                    print("   ❌ Dock not found")
                    return
                }
                
                let dockElement = AXUIElementCreateApplication(dockApp.processIdentifier)
                
                var childrenRef: CFTypeRef?
                let childrenResult = AXUIElementCopyAttributeValue(dockElement, kAXChildrenAttribute as CFString, &childrenRef)
                
                guard childrenResult == .success, let children = childrenRef as? [AXUIElement] else {
                    print("   ❌ Failed to get Dock children")
                    return
                }
                
                for child in children {
                    var roleRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
                    
                    if (roleRef as? String) == "AXList" {
                        var listChildrenRef: CFTypeRef?
                        let listResult = AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &listChildrenRef)
                        
                        if listResult == .success, let listChildren = listChildrenRef as? [AXUIElement] {
                            print("   Found \(listChildren.count) dock items:")
                            
                            for item in listChildren {
                                var titleRef: CFTypeRef?
                                AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleRef)
                                let title = titleRef as? String ?? "(no title)"
                                
                                // Check ALL attributes for WhatsApp
                                if title.lowercased().contains("whatsapp") {
                                    print("\n   🔍 WhatsApp found - dumping all attributes:")
                                    
                                    var attrNamesRef: CFArray?
                                    AXUIElementCopyAttributeNames(item, &attrNamesRef)
                                    
                                    if let attrNames = attrNamesRef as? [String] {
                                        for attr in attrNames {
                                            var valueRef: CFTypeRef?
                                            AXUIElementCopyAttributeValue(item, attr as CFString, &valueRef)
                                            let value = valueRef ?? "nil" as CFTypeRef
                                            print("      \(attr): \(value)")
                                        }
                                    }
                                    print("")
                                }
                                
                                // Also print badge status for all items
                                var statusRef: CFTypeRef?
                                AXUIElementCopyAttributeValue(item, "AXStatusLabel" as CFString, &statusRef)
                                let badge = statusRef as? String
                                
                                let badgeInfo = badge != nil ? "✅ badge: \"\(badge!)\"" : "no badge"
                                print("   - \(title): \(badgeInfo)")
                            }
                        }
                    }
                }
            }
        }
        
        // Create the status bar item (menu bar icon)
        setupMenuBar()
        
        // Create the ContentWindow (hidden initially)
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
