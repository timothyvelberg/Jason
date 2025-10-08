//
//  FinderLogic.swift
//  Jason
//
//  Shows open Finder windows in a simple list
//  - Ring 0: Single "Finder" item
//    - Click: Opens new Finder window
//    - Hover+outward: Shows all open windows + "New Window" option
//
//  - Ring 1: Open Finder windows (simple list)
//    - Click: Brings that window to front
//

import Foundation
import AppKit

class FinderLogic: FunctionProvider {
    
    // MARK: - Provider Info
    
    var providerId: String { "finder-windows" }
    var providerName: String { "Finder" }
    var providerIcon: NSImage {
        return NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")
    }
    
    // MARK: - Provide Functions
    
    func provideFunctions() -> [FunctionNode] {
        print("🔍 [FinderLogic] provideFunctions() called")
        
        // Get all open Finder windows
        let finderWindows = getOpenFinderWindows()
        print("🔍 [FinderLogic] Found \(finderWindows.count) open Finder window(s)")
        
        // Create simple nodes for each window (no children)
        var windowNodes = finderWindows.compactMap { windowInfo in
            createFinderWindowNode(for: windowInfo)
        }
        
        // Add "New Window" action at the end
        windowNodes.append(FunctionNode(
            id: "new-finder-window",
            name: "New Window",
            icon: NSImage(systemSymbolName: "plus.rectangle", accessibilityDescription: nil) ?? NSImage(),
            onSelect: { [weak self] in
                self?.openNewFinderWindow()
            }
        ))
        
        // Return as single "Finder" category
        return [
            FunctionNode(
                id: providerId,
                name: providerName,
                icon: providerIcon,
                children: windowNodes,
                onSelect: { [weak self] in
                    // Primary action: Open new Finder window
                    print("📂 Opening new Finder window")
                    self?.openNewFinderWindow()
                }
            )
        ]
    }
    
    func refresh() {
        print("🔄 [FinderLogic] refresh() called")
    }
    
    // MARK: - Finder Window Discovery
    
    struct FinderWindowInfo {
        let name: String
        let url: URL
        let index: Int
    }
    
    private func getOpenFinderWindows() -> [FinderWindowInfo] {
        print("🔍 [FinderLogic] Querying Finder for open windows...")
        
        // Use System Events to query Finder windows (more reliable)
        let script = """
        tell application "System Events"
            tell process "Finder"
                set windowList to {}
                set allWindows to every window
                
                repeat with i from 1 to count of allWindows
                    try
                        set theWindow to item i of allWindows
                        set windowName to name of theWindow as string
                        
                        -- Skip special windows
                        if windowName is not "" and windowName does not start with "." then
                            copy windowName to end of windowList
                        end if
                    on error errMsg
                        -- Skip windows that can't be accessed
                    end try
                end repeat
                
                return windowList
            end tell
        end tell
        """
        
        var windows: [FinderWindowInfo] = []
        
        guard let appleScript = NSAppleScript(source: script) else {
            print("❌ Failed to create AppleScript")
            return []
        }
        
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)
        
        if let error = error {
            print("❌ AppleScript error: \(error)")
            if let errorMessage = error["NSAppleScriptErrorMessage"] as? String {
                print("   Error message: \(errorMessage)")
            }
            return []
        }
        
        print("✅ AppleScript executed successfully")
        print("   Result type: \(result.descriptorType)")
        print("   Number of items: \(result.numberOfItems)")
        
        // Parse the result - each item is just a window name
        if result.numberOfItems > 0 {
            for i in 1...result.numberOfItems {
                guard let item = result.atIndex(i) else {
                    print("   ⚠️ Could not get item at index \(i)")
                    continue
                }
                
                if let windowName = item.stringValue {
                    print("   ✅ Found window: \(windowName)")
                    
                    // Try to guess the path from the window name
                    let url = guessURLFromWindowName(windowName)
                    windows.append(FinderWindowInfo(name: windowName, url: url, index: i))
                } else {
                    print("   ⚠️ Could not get string value for item \(i)")
                }
            }
        } else {
            print("   ℹ️ No Finder windows currently open")
        }
        
        print("🔍 [FinderLogic] Returning \(windows.count) window(s)")
        return windows
    }
    
    private func guessURLFromWindowName(_ windowName: String) -> URL {
        // Try common locations first
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        
        let commonPaths: [String: String] = [
            "Desktop": "Desktop",
            "Documents": "Documents",
            "Downloads": "Downloads",
            "Pictures": "Pictures",
            "Music": "Music",
            "Movies": "Movies",
            "Applications": "/Applications",
            "Utilities": "/Applications/Utilities"
        ]
        
        if let relativePath = commonPaths[windowName] {
            if relativePath.hasPrefix("/") {
                return URL(fileURLWithPath: relativePath)
            } else {
                return homeDir.appendingPathComponent(relativePath)
            }
        }
        
        // If not a common name, try as subfolder of home directory
        let guessedPath = homeDir.appendingPathComponent(windowName)
        if FileManager.default.fileExists(atPath: guessedPath.path) {
            return guessedPath
        }
        
        // Fallback to home directory
        print("   ⚠️ Could not determine path for window '\(windowName)', using home directory")
        return homeDir
    }
    
    private func createFinderWindowNode(for windowInfo: FinderWindowInfo) -> FunctionNode? {
        print("🪟 [FinderLogic] Creating node for window: \(windowInfo.name)")
        
        // Simple node with context action to close
        return FunctionNode(
            id: "finder-window-\(windowInfo.index)",
            name: windowInfo.name,
            icon: NSWorkspace.shared.icon(forFile: windowInfo.url.path),
            contextActions: [
                FunctionNode(
                    id: "close-window-\(windowInfo.index)",
                    name: "Close Window",
                    icon: NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil) ?? NSImage(),
                    onSelect: { [weak self] in
                        self?.closeFinderWindow(windowInfo.index)
                    }
                )
            ],
            onSelect: { [weak self] in
                // Primary action: Bring this Finder window to front
                self?.bringFinderWindowToFront(windowInfo.index)
            }
        )
    }
    
    // MARK: - Actions
    
    private func openNewFinderWindow() {
        print("🪟 Opening new Finder window")
        
        let script = """
        tell application "Finder"
            activate
            make new Finder window
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            
            if let error = error {
                print("❌ Failed to open new window: \(error)")
            } else {
                print("✅ New Finder window opened")
            }
        }
    }
    
    private func bringFinderWindowToFront(_ windowIndex: Int) {
        print("🪟 Bringing Finder window \(windowIndex) to front")
        
        let script = """
        tell application "System Events"
            tell process "Finder"
                set frontmost to true
                perform action "AXRaise" of window \(windowIndex)
            end tell
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            
            if let error = error {
                print("❌ Failed to bring window to front: \(error)")
                
                // Fallback: try the Finder approach
                let fallbackScript = """
                tell application "Finder"
                    activate
                    set index of window \(windowIndex) to 1
                end tell
                """
                
                if let fallbackAS = NSAppleScript(source: fallbackScript) {
                    fallbackAS.executeAndReturnError(nil)
                }
            } else {
                print("✅ Window brought to front")
            }
        }
    }
    
    private func closeFinderWindow(_ windowIndex: Int) {
        print("❌ Closing Finder window \(windowIndex)")
        
        let script = """
        tell application "Finder"
            close window \(windowIndex)
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            
            if let error = error {
                print("❌ Failed to close window: \(error)")
            } else {
                print("✅ Window closed")
            }
        }
    }
}
