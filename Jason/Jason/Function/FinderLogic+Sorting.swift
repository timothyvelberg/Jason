//
//  FinderLogic+Sorting.swift
//  Jason
//
//  Created by Timothy Velberg on 26/10/2025.
//

import Foundation

// MARK: - Sorting Helper Methods

extension FinderLogic {
    
    /// Sort URLs based on folder sort preference
    func sortURLs(_ urls: [URL], sortOrder: FolderSortOrder) -> [URL] {
        switch sortOrder {
        case .alphabeticalAsc:
            return urls.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
            
        case .alphabeticalDesc:
            return urls.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending
            }
            
        case .modifiedNewest:
            return urls.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                return date1 > date2  // Newest first
            }
            
        case .modifiedOldest:
            return urls.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                return date1 < date2  // Oldest first
            }
            
        case .foldersFirst:
            return urls.sorted { url1, url2 in
                let isDir1 = (try? url1.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let isDir2 = (try? url2.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                
                if isDir1 != isDir2 {
                    return isDir1  // Folders first
                }
                // Then alphabetical
                return url1.lastPathComponent.localizedStandardCompare(url2.lastPathComponent) == .orderedAscending
            }
            
        case .sizeDescending:
            return urls.sorted { url1, url2 in
                let size1 = (try? url1.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                let size2 = (try? url2.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return size1 > size2  // Largest first
            }
            
        case .sizeAscending:
            return urls.sorted { url1, url2 in
                let size1 = (try? url1.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                let size2 = (try? url2.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return size1 < size2  // Smallest first
            }
        }
    }
    
    /// Get folder URLs with required properties for sorting
    func getFolderURLs(at folderURL: URL) -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .contentModificationDateKey,
                    .fileSizeKey
                ],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        } catch {
            print("❌ [FinderLogic] Failed to read folder: \(error)")
            return []
        }
    }
}
