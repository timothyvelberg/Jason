//
//  FolderSortOrder.swift
//  Jason
//
//  Unified sorting options for folder contents and dynamic files
//

import Foundation

/// Sorting options for folder contents
enum FolderSortOrder: String, CaseIterable, Codable {
    case alphabeticalAsc = "alphabetical_asc"           // A → Z
    case alphabeticalDesc = "alphabetical_desc"         // Z → A
    case modifiedNewest = "modified_newest"             // Newest modified first
    case modifiedOldest = "modified_oldest"             // Oldest modified first
    case createdNewest = "created_newest"               // Newest created first
    case createdOldest = "created_oldest"               // Oldest created first
    case foldersFirst = "folders_first"                 // Folders, then files alphabetically
    case sizeDescending = "size_descending"             // Largest first
    case sizeAscending = "size_ascending"               // Smallest first
    case addedNewest = "added_newest"                   // Most recently added to folder
    case addedOldest = "added_oldest"                   // Oldest added to folder
    
    /// Human-readable display name
    var displayName: String {
        switch self {
        case .alphabeticalAsc: return "A → Z"
        case .alphabeticalDesc: return "Z → A"
            
        case .modifiedNewest: return "Newest Modified"
        case .modifiedOldest: return "Oldest Modified"
            
        case .createdNewest: return "Newest Created"
        case .createdOldest: return "Oldest Created"
            
        case .foldersFirst: return "Folders First"
        case .sizeDescending: return "Largest First"
        case .sizeAscending: return "Smallest First"
        case .addedNewest: return "Recently Added"
        case .addedOldest: return "Oldest Added"
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
        case .createdNewest:
            return "ORDER BY creation_date DESC"
        case .createdOldest:
            return "ORDER BY creation_date ASC"
        case .foldersFirst:
            return "ORDER BY is_directory DESC, item_name COLLATE NOCASE ASC"
        case .sizeDescending:
            return "ORDER BY file_size DESC"
        case .sizeAscending:
            return "ORDER BY file_size ASC"
        case .addedNewest: 
            return "ORDER BY date_added DESC"
        case .addedOldest: 
            return "ORDER BY date_added ASC"
        }
    }
    
    /// Icon for UI display
    var icon: String {
        switch self {
        case .alphabeticalAsc: return "textformat.abc"
        case .alphabeticalDesc: return "textformat.abc"
        case .modifiedNewest: return "clock.arrow.circlepath"
        case .modifiedOldest: return "clock.arrow.circlepath"
        case .createdNewest: return "calendar.badge.plus"
        case .createdOldest: return "calendar.badge.minus"
        case .foldersFirst: return "folder.badge.plus"
        case .sizeDescending: return "square.stack.3d.up"
        case .sizeAscending: return "square.stack.3d.down.forward"
        case .addedNewest: return "clock.badge.checkmark"
        case .addedOldest: return "clock.badge.checkmark"
        }
    }
}
