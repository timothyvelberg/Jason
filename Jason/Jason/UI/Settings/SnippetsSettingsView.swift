//
//  SnippetsSettingsView.swift
//  Jason
//
//  Created by Timothy Velberg on 07/02/2026.

import SwiftUI

// MARK: - Snippets Settings View

struct SnippetsSettingsView: View {
    @State private var snippets: [SnippetsProvider.Snippet] = []
    @State private var editingSnippet: SnippetsProvider.Snippet?
    @State private var isAddingNew: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            if snippets.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "pencil.line")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No snippets yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Add text snippets for quick pasting from clipboard history")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(snippets, id: \.id) { snippet in
                        SnippetRow(
                            snippet: snippet,
                            onEdit: {
                                editingSnippet = snippet
                            },
                            onRemove: {
                                deleteSnippet(snippet)
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    .onMove(perform: moveSnippet)
                }
                .listStyle(.inset)
            }
            
            Divider()
            
            HStack {
                Button {
                    isAddingNew = true
                } label: {
                    Label("Add Snippet", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
                
                Text("\(snippets.count) snippet(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .onAppear {
            loadSnippets()
        }
        .sheet(isPresented: $isAddingNew) {
            EditSnippetView(
                mode: .add,
                onSave: { title, content, triggerText in
                    addSnippet(title: title, content: content, triggerText: triggerText)
                    isAddingNew = false
                },
                onCancel: {
                    isAddingNew = false
                }
            )
        }
        .sheet(item: $editingSnippet) { snippet in
            EditSnippetView(
                mode: .edit(snippet),
                onSave: { title, content, triggerText in
                    updateSnippet(id: snippet.id, title: title, content: content, triggerText: triggerText)
                    editingSnippet = nil
                },
                onCancel: {
                    editingSnippet = nil
                }
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

struct SnippetRow: View {
    let snippet: SnippetsProvider.Snippet
    let onEdit: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14))
                .foregroundColor(.secondary.opacity(0.5))
                .help("Drag to reorder")
            
            Image(systemName: "pencil.line")
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(snippet.title)
                    .font(.body)
                    .fontWeight(.medium)
                
                HStack(spacing: 8) {
                    Text(snippet.content)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if let trigger = snippet.triggerText, !trigger.isEmpty {
                        Text("• Trigger: \(trigger)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)
                .help("Edit snippet")
                
                Button(action: onRemove) {
                    Image(systemName: "trash.circle.fill")
                        .font(.title3)
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("Delete snippet")
            }
        }
        .padding(.vertical, 4)
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
                Button("Cancel") {
                    onCancel()
                }
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

// MARK: - Make Snippet Identifiable for .sheet(item:)

extension SnippetsProvider.Snippet: Identifiable {}
