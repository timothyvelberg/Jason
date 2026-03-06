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

    private var thumbnailCache: [String: NSImage] = [:]
    private var thumbnailAccessOrder: [String] = []
    private let thumbnailCacheLimit = 200

    private var iconCache: [String: NSImage] = [:]

    private func clearImageCache() {
        iconCache.removeAll()
    }

    // MARK: - Icon Configuration Structures

    private enum FolderIconType {
        case systemWithColor(NSColor)
        case customAsset(String)
        case composite(baseAsset: String, symbol: String, symbolColor: NSColor, symbolSize: CGFloat, symbolOffset: CGFloat)
        case layered(color: NSColor)
    }

    private struct FolderConfig {
        let type: FolderIconType
    }

    // MARK: - Folder Mappings

    private var pathBasedFolderIcons: [String: FolderConfig] = [:]

    private let nameBasedFolderIcons: [String: FolderConfig] = [
        "Documents": FolderConfig(type: .systemWithColor(NSColor(red: 0.3, green: 0.5, blue: 0.8, alpha: 1.0))),
        "Music": FolderConfig(type: .systemWithColor(NSColor(red: 0.9, green: 0.3, blue: 0.4, alpha: 1.0))),
        "Pictures": FolderConfig(type: .systemWithColor(NSColor(red: 0.8, green: 0.2, blue: 0.6, alpha: 1.0))),
        "Movies": FolderConfig(type: .systemWithColor(NSColor(red: 0.6, green: 0.3, blue: 0.8, alpha: 1.0))),
    ]

    // MARK: - Public API - Files

    /// Get icon for a file URL
    func getFileIcon(for url: URL, size: CGFloat = 64, cornerRadius: CGFloat = 8) -> NSImage {
        return createRoundedSystemIcon(for: url, size: size, cornerRadius: cornerRadius)
    }

    /// Get a thumbnail for a file URL. For image files, generates a pixel-accurate
    /// thumbnail. Falls back to getFileIcon for all other file types.
    func getThumbnail(for url: URL, size: CGFloat = 40, cornerRadius: CGFloat = 8) -> NSImage {
        let ext = url.pathExtension.lowercased()
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"]

        guard imageExtensions.contains(ext) else {
            return getFileIcon(for: url, size: size, cornerRadius: cornerRadius)
        }

        let key = "thumbnail-\(url.path)-\(size)-\(cornerRadius)"
        if let cached = thumbnailCache[key] {
            thumbnailAccessOrder.removeAll { $0 == key }
            thumbnailAccessOrder.append(key)
            return cached
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: size
        ]

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return getFileIcon(for: url, size: size, cornerRadius: cornerRadius)
        }

        let thumbnail = NSImage(size: NSSize(width: size, height: size))
        thumbnail.lockFocus()
        let rect = NSRect(origin: .zero, size: NSSize(width: size, height: size))
        NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).addClip()
        NSGraphicsContext.current?.cgContext.draw(cgImage, in: rect)
        thumbnail.unlockFocus()

        thumbnailCache[key] = thumbnail
        thumbnailAccessOrder.append(key)
        if thumbnailCache.count > thumbnailCacheLimit {
            let evicted = thumbnailAccessOrder.removeFirst()
            thumbnailCache.removeValue(forKey: evicted)
        }

        return thumbnail
    }

    // MARK: - Public API - Folders

    /// Get icon for a folder URL with optional custom styling
    func getFolderIcon(for url: URL, size: CGFloat = 64, cornerRadius: CGFloat = 8) -> NSImage {
        let folderName = url.lastPathComponent
        let folderPath = url.path

        if let config = pathBasedFolderIcons[folderPath] {
            return createFolderIcon(config: config, url: url, size: size, cornerRadius: cornerRadius)
        }

        if let config = nameBasedFolderIcons[folderName] {
            return createFolderIcon(config: config, url: url, size: size, cornerRadius: cornerRadius)
        }

        return createLayeredFolderIcon(color: NSColor(hex: "#55C2EE") ?? .systemBlue, size: size, cornerRadius: cornerRadius)
    }

    func setFolderColor(_ color: NSColor, forPath path: String) {
        pathBasedFolderIcons[path] = FolderConfig(type: .layered(color: color))
        clearImageCache()
    }

    func setCustomFolderAsset(_ assetName: String, forPath path: String) {
        pathBasedFolderIcons[path] = FolderConfig(type: .customAsset(assetName))
        clearImageCache()
    }

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
        clearImageCache()
    }

    func removeFolderCustomization(forPath path: String) {
        pathBasedFolderIcons.removeValue(forKey: path)
        clearImageCache()
    }

    func hasCustomFolderIcon(forPath path: String) -> Bool {
        return pathBasedFolderIcons[path] != nil
    }

    func getCustomizedFolderPaths() -> [String] {
        return Array(pathBasedFolderIcons.keys)
    }

    // MARK: - Layered Folder Icon

    func createLayeredFolderIcon(color: NSColor, size: CGFloat = 64, cornerRadius: CGFloat = 0) -> NSImage {
        let key = "layered-\(color.hexString)-\(size)-\(cornerRadius)"
        if let cached = iconCache[key] { return cached }

        let compositeImage = NSImage(size: NSSize(width: size, height: size))
        let backColor = color.adjustingLightness(by: -20)

        compositeImage.lockFocus()

        let rect = NSRect(origin: .zero, size: NSSize(width: size, height: size))

        if cornerRadius > 0 {
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            path.addClip()
        }

        if let backLayer = NSImage(named: "folder-blue-04") {
            drawTintedLayer(backLayer, in: rect, tintColor: backColor)
        }

        if let highlight1 = NSImage(named: "folder-blue-03") {
            highlight1.draw(in: rect, from: NSRect(origin: .zero, size: highlight1.size), operation: .sourceOver, fraction: 1.0)
        }

        if let frontLayer = NSImage(named: "folder-blue-02") {
            drawTintedLayer(frontLayer, in: rect, tintColor: color)
        }

        if let highlight2 = NSImage(named: "folder-blue-01") {
            highlight2.draw(in: rect, from: NSRect(origin: .zero, size: highlight2.size), operation: .sourceOver, fraction: 1.0)
        }

        compositeImage.unlockFocus()

        iconCache[key] = compositeImage
        return compositeImage
    }

    func createLayeredFolderIconWithSymbol(
        color: NSColor,
        symbolName: String,
        symbolColor: NSColor,
        size: CGFloat = 64,
        symbolSize: CGFloat = 24,
        cornerRadius: CGFloat = 0,
        symbolOffset: CGFloat = -4
    ) -> NSImage {
        let key = "layered-\(color.hexString)-\(symbolName)-\(symbolColor.hexString)-\(size)-\(symbolSize)-\(cornerRadius)-\(symbolOffset)"
        if let cached = iconCache[key] { return cached }

        let compositeImage = NSImage(size: NSSize(width: size, height: size))

        compositeImage.lockFocus()

        let baseFolder = createLayeredFolderIcon(color: color, size: size, cornerRadius: cornerRadius)
        baseFolder.draw(in: NSRect(origin: .zero, size: NSSize(width: size, height: size)))

        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .medium)
            if let configuredSymbol = symbol.withSymbolConfiguration(symbolConfig) {

                let symbolActualSize = configuredSymbol.size
                let shadowOffset: CGFloat = 1
                let shadowBlur: CGFloat = 1
                let imageSize = NSSize(
                    width: symbolActualSize.width + shadowBlur * 2,
                    height: symbolActualSize.height + shadowBlur * 2 + shadowOffset
                )

                let coloredSymbol = NSImage(size: imageSize)
                coloredSymbol.lockFocus()

                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
                shadow.shadowOffset = NSSize(width: 0, height: -shadowOffset)
                shadow.shadowBlurRadius = shadowBlur
                shadow.set()

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

        iconCache[key] = compositeImage
        return compositeImage
    }

    private func drawTintedLayer(_ image: NSImage, in rect: NSRect, tintColor: NSColor) {
        let tintedImage = NSImage(size: rect.size)

        tintedImage.lockFocus()

        image.draw(in: NSRect(origin: .zero, size: rect.size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .sourceOver,
                   fraction: 1.0)

        tintColor.setFill()
        NSRect(origin: .zero, size: rect.size).fill(using: .sourceAtop)

        tintedImage.unlockFocus()

        tintedImage.draw(in: rect)
    }

    // MARK: - Composite Icons

    func createCompositeIcon(
        baseAssetName: String,
        symbolName: String,
        symbolColor: NSColor,
        size: CGFloat,
        symbolSize: CGFloat = 24,
        cornerRadius: CGFloat = 8,
        symbolOffset: CGFloat = -8
    ) -> NSImage {
        let key = "composite-\(baseAssetName)-\(symbolName)-\(symbolColor.hexString)-\(size)-\(symbolSize)-\(cornerRadius)-\(symbolOffset)"
        if let cached = iconCache[key] { return cached }

        let compositeImage = NSImage(size: NSSize(width: size, height: size))

        compositeImage.lockFocus()

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

        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .medium)
            if let configuredSymbol = symbol.withSymbolConfiguration(symbolConfig) {

                let symbolActualSize = configuredSymbol.size
                let shadowOffset: CGFloat = 1
                let shadowBlur: CGFloat = 1
                let imageSize = NSSize(
                    width: symbolActualSize.width + shadowBlur * 2,
                    height: symbolActualSize.height + shadowBlur * 2 + shadowOffset
                )

                let coloredSymbol = NSImage(size: imageSize)
                coloredSymbol.lockFocus()

                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
                shadow.shadowOffset = NSSize(width: 0, height: -shadowOffset)
                shadow.shadowBlurRadius = shadowBlur
                shadow.set()

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

        iconCache[key] = compositeImage
        return compositeImage
    }

    // MARK: - Batch Operations

    func getFileIcons(for urls: [URL], size: CGFloat = 64, cornerRadius: CGFloat = 8) -> [URL: NSImage] {
        var icons: [URL: NSImage] = [:]
        for url in urls {
            icons[url] = getFileIcon(for: url, size: size, cornerRadius: cornerRadius)
        }
        return icons
    }

    func getFolderIcons(for urls: [URL], size: CGFloat = 64, cornerRadius: CGFloat = 8) -> [URL: NSImage] {
        var icons: [URL: NSImage] = [:]
        for url in urls {
            icons[url] = getFolderIcon(for: url, size: size, cornerRadius: cornerRadius)
        }
        return icons
    }

    // MARK: - Icon Creation - Files

    private func createRoundedSystemIcon(for url: URL, size: CGFloat, cornerRadius: CGFloat) -> NSImage {
        let systemIcon = NSWorkspace.shared.icon(forFile: url.path)
        let roundedIcon = NSImage(size: NSSize(width: size, height: size))

        roundedIcon.lockFocus()

        let rect = NSRect(origin: .zero, size: NSSize(width: size, height: size))
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.addClip()

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
        case .layered(let color):
            return createLayeredFolderIcon(color: color, size: size, cornerRadius: cornerRadius)
        }
    }

    private func createColoredFolderIcon(for url: URL, color: NSColor, size: CGFloat, cornerRadius: CGFloat) -> NSImage {
        let systemIcon = NSWorkspace.shared.icon(forFile: url.path)
        let coloredIcon = NSImage(size: NSSize(width: size, height: size))

        coloredIcon.lockFocus()

        let rect = NSRect(origin: .zero, size: NSSize(width: size, height: size))
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.addClip()

        systemIcon.draw(
            in: rect,
            from: NSRect(origin: .zero, size: systemIcon.size),
            operation: .sourceOver,
            fraction: 1.0
        )

        color.setFill()
        rect.fill(using: .sourceAtop)

        coloredIcon.unlockFocus()

        return coloredIcon
    }

    private func createCustomAssetIcon(assetName: String, size: CGFloat, cornerRadius: CGFloat) -> NSImage {
        guard let assetImage = NSImage(named: assetName) else {
            print("[IconProvider] Asset '\(assetName)' not found - using system icon")
            return NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage()
        }

        let roundedIcon = NSImage(size: NSSize(width: size, height: size))

        roundedIcon.lockFocus()

        let rect = NSRect(origin: .zero, size: NSSize(width: size, height: size))
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.addClip()

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
        let folderIcon = NSImage(named: "folder-blue") ?? NSWorkspace.shared.icon(forFile: url.path)
        let roundedIcon = NSImage(size: NSSize(width: size, height: size))

        roundedIcon.lockFocus()

        let rect = NSRect(origin: .zero, size: NSSize(width: size, height: size))
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.addClip()

        folderIcon.draw(
            in: rect,
            from: NSRect(origin: .zero, size: folderIcon.size),
            operation: .sourceOver,
            fraction: 1.0
        )

        roundedIcon.unlockFocus()

        return roundedIcon
    }

    // MARK: - Persistence Support

    func loadFolderCustomizations(from entries: [(path: String, color: NSColor)]) {
        for entry in entries {
            setFolderColor(entry.color, forPath: entry.path)
        }
        print("[IconProvider] Loaded \(entries.count) custom folder colors")
    }

    func exportFolderCustomizations() -> [(path: String, colorHex: String)] {
        return pathBasedFolderIcons.compactMap { path, config in
            if case .systemWithColor(let color) = config.type {
                return (path: path, colorHex: color.hexString)
            }
            return nil
        }
    }

    // MARK: - Database Integration

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

        print("[IconProvider] Loaded \(customFolders.count) custom folder icons from database")
    }

    func saveFolderIconToDatabase(
        path: String,
        iconName: String?,
        iconColor: NSColor?,
        baseAsset: String = "folder-blue",
        symbolSize: CGFloat = 24.0,
        symbolOffset: CGFloat = -8.0
    ) {
        DatabaseManager.shared.setFolderIcon(
            path: path,
            iconName: iconName,
            iconColorHex: iconColor?.hexString,
            baseAsset: baseAsset,
            symbolSize: symbolSize,
            symbolOffset: symbolOffset
        )

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

    func removeFolderIconFromDatabase(path: String) {
        DatabaseManager.shared.removeFolderIcon(path: path)
        removeFolderCustomization(forPath: path)
    }

    func getFolderIconFromDatabase(for url: URL, size: CGFloat = 64, cornerRadius: CGFloat = 8) -> NSImage {
        let path = url.path

        if let folderEntry = DatabaseManager.shared.getFolder(path: path),
           let iconName = folderEntry.iconName,
           let iconColor = folderEntry.iconColor {

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

        return getFolderIcon(for: url, size: size, cornerRadius: cornerRadius)
    }
}

// MARK: - NSColor Extension for Hex Conversion

extension NSColor {
    var hexString: String {
        guard let rgbColor = usingColorSpace(.deviceRGB) else {
            return "#000000"
        }

        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)

        return String(format: "#%02X%02X%02X", r, g, b)
    }

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

// MARK: - NSColor Extension for HSL Adjustment

extension NSColor {
    func adjustingLightness(by delta: CGFloat) -> NSColor {
        guard let rgbColor = usingColorSpace(.deviceRGB) else { return self }

        let r = rgbColor.redComponent
        let g = rgbColor.greenComponent
        let b = rgbColor.blueComponent

        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let l = (maxC + minC) / 2

        var h: CGFloat = 0
        var s: CGFloat = 0

        if maxC != minC {
            let d = maxC - minC
            s = l > 0.5 ? d / (2 - maxC - minC) : d / (maxC + minC)

            switch maxC {
            case r:
                h = (g - b) / d + (g < b ? 6 : 0)
            case g:
                h = (b - r) / d + 2
            case b:
                h = (r - g) / d + 4
            default:
                break
            }
            h /= 6
        }

        let newL = max(0, min(1, l + (delta / 100)))

        return Self.fromHSL(hue: h, saturation: s, lightness: newL)
    }

    static func fromHSL(hue h: CGFloat, saturation s: CGFloat, lightness l: CGFloat, alpha: CGFloat = 1.0) -> NSColor {
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h * 6).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2

        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0

        let segment = Int(h * 6) % 6

        switch segment {
        case 0: r = c; g = x; b = 0
        case 1: r = x; g = c; b = 0
        case 2: r = 0; g = c; b = x
        case 3: r = 0; g = x; b = c
        case 4: r = x; g = 0; b = c
        case 5: r = c; g = 0; b = x
        default: break
        }

        return NSColor(red: r + m, green: g + m, blue: b + m, alpha: alpha)
    }
}
