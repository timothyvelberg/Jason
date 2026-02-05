//
//  PanelActionHandler.swift
//  Jason
//
//  Shared panel action handling for both CircularUIManager and PanelUIManager.
//  Eliminates duplicated behavior switch logic and panel refresh patterns.
//

import Foundation
import AppKit

class PanelActionHandler {
    
    // MARK: - Dependencies (injected by owning manager)
    
    /// Weak reference to the panel manager this handler operates on
    weak var listPanelManager: ListPanelManager?
    
    /// Find a provider by its ID. Abstracts CUM's functionManager.providers vs PUM's self.providers.
    var findProvider: ((String) -> (any FunctionProvider)?)?
    
    /// Hide the owning UI manager
    var hideUI: (() -> Void)?
    
    // MARK: - Left Click
    
    func handleLeftClick(node: FunctionNode, modifiers: NSEvent.ModifierFlags, fromLevel level: Int) {
        print("[PanelAction] Left click: '\(node.name)' at level \(level)")
        
        let behavior = node.onLeftClick.resolve(with: modifiers)
        
        switch behavior {
        case .execute(let action):
            action()
            hideUI?()
            
        case .executeKeepOpen(let action):
            action()
            
        case .expand, .navigateInto:
            guard let children = node.children, !children.isEmpty else {
                print("[PanelAction] Node '\(node.name)' has no children")
                return
            }
            
            listPanelManager?.pushPanel(
                title: node.name,
                items: children,
                fromPanelAtLevel: level,
                sourceNodeId: node.id,
                contextActions: node.contextActions
            )
            
        case .launchRing(let configId):
            print("[PanelAction] Launching ring config \(configId)")
            hideUI?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                CircularUIInstanceManager.shared.show(configId: configId)
            }
            
        case .drag(let provider):
            switch provider.clickBehavior {
            case .execute(let action):
                action()
                hideUI?()
            case .navigate:
                if let children = node.children, !children.isEmpty {
                    listPanelManager?.pushPanel(
                        title: node.name,
                        items: children,
                        fromPanelAtLevel: level,
                        sourceNodeId: node.id,
                        contextActions: node.contextActions
                    )
                }
            case .none:
                break
            }
            
        case .doNothing:
            break
        }
    }
    
    // MARK: - Right Click
    
    func handleRightClick(node: FunctionNode, modifiers: NSEvent.ModifierFlags) {
        print("[PanelAction] Right click: '\(node.name)'")
        
        let behavior = node.onRightClick.resolve(with: modifiers)
        
        switch behavior {
        case .execute(let action):
            action()
            hideUI?()
            
        case .executeKeepOpen(let action):
            action()
            
        case .expand:
            // Toggle context actions via expandedItemId
            guard let panelManager = listPanelManager else { return }
            if let panelIndex = panelManager.panelStack.firstIndex(where: { panel in
                panel.items.contains { $0.id == node.id }
            }) {
                if panelManager.panelStack[panelIndex].expandedItemId == node.id {
                    panelManager.panelStack[panelIndex].expandedItemId = nil
                } else {
                    panelManager.panelStack[panelIndex].expandedItemId = node.id
                }
            }
            
        case .launchRing(let configId):
            print("[PanelAction] Right click launching ring config \(configId)")
            hideUI?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                CircularUIInstanceManager.shared.show(configId: configId)
            }
            
        default:
            // Fallback: toggle expandedItemId (default right-click behavior for items
            // whose onRightClick doesn't define a specific action)
            guard let panelManager = listPanelManager else { return }
            if let panelIndex = panelManager.panelStack.firstIndex(where: { panel in
                panel.items.contains { $0.id == node.id }
            }) {
                if panelManager.panelStack[panelIndex].expandedItemId == node.id {
                    panelManager.panelStack[panelIndex].expandedItemId = nil
                } else {
                    panelManager.panelStack[panelIndex].expandedItemId = node.id
                }
            }
        }
    }
    
    // MARK: - Context Action
    
    func handleContextAction(actionNode: FunctionNode, modifiers: NSEvent.ModifierFlags) {
        print("[PanelAction] Context action: '\(actionNode.name)'")
        
        let behavior = actionNode.onLeftClick.resolve(with: modifiers)
        
        switch behavior {
        case .execute(let action):
            action()
            hideUI?()
            
        case .executeKeepOpen(let action):
            action()
            
        case .launchRing(let configId):
            print("[PanelAction] Context action launching ring config \(configId)")
            hideUI?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                CircularUIInstanceManager.shared.show(configId: configId)
            }
            
        default:
            print("[PanelAction] Unhandled behavior for context action '\(actionNode.name)'")
        }
    }
    
    // MARK: - Panel Refresh
    
    func refreshPanelItems(at level: Int) {
        listPanelManager?.refreshPanelItems(at: level)
    }
}
