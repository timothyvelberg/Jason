//
//  DatabaseManager+Models.swift
//  Jason
//
//  Created by Timothy Velberg on 15/10/2025.

import Foundation
import AppKit

// MARK: - Models

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
    let sortOrder: FolderSortOrder   
    let fileExtensions: String?
    let namePattern: String?
    let listSortOrder: Int
    let iconData: Data?
    let lastAccessed: Int?
    let accessCount: Int
}

// MARK: - Ring Configuration Models

struct RingConfigurationEntry: Identifiable {
    let id: Int
    let name: String
    let shortcut: String           // DEPRECATED
    let ringRadius: CGFloat
    let centerHoleRadius: CGFloat
    let iconSize: CGFloat
    let startAngle: CGFloat

    let createdAt: Int
    let isActive: Bool
    let displayOrder: Int
    
    // Trigger data
    let triggerType: String        // "keyboard", "mouse", or "trackpad"
    let keyCode: UInt16?           // For keyboard triggers
    let modifierFlags: UInt?       // For keyboard, mouse, and trackpad triggers
    let buttonNumber: Int32?       // For mouse triggers (2=middle, 3=back, 4=forward)
    let swipeDirection: String?    // For trackpad triggers ("up", "down", "left", "right")
    let fingerCount: Int?          // For trackpad triggers (3 or 4 fingers)
    let isHoldMode: Bool           // true = hold to show, false = tap to toggle
    let autoExecuteOnRelease: Bool // true = auto-execute on release (only when isHoldMode = true)
}

struct CircleCalibrationEntry {
    let maxRadiusVariance: Float
    let minCircles: Float
    let minRadius: Float
    let calibratedAt: Date
}

struct RingProviderEntry: Identifiable {
    let id: Int
    let ringId: Int
    let providerType: String
    let providerOrder: Int
    let parentItemAngle: CGFloat?
    let providerConfig: String?
}

struct RingTriggerEntry: Identifiable {
    let id: Int
    let ringId: Int
    let triggerType: String            // "keyboard", "mouse", "trackpad"
    let keyCode: UInt16?
    let modifierFlags: UInt
    let buttonNumber: Int32?
    let swipeDirection: String?
    let fingerCount: Int?
    let isHoldMode: Bool
    let autoExecuteOnRelease: Bool
    let createdAt: Int
}

// MARK: - Errors
