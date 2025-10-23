//
//  FileIconProvider.swift
//  Jason
//
//  Created by Timothy Velberg on 23/10/2025.
//

import Foundation
import AppKit

class FileIconProvider {
    
    // MARK: - Singleton
    
    static let shared = FileIconProvider()
    
    private init() {}
    
    // MARK: - Icon Configuration
    
    private struct IconConfig {
        let symbolName: String
        let backgroundColor: NSColor
        let foregroundColor: NSColor
    }
    
    // Custom icon mappings by file extension
    private let customIcons: [String: IconConfig] = [
        // Documents
        "pdf": IconConfig(symbolName: "doc.fill", backgroundColor: NSColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1.0), foregroundColor: .white),
        "doc": IconConfig(symbolName: "doc.text.fill", backgroundColor: NSColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0), foregroundColor: .white),
        "docx": IconConfig(symbolName: "doc.text.fill", backgroundColor: NSColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0), foregroundColor: .white),
        "txt": IconConfig(symbolName: "doc.plaintext.fill", backgroundColor: NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0), foregroundColor: .white),
        "rtf": IconConfig(symbolName: "doc.richtext.fill", backgroundColor: NSColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0), foregroundColor: .white),
        
        // Spreadsheets
        "xls": IconConfig(symbolName: "tablecells.fill", backgroundColor: NSColor(red: 0.1, green: 0.6, blue: 0.3, alpha: 1.0), foregroundColor: .white),
        "xlsx": IconConfig(symbolName: "tablecells.fill", backgroundColor: NSColor(red: 0.1, green: 0.6, blue: 0.3, alpha: 1.0), foregroundColor: .white),
        "csv": IconConfig(symbolName: "tablecells.fill", backgroundColor: NSColor(red: 0.2, green: 0.5, blue: 0.4, alpha: 1.0), foregroundColor: .white),
        
        // Presentations
        "ppt": IconConfig(symbolName: "rectangle.on.rectangle.fill", backgroundColor: NSColor(red: 0.9, green: 0.4, blue: 0.1, alpha: 1.0), foregroundColor: .white),
        "pptx": IconConfig(symbolName: "rectangle.on.rectangle.fill", backgroundColor: NSColor(red: 0.9, green: 0.4, blue: 0.1, alpha: 1.0), foregroundColor: .white),
        
        // Code
        "swift": IconConfig(symbolName: "swift", backgroundColor: NSColor(red: 0.9, green: 0.4, blue: 0.2, alpha: 1.0), foregroundColor: .white),
        "py": IconConfig(symbolName: "chevron.left.forwardslash.chevron.right", backgroundColor: NSColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1.0), foregroundColor: .white),
        "js": IconConfig(symbolName: "chevron.left.forwardslash.chevron.right", backgroundColor: NSColor(red: 0.9, green: 0.8, blue: 0.2, alpha: 1.0), foregroundColor: .black),
        "ts": IconConfig(symbolName: "chevron.left.forwardslash.chevron.right", backgroundColor: NSColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1.0), foregroundColor: .white),
        "html": IconConfig(symbolName: "chevron.left.forwardslash.chevron.right", backgroundColor: NSColor(red: 0.9, green: 0.3, blue: 0.2, alpha: 1.0), foregroundColor: .white),
        "css": IconConfig(symbolName: "paintbrush.fill", backgroundColor: NSColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1.0), foregroundColor: .white),
        "json": IconConfig(symbolName: "curlybraces", backgroundColor: NSColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0), foregroundColor: .white),
        "xml": IconConfig(symbolName: "chevron.left.forwardslash.chevron.right", backgroundColor: NSColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1.0), foregroundColor: .white),
        
        // Archives
        "zip": IconConfig(symbolName: "doc.zipper", backgroundColor: NSColor(red: 0.5, green: 0.3, blue: 0.6, alpha: 1.0), foregroundColor: .white),
        "rar": IconConfig(symbolName: "doc.zipper", backgroundColor: NSColor(red: 0.6, green: 0.3, blue: 0.5, alpha: 1.0), foregroundColor: .white),
        "7z": IconConfig(symbolName: "doc.zipper", backgroundColor: NSColor(red: 0.4, green: 0.3, blue: 0.6, alpha: 1.0), foregroundColor: .white),
        "tar": IconConfig(symbolName: "doc.zipper", backgroundColor: NSColor(red: 0.5, green: 0.4, blue: 0.3, alpha: 1.0), foregroundColor: .white),
        "gz": IconConfig(symbolName: "doc.zipper", backgroundColor: NSColor(red: 0.5, green: 0.4, blue: 0.3, alpha: 1.0), foregroundColor: .white),
        
        // Audio
        "mp3": IconConfig(symbolName: "music.note", backgroundColor: NSColor(red: 0.8, green: 0.2, blue: 0.4, alpha: 1.0), foregroundColor: .white),
        "wav": IconConfig(symbolName: "waveform", backgroundColor: NSColor(red: 0.7, green: 0.3, blue: 0.5, alpha: 1.0), foregroundColor: .white),
        "m4a": IconConfig(symbolName: "music.note", backgroundColor: NSColor(red: 0.8, green: 0.3, blue: 0.4, alpha: 1.0), foregroundColor: .white),
        "flac": IconConfig(symbolName: "waveform", backgroundColor: NSColor(red: 0.6, green: 0.3, blue: 0.6, alpha: 1.0), foregroundColor: .white),
        
        // Video
        "mp4": IconConfig(symbolName: "video.fill", backgroundColor: NSColor(red: 0.2, green: 0.3, blue: 0.8, alpha: 1.0), foregroundColor: .white),
        "mov": IconConfig(symbolName: "video.fill", backgroundColor: NSColor(red: 0.3, green: 0.3, blue: 0.7, alpha: 1.0), foregroundColor: .white),
        "avi": IconConfig(symbolName: "video.fill", backgroundColor: NSColor(red: 0.4, green: 0.3, blue: 0.6, alpha: 1.0), foregroundColor: .white),
        "mkv": IconConfig(symbolName: "video.fill", backgroundColor: NSColor(red: 0.3, green: 0.4, blue: 0.7, alpha: 1.0), foregroundColor: .white),
        
        // Images (for non-thumbnail cases)
        "svg": IconConfig(symbolName: "photo.fill", backgroundColor: NSColor(red: 0.9, green: 0.6, blue: 0.2, alpha: 1.0), foregroundColor: .white),
        "psd": IconConfig(symbolName: "photo.fill", backgroundColor: NSColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0), foregroundColor: .white),
        
        // Fonts
        "ttf": IconConfig(symbolName: "textformat", backgroundColor: NSColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0), foregroundColor: .white),
        "otf": IconConfig(symbolName: "textformat", backgroundColor: NSColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0), foregroundColor: .white),
        
        // Misc
        "dmg": IconConfig(symbolName: "internaldrive.fill", backgroundColor: NSColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0), foregroundColor: .white),
        "pkg": IconConfig(symbolName: "shippingbox.fill", backgroundColor: NSColor(red: 0.7, green: 0.5, blue: 0.3, alpha: 1.0), foregroundColor: .white),
    ]
    
    // MARK: - Public API
    
    /// Get icon for a file URL with optional custom styling
    func getIcon(for url: URL, size: CGFloat = 64, cornerRadius: CGFloat = 8) -> NSImage {
        let fileExtension = url.pathExtension.lowercased()
        
        // Check if we have a custom icon for this file type
        if let config = customIcons[fileExtension] {
            return createCustomIcon(config: config, size: size, cornerRadius: cornerRadius)
        }
        
        // Fallback to system icon with rounded corners
        return createRoundedSystemIcon(for: url, size: size, cornerRadius: cornerRadius)
    }
    
    /// Check if a file extension has a custom icon
    func hasCustomIcon(for fileExtension: String) -> Bool {
        return customIcons[fileExtension.lowercased()] != nil
    }
    
    // MARK: - Icon Creation
    
    private func createCustomIcon(config: IconConfig, size: CGFloat, cornerRadius: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        
        image.lockFocus()
        
        let rect = NSRect(origin: .zero, size: NSSize(width: size, height: size))
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        
        // Draw background
        config.backgroundColor.setFill()
        path.fill()
        
        // Draw SF Symbol
        if let symbol = NSImage(systemSymbolName: config.symbolName, accessibilityDescription: nil) {
            let symbolSize = size * 0.5  // Symbol takes up 50% of icon
            let symbolRect = NSRect(
                x: (size - symbolSize) / 2,
                y: (size - symbolSize) / 2,
                width: symbolSize,
                height: symbolSize
            )
            
            // Configure symbol with color
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .regular)
            let coloredSymbol = symbol.withSymbolConfiguration(symbolConfig)
            
            // Draw symbol with tint color
            coloredSymbol?.lockFocus()
            config.foregroundColor.setFill()
            rect.fill(using: .sourceAtop)
            coloredSymbol?.unlockFocus()
            
            coloredSymbol?.draw(in: symbolRect)
        }
        
        image.unlockFocus()
        
        return image
    }
    
    private func createRoundedSystemIcon(for url: URL, size: CGFloat, cornerRadius: CGFloat) -> NSImage {
        let systemIcon = NSWorkspace.shared.icon(forFile: url.path)
        let roundedIcon = NSImage(size: NSSize(width: size, height: size))
        
        roundedIcon.lockFocus()
        
        let rect = NSRect(origin: .zero, size: NSSize(width: size, height: size))
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        
        // Clip to rounded rect
        path.addClip()
        
        // Draw system icon
        systemIcon.draw(
            in: rect,
            from: NSRect(origin: .zero, size: systemIcon.size),
            operation: .sourceOver,
            fraction: 1.0
        )
        
        roundedIcon.unlockFocus()
        
        return roundedIcon
    }
    
    // MARK: - Batch Operations
    
    /// Get icons for multiple URLs (useful for batch loading)
    func getIcons(for urls: [URL], size: CGFloat = 64, cornerRadius: CGFloat = 8) -> [URL: NSImage] {
        var icons: [URL: NSImage] = [:]
        for url in urls {
            icons[url] = getIcon(for: url, size: size, cornerRadius: cornerRadius)
        }
        return icons
    }
}
