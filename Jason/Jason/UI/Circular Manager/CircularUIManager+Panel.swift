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
        panelActionHandler?.handleLeftClick(node: node, modifiers: modifiers, fromLevel: level)
    }
    
    // MARK: - Panel Item Right Click
    
    func handlePanelItemRightClick(node: FunctionNode, modifiers: NSEvent.ModifierFlags) {
        panelActionHandler?.handleRightClick(node: node, modifiers: modifiers)
    }
    
    // MARK: - Panel Context Action
    
    func handlePanelContextAction(actionNode: FunctionNode, modifiers: NSEvent.ModifierFlags) {
        panelActionHandler?.handleContextAction(actionNode: actionNode, modifiers: modifiers)
    }
}
