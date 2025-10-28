//
//  FinderLogic+Sorting.swift
//  Jason
//
//  Sorting extension for FinderLogic - now uses FolderSortingUtility
//

import Foundation

// MARK: - Sorting Helper Methods

extension FinderLogic {
    
    /// Sort URLs based on folder sort preference
    /// This is now a thin wrapper around FolderSortingUtility
    func sortURLs(_ urls: [URL], sortOrder: FolderSortOrder) -> [URL] {
        return FolderSortingUtility.sortURLs(urls, by: sortOrder)
    }
    
    /// Get folder URLs with required properties for sorting
    /// This is now a thin wrapper around FolderSortingUtility
    func getFolderURLs(at folderURL: URL) -> [URL] {
        return FolderSortingUtility.getFolderURLs(at: folderURL)
    }
}
