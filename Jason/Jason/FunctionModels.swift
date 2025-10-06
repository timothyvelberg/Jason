//
//  FunctionModels.swift
//  Jason
//
//  Created by Timothy Velberg on 06/10/2025.
//

import Foundation
import AppKit

// MARK: - FunctionNode (Tree Structure)

class FunctionNode: Identifiable, ObservableObject {
    let id: String
    let name: String
    let icon: NSImage
    let children: [FunctionNode]?
    let action: (() -> Void)?
    
    init(
        id: String,
        name: String,
        icon: NSImage,
        children: [FunctionNode]? = nil,
        action: (() -> Void)? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.children = children
        self.action = action
    }
    
    // Leaf = has action, no children
    var isLeaf: Bool {
        return children == nil && action != nil
    }
    
    // Branch = has children (even if empty array)
    var isBranch: Bool {
        return children != nil
    }
    
    // Is this a valid branch (has actual children)?
    var hasChildren: Bool {
        return (children?.count ?? 0) > 0
    }
    
    var childCount: Int {
        return children?.count ?? 0
    }
}

// MARK: - Legacy Structures (to be removed after migration)

struct FunctionItem {
    let id: String
    let name: String
    let icon: NSImage
    let action: () -> Void
}

struct FunctionCategory {
    let id: String
    let name: String
    let icon: NSImage
    let functions: [FunctionItem]
}
