//
//  StandardContextActions.swift
//  Jason
//
//  Created by Timothy Velberg on 11/10/2025.
//

import Foundation
import AppKit

/// Factory for creating standard context actions that can be reused across providers
struct StandardContextActions {
    
    // MARK: - App Actions
    
    /// Create a "Bring to Front" action for an application
    static func bringToFront(_ app: NSRunningApplication, manager: AppSwitcherManager) -> FunctionNode {
        return FunctionNode(
            id: "activate-\(app.processIdentifier)",
            name: "Bring to Front",
            type: .action,
            icon: NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil) ?? NSImage(),
            onLeftClick: ModifierAwareInteraction(base: .execute { [weak manager] in
                manager?.switchToApp(app)
            }),
            onMiddleClick: ModifierAwareInteraction(base: .executeKeepOpen { [weak manager] in
                manager?.switchToApp(app)
            })
        )
    }
    
    /// Create a "Hide" action for an application
    static func hideApp(_ app: NSRunningApplication, manager: AppSwitcherManager) -> FunctionNode {
        return FunctionNode(
            id: "hide-\(app.processIdentifier)",
            name: "Hide",
            type: .action,
            icon: NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil) ?? NSImage(),
            onLeftClick: ModifierAwareInteraction(base: .execute { [weak manager] in
                manager?.hideApp(app)
            }),
            onMiddleClick: ModifierAwareInteraction(base: .executeKeepOpen { [weak manager] in
                manager?.hideApp(app)
            })
        )
    }
    
    /// Create a "Quit" action for an application
    static func quitApp(_ app: NSRunningApplication, manager: AppSwitcherManager) -> FunctionNode {
        return FunctionNode(
            id: "quit-\(app.processIdentifier)",
            name: "Quit",
            type: .action,
            icon: NSImage(named: "context_actions_close") ?? NSImage(),
            onLeftClick: ModifierAwareInteraction(base: .executeKeepOpen { [weak manager] in
                manager?.quitApp(app)
            }),
            onMiddleClick: ModifierAwareInteraction(base: .executeKeepOpen { [weak manager] in
                manager?.quitApp(app)
            })
        )
    }
    
    // MARK: - File Actions
    
    /// Create an "Open" action for a file/folder
    static func openFile(_ url: URL) -> FunctionNode {
        return FunctionNode(
            id: "open-\(url.path)",
            name: "Open",
            type: .action,
            icon: NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil) ?? NSImage(),
            onLeftClick: ModifierAwareInteraction(base: .execute {
                NSWorkspace.shared.open(url)
            }),
            onMiddleClick: ModifierAwareInteraction(base: .executeKeepOpen {
                NSWorkspace.shared.open(url)
            })
        )
    }
    
    /// Create a "Show in Finder" action for a file/folder
    static func showInFinder(_ url: URL) -> FunctionNode {
        return FunctionNode(
            id: "show-in-finder-\(url.path)",
            name: "Show in Finder",
            type: .action,
            icon: NSImage(named: "context_actions_folder") ?? NSImage(),
            onLeftClick: ModifierAwareInteraction(base: .execute {
                NSWorkspace.shared.selectFileAndActivate(url)
            }),
            onMiddleClick: ModifierAwareInteraction(base: .executeKeepOpen {
                NSWorkspace.shared.selectFileAndActivate(url)
            })
        )
    }
    
    /// Create a "Delete" action for a file/folder (moves to trash)
    static func deleteFile(_ url: URL, onComplete: @escaping (Bool) -> Void = { _ in }) -> FunctionNode {
        let fileName = url.lastPathComponent
        return FunctionNode(
            id: "delete-\(url.path)",
            name: "Delete",
            type: .action,
            icon: NSImage(named: "context_actions_delete") ?? NSImage(),
            onLeftClick: ModifierAwareInteraction(base: .executeKeepOpen {
                print("🗑️ Moving to trash: \(fileName)")
                NSWorkspace.shared.recycle([url]) { trashedURLs, error in
                    if let error = error {
                        print("❌ Failed to delete file: \(error.localizedDescription)")
                        onComplete(false)
                    } else {
                        print("✅ File moved to trash: \(fileName)")
                        onComplete(true)
                    }
                }
            }),
            onMiddleClick: ModifierAwareInteraction(base: .executeKeepOpen {
                print("🗑️ Moving to trash (UI stays open): \(fileName)")
                NSWorkspace.shared.recycle([url]) { trashedURLs, error in
                    if let error = error {
                        print("❌ Failed to delete file: \(error.localizedDescription)")
                        onComplete(false)
                    } else {
                        print("✅ File moved to trash: \(fileName)")
                        onComplete(true)
                    }
                }
            })
        )
    }
    
    /// Create a "Copy" action for a file/folder (copies to clipboard)
    static func copyFile(_ url: URL) -> FunctionNode {
        let fileName = url.lastPathComponent
        return FunctionNode(
            id: "copy-\(url.path)",
            name: "Copy",
            type: .action,
            icon: NSImage(named: "context_actions_copy") ?? NSImage(),
            onLeftClick: ModifierAwareInteraction(base: .execute {
                print("📋 Copying to clipboard: \(fileName)")
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([url as NSURL])
                print("✅ File copied to clipboard: \(fileName)")
            }),
            onMiddleClick: ModifierAwareInteraction(base: .executeKeepOpen {
                print("📋 Copying to clipboard (UI stays open): \(fileName)")
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([url as NSURL])
                print("✅ File copied to clipboard: \(fileName)")
            })
        )
    }
}

extension NSWorkspace {
    /// Opens a URL and ensures the handling app activates (comes to front)
    func openAndActivate(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        
        self.open(url, configuration: configuration) { app, error in
            if let error = error {
                print("❌ Failed to open \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
    
    /// Reveals file in Finder and ensures Finder activates (comes to front)
    func selectFileAndActivate(_ url: URL) {
        self.activateFileViewerSelecting([url])
        
        // Explicitly bring Finder to front
        if let finder = self.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.finder" }) {
            finder.activate()
        }
    }
}
