//
//  SnippetsProvider.swift
//  Jason
//
//  Created by Timothy Velberg on 07/02/2026.
//

import Foundation
import AppKit

class SnippetsProvider: FunctionProvider {
    
    // MARK: - FunctionProvider Protocol
    
    var providerId: String { "snippets" }
    var providerName: String { "Snippets" }
    var providerIcon: NSImage { NSImage(systemSymbolName: "pencil.line", accessibilityDescription: "Snippets") ?? NSImage() }
    var defaultTypingMode: TypingMode { .search }
    
    // MARK: - Snippet Model
    
    struct Snippet {
        let id: String
        var title: String
        var content: String
        var triggerText: String?
        var sortOrder: Int
        let createdAt: Date
    }
    
    // MARK: - Storage
    
    private(set) var snippets: [Snippet] = []
    
    // MARK: - Initialization
    
    init() {
        loadSnippets()
        print("📌 [SnippetsProvider] Initialized with \(snippets.count) snippets")
    }
    
    private func loadSnippets() {
        snippets = DatabaseManager.shared.getAllSnippets()
    }
    
    // MARK: - FunctionProvider Methods
    
    func provideFunctions() -> [FunctionNode] {
        let children = buildSnippetNodes()
        
        return [
            FunctionNode(
                id: "snippets-category",
                name: "Snippets",
                type: .category,
                icon: providerIcon,
                children: children,
                childDisplayMode: .panel,
                providerId: providerId,
                onLeftClick: ModifierAwareInteraction(base: .doNothing),
                onRightClick: ModifierAwareInteraction(base: .doNothing),
                onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                onBoundaryCross: ModifierAwareInteraction(base: .expand)
            )
        ]
    }
    
    // MARK: - Build Nodes (internal so ClipboardHistoryProvider can access)
    
    func buildSnippetNodes() -> [FunctionNode] {
        if snippets.isEmpty {
            return [
                FunctionNode(
                    id: "snippets-empty",
                    name: "No snippets saved",
                    type: .action,
                    icon: NSImage(systemSymbolName: "pencil.line", accessibilityDescription: nil) ?? NSImage(),
                    showLabel: true,
                    providerId: providerId,
                    onLeftClick: ModifierAwareInteraction(base: .doNothing),
                    onRightClick: ModifierAwareInteraction(base: .doNothing),
                    onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                    onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
                )
            ]
        }
        
        return snippets.map { makeSnippetNode($0) }
    }
    
    private func makeSnippetNode(_ snippet: Snippet) -> FunctionNode {
        let deleteAction = FunctionNode(
            id: "snippet-delete-\(snippet.id)",
            name: "Delete",
            type: .action,
            icon: NSImage(named: "context_actions_delete") ?? NSImage(),
            onLeftClick: ModifierAwareInteraction(
                base: .execute { [weak self] in
                    self?.deleteSnippet(id: snippet.id)
                },
                command: .executeKeepOpen { [weak self] in
                    self?.deleteSnippet(id: snippet.id)
                }
            ),
            onMiddleClick: ModifierAwareInteraction(base: .doNothing)
        )
        
        return FunctionNode(
            id: "snippet-\(snippet.id)",
            name: snippet.title,
            type: .file,
            icon: NSImage(systemSymbolName: "pencil.line", accessibilityDescription: nil) ?? NSImage(),
            contextActions: [deleteAction],
            metadata: [
                "fullContent": snippet.content
            ],
            providerId: providerId,
            onLeftClick: ModifierAwareInteraction(base: .execute { [weak self] in
                self?.pasteSnippet(snippet)
            }),
            onRightClick: ModifierAwareInteraction(base: .expand),
            onMiddleClick: ModifierAwareInteraction(base: .doNothing),
            onBoundaryCross: ModifierAwareInteraction(base: .execute { [weak self] in
                self?.pasteSnippet(snippet)
            })
        )
    }
    
    // MARK: - Actions
    
    private func pasteSnippet(_ snippet: Snippet) {
        print("📌 [SnippetsProvider] Pasting snippet: \"\(snippet.title)\"")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(snippet.content, forType: .string)
        ShortcutExecutor.execute(keyCode: 9, modifierFlags: NSEvent.ModifierFlags.command.rawValue)
    }
    
    private func deleteSnippet(id: String) {
        DatabaseManager.shared.deleteSnippet(id: id)
        loadSnippets()
        NotificationCenter.default.postProviderUpdate(providerId: providerId)
        print("🗑️ [SnippetsProvider] Deleted snippet: \(id) (\(snippets.count) remaining)")
    }
    
    // MARK: - Public Methods
    
    func addSnippet(title: String, content: String, triggerText: String? = nil) {
        let id = UUID().uuidString
        let sortOrder = DatabaseManager.shared.getNextSnippetSortOrder()
        DatabaseManager.shared.saveSnippet(id: id, title: title, content: content, triggerText: triggerText, sortOrder: sortOrder, createdAt: Date())
        loadSnippets()
        NotificationCenter.default.postProviderUpdate(providerId: providerId)
    }
    
    func updateSnippet(id: String, title: String, content: String, triggerText: String?) {
        DatabaseManager.shared.updateSnippet(id: id, title: title, content: content, triggerText: triggerText)
        loadSnippets()
        NotificationCenter.default.postProviderUpdate(providerId: providerId)
    }
    
    func refresh() {
        loadSnippets()
    }
}
