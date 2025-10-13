//
//  FinderLogic.swift
//  Jason
//
//  Shows open Finder windows + Downloads files
//  - Ring 0: "Finder Windows" and "Downloads"
//  - Ring 1: Open Finder windows OR Downloads files (last 10)
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
        
        // Create both sections
        let finderWindowsNode = createFinderWindowsNode()
        let downloadsFilesNode = createDownloadsFilesNode()
        
        return [finderWindowsNode, downloadsFilesNode]
    }
    
    func refresh() {
        print("🔄 [FinderLogic] refresh() called")
    }
    
    // MARK: - Finder Windows Section
    
    private func createFinderWindowsNode() -> FunctionNode {
        let finderWindows = getOpenFinderWindows()
        print("🔍 [FinderLogic] Found \(finderWindows.count) open Finder window(s)")
        
        var windowNodes = finderWindows.compactMap { windowInfo in
            createFinderWindowNode(for: windowInfo)
        }
        
        // Add "New Window" action
        windowNodes.append(FunctionNode(
            id: "new-finder-window",
            name: "New Window",
            icon: NSImage(systemSymbolName: "plus.rectangle", accessibilityDescription: nil) ?? NSImage(),
            preferredLayout: nil,
            onLeftClick: .execute { [weak self] in
                self?.openNewFinderWindow()
            },
            onMiddleClick: .executeKeepOpen { [weak self] in
                self?.openNewFinderWindow()
            }
        ))
        
        return FunctionNode(
            id: "finder-windows-section",
            name: "Finder Windows",
            icon: providerIcon,
            children: windowNodes,
            preferredLayout: .partialSlice,
            onLeftClick: .expand,
            onRightClick: .execute { [weak self] in
                self?.openNewFinderWindow()
            },
            onMiddleClick: .expand,
            onBoundaryCross: .expand
        )
    }
    
    // MARK: - Downloads Files Section (DRAGGABLE!)
    
    private func createDownloadsFilesNode() -> FunctionNode {
        let downloadsFiles = getDownloadsFiles()
        print("📥 [FinderLogic] Found \(downloadsFiles.count) file(s) in Downloads (showing last 10)")
        
        let fileNodes = downloadsFiles.map { fileURL in
            createDraggableFileNode(for: fileURL)
        }
        
        return FunctionNode(
            id: "downloads-files-section",
            name: "Downloads",
            icon: NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil) ?? NSImage(),
            children: fileNodes,
            preferredLayout: .fullCircle,
            onLeftClick: .expand,
            onRightClick: .expand,
            onMiddleClick: .expand,
            onBoundaryCross: .expand
        )
    }
    
    private func getDownloadsFiles() -> [URL] {
        let downloadsURL = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first!
        
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: downloadsURL,
                includingPropertiesForKeys: [.isDirectoryKey, .nameKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            // Sort by modification date (newest first)
            let sortedFiles = files.sorted { url1, url2 in
                guard let date1 = try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      let date2 = try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
                    return false
                }
                return date1 > date2
            }
            
            // Return only the last 10 files
            return Array(sortedFiles.prefix(10))
        } catch {
            print("❌ Failed to read Downloads: \(error)")
            return []
        }
    }

    private func createDraggableFileNode(for url: URL) -> FunctionNode {
        let fileName = url.lastPathComponent
        let fileIcon = NSWorkspace.shared.icon(forFile: url.path)
        
        // Create thumbnail for images
        let dragImage = createThumbnail(for: url)
        
        print("📄 [FinderLogic] Creating draggable node for: \(fileName)")
        
        return FunctionNode(
            id: "downloads-file-\(url.path)",
            name: fileName,
            icon: dragImage,
            
            // Context actions (right-click menu)
            contextActions: [
                StandardContextActions.deleteFile(url),
                StandardContextActions.openFile(url),
                StandardContextActions.showInFinder(url)
            ],
            
            preferredLayout: .partialSlice,
            itemAngleSize: 15,
            previewURL: url,
            showLabel: true,
            childRingThickness: 48,
            childIconSize: 24,
            
            

            // 🎯 LEFT CLICK = OPEN FILE (or drag if you move the mouse!)
            onLeftClick: .drag(DragProvider(
                fileURLs: [url],
                dragImage: dragImage,
                allowedOperations: .move,
                onClick: {
                    print("📂 Opening file: \(fileName)")
                    NSWorkspace.shared.open(url)
                },
                onDragStarted: {
                    print("📦 Started dragging: \(fileName)")
                },
                onDragCompleted: { success in
                    if success {
                        print("✅ Successfully dragged: \(fileName)")
                    } else {
                        print("❌ Drag cancelled: \(fileName)")
                    }
                }
            )),
            
            // RIGHT CLICK = SHOW CONTEXT MENU
            onRightClick: .expand,
            
            // MIDDLE CLICK = QUICK OPEN
            onMiddleClick: .executeKeepOpen {
                print("🖱️ Middle-click opening: \(fileName)")
                NSWorkspace.shared.open(url)
            },
            
            onBoundaryCross: .doNothing
        )
    }
    
    // Helper method to create rounded icon for non-image files
    private func createRoundedIcon(for url: URL, size: NSSize, cornerRadius: CGFloat) -> NSImage {
        let fileIcon = NSWorkspace.shared.icon(forFile: url.path)
        let roundedIcon = NSImage(size: size)
        
        roundedIcon.lockFocus()
        
        // Draw background with rounded corners
        let rect = NSRect(origin: .zero, size: size)
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        
        // Optional: Add subtle background color
        NSColor.controlBackgroundColor.withAlphaComponent(0.1).setFill()
        path.fill()
        
        // Clip to rounded rect
        path.addClip()
        
        // Draw the icon slightly smaller to add padding
        let padding: CGFloat = 8
        let iconRect = rect.insetBy(dx: padding, dy: padding)
        fileIcon.draw(
            in: iconRect,
            from: NSRect(origin: .zero, size: fileIcon.size),
            operation: .sourceOver,
            fraction: 1.0
        )
        
        roundedIcon.unlockFocus()
        
        return roundedIcon
    }
    
    // MARK: - File Actions

    private func deleteFile(_ url: URL) {
        print("🗑️ Moving to trash: \(url.lastPathComponent)")
        
        NSWorkspace.shared.recycle([url]) { trashedURLs, error in
            if let error = error {
                print("❌ Failed to delete file: \(error.localizedDescription)")
            } else {
                print("✅ File moved to trash: \(url.lastPathComponent)")
            }
        }
    }
    
    // Helper: Create thumbnail for images
    private func createThumbnail(for url: URL) -> NSImage {
        let thumbnailSize = NSSize(width: 64, height: 64)
        let cornerRadius: CGFloat = 8  // Rounded corners!
        
        // Check if it's an image file
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"]
        let fileExtension = url.pathExtension.lowercased()
        
        if imageExtensions.contains(fileExtension) {
            if let image = NSImage(contentsOf: url) {
                let thumbnail = NSImage(size: thumbnailSize)
                
                thumbnail.lockFocus()
                
                // Create rounded rect path
                let rect = NSRect(origin: .zero, size: thumbnailSize)
                let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
                
                // Clip to rounded rect
                path.addClip()
                
                // Draw image within rounded rect
                image.draw(
                    in: rect,
                    from: NSRect(origin: .zero, size: image.size),
                    operation: .sourceOver,
                    fraction: 1.0
                )
                
                thumbnail.unlockFocus()
                
                return thumbnail
            }
        }
        
        // For non-images, create rounded icon
        return createRoundedIcon(for: url, size: thumbnailSize, cornerRadius: cornerRadius)
    }
    
    // MARK: - Finder Window Discovery
    
    struct FinderWindowInfo {
        let name: String
        let url: URL
        let index: Int
    }
    
    private func getOpenFinderWindows() -> [FinderWindowInfo] {
        print("🔍 [FinderLogic] Querying Finder for open windows...")
        
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
            return []
        }
        
        if result.numberOfItems > 0 {
            for i in 1...result.numberOfItems {
                guard let item = result.atIndex(i),
                      let windowName = item.stringValue else {
                    continue
                }
                
                let url = guessURLFromWindowName(windowName)
                windows.append(FinderWindowInfo(name: windowName, url: url, index: i))
            }
        }
        
        return windows
    }
    
    private func guessURLFromWindowName(_ windowName: String) -> URL {
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
        
        let guessedPath = homeDir.appendingPathComponent(windowName)
        if FileManager.default.fileExists(atPath: guessedPath.path) {
            return guessedPath
        }
        
        return homeDir
    }
    
    private func createFinderWindowNode(for windowInfo: FinderWindowInfo) -> FunctionNode? {
        return FunctionNode(
            id: "finder-window-\(windowInfo.index)",
            name: windowInfo.name,
            icon: NSWorkspace.shared.icon(forFile: windowInfo.url.path),
            contextActions: [
                FunctionNode(
                    id: "close-window-\(windowInfo.index)",
                    name: "Close Window",
                    icon: NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil) ?? NSImage(),
                    preferredLayout: nil,
                    onLeftClick: .execute { [weak self] in
                        self?.closeFinderWindow(windowInfo.index)
                    },
                    onMiddleClick: .executeKeepOpen { [weak self] in
                        self?.closeFinderWindow(windowInfo.index)
                    }
                )
            ],
            preferredLayout: .partialSlice,
            itemAngleSize: 20.0,
            onLeftClick: .execute { [weak self] in
                self?.bringFinderWindowToFront(windowInfo.index)
            },
            onRightClick: .expand,
            onMiddleClick: .executeKeepOpen { [weak self] in
                self?.bringFinderWindowToFront(windowInfo.index)
            },
            onBoundaryCross: .doNothing
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
