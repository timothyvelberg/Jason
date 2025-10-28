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
    
    private let maxItemsPerFolder: Int = 20
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
           let folderPath = folderURL.path
           let db = DatabaseManager.shared
           
           // Get custom max items from metadata
           let customMaxItems = metadata["maxItems"] as? Int
           
           // 🔍 DIAGNOSTIC: Get sort order EARLY
           let requestedSortOrder = getSortOrderForFolder(path: folderPath)
           print("🎯 [SORT DIAGNOSTIC] Folder: \(node.name)")
           print("   Requested sort order: \(requestedSortOrder.displayName) (\(requestedSortOrder.rawValue))")
           
           // ⚡ STEP 1: Record that we're accessing this folder
           db.recordFolderAccess(folderPath: folderPath)
           
           // ⚡ STEP 2: Check if this is a HEAVY folder and try ENHANCED CACHE
           if db.isHeavyFolder(path: folderPath) {
               print("📦 [FinderLogic] Heavy folder detected: \(node.name)")
               
               if let cachedItems = db.getEnhancedCachedFolderContents(folderPath: folderPath) {
                   print("⚡ [EnhancedCache] CACHE HIT! Loaded \(cachedItems.count) items instantly")
                   
                   // Convert to nodes
                   var nodes = cachedItems.map { item in
                       if item.isDirectory {
                           return createFolderNodeFromCache(item: item)
                       } else {
                           return createFileNodeFromCache(item: item)
                       }
                   }
                   
                   // 🔍 DIAGNOSTIC: Log BEFORE sorting
                   print("🔍 [BEFORE SORT] First 5 items:")
                   for (i, node) in nodes.prefix(5).enumerated() {
                       print("   [\(i+1)] \(node.name)")
                   }
                   
                   // 🎯 Apply current sort order preference
                   nodes = sortNodes(nodes, by: requestedSortOrder)
                   
                   // 🔍 DIAGNOSTIC: Log AFTER sorting
                   print("✅ [AFTER SORT] First 5 items:")
                   for (i, node) in nodes.prefix(5).enumerated() {
                       print("   [\(i+1)] \(node.name)")
                   }
                   
                   // Apply custom limit if specified
                   if let limit = customMaxItems {
                       print("✂️ [FinderLogic] Applying custom limit: \(limit) items")
                       return Array(nodes.prefix(limit))
                   }
                   
                   return nodes
               } else {
                   print("⚠️ [EnhancedCache] Cache miss for heavy folder - will reload and cache")
               }
           }
           
           // 💿 STEP 3: CACHE MISS OR NOT A HEAVY FOLDER - Load from disk
           print("💿 [START] Loading from disk: \(folderURL.path)")
           let startTime = Date()
           
           // 🔍 Check ACTUAL folder size BEFORE limiting display
           let actualItemCount = countFolderItems(at: folderURL)
           print("📊 [FinderLogic] Actual folder contains: \(actualItemCount) items")
           
           // 🔧 FIXED: Pass the sort order to getFolderContents
           let nodes: [FunctionNode] = await Task.detached(priority: .userInitiated) { [weak self] () -> [FunctionNode] in
               guard let self = self else {
                   print("❌ [FinderLogic] Self deallocated during load")
                   return []
               }
               print("🧵 [BACKGROUND] Started loading: \(folderURL.path)")
               
               // 🔧 NEW: Pass sort order parameter
               let result = self.getFolderContents(at: folderURL, sortOrder: requestedSortOrder, maxItems: customMaxItems)
               
               print("🧵 [BACKGROUND] Finished loading: \(folderURL.path) - \(result.count) items (displayed)")
               return result
           }.value
           
           let elapsed = Date().timeIntervalSince(startTime)
           print("✅ [END] Loaded \(nodes.count) nodes (displayed) in \(String(format: "%.2f", elapsed))s")
           
           // 📊 STEP 4: If folder has >100 items (ACTUAL COUNT), mark as HEAVY and cache it
           if actualItemCount > 100 {
               print("📊 [EnhancedCache] Folder has \(actualItemCount) items - marking as HEAVY and caching with thumbnails")
               
               // Mark as heavy folder with ACTUAL count
               db.markAsHeavyFolder(path: folderPath, itemCount: actualItemCount)
               
               // Convert nodes to EnhancedFolderItem format WITH THUMBNAILS
               let enhancedItems = convertToEnhancedFolderItems(nodes: nodes, folderURL: folderURL)
               
               // Save to Enhanced Cache
               db.saveEnhancedFolderContents(folderPath: folderPath, items: enhancedItems)
               print("💾 [EnhancedCache] Cached \(nodes.count) items (with thumbnails) for future instant loads!")
               print("   (Folder actually has \(actualItemCount) items, but caching \(nodes.count) displayed items)")
           } else {
               print("ℹ️ [EnhancedCache] Folder has only \(actualItemCount) items - not caching (threshold: 100)")
           }
           
           // 📝 STEP 5: Update folder access tracking (for usage stats)
           db.updateFolderAccess(path: folderPath)
           
           return nodes
       }
    
    // MARK: - Sorting Helper Methods

    /// Get the sort order preference for a folder
      private func getSortOrderForFolder(path: String) -> FolderSortOrder {
          let favoriteFolders = DatabaseManager.shared.getFavoriteFolders()
          
          if let favoriteFolder = favoriteFolders.first(where: { $0.folder.path == path }),
             let sortOrder = favoriteFolder.settings.contentSortOrder {
              return sortOrder
          }
          
          // Default to modified newest
          return .modifiedNewest
      }

      /// Sort nodes according to the sort order
      private func sortNodes(_ nodes: [FunctionNode], by sortOrder: FolderSortOrder) -> [FunctionNode] {
          print("🔄 [sortNodes] Sorting \(nodes.count) nodes by: \(sortOrder.displayName)")
          
          // Extract URLs from nodes for sorting
          var urlNodePairs: [(URL, FunctionNode)] = []
          
          for node in nodes {
              if let previewURL = node.previewURL {
                  urlNodePairs.append((previewURL, node))
              } else if let metadata = node.metadata,
                        let urlString = metadata["folderURL"] as? String {
                  urlNodePairs.append((URL(fileURLWithPath: urlString), node))
              }
          }
          
          // 🔍 DIAGNOSTIC: Log URLs being sorted
          print("🔍 [sortNodes] URLs to sort:")
          for (i, pair) in urlNodePairs.prefix(5).enumerated() {
              print("   [\(i+1)] \(pair.0.lastPathComponent)")
          }
          
          // Sort the URLs using existing sort logic
          let urls = urlNodePairs.map { $0.0 }
          let sortedURLs = sortURLs(urls, sortOrder: sortOrder)
          
          // 🔍 DIAGNOSTIC: Log sorted URLs
          print("🔍 [sortNodes] Sorted URLs:")
          for (i, url) in sortedURLs.prefix(5).enumerated() {
              print("   [\(i+1)] \(url.lastPathComponent)")
          }
          
          // Reorder nodes to match sorted URLs
          var sortedNodes: [FunctionNode] = []
          for sortedURL in sortedURLs {
              if let pair = urlNodePairs.first(where: { $0.0 == sortedURL }) {
                  sortedNodes.append(pair.1)
              }
          }
          
          return sortedNodes
      }

    // MARK: - Enhanced Cache Helper Methods

    /// Create a file node from cached data WITHOUT disk I/O
    private func createFileNodeFromCache(item: EnhancedFolderItem) -> FunctionNode {
        let url = URL(fileURLWithPath: item.path)
        let fileName = item.name
        
        // 🎨 Use cached thumbnail if available, otherwise create icon from metadata
        let icon: NSImage
        if let thumbnailData = item.thumbnailData, let cachedThumbnail = NSImage(data: thumbnailData) {
            // ⚡ INSTANT! No disk access!
            icon = cachedThumbnail
            print("🖼️ [FinderLogic] Using cached thumbnail for: \(fileName)")
        } else if item.hasCustomIcon {
            // Use IconProvider with cached extension (fast, no disk read)
            icon = IconProvider.shared.getFileIcon(for: url, size: 64, cornerRadius: 8)
            print("🎨 [FinderLogic] Using custom icon for: \(fileName)")
        } else {
            // Fallback to system icon
            icon = IconProvider.shared.getFileIcon(for: url, size: 64, cornerRadius: 8)
            print("📄 [FinderLogic] Using system icon for: \(fileName)")
        }
        
        return FunctionNode(
            id: "file-\(item.path)",
            name: fileName,
            icon: icon,
            
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
            
            onLeftClick: .drag(DragProvider(
                fileURLs: [url],
                dragImage: icon,
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
            
            onRightClick: .expand,
            
            onMiddleClick: .executeKeepOpen {
                print("🖱️ Middle-click opening: \(fileName)")
                NSWorkspace.shared.open(url)
            },
            
            onBoundaryCross: .doNothing
        )
    }

    /// Create a folder node from cached data WITHOUT disk I/O
    private func createFolderNodeFromCache(item: EnhancedFolderItem) -> FunctionNode {
        let url = URL(fileURLWithPath: item.path)
        let folderName = item.name
        
        // Get folder icon (uses cached config if available)
        let icon = IconProvider.shared.getFolderIcon(for: url, size: 64, cornerRadius: 8)
        
        print("📁 [FinderLogic] Creating folder node from cache for: \(folderName)")
        
        return FunctionNode(
            id: "folder-\(item.path)",
            name: folderName,
            icon: icon,
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
            
            metadata: [
                "folderURL": item.path,
            ],
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

    /// Convert FunctionNodes to EnhancedFolderItems WITH THUMBNAILS
    private func convertToEnhancedFolderItems(nodes: [FunctionNode], folderURL: URL) -> [EnhancedFolderItem] {
        return nodes.compactMap { node -> EnhancedFolderItem? in
            var path: String?
            var isDirectory = false
            var modDate = Date()
            var fileExtension = ""
            var fileSize: Int64 = 0
            var thumbnailData: Data?
            
            // Check if it's a folder node
            if let metadata = node.metadata,
               let folderURLString = metadata["folderURL"] as? String {
                path = folderURLString
                isDirectory = true
            }
            // Check if it's a file node
            else if let previewURL = node.previewURL {
                path = previewURL.path
                isDirectory = false
                fileExtension = previewURL.pathExtension.lowercased()
                
                // Get file attributes
                if let attrs = try? FileManager.default.attributesOfItem(atPath: previewURL.path) {
                    if let date = attrs[.modificationDate] as? Date {
                        modDate = date
                    }
                    if let size = attrs[.size] as? Int64 {
                        fileSize = size
                    }
                }
                
                // 🎨 EXTRACT THUMBNAIL from the already-generated icon!
                let iconImage = node.icon
                if let tiffData = iconImage.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    thumbnailData = pngData
                }
            }
            
            guard let itemPath = path else { return nil }
            
            // Check if file extension has custom icon
            let hasCustomIcon = !fileExtension.isEmpty && IconProvider.shared.hasCustomFileIcon(for: fileExtension)
            
            // Check if it's an image file
            let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"]
            let isImageFile = imageExtensions.contains(fileExtension)
            
            return EnhancedFolderItem(
                name: node.name,
                path: itemPath,
                isDirectory: isDirectory,
                modificationDate: modDate,
                fileExtension: fileExtension,
                fileSize: fileSize,
                hasCustomIcon: hasCustomIcon,
                isImageFile: isImageFile,
                thumbnailData: thumbnailData,  // 🎨 THE THUMBNAIL!
                folderConfigJSON: nil  // TODO: Add folder config if needed
            )
        }
    }

    /// Count actual items in folder WITHOUT loading them all
    private func countFolderItems(at url: URL) -> Int {
        do {
            let items = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            return items.count
        } catch {
            print("⚠️ [FinderLogic] Failed to count folder items: \(error)")
            return 0
        }
    }

    // MARK: - Replace the createFavoriteFoldersNode method with this:

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
                folderEntry: folder,  // Pass the entire FolderEntry
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
            onBoundaryCross: .expand
        )
    }

    // MARK: - Replace the createFavoriteFolderEntry method with this:
    
    // Updated createFavoriteFolderEntry method for FinderLogic.swift

    private func createFavoriteFolderEntry(folderEntry: FolderEntry, settings: FavoriteFolderSettings) -> FunctionNode {
        let path = URL(fileURLWithPath: folderEntry.path)
        var metadata: [String: Any] = [
            "folderURL": folderEntry.path
        ]
        
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
        
        // Generate folder icon based on database settings
        let folderIcon: NSImage = {
            // Use custom folder if baseAsset is not default OR if symbol is provided
            if folderEntry.baseAsset != "folder-blue" || folderEntry.iconName != nil {
                let symbolName = folderEntry.iconName ?? ""
                
                if !symbolName.isEmpty {
                    print("🎨 [FinderLogic] Custom folder '\(folderEntry.title)': \(folderEntry.baseAsset) + symbol '\(symbolName)'")
                } else {
                    print("🎨 [FinderLogic] Custom folder '\(folderEntry.title)': \(folderEntry.baseAsset)")
                }
                
                return IconProvider.shared.createCompositeIcon(
                    baseAssetName: folderEntry.baseAsset,
                    symbolName: symbolName,  // Empty string if no symbol (will be ignored)
                    symbolColor: .white,     // Always white for symbols
                    size: 64,
                    symbolSize: folderEntry.symbolSize,
                    cornerRadius: 8,
                    symbolOffset: -4  // Hardcoded offset
                )
            }
            
            // Default system folder icon
            print("📁 [FinderLogic] Using default system icon for '\(folderEntry.title)'")
            return IconProvider.shared.getFolderIcon(for: path, size: 64, cornerRadius: 8)
        }()
        
        return FunctionNode(
            id: "favorite-\(path.path)",
            name: folderEntry.title,
            icon: folderIcon,
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

    /// Add default favorites on first run
    private func addDefaultFavorites() {
        // Downloads - Newest First (see latest downloads!)
        if let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            let settings = FavoriteFolderSettings(
                maxItems: 20,
                preferredLayout: nil,
                itemAngleSize: nil,
                slicePositioning: nil,
                childRingThickness: nil,
                childIconSize: nil,
                contentSortOrder: .modifiedNewest
            )
            _ = DatabaseManager.shared.addFavoriteFolder(
                path: downloadsURL.path,
                title: "Downloads",
                settings: settings
            )
        }
        
        // Git folder - Alphabetical (organized code!)
        let gitPath = "/Users/timothy/Files/Git/"
        if FileManager.default.fileExists(atPath: gitPath) {
            let settings = FavoriteFolderSettings(
                maxItems: nil,
                preferredLayout: nil,
                itemAngleSize: nil,
                slicePositioning: nil,
                childRingThickness: nil,
                childIconSize: nil,
                contentSortOrder: .alphabeticalAsc  // ← ADD THIS!
            )
            _ = DatabaseManager.shared.addFavoriteFolder(
                path: gitPath,
                title: "Git",
                settings: settings
            )
        }
        
        // Screenshots - Newest First (see latest captures!)
        let screenshotsPath = "/Users/timothy/Library/CloudStorage/Dropbox/Screenshots/"
        if FileManager.default.fileExists(atPath: screenshotsPath) {
            let settings = FavoriteFolderSettings(
                maxItems: 10,
                preferredLayout: nil,
                itemAngleSize: nil,
                slicePositioning: nil,
                childRingThickness: nil,
                childIconSize: nil,
                contentSortOrder: .modifiedNewest
            )
            _ = DatabaseManager.shared.addFavoriteFolder(
                path: screenshotsPath,
                title: "Screenshots",
                settings: settings
            )
        }
        
        print("✅ [FinderLogic] Added default favorites with smart sorting")
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
        
        // Get folder icon from database (will use custom icon if set, otherwise default)
        let folderIcon = IconProvider.shared.getFolderIconFromDatabase(
            for: path,
            size: 64
        )
        
        return FunctionNode(
            id: "favorite-\(path.path)",
            name: name,
            icon: folderIcon,  // Use database icon instead of hardcoded
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
    
    private func createCompositeIcon(baseAssetName: String, symbolName: String, symbolColor: NSColor, size: CGFloat, cornerRadius: CGFloat) -> NSImage {
        let compositeImage = NSImage(size: NSSize(width: size, height: size))
        
        compositeImage.lockFocus()
        
        // Draw base icon (your custom folder)
        if let baseImage = NSImage(named: baseAssetName) {
            let imageSize = baseImage.size
            let scale = min(size / imageSize.width, size / imageSize.height)
            let scaledWidth = imageSize.width * scale
            let scaledHeight = imageSize.height * scale
            
            let drawRect = NSRect(
                x: (size - scaledWidth) / 2,
                y: (size - scaledHeight) / 2,
                width: scaledWidth,
                height: scaledHeight
            )
            
            baseImage.draw(
                in: drawRect,
                from: NSRect(origin: .zero, size: baseImage.size),
                operation: .sourceOver,
                fraction: 1.0
            )
        }
        
        // Create colored SF Symbol with preserved aspect ratio
        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: size * 0.4, weight: .medium)
            if let configuredSymbol = symbol.withSymbolConfiguration(symbolConfig) {
                
                let symbolSize = configuredSymbol.size
                
                // Create colored version in its own context
                let coloredSymbol = NSImage(size: symbolSize)
                coloredSymbol.lockFocus()
                
                configuredSymbol.draw(
                    in: NSRect(origin: .zero, size: symbolSize),
                    from: NSRect(origin: .zero, size: symbolSize),
                    operation: .sourceOver,
                    fraction: 1.0
                )
                
                symbolColor.setFill()
                NSRect(origin: .zero, size: symbolSize).fill(using: .sourceAtop)
                
                coloredSymbol.unlockFocus()
                
                // Draw colored symbol centered on composite
                let symbolRect = NSRect(
                    x: (size - symbolSize.width) / 2,
                    y: (size - symbolSize.height) / 2 - 4,
                    width: symbolSize.width,
                    height: symbolSize.height
                )
                
                coloredSymbol.draw(in: symbolRect)
            }
        }
        
        compositeImage.unlockFocus()
        
        return compositeImage
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
    
    // MARK: - Downloads Files Section
    
    private func createDraggableFileNode(for url: URL) -> FunctionNode {
        
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

    private func createFolderNode(for url: URL) -> FunctionNode {
        let folderName = url.lastPathComponent
        
        print("📁 [FinderLogic] Creating folder node for: \(folderName)")
        
        return FunctionNode(
            id: "folder-\(url.path)",
            name: folderName,
            icon: IconProvider.shared.getFolderIcon(for: url, size: 64, cornerRadius: 8),
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
            
            metadata: [
                "folderURL": url.path,
            ],
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
    private func getFolderContents(at url: URL, sortOrder: FolderSortOrder, maxItems: Int? = nil) -> [FunctionNode] {
        print("📂 [getFolderContents] START: \(url.path)")
        print("🎯 [getFolderContents] Using sort order: \(sortOrder.displayName) (\(sortOrder.rawValue))")
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .nameKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            
            print("📂 [getFolderContents] Found \(contents.count) items")
            
            // 🔍 DIAGNOSTIC: Log BEFORE sorting
            print("🔍 [BEFORE SORT] First 5 items:")
            for (i, url) in contents.prefix(5).enumerated() {
                print("   [\(i+1)] \(url.lastPathComponent)")
            }
            
            // 🔧 FIXED: Use the NEW sortURLs method with FolderSortOrder
            let sortedContents = sortURLs(contents, sortOrder: sortOrder)
            
            // 🔍 DIAGNOSTIC: Log AFTER sorting
            print("✅ [AFTER SORT] First 5 items:")
            for (i, url) in sortedContents.prefix(5).enumerated() {
                print("   [\(i+1)] \(url.lastPathComponent)")
            }
            
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
        return IconProvider.shared.getFileIcon(for: url, size: thumbnailSize.width, cornerRadius: cornerRadius)
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
