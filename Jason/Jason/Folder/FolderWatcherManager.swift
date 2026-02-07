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
class FolderWatcherManager: LiveDataStream {
    static let shared = FolderWatcherManager()
    
    // MARK: - LiveDataStream Protocol
    
    var streamId: String { "folder-watcher" }
    
    var isMonitoring: Bool {
        // We're monitoring if we have any active watchers
        return !watchers.isEmpty
    }
    
    func startMonitoring() {
        startWatchingFavorites()
        startWatchingDynamicFileFolders()
    }
    
    func stopMonitoring() {
        stopAll()
    }
    
    // MARK: - Properties
    
    // Track active watchers by folder path
    private var watchers: [String: FolderWatcher] = [:]
    private let watcherQueue = DispatchQueue(label: "com.jason.folderwatcher", qos: .utility)
    
    // Limit concurrent refreshes to prevent CPU spikes
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
        
        // Get all database data on MAIN thread FIRST (avoid threading issues)
        let favoriteFolders = DatabaseManager.shared.getFavoriteFolders()
        
        // Build list of folders to watch (also check heavy status on main thread)
        var foldersToWatch: [(path: String, name: String)] = []
        for (folder, _) in favoriteFolders {
            
            let isHeavy = DatabaseManager.shared.isHeavyFolder(path: folder.path)
            if isHeavy {
                foldersToWatch.append((path: folder.path, name: folder.title))
            }
        }
        
        // Now dispatch to background thread with the data we already fetched
        watcherQueue.async { [weak self] in
            guard let self = self else { return }
            
            var watchedCount = 0
            for folder in foldersToWatch {
                self.startWatching(path: folder.path, itemName: folder.name)
                watchedCount += 1
            }
        }
    }
    
    /// Start watching folders used by dynamic files (that aren't already watched)
    func startWatchingDynamicFileFolders() {
        
        // Get all dynamic files
        let dynamicFiles = DatabaseManager.shared.getFavoriteDynamicFiles()
        print("[FolderWatcher] Found \(dynamicFiles.count) dynamic files total")
        
        // Get unique folder paths
        let uniqueFolderPaths = Set(dynamicFiles.map { $0.folderPath })
        print("[FolderWatcher] Unique source folders: \(uniqueFolderPaths.count)")
        
        // Build list of folders to watch
        var foldersToWatch: [(path: String, name: String)] = []
        
        for folderPath in uniqueFolderPaths {
            // Skip if already being watched (e.g., it's also a favorite folder)
            if watchers[folderPath] != nil {
                continue
            }
            
            // Verify folder exists
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folderPath, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                print("   Folder doesn't exist: \(folderPath)")
                continue
            }
            
            // Check if folder is heavy (>100 items) - if not, we still watch it for dynamic files
            // but we mark it as heavy so it gets cached
            let itemCount = countFolderItems(at: folderPath)
            let folderName = URL(fileURLWithPath: folderPath).lastPathComponent
            
            if itemCount > 100 {
                // Mark as heavy if not already
                if !DatabaseManager.shared.isHeavyFolder(path: folderPath) {
                    DatabaseManager.shared.markAsHeavyFolder(path: folderPath, itemCount: itemCount)
                    print("   Marked as heavy folder: \(folderName) (\(itemCount) items)")
                }
                foldersToWatch.append((path: folderPath, name: folderName))
                print("   Will watch: \(folderName)")
            } else {
                // Even for smaller folders, we might want to watch them for instant updates
                // For now, only watch heavy folders to keep overhead low
                print("   Skipping (only \(itemCount) items): \(folderName)")
            }
        }
        
        // Start watching on background thread
        watcherQueue.async { [weak self] in
            guard let self = self else { return }
            
            var watchedCount = 0
            for folder in foldersToWatch {
                self.startWatching(path: folder.path, itemName: folder.name)
                watchedCount += 1
            }
            
            if watchedCount > 0 {
                print("[FolderWatcher] Started watching \(watchedCount) dynamic file source folders")
            }
        }
    }
    
    /// Start watching a specific folder
    func startWatching(path: String, itemName: String) {
        watcherQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Don't create duplicate watchers
            guard self.watchers[path] == nil else {
                print("[FolderWatcher] Already watching: \(itemName)")
                return
            }
            
            // Verify folder exists
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                print("[FolderWatcher] Path doesn't exist or isn't a directory: \(path)")
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
        }
    }
    
    /// Stop watching a specific folder
    func stopWatching(path: String) {
        watcherQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Cancel any pending debounced refresh
            if let pending = self.pendingRefreshes[path] {
                pending.cancel()
                self.pendingRefreshes.removeValue(forKey: path)
            }
            
            if let watcher = self.watchers[path] {
                watcher.stop()
                self.watchers.removeValue(forKey: path)
                print("[FolderWatcher] Stopped watching: \(path)")
            }
        }
    }
    
    /// Stop watching all folders
    func stopAll() {
        watcherQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Cancel all pending refreshes
            for (_, pending) in self.pendingRefreshes {
                pending.cancel()
            }
            self.pendingRefreshes.removeAll()
            
            for (_, watcher) in self.watchers {
                watcher.stop()
            }
            self.watchers.removeAll()
            print("[FolderWatcher] Stopped watching all folders")
        }
    }
    
    /// Get list of currently watched folders (thread-safe)
    func getWatchedFolders() -> [String] {
        return watcherQueue.sync {
            Array(watchers.keys)
        }
    }
    
    /// Reconcile active watchers against current database state.
    /// Stops watchers for folders that are no longer needed by any favorite or dynamic file.
    /// Call this after removing a favorite folder or dynamic file from the database.
    func reconcileWatchers() {
        // Gather DB state on the calling thread (main) before dispatching
        let heavyFavoritePaths = Set(
            DatabaseManager.shared.getFavoriteFolders()
                .map { $0.folder.path }
                .filter { DatabaseManager.shared.isHeavyFolder(path: $0) }
        )
        
        let dynamicFileFolderPaths = Set(
            DatabaseManager.shared.getFavoriteDynamicFiles()
                .map { $0.folderPath }
        )
        
        let neededPaths = heavyFavoritePaths.union(dynamicFileFolderPaths)
        
        watcherQueue.async { [weak self] in
            guard let self = self else { return }
            
            let activePaths = Set(self.watchers.keys)
            let stalePaths = activePaths.subtracting(neededPaths)
            
            for path in stalePaths {
                // Cancel pending refresh
                if let pending = self.pendingRefreshes[path] {
                    pending.cancel()
                    self.pendingRefreshes.removeValue(forKey: path)
                }
                
                if let watcher = self.watchers[path] {
                    watcher.stop()
                    self.watchers.removeValue(forKey: path)
                    print("[FolderWatcher] 🧹 Reconcile: stopped stale watcher for \(path)")
                }
            }
            
            if stalePaths.isEmpty {
                print("[FolderWatcher] 🧹 Reconcile: all watchers still needed")
            } else {
                print("[FolderWatcher] 🧹 Reconcile: removed \(stalePaths.count) stale watcher(s), \(self.watchers.count) remaining")
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func countFolderItems(at path: String) -> Int {
        let folderURL = URL(fileURLWithPath: path)
        do {
            let items = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            return items.count
        } catch {
            print("[FolderWatcher] Failed to count folder items: \(error)")
            return 0
        }
    }
    
    private func handleFolderChange(path: String, name: String) {
        // Cancel any pending refresh for this folder
        pendingRefreshes[path]?.cancel()
        
        // Create new debounced refresh
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            print("[FolderWatcher] Change detected in: \(name)")
            print("[FolderWatcher] Queueing cache refresh...")
            
            //Add to operation queue
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
            return
        }
        
        // Create and queue the refresh operation
        let operation = RefreshOperation(path: path, folderName: name)
        refreshQueue.addOperation(operation)
        
        let queueDepth = refreshQueue.operationCount
        let activeCount = refreshQueue.operations.filter { $0.isExecuting }.count
        print("[FolderWatcher] Queued refresh for \(name)")
        print("   Queue: \(queueDepth) total, \(activeCount) active")
    }
    
    /// Manual refresh (for user-initiated refreshes)
    func forceRefresh(path: String, name: String) {
        print("[FolderWatcher] Force refresh requested for \(name)")
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
            print("[FolderWatcher] Failed to create event stream for: \(name)")
            return
        }
        
        // Schedule on queue
        FSEventStreamSetDispatchQueue(stream, queue)
        
        // Start monitoring
        if FSEventStreamStart(stream) {
//            print("[FolderWatcher] 🎬 Monitoring started for: \(name)")
            return
        } else {
            print("[FolderWatcher] Failed to start monitoring for: \(name)")
            
        }
    }
    
    func stop() {
        guard let stream = eventStream else { return }
        
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        
        eventStream = nil
        print("[FolderWatcher] Monitoring stopped for: \(name)")
    }
    
    deinit {
        stop()
    }
}
