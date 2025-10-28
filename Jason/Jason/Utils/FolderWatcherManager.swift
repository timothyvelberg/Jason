//
//  FolderWatcherManager.swift
//  Jason
//
//  Manages file system watching for favorite heavy folders
//  NOW WITH PROACTIVE CACHE REFRESH - cache updates in background when files change
//

import Foundation
import AppKit

/// Manages file system watching for favorite heavy folders to keep cache synchronized
class FolderWatcherManager {
    static let shared = FolderWatcherManager()
    
    // Track active watchers by folder path
    private var watchers: [String: FolderWatcher] = [:]
    private let watcherQueue = DispatchQueue(label: "com.jason.folderwatcher", qos: .utility)
    
    // Debouncing configuration
    private var pendingRefreshes: [String: DispatchWorkItem] = [:]
    private let debounceInterval: TimeInterval = 1.0 // Wait 1s after last change
    
    private init() {
        print("[FolderWatcher] 🎬 Manager initialized")
    }
    
    // MARK: - Public API
    
    /// Start watching all favorite heavy folders
    func startWatchingFavorites() {
        print("🔍 [FolderWatcher] ========== Starting Favorite Watchers ==========")
        
        // Get all database data on MAIN thread FIRST (avoid threading issues)
        let favoriteFolders = DatabaseManager.shared.getFavoriteFolders()
        print("🔍 [FolderWatcher] Found \(favoriteFolders.count) favorite folders total")
        
        // Build list of folders to watch (also check heavy status on main thread)
        var foldersToWatch: [(path: String, name: String)] = []
        for (folder, _) in favoriteFolders {
            print("🔍 [FolderWatcher] Checking: '\(folder.title)'")
            print("   📂 Path: \(folder.path)")
            
            let isHeavy = DatabaseManager.shared.isHeavyFolder(path: folder.path)
            print("   ⚖️ Is heavy: \(isHeavy)")
            
            if isHeavy {
                foldersToWatch.append((path: folder.path, name: folder.title))
                print("   ✅ Will watch this folder")
            } else {
                print("   ⏭️ Skipping (not marked as heavy)")
            }
        }
        
        print("🔍 [FolderWatcher] Total folders to watch: \(foldersToWatch.count)")
        print("🔍 [FolderWatcher] ===============================================")
        
        // Now dispatch to background thread with the data we already fetched
        watcherQueue.async { [weak self] in
            guard let self = self else { return }
            
            var watchedCount = 0
            for folder in foldersToWatch {
                self.startWatching(path: folder.path, itemName: folder.name)
                watchedCount += 1
            }
            
            print("[FolderWatcher] 👀 Started watching \(watchedCount) favorite heavy folders")
        }
    }
    
    /// Start watching a specific folder
    func startWatching(path: String, itemName: String) {
        watcherQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Don't create duplicate watchers
            guard self.watchers[path] == nil else {
                print("[FolderWatcher] ℹ️ Already watching: \(itemName)")
                return
            }
            
            // Verify folder exists
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                print("[FolderWatcher] ⚠️ Path doesn't exist or isn't a directory: \(path)")
                return
            }
            
            // Create watcher
            let watcher = FolderWatcher(
                path: path,
                name: itemName,
                onChange: { [weak self] changedPath in
                    self?.handleFolderChange(path: changedPath, name: itemName)
                }
            )
            
            self.watchers[path] = watcher
            print("[FolderWatcher] ✅ Started watching: \(itemName) (\(path))")
        }
    }
    
    /// Stop watching a specific folder
    func stopWatching(path: String) {
        watcherQueue.async { [weak self] in
            guard let self = self else { return }
            
            if let watcher = self.watchers[path] {
                watcher.stop()
                self.watchers.removeValue(forKey: path)
                print("[FolderWatcher] 🛑 Stopped watching: \(path)")
            }
        }
    }
    
    /// Stop watching all folders
    func stopAll() {
        watcherQueue.async { [weak self] in
            guard let self = self else { return }
            
            for (_, watcher) in self.watchers {
                watcher.stop()
            }
            self.watchers.removeAll()
            print("[FolderWatcher] 🛑 Stopped watching all folders")
        }
    }
    
    /// Get list of currently watched folders
    func getWatchedFolders() -> [String] {
        return Array(watchers.keys)
    }
    
    // MARK: - Private Methods
    
    private func handleFolderChange(path: String, name: String) {
        // Cancel any pending refresh for this folder
        pendingRefreshes[path]?.cancel()
        
        // Create new debounced refresh
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            print("[FolderWatcher] 📂 Change detected in: \(name)")
            print("[FolderWatcher] 🔄 Refreshing cache in background...")
            
            // 🆕 PROACTIVE REFRESH: Update cache with new contents
            self.refreshCacheInBackground(path: path, name: name)
            
            // Remove from pending
            self.pendingRefreshes.removeValue(forKey: path)
        }
        
        pendingRefreshes[path] = workItem
        
        // Execute after debounce interval
        watcherQueue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
    
    // MARK: - Proactive Cache Refresh
    
    /// Refresh cache in background when file changes are detected
    private func refreshCacheInBackground(path: String, name: String) {
        let folderURL = URL(fileURLWithPath: path)
        
        // Get folder settings from database
        let favoriteFolders = DatabaseManager.shared.getFavoriteFolders()
        guard let favoriteFolder = favoriteFolders.first(where: { $0.folder.path == path }) else {
            print("[FolderWatcher] ⚠️ Folder '\(name)' not in favorites, just invalidating")
            DatabaseManager.shared.invalidateEnhancedCache(for: path)
            return
        }
        
        let maxItems = favoriteFolder.settings.maxItems ?? 20
        let sortOrder = favoriteFolder.settings.contentSortOrder ?? .modifiedNewest
        
        print("[FolderWatcher] 📊 Reloading contents: max=\(maxItems), sort=\(sortOrder.displayName)")
        
        // Load folder contents
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .contentModificationDateKey,
                    .fileSizeKey,
                    .nameKey
                ],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            
            print("[FolderWatcher] 📂 Found \(contents.count) items")
            
            // 🎯 Sort using the shared utility
            let sortedContents = FolderSortingUtility.sortURLs(contents, by: sortOrder)
            
            // Limit to configured max items
            let limitedContents = Array(sortedContents.prefix(maxItems))
            
            print("[FolderWatcher] 📊 Processing \(limitedContents.count) items (after limit)")
            
            // Create enhanced items
            var enhancedItems: [EnhancedFolderItem] = []
            for url in limitedContents {
                let values = try? url.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .contentModificationDateKey,
                    .fileSizeKey
                ])
                
                let isDir = values?.isDirectory ?? false
                let modDate = values?.contentModificationDate ?? Date()
                let fileSize = Int64(values?.fileSize ?? 0)
                let fileExtension = url.pathExtension.lowercased()
                
                enhancedItems.append(EnhancedFolderItem(
                    name: url.lastPathComponent,
                    path: url.path,
                    isDirectory: isDir,
                    modificationDate: modDate,
                    fileExtension: fileExtension,
                    fileSize: fileSize,
                    hasCustomIcon: false,
                    isImageFile: ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"].contains(fileExtension),
                    thumbnailData: nil,  // Skip thumbnails in background refresh for speed
                    folderConfigJSON: nil
                ))
            }
            
            // Clear old cache and save new
            DatabaseManager.shared.invalidateEnhancedCache(for: path)
            DatabaseManager.shared.saveEnhancedFolderContents(folderPath: path, items: enhancedItems)
            
            print("[FolderWatcher] ✅ Cache refreshed - \(enhancedItems.count) items ready!")
            print("[FolderWatcher] 🎯 Next time '\(name)' is opened, it will load instantly with fresh data")
            
        } catch {
            print("[FolderWatcher] ❌ Failed to refresh cache: \(error)")
            // Fallback: just invalidate so next visit will reload
            DatabaseManager.shared.invalidateEnhancedCache(for: path)
        }
    }
}

// MARK: - Individual Folder Watcher

/// Watches a single folder for file system changes using FSEvents
private class FolderWatcher {
    let path: String
    let name: String
    let onChange: (String) -> Void
    
    private var eventStream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.jason.folderwatcher.stream", qos: .utility)
    
    init(path: String, name: String, onChange: @escaping (String) -> Void) {
        self.path = path
        self.name = name
        self.onChange = onChange
        
        start()
    }
    
    private func start() {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        let callback: FSEventStreamCallback = { (
            streamRef: ConstFSEventStreamRef,
            clientCallBackInfo: UnsafeMutableRawPointer?,
            numEvents: Int,
            eventPaths: UnsafeMutableRawPointer,
            eventFlags: UnsafePointer<FSEventStreamEventFlags>,
            eventIds: UnsafePointer<FSEventStreamEventId>
        ) in
            guard let info = clientCallBackInfo else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            
            // Get paths
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as! [String]
            
            // Check if any relevant changes occurred
            for i in 0..<numEvents {
                let flags = eventFlags[i]
                let path = paths[i]
                
                // Filter for relevant events (created, removed, modified, renamed)
                let relevantFlags: FSEventStreamEventFlags =
                    FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated) |
                    FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) |
                    FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified) |
                    FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)
                
                if flags & relevantFlags != 0 {
                    watcher.onChange(watcher.path)
                    break // One change is enough to trigger refresh
                }
            }
        }
        
        // Create event stream
        eventStream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // Latency in seconds
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )
        
        guard let stream = eventStream else {
            print("[FolderWatcher] ❌ Failed to create event stream for: \(name)")
            return
        }
        
        // Schedule on queue
        FSEventStreamSetDispatchQueue(stream, queue)
        
        // Start monitoring
        if FSEventStreamStart(stream) {
            print("[FolderWatcher] 🎬 Monitoring started for: \(name)")
        } else {
            print("[FolderWatcher] ❌ Failed to start monitoring for: \(name)")
        }
    }
    
    func stop() {
        guard let stream = eventStream else { return }
        
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        
        eventStream = nil
        print("[FolderWatcher] 🛑 Monitoring stopped for: \(name)")
    }
    
    deinit {
        stop()
    }
}
