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
    
    private let maxItemsPerFolder: Int = 20
    private let sortOrder: SortOrder = .dateModifiedNewest
    
    private var nodeCache: [String: [FunctionNode]] = [:]
    
    // MARK: - Cache
    
    private var folderContentsCache: [String: [FunctionNode]] = [:]
    private let cacheTimeout: TimeInterval = 30.0  // 30 seconds
    private var cacheTimestamps: [String: Date] = [:]


    // MARK: - Serialization Helpers

    /// Serialize nodes to JSON for database storage
    private func serializeNodes(_ nodes: [FunctionNode]) -> String {
        var items: [[String: Any]] = []
        
        for node in nodes {
            var item: [String: Any] = [
                "name": node.name,
                "id": node.id
            ]
            
            // Extract file path from metadata
            if let metadata = node.metadata,
               let folderURL = metadata["folderURL"] as? String {
                item["path"] = folderURL
                item["isDirectory"] = true
            } else if let previewURL = node.previewURL {
                item["path"] = previewURL.path
                item["isDirectory"] = false
            }
            
            items.append(item)
        }
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: items),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "[]"
    }

    /// Deserialize nodes from JSON
    private func deserializeNodes(from json: String, folderURL: URL) -> [FunctionNode]? {
        guard let jsonData = json.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            print("❌ Failed to deserialize JSON")
            return nil
        }
        
        var nodes: [FunctionNode] = []
        
        for item in items {
            guard let name = item["name"] as? String,
                  let path = item["path"] as? String,
                  let isDirectory = item["isDirectory"] as? Bool else {
                continue
            }
            
            let url = URL(fileURLWithPath: path)
            
            if isDirectory {
                // Recreate folder node
                nodes.append(createFolderNode(for: url))
            } else {
                // Recreate file node
                nodes.append(createFileNode(for: url))
            }
        }
        
        return nodes
    }
    
    // MARK: - Provide Functions
    
    func provideFunctions() -> [FunctionNode] {
        print("🔍 [FinderLogic] provideFunctions() called")
        
//        let finderWindowsNode = createFinderWindowsNode()
        let favoriteFoldersNode = createFavoriteFoldersNode()

        return [favoriteFoldersNode]  // Clean Ring 0!
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
        nodeCache.removeAll()
        // NEW: Also clear database cache on explicit refresh
//        DatabaseManager.shared.clearAllFolderCache()
    }
    
    // MARK: - Dynamic Loading (WITH DATABASE INTEGRATION)

    func loadChildren(for node: FunctionNode) async -> [FunctionNode] {
        print("📂 [FinderLogic] loadChildren called for: \(node.name)")
        
        guard let metadata = node.metadata,
              let urlString = metadata["folderURL"] as? String else {
            print("❌ No folderURL in metadata")
            return []
        }
        
        let folderURL = URL(fileURLWithPath: urlString)
        let cacheKey = folderURL.path
        
        // 👇 NEW: Get custom max items from metadata
        let customMaxItems = metadata["maxItems"] as? Int
        
        // 1. CHECK DATABASE FIRST
        if !DatabaseManager.shared.isCacheStale(for: cacheKey) {
            if let cached = DatabaseManager.shared.getFolderCache(for: cacheKey) {
                print("⚡ [FinderLogic] Using DATABASE cache for: \(node.name) (\(cached.itemCount) items)")
                
                // Deserialize from JSON
                if let nodes = deserializeNodes(from: cached.itemsJSON, folderURL: folderURL) {
                    // Apply custom limit if specified
                    if let limit = customMaxItems {
                        print("✂️ [FinderLogic] Applying custom limit: \(limit) items")
                        return Array(nodes.prefix(limit))
                    }
                    return nodes
                }
            }
        }
        
        // 2. CACHE MISS OR STALE - LOAD FROM DISK
        print("🔄 [START] Loading from disk: \(folderURL.path)")
        let startTime = Date()
        
        let nodes: [FunctionNode] = await Task.detached(priority: .userInitiated) { [weak self] () -> [FunctionNode] in
            guard let self = self else {
                print("❌ [FinderLogic] Self deallocated during load")
                return []
            }
            print("🧵 [BACKGROUND] Started loading: \(folderURL.path)")
            let result = self.getFolderContents(at: folderURL, maxItems: customMaxItems)  // 👈 Pass custom limit
            print("🧵 [BACKGROUND] Finished loading: \(folderURL.path) - \(result.count) items")
            return result
        }.value
        
        let elapsed = Date().timeIntervalSince(startTime)
        print("✅ [END] Loaded \(nodes.count) nodes in \(String(format: "%.2f", elapsed))s")
        
        // 3. SAVE TO DATABASE
        let itemsJSON = serializeNodes(nodes)
        let cacheEntry = FolderCacheEntry(
            path: cacheKey,
            lastScanned: Int(Date().timeIntervalSince1970),
            itemsJSON: itemsJSON,
            itemCount: nodes.count
        )
        DatabaseManager.shared.saveFolderCache(cacheEntry)
        
        // 4. RECORD USAGE
        DatabaseManager.shared.updateFolderAccess(path: cacheKey)
        
        return nodes
    }
    
    private func createFavoriteFoldersNode() -> FunctionNode {
        // Get favorites from database
        let favoritesFromDB = DatabaseManager.shared.getFavoriteFolders()
        
        // If no favorites in database, add defaults
        if favoritesFromDB.isEmpty {
            print("📁 [FinderLogic] No favorites found - adding defaults")
            addDefaultFavorites()
            // Fetch again after adding defaults
            return createFavoriteFoldersNode()
        }
        
        let favoriteChildren = favoritesFromDB.map { (folder, settings) in
            createFavoriteFolderEntry(
                name: folder.title,
                path: URL(fileURLWithPath: folder.path),
                icon: NSImage(named: "folder") ?? NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage(),
                settings: settings
            )
        }
        
        return FunctionNode(
            id: "favorite-folders-section",
            name: "Folders",
            icon: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage(),
            children: favoriteChildren,
            preferredLayout: .partialSlice,
            slicePositioning: .center,
            onLeftClick: .expand,
            onRightClick: .expand,
            onMiddleClick: .expand,
            onBoundaryCross: .expand
        )
    }

    /// Add default favorites on first run
    private func addDefaultFavorites() {
        // Downloads
        if let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            let settings = FavoriteFolderSettings(
                maxItems: 20,
                preferredLayout: nil,
                itemAngleSize: nil,
                slicePositioning: nil,
                childRingThickness: nil,
                childIconSize: nil
            )
            _ = DatabaseManager.shared.addFavoriteFolder(
                path: downloadsURL.path,
                title: "Downloads",
                settings: settings
            )
        }
        
        // Git folder (if it exists)
        let gitPath = "/Users/timothy/Files/Git/"
        if FileManager.default.fileExists(atPath: gitPath) {
            _ = DatabaseManager.shared.addFavoriteFolder(
                path: gitPath,
                title: "Git",
                settings: nil  // Use all defaults
            )
        }
        
        // Screenshots (if it exists)
        let screenshotsPath = "/Users/timothy/Library/CloudStorage/Dropbox/Screenshots/"
        if FileManager.default.fileExists(atPath: screenshotsPath) {
            let settings = FavoriteFolderSettings(
                maxItems: 10,
                preferredLayout: nil,
                itemAngleSize: nil,
                slicePositioning: nil,
                childRingThickness: nil,
                childIconSize: nil
            )
            _ = DatabaseManager.shared.addFavoriteFolder(
                path: screenshotsPath,
                title: "Screenshots",
                settings: settings
            )
        }
        
        print("✅ [FinderLogic] Added default favorites")
    }
    
    /// Get icon for folder (from database or system default)
    private func getIconForFolder(_ folder: FolderEntry) -> NSImage {
        // If custom icon stored in database, use it (future feature)
        if let iconName = folder.icon {
            if let icon = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
                return icon
            }
        }
        
        // Otherwise use system folder icon
        return NSWorkspace.shared.icon(forFile: folder.path)
    }

    private func createFavoriteFolderEntry(name: String, path: URL, icon: NSImage, settings: FavoriteFolderSettings) -> FunctionNode {
        var metadata: [String: Any] = ["folderURL": path.path]
        
        // Add custom max items if specified
        if let maxItems = settings.maxItems {
            metadata["maxItems"] = maxItems
        }
        
        // Convert string settings to enums with defaults
        let layout: LayoutStyle = {
            guard let layoutString = settings.preferredLayout else { return .fullCircle }
            return layoutString == "partialSlice" ? .partialSlice : .fullCircle
        }()
        
        let positioning: SlicePositioning = {
            guard let posString = settings.slicePositioning else { return .startClockwise }
            switch posString {
            case "startCounterClockwise": return .startCounterClockwise
            case "center": return .center
            default: return .startClockwise
            }
        }()
        
        // Get numeric settings with defaults
        let itemAngle = settings.itemAngleSize.map { CGFloat($0) }
        let childThickness = settings.childRingThickness.map { CGFloat($0) }
        let childIcon = settings.childIconSize.map { CGFloat($0) }
        
        return FunctionNode(
            id: "favorite-\(path.path)",
            name: name,
            icon: icon,
            children: nil,
            preferredLayout: layout,
            itemAngleSize: itemAngle,
            showLabel: true,
            
            childRingThickness: childThickness,
            childIconSize: childIcon,
            
            slicePositioning: positioning,
            
            metadata: metadata,
            providerId: self.providerId,
            
            onLeftClick: .navigateInto,
            onRightClick: .expand,
            onMiddleClick: .executeKeepOpen {
                DatabaseManager.shared.updateFolderAccess(path: path.path)
                NSWorkspace.shared.open(path)
            },
            onBoundaryCross: .doNothing
        )
    }
    
    /// Convert LayoutStyle enum to database string
    private func layoutStyleToString(_ layout: LayoutStyle) -> String {
        switch layout {
        case .fullCircle: return "fullCircle"
        case .partialSlice: return "partialSlice"
        }
    }

    /// Convert SlicePositioning enum to database string
    private func slicePositioningToString(_ positioning: SlicePositioning) -> String {
        switch positioning {
        case .startClockwise: return "startClockwise"
        case .startCounterClockwise: return "startCounterClockwise"
        case .center: return "center"
        }
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
            
            slicePositioning: .center,
            
            onLeftClick: .expand,
            onRightClick: .execute { [weak self] in
                self?.openNewFinderWindow()
            },
            onMiddleClick: .expand,
            onBoundaryCross: .expand
        )
    }
    
    // MARK: - Downloads Files Section (DRAGGABLE!)
    
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
        let folderIcon = FolderIconProvider.shared.getIcon(for: url, size: 64, cornerRadius: 8)
        
        print("📁 [FinderLogic] Creating folder node with metadata for: \(folderName)")
        
        return FunctionNode(
            id: "folder-\(url.path)",
            name: folderName,
            icon: folderIcon,
            children: nil,
            contextActions: [
                StandardContextActions.showInFinder(url),
                StandardContextActions.deleteFile(url)
            ],
            preferredLayout: .partialSlice,
            itemAngleSize: 15,
            previewURL: url,
            showLabel: true,
            slicePositioning: .center,
            
            metadata: ["folderURL": url.path],
            providerId: self.providerId,
            onLeftClick: .navigateInto,
            onRightClick: .expand,
            onMiddleClick: .executeKeepOpen {
                print("📂 Middle-click opening folder: \(folderName)")
                NSWorkspace.shared.open(url)
            },
            onBoundaryCross: .doNothing
        )
    }

    // Get folder contents (files and subfolders)
    private func getFolderContents(at url: URL, maxItems: Int? = nil) -> [FunctionNode] {
        print("📂 [getFolderContents] START: \(url.path)")
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .nameKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            
            print("📂 [getFolderContents] Found \(contents.count) items")
            
            let sortedContents = sortContents(contents, by: sortOrder)
            
            // Use custom limit if provided, otherwise use default
            let itemLimit = maxItems ?? maxItemsPerFolder
            let limitedContents = Array(sortedContents.prefix(itemLimit))
            
            print("📂 [getFolderContents] Processing \(limitedContents.count) items (limit: \(itemLimit))")
            
            var nodes: [FunctionNode] = []
            for (index, contentURL) in limitedContents.enumerated() {
                print("   [\(index+1)/\(limitedContents.count)] Processing: \(contentURL.lastPathComponent)")
                let node = createDraggableFileNode(for: contentURL)
                nodes.append(node)
            }
            
            print("✅ [getFolderContents] END: Created \(nodes.count) nodes")
            return nodes
            
        } catch {
            print("❌ [getFolderContents] Failed: \(error)")
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

    // Extract file node creation to separate method
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
            slicePositioning: .center,
            
            
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
//    private func createRoundedIcon(for url: URL, size: NSSize, cornerRadius: CGFloat) -> NSImage {
//        let fileIcon = NSWorkspace.shared.icon(forFile: url.path)
//        let roundedIcon = NSImage(size: size)
//        
//        roundedIcon.lockFocus()
//        
//        // Draw background with rounded corners
//        let rect = NSRect(origin: .zero, size: size)
//        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
//        
//        // Optional: Add subtle background color
//        NSColor.controlBackgroundColor.withAlphaComponent(0.1).setFill()
//        path.fill()
//        
//        // Clip to rounded rect
//        path.addClip()
//        
//        // Draw the icon slightly smaller to add padding
//        let padding: CGFloat = 8
//        let iconRect = rect.insetBy(dx: padding, dy: padding)
//        fileIcon.draw(
//            in: iconRect,
//            from: NSRect(origin: .zero, size: fileIcon.size),
//            operation: .sourceOver,
//            fraction: 1.0
//        )
//        
//        roundedIcon.unlockFocus()
//        
//        return roundedIcon
//    }
    
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
        
        // For non-images, use FileIconProvider
        return FileIconProvider.shared.getIcon(for: url, size: thumbnailSize.width, cornerRadius: cornerRadius)
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
