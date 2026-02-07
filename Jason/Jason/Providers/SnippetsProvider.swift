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
    var providerIcon: NSImage { NSImage(systemSymbolName: "text.snippet", accessibilityDescription: "Snippets") ?? NSImage() }
    var defaultTypingMode: TypingMode { .search }
    
    // MARK: - Snippet Model
    
    struct Snippet {
        let id: String
        var title: String
        var content: String
        let createdAt: Date
    }
    
    // MARK: - In-Memory Storage (temporary)
    
    private(set) var snippets: [Snippet] = []
    
    // MARK: - Initialization
    
    init() {
        loadSampleSnippets()
        print("📌 [SnippetsProvider] Initialized with \(snippets.count) sample snippets")
    }
    
    private func loadSampleSnippets() {
        snippets = [
            Snippet(id: UUID().uuidString, title: "Email Signature", content: "Best regards,\nTimothy Velberg", createdAt: Date()),
            Snippet(id: UUID().uuidString, title: "Phone Number", content: "+31 6 1234 5678", createdAt: Date().addingTimeInterval(-3600)),
            Snippet(id: UUID().uuidString, title: "Home Address", content: "Keizersgracht 123, 1015 CJ Amsterdam", createdAt: Date().addingTimeInterval(-7200)),
        ]
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
                    icon: NSImage(systemSymbolName: "text.snippet", accessibilityDescription: nil) ?? NSImage(),
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
        guard let index = snippets.firstIndex(where: { $0.id == id }) else { return }
        let title = snippets[index].title
        snippets.remove(at: index)
        print("🗑️ [SnippetsProvider] Deleted: '\(title)' (\(snippets.count) remaining)")
    }
}
