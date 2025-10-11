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
            icon: NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil) ?? NSImage(),
            onLeftClick: .execute { [weak manager] in
                manager?.switchToApp(app)
            },
            onMiddleClick: .executeKeepOpen { [weak manager] in
                manager?.switchToApp(app)
            }
        )
    }
    
    /// Create a "Hide" action for an application
    static func hideApp(_ app: NSRunningApplication, manager: AppSwitcherManager) -> FunctionNode {
        return FunctionNode(
            id: "hide-\(app.processIdentifier)",
            name: "Hide",
            icon: NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil) ?? NSImage(),
            onLeftClick: .execute { [weak manager] in
                manager?.hideApp(app)
            },
            onMiddleClick: .executeKeepOpen { [weak manager] in
                manager?.hideApp(app)
            }
        )
    }
    
    /// Create a "Quit" action for an application
    static func quitApp(_ app: NSRunningApplication, manager: AppSwitcherManager) -> FunctionNode {
        return FunctionNode(
            id: "quit-\(app.processIdentifier)",
            name: "Quit",
            icon: NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil) ?? NSImage(),
            onLeftClick: .execute { [weak manager] in
                manager?.quitApp(app)
            },
            onMiddleClick: .executeKeepOpen { [weak manager] in
                manager?.quitApp(app)
            }
        )
    }
    
    // MARK: - File Actions
    
    /// Create an "Open" action for a file/folder
    static func openFile(_ url: URL) -> FunctionNode {
        return FunctionNode(
            id: "open-\(url.path)",
            name: "Open",
            icon: NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil) ?? NSImage(),
            onLeftClick: .execute {
                NSWorkspace.shared.open(url)
            },
            onMiddleClick: .executeKeepOpen {
                NSWorkspace.shared.open(url)
            }
        )
    }
    
    /// Create a "Show in Finder" action for a file/folder
    static func showInFinder(_ url: URL) -> FunctionNode {
        return FunctionNode(
            id: "show-in-finder-\(url.path)",
            name: "Show in Finder",
            icon: NSImage(systemSymbolName: "folder", accessibilityDescription: nil) ?? NSImage(),
            onLeftClick: .execute {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            },
            onMiddleClick: .executeKeepOpen {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        )
    }
    
    /// Create a "Delete" action for a file/folder (moves to trash)
    static func deleteFile(_ url: URL, onComplete: @escaping (Bool) -> Void = { _ in }) -> FunctionNode {
        let fileName = url.lastPathComponent
        return FunctionNode(
            id: "delete-\(url.path)",
            name: "Delete",
            icon: NSImage(systemSymbolName: "trash", accessibilityDescription: nil) ?? NSImage(),
            onLeftClick: .execute {
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
            },
            onMiddleClick: .executeKeepOpen {
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
            }
        )
    }
}
