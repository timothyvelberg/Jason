//
//  FinderLogic.swift
//  Jason
//
//  Created by Timothy Velberg on 08/10/2025.
//

import Foundation
import AppKit

class FinderLogic: FunctionProvider {
    
    // MARK: - Provider Info
    
    var providerId: String { "finder" }
    var providerName: String { "Finder" }
    var providerIcon: NSImage {
        return NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")
    }
    
    // MARK: - Settings
    
    private let maxItemsPerFolder: Int = 5
    
    // TEST: Just your Desktop folder
    private let startingFolders: [URL] = [
        URL(fileURLWithPath: "/Users/timothy/Desktop")
    ]
    
    // MARK: - Provide Functions
    
    func provideFunctions() -> [FunctionNode] {
        print("🔍 [FinderLogic] provideFunctions() called")
        
        // TEST: Return Desktop folder directly (no wrapper)
        // This makes it appear directly in Ring 0
        let folderNodes = startingFolders.compactMap { folderURL in
            createFolderNode(for: folderURL)
        }
        
        print("🔍 [FinderLogic] Returning \(folderNodes.count) root node(s)")
        return folderNodes
    }
    
    func refresh() {
        print("🔄 [FinderLogic] refresh() called")
        // No-op for now, file system is always up-to-date
    }
    
    // MARK: - Private Logic
    
    /// Creates a FunctionNode for a folder
    /// - On press: Opens the folder in Finder
    /// - Sub-category: Shows folder contents (up to maxItemsPerFolder)
    private func createFolderNode(for folderURL: URL) -> FunctionNode? {
        guard folderURL.hasDirectoryPath else { return nil }
        
        print("📂 [FinderLogic] Creating node for folder: \(folderURL.lastPathComponent)")
        
        // Get folder contents
        let contents = getFolderContents(folderURL)
        print("   Found \(contents.count) items")
        
        // Limit to max items
        let limitedContents = Array(contents.prefix(maxItemsPerFolder))
        print("   Showing \(limitedContents.count) items (limit: \(maxItemsPerFolder))")
        
        // Create child nodes for each item
        let childNodes = limitedContents.compactMap { itemURL -> FunctionNode? in
            if itemURL.hasDirectoryPath {
                // It's a folder - recurse
                return createFolderNode(for: itemURL)
            } else {
                // It's a file - create file node
                return createFileNode(for: itemURL)
            }
        }
        
        return FunctionNode(
            id: "folder-\(folderURL.path)",
            name: folderURL.lastPathComponent,
            icon: NSWorkspace.shared.icon(forFile: folderURL.path),
            children: childNodes.isEmpty ? nil : childNodes,
            contextActions: [
                FunctionNode(
                    id: "open-folder-\(folderURL.path)",
                    name: "Open in Finder",
                    icon: NSImage(systemSymbolName: "folder", accessibilityDescription: nil) ?? NSImage(),
                    onSelect: { [weak self] in
                        self?.openInFinder(folderURL)
                    }
                ),
                FunctionNode(
                    id: "reveal-folder-\(folderURL.path)",
                    name: "Reveal in Finder",
                    icon: NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil) ?? NSImage(),
                    onSelect: { [weak self] in
                        self?.revealInFinder(folderURL)
                    }
                )
            ],
            onSelect: { [weak self] in
                // Primary action: Open folder
                self?.openInFinder(folderURL)
            },
            maxDisplayedChildren: maxItemsPerFolder
        )
    }
    
    /// Creates a FunctionNode for a file
    /// - On press: Opens the file
    private func createFileNode(for fileURL: URL) -> FunctionNode? {
        guard !fileURL.hasDirectoryPath else { return nil }
        
        print("📄 [FinderLogic] Creating node for file: \(fileURL.lastPathComponent)")
        
        return FunctionNode(
            id: "file-\(fileURL.path)",
            name: fileURL.lastPathComponent,
            icon: NSWorkspace.shared.icon(forFile: fileURL.path),
            contextActions: [
                FunctionNode(
                    id: "open-file-\(fileURL.path)",
                    name: "Open",
                    icon: NSImage(systemSymbolName: "doc", accessibilityDescription: nil) ?? NSImage(),
                    onSelect: { [weak self] in
                        self?.openFile(fileURL)
                    }
                ),
                FunctionNode(
                    id: "reveal-file-\(fileURL.path)",
                    name: "Reveal in Finder",
                    icon: NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil) ?? NSImage(),
                    onSelect: { [weak self] in
                        self?.revealInFinder(fileURL)
                    }
                ),
                FunctionNode(
                    id: "quicklook-\(fileURL.path)",
                    name: "Quick Look",
                    icon: NSImage(systemSymbolName: "eye", accessibilityDescription: nil) ?? NSImage(),
                    onSelect: { [weak self] in
                        self?.quickLook(fileURL)
                    }
                )
            ],
            onSelect: { [weak self] in
                // Primary action: Open file
                self?.openFile(fileURL)
            }
        )
    }
    
    // MARK: - File System Helpers
    
    private func getFolderContents(_ folderURL: URL) -> [URL] {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            return contents.sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            print("Error reading folder contents: \(error)")
            return []
        }
    }
    
    // MARK: - Actions
    
    private func openInFinder(_ url: URL) {
        print("📂 Opening folder: \(url.lastPathComponent)")
        NSWorkspace.shared.open(url)
    }
    
    private func openFile(_ url: URL) {
        print("📄 Opening file: \(url.lastPathComponent)")
        NSWorkspace.shared.open(url)
    }
    
    private func revealInFinder(_ url: URL) {
        print("👁️ Revealing in Finder: \(url.lastPathComponent)")
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    private func quickLook(_ url: URL) {
        print("👀 Quick Look: \(url.lastPathComponent)")
        // Note: Quick Look requires QLPreviewPanel, more complex to implement
        // For now, just open the file
        NSWorkspace.shared.open(url)
    }
}
