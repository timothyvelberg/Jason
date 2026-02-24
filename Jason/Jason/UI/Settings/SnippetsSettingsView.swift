//
//  SnippetsSettingsView.swift
//  Jason
//
//  Created by Timothy Velberg on 07/02/2026.
//

import SwiftUI

// MARK: - Snippets Settings View

struct SnippetsSettingsView: View {
    @State private var snippets: [SnippetsProvider.Snippet] = []
    @State private var editingSnippet: SnippetsProvider.Snippet?
    @State private var isAddingNew = false
    
    var body: some View {
        SettingsListShell(
            title: "Snippets",
            emptyIcon: "pencil.line",
            emptyTitle: "No snippets yet",
            emptySubtitle: "Add text snippets for quick pasting from clipboard history",
            primaryLabel: "Add Snippet",
            primaryAction: { isAddingNew = true },
            secondaryLabel: nil,
            secondaryAction: nil,
            isEmpty: snippets.isEmpty
        ) {
            ForEach(snippets, id: \.id) { snippet in
                SnippetRow(snippet: snippet) {
                    editingSnippet = snippet
                } onDelete: {
                    deleteSnippet(snippet)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            .onMove(perform: moveSnippet)
        }
        .onAppear { loadSnippets() }
        .sheet(isPresented: $isAddingNew) {
            EditSnippetView(
                mode: .add,
                onSave: { title, content, triggerText in
                    addSnippet(title: title, content: content, triggerText: triggerText)
                    isAddingNew = false
                },
                onCancel: { isAddingNew = false }
            )
        }
        .sheet(item: $editingSnippet) { snippet in
            EditSnippetView(
                mode: .edit(snippet),
                onSave: { title, content, triggerText in
                    updateSnippet(id: snippet.id, title: title, content: content, triggerText: triggerText)
                    editingSnippet = nil
                },
                onCancel: { editingSnippet = nil }
            )
        }
    }
    
    // MARK: - Actions
    
    private func loadSnippets() {
        snippets = DatabaseManager.shared.getAllSnippets()
    }
    
    private func addSnippet(title: String, content: String, triggerText: String?) {
        let id = UUID().uuidString
        let sortOrder = DatabaseManager.shared.getNextSnippetSortOrder()
        DatabaseManager.shared.saveSnippet(id: id, title: title, content: content, triggerText: triggerText, sortOrder: sortOrder, createdAt: Date())
        loadSnippets()
    }
    
    private func updateSnippet(id: String, title: String, content: String, triggerText: String?) {
        DatabaseManager.shared.updateSnippet(id: id, title: title, content: content, triggerText: triggerText)
        loadSnippets()
    }
    
    private func deleteSnippet(_ snippet: SnippetsProvider.Snippet) {
        DatabaseManager.shared.deleteSnippet(id: snippet.id)
        loadSnippets()
    }
    
    private func moveSnippet(from source: IndexSet, to destination: Int) {
        snippets.move(fromOffsets: source, toOffset: destination)
        for (index, snippet) in snippets.enumerated() {
            DatabaseManager.shared.reorderSnippet(id: snippet.id, newSortOrder: index)
        }
        loadSnippets()
    }
}

// MARK: - Snippet Row

private struct SnippetRow: View {
    let snippet: SnippetsProvider.Snippet
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        SettingsRow(
            icon: .systemSymbol("pencil.line", .blue),
            title: snippet.title,
            subtitle: snippet.content,
            showDragHandle: true,
            onEdit: onEdit,
            onDelete: onDelete,
            metadata: {
                if let trigger = snippet.triggerText, !trigger.isEmpty {
                    Text(trigger)
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange)
                        .cornerRadius(4)
                }
            }
        )
    }
}

// MARK: - Edit Snippet View

struct EditSnippetView: View {
    enum Mode {
        case add
        case edit(SnippetsProvider.Snippet)
    }
    
    let mode: Mode
    let onSave: (String, String, String?) -> Void
    let onCancel: () -> Void
    
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var triggerText: String = ""
    
    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !content.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    private var headerTitle: String {
        switch mode {
        case .add: return "Add Snippet"
        case .edit: return "Edit Snippet"
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text(headerTitle)
                .font(.title2)
                .fontWeight(.semibold)
            
            Form {
                Section("Snippet") {
                    TextField("Title", text: $title)
                        .help("Display name shown in the panel")
                    
                    TextEditor(text: $content)
                        .font(.body)
                        .frame(minHeight: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }
                
                Section("Text Expansion (Optional)") {
                    TextField("Trigger text (e.g. -name)", text: $triggerText)
                        .help("Type this anywhere to auto-replace with the snippet content")
                    
                    if !triggerText.trimmingCharacters(in: .whitespaces).isEmpty {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                            Text("Typing \"\(triggerText.trimmingCharacters(in: .whitespaces))\" will be replaced with the snippet content")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            
            HStack(spacing: 12) {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                
                Button("Save") {
                    let trimmedTrigger = triggerText.trimmingCharacters(in: .whitespaces)
                    onSave(
                        title.trimmingCharacters(in: .whitespaces),
                        content,
                        trimmedTrigger.isEmpty ? nil : trimmedTrigger
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding()
        .frame(width: 450, height: 420)
        .onAppear {
            if case .edit(let snippet) = mode {
                title = snippet.title
                content = snippet.content
                triggerText = snippet.triggerText ?? ""
            }
        }
    }
}

// MARK: - Identifiable conformance for sheet(item:)

extension SnippetsProvider.Snippet: Identifiable {}
