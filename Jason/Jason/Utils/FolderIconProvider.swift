//
//  FolderIconProvider.swift
//  Jason
//
//  Created by Timothy Velberg on 23/10/2025.
//

import Foundation
import AppKit

class FolderIconProvider {
    
    // MARK: - Singleton
    
    static let shared = FolderIconProvider()
    
    private init() {}
    
    // MARK: - Icon Type
    
    private enum IconType {
        case systemWithColor(NSColor)     // System folder icon with custom color tint
        case customAsset(String)           // Custom icon from Asset Catalog
        case sfSymbol(SFSymbolConfig)      // SF Symbol-based folder icon
    }
    
    private struct SFSymbolConfig {
        let symbolName: String
        let backgroundColor: NSColor
        let foregroundColor: NSColor
    }
    
    // MARK: - Folder Configuration
    
    private struct FolderConfig {
        let type: IconType
    }
    
    // MARK: - Custom Folder Mappings
    
    // Map specific folder paths to custom icons
    private var pathBasedIcons: [String: FolderConfig] = [:]
    
    // Map folder names to custom icons (applies to any folder with that name)
    private let nameBasedIcons: [String: FolderConfig] = [
        // Examples - customize these or add your own
        "Downloads": FolderConfig(type: .systemWithColor(NSColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1.0))),
        "Documents": FolderConfig(type: .systemWithColor(NSColor(red: 0.3, green: 0.5, blue: 0.8, alpha: 1.0))),
        "Desktop": FolderConfig(type: .systemWithColor(NSColor(red: 0.5, green: 0.4, blue: 0.7, alpha: 1.0))),
        "Projects": FolderConfig(type: .systemWithColor(NSColor(red: 0.9, green: 0.5, blue: 0.2, alpha: 1.0))),
        "Music": FolderConfig(type: .systemWithColor(NSColor(red: 0.9, green: 0.3, blue: 0.4, alpha: 1.0))),
        "Pictures": FolderConfig(type: .systemWithColor(NSColor(red: 0.8, green: 0.2, blue: 0.6, alpha: 1.0))),
        "Movies": FolderConfig(type: .systemWithColor(NSColor(red: 0.6, green: 0.3, blue: 0.8, alpha: 1.0))),
        
        // Example with SF Symbol
        // "Archive": FolderConfig(type: .sfSymbol(SFSymbolConfig(symbolName: "archivebox.fill", backgroundColor: NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0), foregroundColor: .white))),
        
        // Example with custom asset
        // "Special": FolderConfig(type: .customAsset("SpecialFolderIcon")),
    ]
    
    // MARK: - Public API
    
    /// Get icon for a folder URL with optional custom styling
    func getIcon(for url: URL, size: CGFloat = 64, cornerRadius: CGFloat = 8) -> NSImage {
        let folderName = url.lastPathComponent
        let folderPath = url.path
        
        // Priority 1: Check path-based customization (most specific)
        if let config = pathBasedIcons[folderPath] {
            return createIcon(config: config, url: url, size: size, cornerRadius: cornerRadius)
        }
        
        // Priority 2: Check name-based customization
        if let config = nameBasedIcons[folderName] {
            return createIcon(config: config, url: url, size: size, cornerRadius: cornerRadius)
        }
        
        // Priority 3: Fallback to system icon
        return createSystemFolderIcon(for: url, size: size, cornerRadius: cornerRadius)
    }
    
    /// Set a custom color for a specific folder path
    func setColor(_ color: NSColor, forPath path: String) {
        pathBasedIcons[path] = FolderConfig(type: .systemWithColor(color))
        print("🎨 [FolderIconProvider] Set custom color for path: \(path)")
    }
    
    /// Set a custom asset icon for a specific folder path
    func setCustomAsset(_ assetName: String, forPath path: String) {
        pathBasedIcons[path] = FolderConfig(type: .customAsset(assetName))
        print("🎨 [FolderIconProvider] Set custom asset '\(assetName)' for path: \(path)")
    }
    
    /// Remove custom styling for a specific path
    func removeCustomization(forPath path: String) {
        pathBasedIcons.removeValue(forKey: path)
        print("🗑️ [FolderIconProvider] Removed customization for path: \(path)")
    }
    
    /// Check if a folder has custom styling
    func hasCustomIcon(forPath path: String) -> Bool {
        return pathBasedIcons[path] != nil
    }
    
    /// Get all paths with custom icons
    func getCustomizedPaths() -> [String] {
        return Array(pathBasedIcons.keys)
    }
    
    // MARK: - Icon Creation
    
    private func createIcon(config: FolderConfig, url: URL, size: CGFloat, cornerRadius: CGFloat) -> NSImage {
        switch config.type {
        case .systemWithColor(let color):
            return createColoredFolderIcon(for: url, color: color, size: size, cornerRadius: cornerRadius)
        case .customAsset(let assetName):
            return createCustomAssetIcon(assetName: assetName, size: size, cornerRadius: cornerRadius)
        case .sfSymbol(let symbolConfig):
            return createSFSymbolIcon(config: symbolConfig, size: size, cornerRadius: cornerRadius)
        }
    }
    
    private func createColoredFolderIcon(for url: URL, color: NSColor, size: CGFloat, cornerRadius: CGFloat) -> NSImage {
        let systemIcon = NSWorkspace.shared.icon(forFile: url.path)
        let coloredIcon = NSImage(size: NSSize(width: size, height: size))
        
        coloredIcon.lockFocus()
        
        let rect = NSRect(origin: .zero, size: NSSize(width: size, height: size))
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        
        // Clip to rounded rect
        path.addClip()
        
        // Draw the system folder icon
        systemIcon.draw(
            in: rect,
            from: NSRect(origin: .zero, size: systemIcon.size),
            operation: .sourceOver,
            fraction: 1.0
        )
        
        // Apply color tint overlay
        color.setFill()
        rect.fill(using: .sourceAtop)  // This blends the color with the icon
        
        coloredIcon.unlockFocus()
        
        return coloredIcon
    }
    
    private func createCustomAssetIcon(assetName: String, size: CGFloat, cornerRadius: CGFloat) -> NSImage {
        guard let assetImage = NSImage(named: assetName) else {
            print("⚠️ [FolderIconProvider] Asset '\(assetName)' not found - using system icon")
            return NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage()
        }
        
        let roundedIcon = NSImage(size: NSSize(width: size, height: size))
        
        roundedIcon.lockFocus()
        
        let rect = NSRect(origin: .zero, size: NSSize(width: size, height: size))
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        
        // Clip to rounded rect
        path.addClip()
        
        // Draw asset image
        assetImage.draw(
            in: rect,
            from: NSRect(origin: .zero, size: assetImage.size),
            operation: .sourceOver,
            fraction: 1.0
        )
        
        roundedIcon.unlockFocus()
        
        return roundedIcon
    }
    
    private func createSFSymbolIcon(config: SFSymbolConfig, size: CGFloat, cornerRadius: CGFloat) -> NSImage {
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
    
    private func createSystemFolderIcon(for url: URL, size: CGFloat, cornerRadius: CGFloat) -> NSImage {
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
    
    // MARK: - Persistence Support (for future database integration)
    
    /// Load custom folder colors from database
    func loadCustomizations(from entries: [(path: String, color: NSColor)]) {
        for entry in entries {
            setColor(entry.color, forPath: entry.path)
        }
        print("📦 [FolderIconProvider] Loaded \(entries.count) custom folder colors")
    }
    
    /// Export current customizations for database storage
    func exportCustomizations() -> [(path: String, colorHex: String)] {
        return pathBasedIcons.compactMap { path, config in
            if case .systemWithColor(let color) = config.type {
                return (path: path, colorHex: color.hexString)
            }
            return nil
        }
    }
}

// MARK: - NSColor Extension for Hex Conversion

extension NSColor {
    /// Convert NSColor to hex string for database storage
    var hexString: String {
        guard let rgbColor = usingColorSpace(.deviceRGB) else {
            return "#000000"
        }
        
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        
        return String(format: "#%02X%02X%02X", r, g, b)
    }
    
    /// Create NSColor from hex string
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }
        
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
