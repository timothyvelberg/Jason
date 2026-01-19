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
    let copiedAt: Date
    
    init(content: String) {
        self.id = UUID()
        self.content = content
        self.copiedAt = Date()
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
    
    // MARK: - Initialization
    
    private init() {
        // Capture initial state without adding to history
        lastChangeCount = NSPasteboard.general.changeCount
        print("📋 [ClipboardManager] Initialized with changeCount: \(lastChangeCount)")
    }
    
    deinit {
        stopMonitoring()
        print("📋 [ClipboardManager] Deallocated")
    }
    
    // MARK: - Public Interface
    
    /// Start monitoring the clipboard for changes
    func startMonitoring() {
        guard pollTimer == nil else {
            print("📋 [ClipboardManager] Already monitoring")
            return
        }
        
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }
        
        print("📋 [ClipboardManager] Started monitoring (interval: \(pollInterval)s)")
    }
    
    /// Stop monitoring the clipboard
    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        print("📋 [ClipboardManager] Stopped monitoring")
    }
    
    /// Get the current history count
    var historyCount: Int {
        return history.count
    }
    
    /// Clear all history
    func clearHistory() {
        history.removeAll()
        print("📋 [ClipboardManager] History cleared")
    }
    
    /// Paste a specific entry (writes to clipboard, then simulates Cmd+V)
    func paste(entry: ClipboardEntry) {
        // Write the entry content to the clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.content, forType: .string)
        
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
        
        // Read string content from clipboard
        guard let content = NSPasteboard.general.string(forType: .string),
              !content.isEmpty else {
            print("📋 [ClipboardManager] Change detected but no string content")
            return
        }
        
        addEntry(content: content)
    }
    
    private func addEntry(content: String) {
        // Deduplication: check if this content already exists
        if let existingIndex = history.firstIndex(where: { $0.content == content }) {
            // Remove the old entry
            let existing = history.remove(at: existingIndex)
            print("📋 [ClipboardManager] Dedup: moving existing entry to top")
            
            // Create new entry with fresh timestamp and insert at top
            let newEntry = ClipboardEntry(content: content)
            history.insert(newEntry, at: 0)
            
            print("📋 [ClipboardManager] Entry moved to top: \"\(content.prefix(30))...\" (was at index \(existingIndex))")
        } else {
            // New entry - insert at top
            let entry = ClipboardEntry(content: content)
            history.insert(entry, at: 0)
            
            print("📋 [ClipboardManager] New entry added: \"\(content.prefix(30))...\" (total: \(history.count))")
        }
    }
}
