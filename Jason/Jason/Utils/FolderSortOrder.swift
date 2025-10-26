//
//  FolderSortOrder.swift
//  Jason
//
//  Sorting options for folder contents
//

import Foundation

/// Sorting options for folder contents
enum FolderSortOrder: String, CaseIterable {
    case alphabeticalAsc = "alphabetical_asc"           // A → Z
    case alphabeticalDesc = "alphabetical_desc"         // Z → A
    case modifiedNewest = "modified_newest"             // Newest first ⭐ Good for Screenshots/Downloads
    case modifiedOldest = "modified_oldest"             // Oldest first
    case foldersFirst = "folders_first"                 // Folders, then files alphabetically
    case sizeDescending = "size_descending"             // Largest first
    case sizeAscending = "size_ascending"               // Smallest first
    
    /// Human-readable display name
    var displayName: String {
        switch self {
        case .alphabeticalAsc: return "A → Z"
        case .alphabeticalDesc: return "Z → A"
        case .modifiedNewest: return "Newest First"
        case .modifiedOldest: return "Oldest First"
        case .foldersFirst: return "Folders First"
        case .sizeDescending: return "Largest First"
        case .sizeAscending: return "Smallest First"
        }
    }
    
    /// SQL ORDER BY clause for database queries
    var sqlOrderClause: String {
        switch self {
        case .alphabeticalAsc:
            return "ORDER BY item_name COLLATE NOCASE ASC"
        case .alphabeticalDesc:
            return "ORDER BY item_name COLLATE NOCASE DESC"
        case .modifiedNewest:
            return "ORDER BY modification_date DESC"
        case .modifiedOldest:
            return "ORDER BY modification_date ASC"
        case .foldersFirst:
            return "ORDER BY is_directory DESC, item_name COLLATE NOCASE ASC"
        case .sizeDescending:
            return "ORDER BY file_size DESC"
        case .sizeAscending:
            return "ORDER BY file_size ASC"
        }
    }
    
    /// Icon for UI display
    var icon: String {
        switch self {
        case .alphabeticalAsc: return "textformat.abc"
        case .alphabeticalDesc: return "textformat.abc"
        case .modifiedNewest: return "clock.arrow.circlepath"
        case .modifiedOldest: return "clock.arrow.circlepath"
        case .foldersFirst: return "folder.badge.plus"
        case .sizeDescending: return "square.stack.3d.up"
        case .sizeAscending: return "square.stack.3d.down.forward"
        }
    }
}
