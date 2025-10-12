//
//  QuickLookManager.swift
//  Jason
//
//  Created by Timothy Velberg on 12/10/2025.
//

import Foundation
import AppKit
import Quartz

class QuickLookManager: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    
    static let shared = QuickLookManager()
    
    private var previewURLs: [URL] = []
    private(set) var isShowing: Bool = false
    
    private override init() {
        super.init()
    }
    
    // MARK: - Public API
    
    /// Show Quick Look preview for a single file
    func showPreview(for url: URL) {
        print("👁️ [QuickLook] Showing preview for: \(url.lastPathComponent)")
        
        previewURLs = [url]
        
        guard let panel = QLPreviewPanel.shared() else {
            print("❌ [QuickLook] Failed to get QLPreviewPanel")
            return
        }
        
        // Set ourselves as the data source and delegate
        panel.dataSource = self
        panel.delegate = self
        
        // Refresh and show
        panel.reloadData()

        if !panel.isVisible {
            isShowing = true  // ← Set BEFORE showing the panel!
            panel.makeKeyAndOrderFront(nil)
            print("✅ [QuickLook] Preview panel shown")
        } else {
            panel.reloadData()
            print("🔄 [QuickLook] Preview panel refreshed")
        }    }
    
    /// Hide the Quick Look preview
    func hidePreview() {
        guard let panel = QLPreviewPanel.shared() else { return }
        
        if panel.isVisible {
            panel.orderOut(nil)
            isShowing = false
            print("🙈 [QuickLook] Preview panel hidden")
        }
        
        previewURLs = []
    }
    
    /// Toggle preview for a URL
    func togglePreview(for url: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }
        
        if panel.isVisible && previewURLs.first == url {
            hidePreview()
        } else {
            showPreview(for: url)
        }
    }
    
    // MARK: - QLPreviewPanelDataSource
    
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return previewURLs.count
    }
    
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard index < previewURLs.count else { return nil }
        return previewURLs[index] as QLPreviewItem
    }
    
    // MARK: - QLPreviewPanelDelegate
    
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        // Handle keyboard events in the preview panel
        if event.type == .keyDown {
            // ESC key closes the preview
            if event.keyCode == 53 {
                hidePreview()
                return true
            }
        }
        return false
    }
    
    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> NSRect {
        // Return a rect for the zoom animation (optional)
        return NSRect.zero
    }
}
