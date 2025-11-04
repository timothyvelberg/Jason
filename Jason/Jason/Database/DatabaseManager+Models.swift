//
//  DatabaseManager+Models.swift
//  Jason
//
//  Created by Timothy Velberg on 15/10/2025.

import Foundation
import AppKit

// MARK: - Models

struct FolderCacheEntry {
    let path: String
    let lastScanned: Int
    let itemsJSON: String
    let itemCount: Int
}

struct FolderEntry: Identifiable {
    let id: Int
    let path: String
    let title: String
    let icon: String?
    let iconName: String?
    let iconColorHex: String?
    let baseAsset: String
    let symbolSize: CGFloat
    let symbolOffset: CGFloat
    let lastAccessed: Int
    let accessCount: Int
    
    var iconColor: NSColor? {
        guard let hex = iconColorHex else { return nil }
        return NSColor(hex: hex)
    }
}

struct FavoriteFolderEntry {
    let id: Int?
    let folderId: Int
    let sortOrder: Int
    let maxItems: Int?
    let preferredLayout: String?
    let itemAngleSize: Int?
    let slicePositioning: String?
    let childRingThickness: Int?
    let childIconSize: Int?
}

struct FavoriteAppEntry: Identifiable {
    let id: Int
    let bundleIdentifier: String
    let displayName: String
    let sortOrder: Int
    let iconOverride: String?
    let lastAccessed: Int?
    let accessCount: Int
}

struct UsageHistoryEntry {
    let id: Int?
    let itemPath: String
    let itemType: String
    var accessCount: Int
    var lastAccessed: Int
}

struct FavoriteEntry {
    let id: Int?
    let name: String
    let path: String
    let iconData: Data?
    let sortOrder: Int
}

struct FavoriteFolderSettings {
    let maxItems: Int?
    let preferredLayout: String?
    let itemAngleSize: Int?
    let slicePositioning: String?
    let childRingThickness: Int?
    let childIconSize: Int?
    let contentSortOrder: FolderSortOrder?
}

// Static file - direct reference to a specific file
struct FavoriteFileEntry: Identifiable {
    let id: Int?
    let path: String
    let displayName: String?
    let sortOrder: Int
    let iconData: Data?
    let lastAccessed: Int?
    let accessCount: Int
}

// Dynamic file - rule-based query that resolves to a file
struct FavoriteDynamicFileEntry: Identifiable {
    let id: Int?
    let displayName: String
    let folderPath: String
    let queryType: String
    let fileExtensions: String?
    let namePattern: String?
    let sortOrder: Int
    let iconData: Data?
    let lastAccessed: Int?
    let accessCount: Int
}

// MARK: - Errors
