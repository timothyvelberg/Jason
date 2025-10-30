//
//  FolderWatcherManager.swift
//  Jason
//
//  Manages file system watching for favorite heavy folders
//  NOW WITH QUEUED REFRESH SYSTEM - controlled CPU usage with operation queue
//

import Foundation
import AppKit

/// Manages file system watching for favorite heavy folders to keep cache synchronized
class FolderWatcherManager {
    static let shared = FolderWatcherManager()
    
    // Track active watchers by folder path
    private var watchers: [String: FolderWatcher] = [:]
    private let watcherQueue = DispatchQueue(label: "com.jason.folderwatcher", qos: .utility)
    
    // 🆕 OPERATION QUEUE: Limit concurrent refreshes to prevent CPU spikes
    private let refreshQueue = OperationQueue()
    
    // Debouncing configuration
    private var pendingRefreshes: [String: DispatchWorkItem] = [:]
    private let debounceInterval: TimeInterval = 1.0 // Wait 1s after last change
    
    private init() {
        // Configure refresh queue for controlled concurrency
        refreshQueue.maxConcurrentOperationCount = 2  // Max 2 folders refreshing at once
        refreshQueue.qualityOfService = .utility       // Background priority
        refreshQueue.name = "com.jason.folderrefresh"
        
//        print("[FolderWatcher] 🎬 Manager initialized (queue: max 2 concurrent)")
    }
    
    // MARK: - Public API
    
    /// Start watching all favorite heavy folders
    func startWatchingFavorites() {
//        print("🔍 [FolderWatcher] ========== Starting Favorite Watchers ==========")
        
        // Get all database data on MAIN thread FIRST (avoid threading issues)
        let favoriteFolders = DatabaseManager.shared.getFavoriteFolders()
//        print("🔍 [FolderWatcher] Found \(favoriteFolders.count) favorite folders total")
        
        // Build list of folders to watch (also check heavy status on main thread)
        var foldersToWatch: [(path: String, name: String)] = []
        for (folder, _) in favoriteFolders {
//            print("🔍 [FolderWatcher] Checking: '\(folder.title)'")
//            print("   📂 Path: \(folder.path)")
            
            let isHeavy = DatabaseManager.shared.isHeavyFolder(path: folder.path)
//            print("   ⚖️ Is heavy: \(isHeavy)")
            
            if isHeavy {
                foldersToWatch.append((path: folder.path, name: folder.title))
//                print("   ✅ Will watch this folder")
            } else {
//                print("   ⭕️ Skipping (not marked as heavy)")
            }
        }
        
//        print("🔍 [FolderWatcher] Total folders to watch: \(foldersToWatch.count)")
//        print("🔍 [FolderWatcher] ===============================================")
        
        // Now dispatch to background thread with the data we already fetched
        watcherQueue.async { [weak self] in
            guard let self = self else { return }
            
            var watchedCount = 0
            for folder in foldersToWatch {
                self.startWatching(path: folder.path, itemName: folder.name)
                watchedCount += 1
            }
            
//            print("[FolderWatcher] 👀 Started watching \(watchedCount) favorite heavy folders")
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
//            print("[FolderWatcher] ✅ Started watching: \(itemName) (\(path))")
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
            print("[FolderWatcher] 🔄 Queueing cache refresh...")
            
            // 🆕 QUEUE THE REFRESH: Add to operation queue
            self.queueRefresh(for: path, name: name)
            
            // Remove from pending
            self.pendingRefreshes.removeValue(forKey: path)
        }
        
        pendingRefreshes[path] = workItem
        
        // Execute after debounce interval
        watcherQueue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
    
    // MARK: - 🆕 Queued Refresh System
    
    /// Queue a refresh operation (with coalescing to prevent duplicates)
    private func queueRefresh(for path: String, name: String) {
        // 🎯 COALESCING: Check if this folder is already queued
        let alreadyQueued = refreshQueue.operations.contains { operation in
            guard let refreshOp = operation as? RefreshOperation else { return false }
            return refreshOp.path == path
        }
        
        if alreadyQueued {
            print("⏭️ [FolderWatcher] Coalescing: \(name) already queued, skipping duplicate")
            return
        }
        
        // Create and queue the refresh operation
        let operation = RefreshOperation(path: path, folderName: name)
        refreshQueue.addOperation(operation)
        
        let queueDepth = refreshQueue.operationCount
        let activeCount = refreshQueue.operations.filter { $0.isExecuting }.count
        print("⏳ [FolderWatcher] Queued refresh for \(name)")
        print("   📊 Queue: \(queueDepth) total, \(activeCount) active")
    }
    
    /// Manual refresh (for user-initiated refreshes)
    func forceRefresh(path: String, name: String) {
        print("🔄 [FolderWatcher] Force refresh requested for \(name)")
        queueRefresh(for: path, name: name)
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
//            print("[FolderWatcher] 🎬 Monitoring started for: \(name)")
            return
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
