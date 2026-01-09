//
//  shortcutExecuteProvider.swift
//  Jason
//
//  Created by Timothy Velberg on 09/01/2026.

//  Provider for executing keyboard shortcuts
//

import Foundation
import AppKit

class ShortcutExecuteProvider: ObservableObject, FunctionProvider {
    
    // MARK: - FunctionProvider Protocol
    
    var providerId: String {
        return "shortcut-execute"
    }
    
    var providerName: String {
        return "Shortcuts"
    }
    
    var providerIcon: NSImage {
        return NSImage(named: "parent-shortcuts") ?? NSImage()
    }
    
    // MARK: - Initialization
    
    init() {
        print("⌨️ [ShortcutExecuteProvider] Initialized")
    }
    
    // MARK: - FunctionProvider Methods
    
    func provideFunctions() -> [FunctionNode] {
        // Hardcoded shortcuts for testing
        let shortcuts = [
            createShortcutNode(
                id: "shortcut-copy",
                name: "Copy",
                icon: "doc.on.doc",
                keyCode: 8,  // C
                modifierFlags: NSEvent.ModifierFlags.command.rawValue
            ),
            createShortcutNode(
                id: "shortcut-paste",
                name: "Paste",
                icon: "doc.on.clipboard",
                keyCode: 9,  // V
                modifierFlags: NSEvent.ModifierFlags.command.rawValue
            ),
            createShortcutNode(
                id: "shortcut-cut",
                name: "Cut",
                icon: "scissors",
                keyCode: 7,  // X
                modifierFlags: NSEvent.ModifierFlags.command.rawValue
            ),
            createShortcutNode(
                id: "shortcut-undo",
                name: "Undo",
                icon: "arrow.uturn.backward",
                keyCode: 6,  // Z
                modifierFlags: NSEvent.ModifierFlags.command.rawValue
            ),
            createShortcutNode(
                id: "shortcut-redo",
                name: "Redo",
                icon: "arrow.uturn.forward",
                keyCode: 6,  // Z
                modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue
            ),
            createShortcutNode(
                id: "shortcut-select-all",
                name: "Select All",
                icon: "selection.pin.in.out",
                keyCode: 0,  // A
                modifierFlags: NSEvent.ModifierFlags.command.rawValue
            ),
            createShortcutNode(
                id: "shortcut-force-quit",
                name: "Force Quit",
                icon: "xmark.app",
                keyCode: 53,  // Escape
                modifierFlags: NSEvent.ModifierFlags([.command, .option]).rawValue
            ),
            createShortcutNode(
                id: "shortcut-spotlight",
                name: "Spotlight",
                icon: "magnifyingglass",
                keyCode: 49,  // Space
                modifierFlags: NSEvent.ModifierFlags.command.rawValue
            ),
            createShortcutNode(
                id: "shortcut-screenshot",
                name: "Screenshot",
                icon: "camera.viewfinder",
                keyCode: 20,  // 4
                modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue
            )
        ]
        
        // Wrap in category node (parent mode)
        return [
            FunctionNode(
                id: "shortcuts-category",
                name: "Shortcuts",
                type: .category,
                icon: NSImage(named: "parent-shortcuts") ?? NSImage(),
                children: shortcuts,
                preferredLayout: .partialSlice,
                slicePositioning: .center,
                providerId: providerId,
                onLeftClick: ModifierAwareInteraction(base: .expand),
                onRightClick: ModifierAwareInteraction(base: .expand),
                onBoundaryCross: ModifierAwareInteraction(base: .expand)
            )
        ]
    }
    
    func refresh() {
        print("⌨️ [ShortcutExecuteProvider] Refresh called (no-op for now)")
    }
    
    // MARK: - Node Creation
    
    private func createShortcutNode(
        id: String,
        name: String,
        icon: String,
        keyCode: UInt16,
        modifierFlags: UInt
    ) -> FunctionNode {
        let shortcutDisplay = TriggerFormatting.formatShortcut(keyCode: keyCode, modifiers: modifierFlags)
        let iconImage = NSImage(systemSymbolName: icon, accessibilityDescription: nil) ?? NSImage()
        
        return FunctionNode(
            id: id,
            name: name,
            type: .action,
            icon: iconImage,
            preferredLayout: nil,
            showLabel: true,
            providerId: providerId,
            onLeftClick: ModifierAwareInteraction(base: .execute {
                print("⌨️ Executing shortcut: \(name) (\(shortcutDisplay))")
                ShortcutExecutor.execute(keyCode: keyCode, modifierFlags: modifierFlags)
            }),
            onRightClick: ModifierAwareInteraction(base: .doNothing),
            onMiddleClick: ModifierAwareInteraction(base: .doNothing),
            onBoundaryCross: ModifierAwareInteraction(base: .execute {
                print("⌨️ Executing shortcut via boundary: \(name) (\(shortcutDisplay))")
                ShortcutExecutor.execute(keyCode: keyCode, modifierFlags: modifierFlags)
            })
        )
    }
}

// MARK: - Shortcut Executor

/// Utility for posting keyboard shortcuts via CGEvent
struct ShortcutExecutor {
    
    /// Execute a keyboard shortcut by posting CGEvents
    /// - Parameters:
    ///   - keyCode: The main key code
    ///   - modifierFlags: The modifier flags (command, shift, option, control)
    static func execute(keyCode: UInt16, modifierFlags: UInt) {
        // Small delay to ensure the ring has dismissed and target app has focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            postKeyboardShortcut(keyCode: keyCode, modifierFlags: modifierFlags)
        }
    }
    
    private static func postKeyboardShortcut(keyCode: UInt16, modifierFlags: UInt) {
        let source = CGEventSource(stateID: .combinedSessionState)
        
        // Convert NSEvent modifier flags to CGEventFlags
        let nsFlags = NSEvent.ModifierFlags(rawValue: modifierFlags)
        var cgFlags = CGEventFlags()
        
        if nsFlags.contains(.command) { cgFlags.insert(.maskCommand) }
        if nsFlags.contains(.shift) { cgFlags.insert(.maskShift) }
        if nsFlags.contains(.option) { cgFlags.insert(.maskAlternate) }
        if nsFlags.contains(.control) { cgFlags.insert(.maskControl) }
        
        // Create key down event
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) else {
            print("❌ [ShortcutExecutor] Failed to create keyDown event")
            return
        }
        keyDown.flags = cgFlags
        
        // Create key up event
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            print("❌ [ShortcutExecutor] Failed to create keyUp event")
            return
        }
        keyUp.flags = cgFlags
        
        // Post events
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        
        let display = TriggerFormatting.formatShortcut(keyCode: keyCode, modifiers: modifierFlags)
        print("✅ [ShortcutExecutor] Posted shortcut: \(display) (keyCode=\(keyCode), cgFlags=\(cgFlags.rawValue))")
    }
}
