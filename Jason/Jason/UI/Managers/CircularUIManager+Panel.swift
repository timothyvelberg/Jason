//
//  CircularUIManager+Panel.swift
//  Jason
//
//  Created by Timothy Velberg on 29/01/2026.
//

import Foundation
import AppKit

extension CircularUIManager {
    
    // MARK: - Panel Item Left Click
    
    func handlePanelItemLeftClick(node: FunctionNode, modifiers: NSEvent.ModifierFlags) {
        handlePanelItemLeftClick(node: node, modifiers: modifiers, fromLevel: 0)
    }

    func handlePanelItemLeftClick(node: FunctionNode, modifiers: NSEvent.ModifierFlags, fromLevel level: Int) {
        print("[Panel Left Click] On item: '\(node.name)' at level \(level)")
        
        let behavior = node.onLeftClick.resolve(with: modifiers)
        
        switch behavior {
        case .execute(let action):
            action()
            hide()
            
        case .executeKeepOpen(let action):
            action()
            
        case .expand, .navigateInto:
            // Check if we should cascade to panel
            guard let children = node.children, !children.isEmpty else {
                print("[Panel] Node '\(node.name)' has no children")
                return
            }
            
            // Cascade: push new panel to the right
            listPanelManager?.pushPanel(
                title: node.name,
                items: children,
                fromPanelAtLevel: level,
                sourceNodeId: node.id,
                contextActions: node.contextActions
            )
            
        case .launchRing(let configId):
            print("[Panel] Launching ring config \(configId)")
            hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                CircularUIInstanceManager.shared.show(configId: configId)
            }
            
        case .drag(let provider):
            switch provider.clickBehavior {
            case .execute(let action):
                action()
                hide()
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
    
    // MARK: - Panel Item Right Click
    
    func handlePanelItemRightClick(node: FunctionNode, modifiers: NSEvent.ModifierFlags) {
        print("[Panel Right Click] On item: '\(node.name)'")
        
        let behavior = node.onRightClick.resolve(with: modifiers)
        
        switch behavior {
        case .execute(let action):
            action()
            hide()
            
        case .executeKeepOpen(let action):
            action()
            
        case .expand:
            // Show context actions if available
            if let contextActions = node.contextActions, !contextActions.isEmpty {
                print("[Panel] Expanding context actions for '\(node.name)'")
                if let manager = listPanelManager {
                    manager.show(
                        title: node.name,
                        items: contextActions,
                        ringCenter: manager.currentRingCenter,
                        ringOuterRadius: manager.currentRingOuterRadius,
                        angle: manager.currentAngle,
                        screen: self.overlayWindow?.currentScreen
                    )
                }
            }
            
        case .launchRing(let configId):
            print("[Panel Right Click] Launching ring config \(configId)")
            hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                CircularUIInstanceManager.shared.show(configId: configId)
            }
            
        default:
            break
        }
    }
    
    // MARK: - Panel Context Action
    
    func handlePanelContextAction(actionNode: FunctionNode, modifiers: NSEvent.ModifierFlags) {
        print("[Panel Context Action] '\(actionNode.name)'")
        
        // Context actions typically use onLeftClick for their action
        let behavior = actionNode.onLeftClick.resolve(with: modifiers)
        
        switch behavior {
        case .execute(let action):
            action()
            hide()
            
        case .executeKeepOpen(let action):
            action()
            
        case .launchRing(let configId):
            print("[Panel Context] Launching ring config \(configId)")
            hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                CircularUIInstanceManager.shared.show(configId: configId)
            }
            
        default:
            print("[Panel Context] Unhandled behavior for '\(actionNode.name)'")
        }
    }
}
