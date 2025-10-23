//
//  IconProvider.swift
//  Jason
//
//  Unified icon provider for both files and folders with custom styling

import Foundation
import AppKit

class IconProvider {
    
    // MARK: - Singleton
    
    static let shared = IconProvider()
    
    private init() {}
    
    // MARK: - Icon Configuration Structures
    
    private struct FileIconConfig {
        let symbolName: String
        let backgroundColor: NSColor
        let foregroundColor: NSColor
        
        // Convenience initializer with color names
        init(symbolName: String, symbolColor: FileIconColor) {
            self.symbolName = symbolName
            self.backgroundColor = .white
            self.foregroundColor = symbolColor.nsColor
        }
    }
    
    private enum FolderIconType {
        case systemWithColor(NSColor)     // System folder icon with custom color tint
        case customAsset(String)           // Custom icon from Asset Catalog
        case composite(baseAsset: String, symbol: String, symbolColor: NSColor, symbolSize: CGFloat, symbolOffset: CGFloat)
    }
    
    private struct FolderConfig {
        let type: FolderIconType
    }
    
    // Simple color enum
    private enum FileIconColor {
        case red
        case blue
        case green
        case orange
        case purple
        case yellow
        case pink
        case teal
        case gray
        case brown
        
        var nsColor: NSColor {
            switch self {
            case .red: return NSColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1.0)
            case .blue: return NSColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0)
            case .green: return NSColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1.0)
            case .orange: return NSColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1.0)
            case .purple: return NSColor(red: 0.6, green: 0.3, blue: 0.8, alpha: 1.0)
            case .yellow: return NSColor(red: 0.9, green: 0.8, blue: 0.2, alpha: 1.0)
            case .pink: return NSColor(red: 0.9, green: 0.4, blue: 0.6, alpha: 1.0)
            case .teal: return NSColor(red: 0.2, green: 0.7, blue: 0.7, alpha: 1.0)
            case .gray: return NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
            case .brown: return NSColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1.0)
            }
        }
    }
    
    // Custom icon mappings by file extension
    private let fileIcons: [String: FileIconConfig] = [
        // Documents
        "pdf": FileIconConfig(symbolName: "doc.fill", symbolColor: .red),
        "doc": FileIconConfig(symbolName: "doc.text.fill", symbolColor: .blue),
        "docx": FileIconConfig(symbolName: "doc.text.fill", symbolColor: .blue),
        "txt": FileIconConfig(symbolName: "doc.plaintext.fill", symbolColor: .gray),
        "rtf": FileIconConfig(symbolName: "doc.richtext.fill", symbolColor: .gray),
        
        // Spreadsheets
        "xls": FileIconConfig(symbolName: "tablecells.fill", symbolColor: .green),
        "xlsx": FileIconConfig(symbolName: "tablecells.fill", symbolColor: .green),
        "csv": FileIconConfig(symbolName: "tablecells.fill", symbolColor: .teal),
        
        // Presentations
        "ppt": FileIconConfig(symbolName: "rectangle.on.rectangle.fill", symbolColor: .orange),
        "pptx": FileIconConfig(symbolName: "rectangle.on.rectangle.fill", symbolColor: .orange),
        
        // Code
        "swift": FileIconConfig(symbolName: "swift", symbolColor: .orange),
        "py": FileIconConfig(symbolName: "chevron.left.forwardslash.chevron.right", symbolColor: .blue),
        "js": FileIconConfig(symbolName: "chevron.left.forwardslash.chevron.right", symbolColor: .yellow),
        "ts": FileIconConfig(symbolName: "chevron.left.forwardslash.chevron.right", symbolColor: .blue),
        "html": FileIconConfig(symbolName: "chevron.left.forwardslash.chevron.right", symbolColor: .red),
        "css": FileIconConfig(symbolName: "paintbrush.fill", symbolColor: .blue),
        "json": FileIconConfig(symbolName: "curlybraces", symbolColor: .gray),
        "xml": FileIconConfig(symbolName: "chevron.left.forwardslash.chevron.right", symbolColor: .brown),
        
        // Archives
        "zip": FileIconConfig(symbolName: "doc.zipper", symbolColor: .purple),
        "rar": FileIconConfig(symbolName: "doc.zipper", symbolColor: .purple),
        "7z": FileIconConfig(symbolName: "doc.zipper", symbolColor: .purple),
        "tar": FileIconConfig(symbolName: "doc.zipper", symbolColor: .brown),
        "gz": FileIconConfig(symbolName: "doc.zipper", symbolColor: .brown),
        
        // Audio
        "mp3": FileIconConfig(symbolName: "music.note", symbolColor: .pink),
        "wav": FileIconConfig(symbolName: "waveform", symbolColor: .pink),
        "m4a": FileIconConfig(symbolName: "music.note", symbolColor: .pink),
        "flac": FileIconConfig(symbolName: "waveform", symbolColor: .purple),
        
        // Video
        "mp4": FileIconConfig(symbolName: "video.fill", symbolColor: .blue),
        "mov": FileIconConfig(symbolName: "video.fill", symbolColor: .blue),
        "avi": FileIconConfig(symbolName: "video.fill", symbolColor: .purple),
        "mkv": FileIconConfig(symbolName: "video.fill", symbolColor: .teal),
        
        // Images (for non-thumbnail cases)
        "svg": FileIconConfig(symbolName: "photo.fill", symbolColor: .orange),
        "psd": FileIconConfig(symbolName: "photo.fill", symbolColor: .blue),
        
        // Fonts
        "ttf": FileIconConfig(symbolName: "textformat", symbolColor: .gray),
        "otf": FileIconConfig(symbolName: "textformat", symbolColor: .gray),
        
        // Misc
        "dmg": FileIconConfig(symbolName: "internaldrive.fill", symbolColor: .gray),
        "pkg": FileIconConfig(symbolName: "shippingbox.fill", symbolColor: .brown),
    ]
    
    // MARK: - Folder Mappings
    
    // Map specific folder paths to custom icons
    private var pathBasedFolderIcons: [String: FolderConfig] = [:]
    
    // Map folder names to custom icons (applies to any folder with that name)
    private let nameBasedFolderIcons: [String: FolderConfig] = [
        "Downloads": FolderConfig(type: .systemWithColor(NSColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1.0))),
        "Documents": FolderConfig(type: .systemWithColor(NSColor(red: 0.3, green: 0.5, blue: 0.8, alpha: 1.0))),
        "Desktop": FolderConfig(type: .systemWithColor(NSColor(red: 0.5, green: 0.4, blue: 0.7, alpha: 1.0))),
        "Projects": FolderConfig(type: .systemWithColor(NSColor(red: 0.9, green: 0.5, blue: 0.2, alpha: 1.0))),
        "Music": FolderConfig(type: .systemWithColor(NSColor(red: 0.9, green: 0.3, blue: 0.4, alpha: 1.0))),
        "Pictures": FolderConfig(type: .systemWithColor(NSColor(red: 0.8, green: 0.2, blue: 0.6, alpha: 1.0))),
        "Movies": FolderConfig(type: .systemWithColor(NSColor(red: 0.6, green: 0.3, blue: 0.8, alpha: 1.0))),
    ]
    
    // MARK: - Public API - Files
    
    /// Get icon for a file URL with optional custom styling
    func getFileIcon(for url: URL, size: CGFloat = 64, cornerRadius: CGFloat = 8) -> NSImage {
        let fileExtension = url.pathExtension.lowercased()
        
        // Check if we have a custom icon for this file type
        if let config = fileIcons[fileExtension] {
            return createRoundedIcon(config: config, size: size, cornerRadius: cornerRadius)
        }
        
        // Fallback to system icon with rounded corners
        return createRoundedSystemIcon(for: url, size: size, cornerRadius: cornerRadius)
    }
    
    /// Check if a file extension has a custom icon
    func hasCustomFileIcon(for fileExtension: String) -> Bool {
        return fileIcons[fileExtension.lowercased()] != nil
    }
    
    // MARK: - Public API - Folders
    
    /// Get icon for a folder URL with optional custom styling
    func getFolderIcon(for url: URL, size: CGFloat = 64, cornerRadius: CGFloat = 8) -> NSImage {
        let folderName = url.lastPathComponent
        let folderPath = url.path
        
        // Priority 1: Check path-based customization (most specific)
        if let config = pathBasedFolderIcons[folderPath] {
            return createFolderIcon(config: config, url: url, size: size, cornerRadius: cornerRadius)
        }
        
        // Priority 2: Check name-based customization
        if let config = nameBasedFolderIcons[folderName] {
            return createFolderIcon(config: config, url: url, size: size, cornerRadius: cornerRadius)
        }
        
        // Priority 3: Fallback to system icon
        return createSystemFolderIcon(for: url, size: size, cornerRadius: cornerRadius)
    }
    
    /// Set a custom color for a specific folder path
    func setFolderColor(_ color: NSColor, forPath path: String) {
        pathBasedFolderIcons[path] = FolderConfig(type: .systemWithColor(color))
        print("🎨 [IconProvider] Set custom color for folder path: \(path)")
    }
    
    /// Set a custom asset icon for a specific folder path
    func setCustomFolderAsset(_ assetName: String, forPath path: String) {
        pathBasedFolderIcons[path] = FolderConfig(type: .customAsset(assetName))
        print("🎨 [IconProvider] Set custom asset '\(assetName)' for folder path: \(path)")
    }
    
    /// Set a composite icon for a specific folder path
    func setCompositeFolderIcon(
        baseAsset: String,
        symbol: String,
        symbolColor: NSColor,
        symbolSize: CGFloat,
        symbolOffset: CGFloat = -4,
        forPath path: String
    ) {
        pathBasedFolderIcons[path] = FolderConfig(
            type: .composite(
                baseAsset: baseAsset,
                symbol: symbol,
                symbolColor: symbolColor,
                symbolSize: symbolSize,
                symbolOffset: symbolOffset
            )
        )
        print("🎨 [IconProvider] Set composite icon for folder path: \(path)")
    }
    
    /// Remove custom styling for a specific folder path
    func removeFolderCustomization(forPath path: String) {
        pathBasedFolderIcons.removeValue(forKey: path)
        print("🗑️ [IconProvider] Removed customization for folder path: \(path)")
    }
    
    /// Check if a folder has custom styling
    func hasCustomFolderIcon(forPath path: String) -> Bool {
        return pathBasedFolderIcons[path] != nil
    }
    
    /// Get all folder paths with custom icons
    func getCustomizedFolderPaths() -> [String] {
        return Array(pathBasedFolderIcons.keys)
    }
    
    // MARK: - Public API - Composite Icons
    
    /// Create a composite icon with a base asset and SF Symbol overlay using ABSOLUTE symbol size
    /// - Parameters:
    ///   - baseAssetName: Name of the base icon asset (e.g., "_folder-blue_")
    ///   - symbolName: SF Symbol to overlay on top
    ///   - symbolColor: Color of the SF Symbol
    ///   - size: Final icon size
    ///   - symbolSize: ABSOLUTE point size for the symbol (e.g., 24, 32)
    ///   - cornerRadius: Corner radius for the final icon (unused if base asset has its own shape)
    ///   - symbolOffset: Vertical offset for the symbol (negative moves up, positive moves down)
    /// - Returns: Composite NSImage
    func createCompositeIcon(
        baseAssetName: String,
        symbolName: String,
        symbolColor: NSColor,
        size: CGFloat,
        symbolSize: CGFloat = 24,  // ABSOLUTE SIZE (not ratio)
        cornerRadius: CGFloat = 8,
        symbolOffset: CGFloat = -8
    ) -> NSImage {
        let compositeImage = NSImage(size: NSSize(width: size, height: size))
        
        compositeImage.lockFocus()
        
        // Draw base icon (e.g., your custom folder "_folder-blue_")
        if let baseImage = NSImage(named: baseAssetName) {
            let imageSize = baseImage.size
            let scale = min(size / imageSize.width, size / imageSize.height)
            let scaledWidth = imageSize.width * scale
            let scaledHeight = imageSize.height * scale
            
            let drawRect = NSRect(
                x: (size - scaledWidth) / 2,
                y: (size - scaledHeight) / 2,
                width: scaledWidth,
                height: scaledHeight
            )
            
            baseImage.draw(
                in: drawRect,
                from: NSRect(origin: .zero, size: baseImage.size),
                operation: .sourceOver,
                fraction: 1.0
            )
        }
        
        // Create colored SF Symbol with preserved aspect ratio
        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .medium)  // USE ABSOLUTE SIZE
            if let configuredSymbol = symbol.withSymbolConfiguration(symbolConfig) {
                
                let symbolActualSize = configuredSymbol.size
                
                // Create colored version with shadow baked in
                let shadowOffset: CGFloat = 1
                let shadowBlur: CGFloat = 1
                let imageSize = NSSize(
                    width: symbolActualSize.width + shadowBlur * 2,
                    height: symbolActualSize.height + shadowBlur * 2 + shadowOffset
                )
                
                let coloredSymbol = NSImage(size: imageSize)
                coloredSymbol.lockFocus()
                
                // Set up shadow
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
                shadow.shadowOffset = NSSize(width: 0, height: -shadowOffset)
                shadow.shadowBlurRadius = shadowBlur
                shadow.set()
                
                // Draw symbol with padding for shadow
                let drawRect = NSRect(
                    x: shadowBlur,
                    y: shadowBlur + shadowOffset,
                    width: symbolActualSize.width,
                    height: symbolActualSize.height
                )
                
                configuredSymbol.draw(
                    in: drawRect,
                    from: NSRect(origin: .zero, size: symbolActualSize),
                    operation: .sourceOver,
                    fraction: 1.0
                )
                
                symbolColor.setFill()
                drawRect.fill(using: .sourceAtop)
                
                coloredSymbol.unlockFocus()
                
                // Draw colored symbol (with baked-in shadow) centered on composite
                let symbolRect = NSRect(
                    x: (size - imageSize.width) / 2,
                    y: (size - imageSize.height) / 2 + symbolOffset,
                    width: imageSize.width,
                    height: imageSize.height
                )
                
                coloredSymbol.draw(in: symbolRect)
            }
        }
        
        compositeImage.unlockFocus()
        
        return compositeImage
    }
    
    // MARK: - Batch Operations
    
    /// Get icons for multiple file URLs (useful for batch loading)
    func getFileIcons(for urls: [URL], size: CGFloat = 64, cornerRadius: CGFloat = 8) -> [URL: NSImage] {
        var icons: [URL: NSImage] = [:]
        for url in urls {
            icons[url] = getFileIcon(for: url, size: size, cornerRadius: cornerRadius)
        }
        return icons
    }
    
    /// Get icons for multiple folder URLs (useful for batch loading)
    func getFolderIcons(for urls: [URL], size: CGFloat = 64, cornerRadius: CGFloat = 8) -> [URL: NSImage] {
        var icons: [URL: NSImage] = [:]
        for url in urls {
            icons[url] = getFolderIcon(for: url, size: size, cornerRadius: cornerRadius)
        }
        return icons
    }
    
    // MARK: - Icon Creation - Files
    
    private func createRoundedIcon(config: FileIconConfig, size: CGFloat, cornerRadius: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        
        image.lockFocus()
        
        let rect = NSRect(origin: .zero, size: NSSize(width: size, height: size))
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        
        // Draw background
        config.backgroundColor.setFill()
        path.fill()
        
        // Draw SF Symbol with preserved aspect ratio
        if let symbol = NSImage(systemSymbolName: config.symbolName, accessibilityDescription: nil) {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: size * 0.4, weight: .regular)
            if let configuredSymbol = symbol.withSymbolConfiguration(symbolConfig) {
                
                let symbolSize = configuredSymbol.size
                
                // Create colored version in its own context
                let coloredSymbol = NSImage(size: symbolSize)
                coloredSymbol.lockFocus()
                
                configuredSymbol.draw(
                    in: NSRect(origin: .zero, size: symbolSize),
                    from: NSRect(origin: .zero, size: symbolSize),
                    operation: .sourceOver,
                    fraction: 1.0
                )
                
                config.foregroundColor.setFill()
                NSRect(origin: .zero, size: symbolSize).fill(using: .sourceAtop)
                
                coloredSymbol.unlockFocus()
                
                // Draw colored symbol centered
                let symbolRect = NSRect(
                    x: (size - symbolSize.width) / 2,
                    y: (size - symbolSize.height) / 2,
                    width: symbolSize.width,
                    height: symbolSize.height
                )
                
                coloredSymbol.draw(in: symbolRect)
            }
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
    
    // MARK: - Icon Creation - Folders
    
    private func createFolderIcon(config: FolderConfig, url: URL, size: CGFloat, cornerRadius: CGFloat) -> NSImage {
        switch config.type {
        case .systemWithColor(let color):
            return createColoredFolderIcon(for: url, color: color, size: size, cornerRadius: cornerRadius)
        case .customAsset(let assetName):
            return createCustomAssetIcon(assetName: assetName, size: size, cornerRadius: cornerRadius)
        case .composite(let baseAsset, let symbol, let symbolColor, let symbolSize, let symbolOffset):
            return createCompositeIcon(
                baseAssetName: baseAsset,
                symbolName: symbol,
                symbolColor: symbolColor,
                size: size,
                symbolSize: symbolSize,
                cornerRadius: cornerRadius,
                symbolOffset: symbolOffset
            )
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
        rect.fill(using: .sourceAtop)
        
        coloredIcon.unlockFocus()
        
        return coloredIcon
    }
    
    private func createCustomAssetIcon(assetName: String, size: CGFloat, cornerRadius: CGFloat) -> NSImage {
        guard let assetImage = NSImage(named: assetName) else {
            print("⚠️ [IconProvider] Asset '\(assetName)' not found - using system icon")
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
    func loadFolderCustomizations(from entries: [(path: String, color: NSColor)]) {
        for entry in entries {
            setFolderColor(entry.color, forPath: entry.path)
        }
        print("📦 [IconProvider] Loaded \(entries.count) custom folder colors")
    }
    
    /// Export current folder customizations for database storage
    func exportFolderCustomizations() -> [(path: String, colorHex: String)] {
        return pathBasedFolderIcons.compactMap { path, config in
            if case .systemWithColor(let color) = config.type {
                return (path: path, colorHex: color.hexString)
            }
            return nil
        }
    }
    
    // MARK: - Database Integration
    
    /// Load all folder icon customizations from the database
    func loadFolderCustomizationsFromDatabase() {
        let customFolders = DatabaseManager.shared.getFoldersWithCustomIcons()
        
        for folder in customFolders {
            guard let iconName = folder.iconName,
                  let iconColor = folder.iconColor else {
                continue
            }
            
            setCompositeFolderIcon(
                baseAsset: folder.baseAsset,
                symbol: iconName,
                symbolColor: iconColor,
                symbolSize: folder.symbolSize,
                symbolOffset: folder.symbolOffset,
                forPath: folder.path
            )
        }
        
        print("📦 [IconProvider] Loaded \(customFolders.count) custom folder icons from database")
    }
    
    /// Save a folder icon customization to the database
    func saveFolderIconToDatabase(
        path: String,
        iconName: String?,
        iconColor: NSColor?,
        baseAsset: String = "_folder-blue_",
        symbolSize: CGFloat = 24.0,
        symbolOffset: CGFloat = -8.0
    ) {
        // Save to database
        DatabaseManager.shared.setFolderIcon(
            path: path,
            iconName: iconName,
            iconColorHex: iconColor?.hexString,
            baseAsset: baseAsset,
            symbolSize: symbolSize,
            symbolOffset: symbolOffset
        )
        
        // Also update in-memory cache
        if let iconName = iconName, let iconColor = iconColor {
            setCompositeFolderIcon(
                baseAsset: baseAsset,
                symbol: iconName,
                symbolColor: iconColor,
                symbolSize: symbolSize,
                symbolOffset: symbolOffset,
                forPath: path
            )
        } else {
            removeFolderCustomization(forPath: path)
        }
    }
    
    /// Remove a folder icon customization from both database and memory
    func removeFolderIconFromDatabase(path: String) {
        // Remove from database
        DatabaseManager.shared.removeFolderIcon(path: path)
        
        // Remove from in-memory cache
        removeFolderCustomization(forPath: path)
    }
    
    /// Get folder icon from database or generate default
    func getFolderIconFromDatabase(for url: URL, size: CGFloat = 64, cornerRadius: CGFloat = 8) -> NSImage {
        let path = url.path
        
        // Check if folder has custom icon in database
        if let folderEntry = DatabaseManager.shared.getFolder(path: path),
           let iconName = folderEntry.iconName,
           let iconColor = folderEntry.iconColor {
            
            // Generate composite icon with database settings
            return createCompositeIcon(
                baseAssetName: folderEntry.baseAsset,
                symbolName: iconName,
                symbolColor: iconColor,
                size: size,
                symbolSize: folderEntry.symbolSize,
                cornerRadius: cornerRadius,
                symbolOffset: folderEntry.symbolOffset
            )
        }
        
        // Fall back to standard folder icon
        return getFolderIcon(for: url, size: size, cornerRadius: cornerRadius)
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
