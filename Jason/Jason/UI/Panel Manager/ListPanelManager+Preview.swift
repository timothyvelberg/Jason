//
//  ListPanelManager+Preview.swift
//  Jason
//
//  Created by Timothy Velberg on 27/02/2026.
//  Preview panel logic for ListPanelManager.
//

import Foundation
import AppKit

extension ListPanelManager {

    /// Toggle preview panel for the currently selected item
    func togglePreview() {
        // If a preview panel already exists at activePanelLevel + 1, pop it
        if let _ = panelStack.first(where: {
            $0.level == activePanelLevel + 1 && $0.previewContent != nil
        }) {
            popToLevel(activePanelLevel)
            print("[Preview] Closed preview panel")
            return
        }

        // Get the currently selected node
        guard let selectedRow = effectiveSelectedRow(for: activePanelLevel) ?? hoveredRow[activePanelLevel],
              let panel = panelStack.first(where: { $0.level == activePanelLevel }),
              selectedRow < panel.items.count else {
            print("[Preview] No item selected")
            return
        }

        let node = panel.items[selectedRow]
        let content = loadPreviewContent(for: node)

        if case .unsupported = content {
            print("[Preview] Item '\(node.name)' has no previewable content")
            return
        }

        pushPreviewPanel(content: content, fromLevel: activePanelLevel, sourceRowIndex: selectedRow)
    }

    /// Extract preview content from a node
    func loadPreviewContent(for node: FunctionNode) -> PreviewContent {
        print("[Preview] node: '\(node.name)' previewURL: \(node.previewURL?.path ?? "nil") metadata keys: \(node.metadata?.keys.map { $0 } ?? [])")
        // Case 1: Has a previewURL — file from FavoriteFolderProvider
        if let url = node.previewURL {
            let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"]
            let unsupportedExtensions = ["nzb", "zip", "dmg", "mkv", "mp4", "mov", "avi", "mp3", "pdf", "exe", "pkg"]
            let ext = url.pathExtension.lowercased()

            if unsupportedExtensions.contains(ext) {
                return .unsupported
            }

            if imageExtensions.contains(ext) {
                if let image = NSImage(contentsOf: url) {
                    return .image(image)
                }
            } else {
                // Check file size before reading
                let fileSizeLimit: Int = 512 * 1024  // 512KB
                if let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   fileSize > fileSizeLimit {
                    return .unsupported
                }

                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    return .text(text)
                } else if let text = try? String(contentsOf: url, encoding: .isoLatin1) {
                    return .text(text)
                }
            }
            return .unsupported
        }

        // Case 2: Clipboard item — full text content in metadata
        if let fullContent = node.metadata?["fullContent"] as? String {
            return .text(fullContent)
        }

        return .unsupported
    }

    /// Push a preview panel to the right of the source panel
    private func pushPreviewPanel(content: PreviewContent, fromLevel level: Int, sourceRowIndex: Int) {
        guard let sourcePanel = panelStack.first(where: { $0.level == level }) else { return }

        // Pop any existing child panels
        popToLevel(level)

        let config = sourcePanel.config
        let previewWidth = config.previewPanelWidth
        let previewHeight = config.previewPanelMaxHeight

        // Position to the right of the source panel
        let sourceBounds = currentBounds(for: sourcePanel)
        print("[Preview] sourcePanel level: \(level), sourceBounds: \(sourceBounds), currentPos: \(currentPosition(for: sourcePanel))")

        let gap: CGFloat = 8
        let newX = sourceBounds.maxX + gap + (previewWidth / 2)

        let rowTopOffset = sourcePanel.yOffsetForRow(sourceRowIndex)
        let rowHeight = sourcePanel.heightForRow(sourceRowIndex)

        let visualOffset = rowTopOffset - sourcePanel.scrollOffset
        let visibleContentHeight = sourcePanel.visibleContentHeight
        let clampedOffset = max(0, min(visualOffset, visibleContentHeight - rowHeight))

        let rowCenterY = sourceBounds.maxY - PanelConfig.contentTopInset - clampedOffset - (rowHeight / 2)
        let newY = rowCenterY

        let position = CGPoint(x: newX, y: newY)
        let constrainedPosition = constrainToScreenBounds(
            position: position,
            panelWidth: previewWidth,
            panelHeight: previewHeight
        )

        let previewPanel = PanelState(
            title: "Preview",
            items: [],
            position: constrainedPosition,
            level: level + 1,
            sourceNodeId: nil,
            sourceRowIndex: sourceRowIndex,
            spawnAngle: nil,
            contextActions: nil,
            previewContent: content,
            config: config,
            providerId: nil,
            contentIdentifier: nil,
            expandedItemId: nil,
            isOverlapping: false,
            scrollOffset: 0,
            typingMode: .typeAhead,
            activeTypingMode: .typeAhead
        )

        panelStack.append(previewPanel)
        print("[Preview] Pushed preview panel at level \(level + 1)")
    }
}
