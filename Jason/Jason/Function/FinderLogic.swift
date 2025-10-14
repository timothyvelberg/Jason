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
    
    // MARK: - Configuration
    enum SortOrder {
        case nameAscending
        case nameDescending
        case dateModifiedNewest
        case dateModifiedOldest
        case dateCreatedNewest
        case dateCreatedOldest
        case size
    }
    
    private let maxItemsPerFolder: Int = 32
    private let sortOrder: SortOrder = .dateModifiedNewest
    
    private var nodeCache: [String: [FunctionNode]] = [:]
    
    // MARK: - Cache
    
    private var folderContentsCache: [String: [FunctionNode]] = [:]
    private let cacheTimeout: TimeInterval = 30.0  // 30 seconds
    private var cacheTimestamps: [String: Date] = [:]
    
    // MARK: - Dynamic Loading
    
    func loadChildren(for node: FunctionNode) -> [FunctionNode] {
        print("📂 [FinderLogic] loadChildren called for: \(node.name)")
        
        guard let metadata = node.metadata,
              let urlString = metadata["folderURL"] as? String else {
            print("❌ No folderURL in metadata")
            return []
        }
        
        let folderURL = URL(fileURLWithPath: urlString)
        let cacheKey = folderURL.path
        
        // Check cache first
        if let cachedNodes = nodeCache[cacheKey] {
            print("⚡ [FinderLogic] Using cached nodes for: \(node.name) (\(cachedNodes.count) items)")
            return cachedNodes
        }
        
        // Cache miss - load and create nodes
        print("📂 [FinderLogic] Loading contents of: \(folderURL.path)")
        let nodes = getFolderContents(at: folderURL)
        
        // Cache the nodes
        nodeCache[cacheKey] = nodes
        print("💾 [FinderLogic] Cached \(nodes.count) nodes for: \(node.name)")
        
        return nodes
    }
    
    // MARK: - Provide Functions
    
    func provideFunctions() -> [FunctionNode] {
        print("🔍 [FinderLogic] provideFunctions() called")
        
        // Create both sections
        let finderWindowsNode = createFinderWindowsNode()
        let downloadsFilesNode = createDownloadsFilesNode()
        return [finderWindowsNode, downloadsFilesNode]
    }
    
    func clearCache() {
        nodeCache.removeAll()
        print("🗑️ [FinderLogic] Cache cleared")
    }
    
    func invalidateCache(for url: URL) {
        let cacheKey = url.path
        nodeCache.removeValue(forKey: cacheKey)
        print("🗑️ [FinderLogic] Invalidated cache for: \(url.path)")
    }
    
    func refresh() {
        print("🔄 [FinderLogic] refresh() called")
        clearCache()  // Clear cache on explicit refresh
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
        
        // Check if this is a directory
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        
        if isDirectory.boolValue {
            // This is a FOLDER - create navigable folder node
            return createFolderNode(for: url)
        } else {
            // This is a FILE - create draggable file node
            return createFileNode(for: url)
        }
    }

    // Create folder node with navigation capability
    private func createFolderNode(for url: URL) -> FunctionNode {
        let folderName = url.lastPathComponent
        let folderIcon = NSWorkspace.shared.icon(forFile: url.path)
        
        print("📁 [FinderLogic] Creating folder node with metadata for: \(folderName)")
        
        return FunctionNode(
            id: "folder-\(url.path)",
            name: folderName,
            icon: folderIcon,
            children: nil,  // No static children
            contextActions: [
                StandardContextActions.showInFinder(url),
                StandardContextActions.deleteFile(url)
            ],
            preferredLayout: .fullCircle,
            itemAngleSize: 15,
            previewURL: url,
            showLabel: true,
            
            // NEW: Store metadata for dynamic loading
            metadata: ["folderURL": url.path],
            providerId: self.providerId,
            
            // 🎯 LEFT CLICK = NAVIGATE INTO FOLDER
            onLeftClick: .navigateInto,
            
            // RIGHT CLICK = SHOW CONTEXT MENU
            onRightClick: .expand,
            
            // MIDDLE CLICK = OPEN IN FINDER
            onMiddleClick: .executeKeepOpen {
                print("📂 Middle-click opening folder: \(folderName)")
                NSWorkspace.shared.open(url)
            },
            
            // BOUNDARY CROSS = NAVIGATE INTO
            onBoundaryCross: .navigateInto
        )
    }

    // Update createGitFolderNode to use metadata
    private func createGitFolderNode() -> FunctionNode {
        let gitURL = URL(fileURLWithPath: "/Users/timothy/Files/Git/")
        
        // Check if the folder exists
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: gitURL.path, isDirectory: &isDirectory)
        
        if !exists || !isDirectory.boolValue {
            print("⚠️ [FinderLogic] Git folder does not exist at: \(gitURL.path)")
            return FunctionNode(
                id: "git-folder-missing",
                name: "Git (Not Found)",
                icon: NSImage(systemSymbolName: "folder.badge.questionmark", accessibilityDescription: nil) ?? NSImage(),
                preferredLayout: nil,
                onLeftClick: .doNothing
            )
        }
        
        print("📁 [FinderLogic] Creating Git folder node with metadata")
        
        return FunctionNode(
            id: "git-folder-section",
            name: "Git",
            icon: NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: nil) ?? NSImage(),
            children: nil,  // No static children
            preferredLayout: .fullCircle,
            
            // NEW: Store metadata for dynamic loading
            metadata: ["folderURL": gitURL.path],
            providerId: self.providerId,
            
            onLeftClick: .navigateInto,
            onRightClick: .expand,
            onMiddleClick: .executeKeepOpen {
                NSWorkspace.shared.open(gitURL)
            },
            onBoundaryCross: .navigateInto
        )
    }

    // Update createDownloadsFilesNode to use metadata
    private func createDownloadsFilesNode() -> FunctionNode {
        let downloadsURL = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first!
        
        print("📥 [FinderLogic] Creating Downloads node with metadata")
        
        return FunctionNode(
            id: "downloads-files-section",
            name: "Downloads",
            icon: NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil) ?? NSImage(),
            children: nil,  // No static children
            preferredLayout: .fullCircle,
            
//            childRingThickness: 16,
//            childIconSize: 8,
            
            // NEW: Store metadata for dynamic loading
            metadata: ["folderURL": downloadsURL.path],
            providerId: self.providerId,
            
            onLeftClick: .navigateInto,
            onRightClick: .expand,
            onMiddleClick: .expand,
            onBoundaryCross: .navigateInto
        )
    }

    // Get folder contents (files and subfolders)
    private func getFolderContents(at url: URL) -> [FunctionNode] {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .nameKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            
            // Sort based on configuration
            let sortedContents = sortContents(contents, by: sortOrder)
            
            // Limit to max items
            let limitedContents = Array(sortedContents.prefix(maxItemsPerFolder))
            
            print("📂 Showing \(limitedContents.count) of \(contents.count) items (sorted by \(sortOrder))")
            
            // Recursively create nodes for contents
            return limitedContents.map { contentURL in
                createDraggableFileNode(for: contentURL)
            }
        } catch {
            print("❌ Failed to read folder contents: \(error)")
            return []
        }
    }

    // NEW: Sort contents based on sort order
    private func sortContents(_ contents: [URL], by sortOrder: SortOrder) -> [URL] {
        switch sortOrder {
        case .nameAscending:
            return contents.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            
        case .nameDescending:
            return contents.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
            
        case .dateModifiedNewest:
            return contents.sorted { url1, url2 in
                guard let date1 = try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      let date2 = try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
                    return false
                }
                return date1 > date2
            }
            
        case .dateModifiedOldest:
            return contents.sorted { url1, url2 in
                guard let date1 = try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      let date2 = try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
                    return false
                }
                return date1 < date2
            }
            
        case .dateCreatedNewest:
            return contents.sorted { url1, url2 in
                guard let date1 = try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate,
                      let date2 = try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate else {
                    return false
                }
                return date1 > date2
            }
            
        case .dateCreatedOldest:
            return contents.sorted { url1, url2 in
                guard let date1 = try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate,
                      let date2 = try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate else {
                    return false
                }
                return date1 < date2
            }
            
        case .size:
            return contents.sorted { url1, url2 in
                guard let size1 = try? url1.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      let size2 = try? url2.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                    return false
                }
                return size1 > size2
            }
        }
    }

    // RENAMED: Extract file node creation to separate method
    private func createFileNode(for url: URL) -> FunctionNode {
        let fileName = url.lastPathComponent
        let dragImage = createThumbnail(for: url)
        
        print("📄 [FinderLogic] Creating file node for: \(fileName)")
        
        return FunctionNode(
            id: "file-\(url.path)",
            name: fileName,
            icon: dragImage,
            
            contextActions: [
                StandardContextActions.deleteFile(url),
                StandardContextActions.copyFile(url),
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
