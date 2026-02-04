import Foundation
import AppKit

class TodoListProvider: FunctionProvider {
    
    var providerId: String { "todo-list" }
    var providerName: String { "Todo List" }
    var providerIcon: NSImage { NSImage(systemSymbolName: "checklist", accessibilityDescription: "Todo List") ?? NSImage() }
    var defaultTypingMode: TypingMode { .input }
    var onTodoChanged: (() -> Void)?
    
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
        let items = buildTodoNodes()
        return [
            FunctionNode(
                id: "todo-list",
                name: "Todo List",
                type: .category,
                icon: NSImage(named: "parent-todo") ?? NSImage(),
                children: items,
                childDisplayMode: .panel,
                providerId: "todo-list", 
                onLeftClick: ModifierAwareInteraction(base: .doNothing),
                onRightClick: ModifierAwareInteraction(base: .doNothing),
                onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                onBoundaryCross: ModifierAwareInteraction(base: .expand)
            )
        ]
    }
    
    private func buildTodoNodes() -> [FunctionNode] {
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
                contextActions: [deleteAction(for: todo)],
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
    
    func loadChildren(for node: FunctionNode) async -> [FunctionNode] {
        return buildTodoNodes()
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
    
    private func deleteTodo(id: String) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        let title = todos[index].title
        todos.remove(at: index)
        print("🗑️ [TodoListProvider] Deleted: '\(title)' (\(todos.count) remaining)")
        onTodoChanged?()
    }

    private func toggleTodo(id: String) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].isCompleted.toggle()
        print("[TodoListProvider] Toggled: '\(todos[index].title)' → \(todos[index].isCompleted ? "done" : "undone")")
        onTodoChanged?()
    }
    
    private func deleteAction(for todo: TodoItem) -> FunctionNode {
        let providerId = self.providerId
        return FunctionNode(
            id: "delete-todo-\(todo.id)",
            name: "Delete",
            type: .action,
            icon: NSImage(named: "context_actions_delete") ?? NSImage(),
            onLeftClick: ModifierAwareInteraction(
                base: .execute { [weak self] in
                    self?.deleteTodo(id: todo.id)
                },
                command: .executeKeepOpen { [weak self] in
                    self?.deleteTodo(id: todo.id)
                }
            ),
            onMiddleClick: ModifierAwareInteraction(base: .doNothing)
        )
    }
}
