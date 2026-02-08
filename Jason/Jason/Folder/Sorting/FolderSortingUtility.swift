//
//  FolderSortingUtility.swift
//  Jason
//
//  Created by Timothy Velberg on 28/10/2025.
//

import Foundation
import AppKit

/// Utility class for sorting folder contents
class FolderSortingUtility {
    
    // MARK: - URL Sorting
    
    /// Sort URLs based on folder sort preference
    static func sortURLs(_ urls: [URL], by sortOrder: FolderSortOrder) -> [URL] {
        print("🔄 [SortingUtility] Sorting \(urls.count) URLs by: \(sortOrder.displayName)")
        
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
            
        case .createdNewest:
            return urls.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                return date1 > date2  // Newest first
            }
            
        case .createdOldest:
            return urls.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
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
        case .addedNewest:
            return urls.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate ?? Date.distantPast
                return date1 > date2
            }

        case .addedOldest:
            return urls.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate ?? Date.distantPast
                return date1 < date2
            }
        }
    }
    
    // MARK: - Node Sorting
    
    /// Sort FunctionNodes by extracting their URLs and reordering based on sort preference
    static func sortNodes(_ nodes: [FunctionNode], by sortOrder: FolderSortOrder) -> [FunctionNode] {
        print("🔄 [SortingUtility] Sorting \(nodes.count) nodes by: \(sortOrder.displayName)")
        
        // Extract URLs from nodes for sorting
        var urlNodePairs: [(URL, FunctionNode)] = []
        
        for node in nodes {
            if let previewURL = node.previewURL {
                urlNodePairs.append((previewURL, node))
            } else if let metadata = node.metadata,
                      let urlString = metadata["folderURL"] as? String {
                urlNodePairs.append((URL(fileURLWithPath: urlString), node))
            }
        }
        
        // Sort the URLs using existing sort logic
        let urls = urlNodePairs.map { $0.0 }
        let sortedURLs = sortURLs(urls, by: sortOrder)
        
        // Reorder nodes to match sorted URLs
        var sortedNodes: [FunctionNode] = []
        for sortedURL in sortedURLs {
            if let pair = urlNodePairs.first(where: { $0.0 == sortedURL }) {
                sortedNodes.append(pair.1)
            }
        }
        
        return sortedNodes
    }
    
    // MARK: - Helper: Get Folder URLs with Properties
    
    /// Get folder URLs with required properties for sorting
    static func getFolderURLs(at folderURL: URL) -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .contentModificationDateKey,
                    .creationDateKey,
                    .addedToDirectoryDateKey,
                    .fileSizeKey
                ],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        } catch {
            print("❌ [SortingUtility] Failed to read folder: \(error)")
            return []
        }
    }
    
    // MARK: - Enhanced Item Sorting
    
    /// Sort EnhancedFolderItems (for cache refresh)
    static func sortEnhancedItems(_ items: [EnhancedFolderItem], by sortOrder: FolderSortOrder) -> [EnhancedFolderItem] {
        print("🔄 [SortingUtility] Sorting \(items.count) enhanced items by: \(sortOrder.displayName)")
        
        switch sortOrder {
        case .alphabeticalAsc:
            return items.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            
        case .alphabeticalDesc:
            return items.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedDescending
            }
            
        case .modifiedNewest:
            return items.sorted { $0.modificationDate > $1.modificationDate }
            
        case .modifiedOldest:
            return items.sorted { $0.modificationDate < $1.modificationDate }
            
        case .createdNewest:
            return items.sorted { $0.creationDate > $1.creationDate }

        case .createdOldest:
            return items.sorted { $0.creationDate < $1.creationDate }

        case .addedNewest:
            return items.sorted { $0.dateAdded > $1.dateAdded }

        case .addedOldest:
            return items.sorted { $0.dateAdded < $1.dateAdded }
            
        case .foldersFirst:
            return items.sorted { item1, item2 in
                if item1.isDirectory != item2.isDirectory {
                    return item1.isDirectory  // Folders first
                }
                // Then alphabetical
                return item1.name.localizedStandardCompare(item2.name) == .orderedAscending
            }
            
        case .sizeDescending:
            return items.sorted { $0.fileSize > $1.fileSize }
            
        case .sizeAscending:
            return items.sorted { $0.fileSize < $1.fileSize }
        
        }
    }
}
