//
//  KeyboardEventHandler.swift
//  Jason
//
//  Created by Timothy Velberg on 31/07/2025.
//

import Foundation
import AppKit

extension AppSwitcherManager {
    
    // MARK: - Keyboard Event Handling
    
    func handleGlobalKeyEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            handleKeyDown(event, isGlobal: true)
        case .keyUp:
            handleKeyUp(event, isGlobal: true)
        case .flagsChanged:
            handleFlagsChanged(event, isGlobal: true)
        default:
            break
        }
    }
    
    func handleLocalKeyEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            handleKeyDown(event, isGlobal: false)
        case .keyUp:
            handleKeyUp(event, isGlobal: false)
        case .flagsChanged:
            handleFlagsChanged(event, isGlobal: false)
        default:
            break
        }
    }
    
    private func handleKeyDown(_ event: NSEvent, isGlobal: Bool) {
        let isCtrlPressed = event.modifierFlags.contains(.control)
        let isKey2 = event.keyCode == 19  // Key code for "2"
        
        if isCtrlPressed && isKey2 && !isVisible {
            print("🔥 \(isGlobal ? "Global" : "Local") Ctrl+2 detected!")
            showAppSwitcher()
            return
        }
        
        // Handle navigation when switcher is visible
        if isVisible {
            print("🎮 Navigation key detected: \(event.keyCode)")
            switch event.keyCode {
            case 48: // Tab key
                print("📋 Tab key pressed")
                if event.modifierFlags.contains(.shift) {
                    navigatePrevious()
                } else {
                    navigateNext()
                }
            case 125: // Down arrow
                print("⬇️ Down arrow pressed")
                navigateNext()
            case 126: // Up arrow
                print("⬆️ Up arrow pressed")
                navigatePrevious()
            case 123: // Left arrow
                print("⬅️ Left arrow pressed")
                navigatePrevious()
            case 124: // Right arrow
                print("➡️ Right arrow pressed")
                navigateNext()
            case 36: // Enter/Return
                print("↩️ Enter pressed")
                selectCurrentApp()
            case 53: // Escape
                print("⌨️ Escape pressed - hiding app switcher")
                hideAppSwitcher()
            default:
                print("❓ Unknown key: \(event.keyCode)")
                break
            }
        }
    }
    
    private func handleKeyUp(_ event: NSEvent, isGlobal: Bool) {
        // We'll handle this in flagsChanged for better reliability
    }
    
    private func handleFlagsChanged(_ event: NSEvent, isGlobal: Bool) {
        let wasCtrlPressed = isCtrlPressed
        let isCtrlCurrentlyPressed = event.modifierFlags.contains(.control)
        
        isCtrlPressed = isCtrlCurrentlyPressed
        
        // If Ctrl was released and switcher is visible, select the current app
        if wasCtrlPressed && !isCtrlCurrentlyPressed && isVisible {
            print("🎹 Ctrl released - selecting current app")
            selectCurrentApp()
        }
    }
}
