import Foundation
import AppKit

class TodoListProvider: FunctionProvider {
    
    var providerId: String { "todo-list" }
    var providerName: String { "Todo List" }
    var providerIcon: NSImage { NSImage(systemSymbolName: "checklist", accessibilityDescription: "Todo List") ?? NSImage() }
    var defaultTypingMode: TypingMode { .input }
    
    // In-memory storage for now
    private(set) var todos: [TodoItem] = []
    
    struct TodoItem {
        let id: String
        var title: String
        var isCompleted: Bool
        let createdAt: Date
    }
    
    init() {
        // Seed with test data
        todos = [
            TodoItem(id: UUID().uuidString, title: "Build todo provider", isCompleted: false, createdAt: Date()),
            TodoItem(id: UUID().uuidString, title: "Wire input mode", isCompleted: false, createdAt: Date()),
            TodoItem(id: UUID().uuidString, title: "Add persistence", isCompleted: false, createdAt: Date()),
        ]
    }
    
    func provideFunctions() -> [FunctionNode] {
        return todos.map { todo in
            let icon: NSImage
            if todo.isCompleted {
                icon = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Done") ?? NSImage()
            } else {
                icon = NSImage(systemSymbolName: "circle", accessibilityDescription: "Todo") ?? NSImage()
            }
            
            return FunctionNode(
                id: todo.id,
                name: todo.title,
                type: .file,
                icon: icon,
                onLeftClick: ModifierAwareInteraction(
                    base: .execute { [weak self] in
                        self?.toggleTodo(id: todo.id)
                    },
                    command: .executeKeepOpen { [weak self] in
                        self?.toggleTodo(id: todo.id)
                    }
                )
            )
        }
    }
    
    func addTodo(title: String) {
        let todo = TodoItem(
            id: UUID().uuidString,
            title: title,
            isCompleted: false,
            createdAt: Date()
        )
        todos.insert(todo, at: 0)
        print("[TodoListProvider] Added: '\(title)' (\(todos.count) total)")
    }
    
    private func toggleTodo(id: String) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].isCompleted.toggle()
        print("[TodoListProvider] Toggled: '\(todos[index].title)' → \(todos[index].isCompleted ? "done" : "undone")")
    }
}
