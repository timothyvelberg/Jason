//
//  ClipboardHistoryProvider.swift
//  Jason
//
//  Created by Timothy Velberg on 19/01/2026.
//


import Foundation
import AppKit

class ClipboardHistoryProvider: ObservableObject, FunctionProvider {
    
    // MARK: - FunctionProvider Protocol
    
    var providerId: String {
        return "clipboard-history"
    }
    
    var providerName: String {
        return "Clipboard"
    }
    
    var providerIcon: NSImage {
        return NSImage(named: "parent-clipboard") ?? NSImage()
    }
    
    // MARK: - Private Properties
    
    private let clipboardManager = ClipboardManager.shared
    
    // MARK: - Initialization
    
    init() {
        print("📋 [ClipboardHistoryProvider] Initialized")
    }
    
    // MARK: - FunctionProvider Methods
    
    func provideFunctions() -> [FunctionNode] {
        let entries = clipboardManager.history
        
        // Handle empty state - show placeholder
        let children: [FunctionNode]
        if entries.isEmpty {
            children = [
                FunctionNode(
                    id: "clipboard-empty",
                    name: "No clipboard history",
                    type: .action,
                    icon: NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil) ?? NSImage(),
                    showLabel: true,
                    providerId: providerId,
                    onLeftClick: ModifierAwareInteraction(base: .doNothing),
                    onRightClick: ModifierAwareInteraction(base: .doNothing),
                    onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                    onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
                )
            ]
        } else {
            children = entries.map { entry in
                createEntryNode(entry: entry)
            }
        }
        
        // Return parent category node with panel display mode
        return [
            FunctionNode(
                id: "clipboard-history-category",
                name: "Clipboard",
                type: .category,
                icon: providerIcon,
                children: children,
                childDisplayMode: .panel,
                preferredLayout: .partialSlice,
                slicePositioning: .center,
                providerId: providerId,
                onLeftClick: ModifierAwareInteraction(base: .expand),
                onRightClick: ModifierAwareInteraction(base: .expand),
                onBoundaryCross: ModifierAwareInteraction(base: .expand)
            )
        ]
    }
    
    func refresh() {
        print("📋 [ClipboardHistoryProvider] Refresh called")
        objectWillChange.send()
    }
    
    // MARK: - Private Methods
    
    private func createEntryNode(entry: ClipboardEntry) -> FunctionNode {
        // Truncate content for display
        let displayText = truncateForDisplay(entry.content, maxLength: 50)
        
        // Format timestamp
        let timeAgo = formatTimeAgo(entry.copiedAt)
        
        // Create display name with truncated content
        let displayName = displayText
        
        return FunctionNode(
            id: "clipboard-\(entry.id.uuidString)",
            name: displayName,
            type: .action,
            icon: iconForContent(entry.content),
            showLabel: true,
            metadata: [
                "fullContent": entry.content,
                "copiedAt": entry.copiedAt,
                "timeAgo": timeAgo
            ],
            providerId: providerId,
            onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                self?.pasteEntry(entry)
            }),
            onRightClick: ModifierAwareInteraction(base: .doNothing),
            onMiddleClick: ModifierAwareInteraction(base: .doNothing),
            onBoundaryCross: ModifierAwareInteraction(base: .execute { [weak self] in
                self?.pasteEntry(entry)
            })
        )
    }
    
    private func pasteEntry(_ entry: ClipboardEntry) {
        print("📋 [ClipboardHistoryProvider] Pasting entry: \"\(entry.content.prefix(30))...\"")
        clipboardManager.paste(entry: entry)
    }
    
    // MARK: - Helper Methods
    
    private func truncateForDisplay(_ text: String, maxLength: Int) -> String {
        // Replace newlines with spaces for single-line display
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
                             .replacingOccurrences(of: "\r", with: " ")
                             .trimmingCharacters(in: .whitespaces)
        
        if singleLine.count <= maxLength {
            return singleLine
        }
        
        let truncated = String(singleLine.prefix(maxLength))
        return truncated + "…"
    }
    
    private func formatTimeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        
        if seconds < 60 {
            return "just now"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes)m ago"
        } else if seconds < 86400 {
            let hours = seconds / 3600
            return "\(hours)h ago"
        } else {
            let days = seconds / 86400
            return "\(days)d ago"
        }
    }
    
    private func iconForContent(_ content: String) -> NSImage {
        // Could be extended later to show different icons for URLs, code, etc.
        // For now, use a simple text icon
        
        if content.hasPrefix("http://") || content.hasPrefix("https://") {
            return NSImage(systemSymbolName: "link", accessibilityDescription: nil) ?? NSImage()
        }
        
        if content.contains("@") && content.contains(".") {
            return NSImage(systemSymbolName: "envelope", accessibilityDescription: nil) ?? NSImage()
        }
        
        // Default text icon
        return NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil) ?? NSImage()
    }
}
