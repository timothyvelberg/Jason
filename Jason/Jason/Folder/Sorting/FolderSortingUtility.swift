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
        print("[SortingUtility] Sorting \(urls.count) URLs by: \(sortOrder.displayName)")
        
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
            let dates = Dictionary(uniqueKeysWithValues: urls.map { url in
                (url, (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast)
            })
            return urls.sorted { dates[$0, default: .distantPast] > dates[$1, default: .distantPast] }
            
        case .modifiedOldest:
            let dates = Dictionary(uniqueKeysWithValues: urls.map { url in
                (url, (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast)
            })
            return urls.sorted { dates[$0, default: .distantPast] < dates[$1, default: .distantPast] }
            
        case .createdNewest:
            let dates = Dictionary(uniqueKeysWithValues: urls.map { url in
                (url, (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast)
            })
            return urls.sorted { dates[$0, default: .distantPast] > dates[$1, default: .distantPast] }
            
        case .createdOldest:
            let dates = Dictionary(uniqueKeysWithValues: urls.map { url in
                (url, (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast)
            })
            return urls.sorted { dates[$0, default: .distantPast] < dates[$1, default: .distantPast] }
            
        case .addedNewest:
            let dates = Dictionary(uniqueKeysWithValues: urls.map { url in
                (url, (try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate ?? Date.distantPast)
            })
            return urls.sorted { dates[$0, default: .distantPast] > dates[$1, default: .distantPast] }
            
        case .addedOldest:
            let dates = Dictionary(uniqueKeysWithValues: urls.map { url in
                (url, (try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate ?? Date.distantPast)
            })
            return urls.sorted { dates[$0, default: .distantPast] < dates[$1, default: .distantPast] }
            
        case .foldersFirst:
            return urls.sorted { url1, url2 in
                let isDir1 = (try? url1.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let isDir2 = (try? url2.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if isDir1 != isDir2 { return isDir1 }
                return url1.lastPathComponent.localizedStandardCompare(url2.lastPathComponent) == .orderedAscending
            }
            
        case .sizeDescending:
            let sizes = Dictionary(uniqueKeysWithValues: urls.map { url in
                (url, (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            })
            return urls.sorted { sizes[$0, default: 0] > sizes[$1, default: 0] }
            
        case .sizeAscending:
            let sizes = Dictionary(uniqueKeysWithValues: urls.map { url in
                (url, (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            })
            return urls.sorted { sizes[$0, default: 0] < sizes[$1, default: 0] }
        }
    }
    
    // MARK: - Node Sorting
    
    /// Sort FunctionNodes by extracting their URLs and reordering based on sort preference
    static func sortNodes(_ nodes: [FunctionNode], by sortOrder: FolderSortOrder) -> [FunctionNode] {
        print("[SortingUtility] Sorting \(nodes.count) nodes by: \(sortOrder.displayName)")
        
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
            print("[SortingUtility] Failed to read folder: \(error)")
            return []
        }
    }
    
    // MARK: - Enhanced Item Sorting
    
    /// Sort EnhancedFolderItems (for cache refresh)
    static func sortEnhancedItems(_ items: [EnhancedFolderItem], by sortOrder: FolderSortOrder) -> [EnhancedFolderItem] {
        print("[SortingUtility] Sorting \(items.count) enhanced items by: \(sortOrder.displayName)")
        
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
