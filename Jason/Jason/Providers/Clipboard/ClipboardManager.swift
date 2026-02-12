//
//  ClipboardManager.swift
//  Jason
//
//  Created by Timothy Velberg on 19/01/2026.
//

import Foundation
import AppKit

// MARK: - Clipboard Entry Model

struct ClipboardEntry: Identifiable, Equatable {
    let id: UUID
    let content: String
    let rtfData: Data?
    let htmlData: Data?
    let sourceAppBundleId: String?
    let copiedAt: Date
    
    // New entry
    init(content: String, rtfData: Data? = nil, htmlData: Data? = nil, sourceAppBundleId: String? = nil) {
        self.id = UUID()
        self.content = content
        self.rtfData = rtfData
        self.htmlData = htmlData
        self.sourceAppBundleId = sourceAppBundleId
        self.copiedAt = Date()
    }

    // Load from database
    init(id: UUID, content: String, rtfData: Data? = nil, htmlData: Data? = nil, sourceAppBundleId: String? = nil, copiedAt: Date) {
        self.id = id
        self.content = content
        self.rtfData = rtfData
        self.htmlData = htmlData
        self.sourceAppBundleId = sourceAppBundleId
        self.copiedAt = copiedAt
    }
    
    static func == (lhs: ClipboardEntry, rhs: ClipboardEntry) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Clipboard Manager

class ClipboardManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = ClipboardManager()
    
    // MARK: - Published Properties
    
    @Published private(set) var history: [ClipboardEntry] = []
    
    // MARK: - Private Properties
    
    private var pollTimer: Timer?
    private var lastChangeCount: Int = 0
    private let pollInterval: TimeInterval = 0.5
    private var addCounter: Int = 0
    
    // MARK: - Initialization
    
    private init() {
        // Load history from database
        history = DatabaseManager.shared.getAllClipboardEntries()
        print("[ClipboardManager] Loaded \(history.count) entries from database")
        
        // Capture initial state without adding to history
        lastChangeCount = NSPasteboard.general.changeCount
        print("[ClipboardManager] Initialized with changeCount: \(lastChangeCount)")
    }
    
    deinit {
        stopMonitoring()
        print("[ClipboardManager] Deallocated")
    }
    
    // MARK: - Public Interface
    
    /// Start monitoring the clipboard for changes
    func startMonitoring() {
        guard pollTimer == nil else {
            print("[ClipboardManager] Already monitoring")
            return
        }
        
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }
        
        print("[ClipboardManager] Started monitoring (interval: \(pollInterval)s)")
    }
    
    /// Stop monitoring the clipboard
    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        print("[ClipboardManager] Stopped monitoring")
    }
    
    /// Get the current history count
    var historyCount: Int {
        return history.count
    }
    
    func clearHistory() {
        history.removeAll()
        DatabaseManager.shared.clearClipboardHistory()
        print("[ClipboardManager] History cleared")
    }
    
    func paste(entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        // Check if Command is held - paste plain text only
        let plainTextOnly = NSEvent.modifierFlags.contains(.command)
        
        if plainTextOnly {
            pasteboard.declareTypes([.string], owner: nil)
            pasteboard.setString(entry.content, forType: .string)
            print("📋 [ClipboardManager] Pasting plain text only (⌘ held)")
        } else {
            // Declare types we're going to write
            var types: [NSPasteboard.PasteboardType] = [.string]
            if entry.rtfData != nil {
                types.insert(.rtf, at: 0)
            }
            if entry.htmlData != nil {
                types.insert(.html, at: 0)
            }
            pasteboard.declareTypes(types, owner: nil)
            
            // Restore HTML if available
            if let htmlData = entry.htmlData {
                pasteboard.setData(htmlData, forType: .html)
                print("📋 [ClipboardManager] Restored HTML data (\(htmlData.count) bytes)")
            }
            
            // Restore RTF if available
            if let rtfData = entry.rtfData {
                pasteboard.setData(rtfData, forType: .rtf)
                print("📋 [ClipboardManager] Restored RTF data (\(rtfData.count) bytes)")
            }
            
            // Always set string representation
            pasteboard.setString(entry.content, forType: .string)
        }
        
        // Update our changeCount so we don't re-capture this as a new entry
        lastChangeCount = pasteboard.changeCount
        
        print("📋 [ClipboardManager] Pasting entry: \"\(entry.content.prefix(30))...\"")
        
        // Execute Cmd+V via ShortcutExecutor
        ShortcutExecutor.execute(keyCode: 9, modifierFlags: NSEvent.ModifierFlags.command.rawValue)
    }
    
    // MARK: - Private Methods
    
    private func checkForChanges() {
        let currentChangeCount = NSPasteboard.general.changeCount
        
        guard currentChangeCount != lastChangeCount else {
            return  // No change
        }
        
        lastChangeCount = currentChangeCount
        
        let pasteboard = NSPasteboard.general
        let sourceAppBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        
        // Read string content from clipboard (required)
        guard let content = pasteboard.string(forType: .string),
              !content.isEmpty else {
            print("[ClipboardManager] Change detected but no string content")
            return
        }
        
        // Read RTF data if available (optional)
        let rtfData = pasteboard.data(forType: .rtf)
        if rtfData != nil {
            print("📋 [ClipboardManager] Captured RTF data (\(rtfData!.count) bytes)")
        }
        
        // Read HTML data if available (optional)
        let htmlData = pasteboard.data(forType: .html)
        if htmlData != nil {
            print("📋 [ClipboardManager] Captured HTML data (\(htmlData!.count) bytes)")
        }
        
        if let bundleId = sourceAppBundleId {
            print("📋 [ClipboardManager] Source app: \(bundleId)")
        }
        
        addEntry(content: content, rtfData: rtfData, htmlData: htmlData, sourceAppBundleId: sourceAppBundleId)
    }
    
    private func addEntry(content: String, rtfData: Data? = nil, htmlData: Data? = nil, sourceAppBundleId: String? = nil) {
        // Deduplication: check if this content already exists
        if let existingIndex = history.firstIndex(where: { $0.content == content }) {
            // Remove the old entry from memory and database
            let existing = history.remove(at: existingIndex)
            DatabaseManager.shared.deleteClipboardEntry(id: existing.id)
            print("[ClipboardManager] Dedup: moving existing entry to top")
            
            // Create new entry with fresh timestamp and insert at top
            let newEntry = ClipboardEntry(content: content, rtfData: rtfData, htmlData: htmlData, sourceAppBundleId: sourceAppBundleId)
            history.insert(newEntry, at: 0)
            DatabaseManager.shared.saveClipboardEntry(newEntry)
            
            print("[ClipboardManager] Entry moved to top: \"\(content.prefix(30))...\" (was at index \(existingIndex))")
        } else {
            // New entry - insert at top
            let entry = ClipboardEntry(content: content, rtfData: rtfData, htmlData: htmlData, sourceAppBundleId: sourceAppBundleId)
            history.insert(entry, at: 0)
            DatabaseManager.shared.saveClipboardEntry(entry)
            
            print("[ClipboardManager] New entry added: \"\(content.prefix(30))...\" (total: \(history.count))")
        }
        // Prune every 10th new entry
        addCounter += 1
        if addCounter >= 10 {
            addCounter = 0
            
            // Cap in-memory array
            if history.count > 200 {
                history = Array(history.prefix(200))
                print("🧹 [ClipboardManager] Trimmed in-memory history to 200")
            }
            
            // Prune database
            DatabaseManager.shared.pruneClipboardHistory(keepCount: 200)
        }
    }
    
    func remove(entry: ClipboardEntry) {
        if let index = history.firstIndex(where: { $0.id == entry.id }) {
            history.remove(at: index)
            DatabaseManager.shared.deleteClipboardEntry(id: entry.id)
            print("[ClipboardManager] Removed entry: \"\(entry.content.prefix(30))...\" (remaining: \(history.count))")
        }
    }
}
