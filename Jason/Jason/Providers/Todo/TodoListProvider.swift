import Foundation
import AppKit

class TodoListProvider: FunctionProvider, MutableListProvider {

    var providerId: String { "todo-list" }
    var providerName: String { "Todo List" }
    var providerIcon: NSImage { NSImage(systemSymbolName: "checklist", accessibilityDescription: "Todo List") ?? NSImage() }
    var defaultTypingMode: TypingMode { .input }
    var panelConfig: PanelConfig { PanelConfig(lineLimit: 3, panelWidth:320) }
    var onItemsChanged: (() -> Void)?
    
    // In-memory storage for now
    private(set) var todos: [TodoItem] = []
    
    struct TodoItem {
        let id: String
        var title: String
        var isCompleted: Bool
        let createdAt: Date
    }
    
    init() {
        todos = DatabaseManager.shared.getAllTodos()
        print("[TodoListProvider] Loaded \(todos.count) todos from database")
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
        todos = DatabaseManager.shared.getAllTodos()
        if todos.isEmpty {
            return [
                FunctionNode(
                    id: "todo-empty",
                    name: "No todos yet",
                    type: .action,
                    icon: NSImage(systemSymbolName: "checklist", accessibilityDescription: nil) ?? NSImage(),
                    showLabel: true,
                    providerId: providerId,
                    onLeftClick: ModifierAwareInteraction(base: .doNothing),
                    onRightClick: ModifierAwareInteraction(base: .doNothing),
                    onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                    onBoundaryCross: ModifierAwareInteraction(base: .doNothing)
                )
            ]
        }
        
        let incomplete = todos.filter { !$0.isCompleted }
        let completed = todos.filter { $0.isCompleted }

        var nodes: [FunctionNode] = []

        // Group header
        nodes.append(FunctionNode(
            id: "group-default",
            name: "DPG",
            type: .sectionHeader(style: .category),
            icon: NSImage(),
            providerId: providerId
        ))

        if !incomplete.isEmpty {
            nodes.append(FunctionNode(
                id: "section-todo",
                name: "To Do",
                type: .sectionHeader(style: .subtle),
                icon: NSImage(),
                providerId: providerId
            ))
            nodes.append(contentsOf: incomplete.map { makeTodoNode($0) })
        }

        if !completed.isEmpty {
            nodes.append(FunctionNode(
                id: "section-done",
                name: "Done",
                type: .sectionHeader(style: .subtle),
                icon: NSImage(),
                providerId: providerId
            ))
            nodes.append(contentsOf: completed.map { makeTodoNode($0) })
        }

        return nodes
    }
    
    func loadChildren(for node: FunctionNode) async -> [FunctionNode] {
        return buildTodoNodes()
    }
    
    private func makeTodoNode(_ todo: TodoItem) -> FunctionNode {
        let icon: NSImage
        if todo.isCompleted {
            icon = NSImage(named: "icon_done") ?? NSImage()
        } else {
            icon = NSImage(named: "icon_todo") ?? NSImage()
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
    
    func addItem(title: String) {
        let todo = TodoItem(
            id: UUID().uuidString,
            title: title,
            isCompleted: false,
            createdAt: Date()
        )
        todos.insert(todo, at: 0)
        DatabaseManager.shared.saveTodo(id: todo.id, title: todo.title, createdAt: todo.createdAt)
        print("[TodoListProvider] Added: '\(title)' (\(todos.count) total)")
    }
    
    private func deleteTodo(id: String) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        let title = todos[index].title
        todos.remove(at: index)
        DatabaseManager.shared.deleteTodo(id: id)
        print("🗑️ [TodoListProvider] Deleted: '\(title)' (\(todos.count) remaining)")
        onItemsChanged?()

    }

    private func toggleTodo(id: String) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].isCompleted.toggle()
        DatabaseManager.shared.toggleTodo(id: id)
        print("[TodoListProvider] Toggled: '\(todos[index].title)' → \(todos[index].isCompleted ? "done" : "undone")")
        onItemsChanged?()
    }
    
    private func deleteAction(for todo: TodoItem) -> FunctionNode {
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
