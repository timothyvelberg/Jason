//
//  PermissionManager.swift
//  Jason
//
//  Created by Timothy Velberg on 16/01/2026.
//  Handles upfront permission requests for protected folders
//

import Foundation
import AppKit

class PermissionManager {
    
    static let shared = PermissionManager()
    
    private init() {}
    
    /// Call this early at app launch, before any UI
    func requestAccessToFavoriteFolders() {
        print("🔐 [Permissions] Checking folder access...")
        
        // Get favorite folders from database
        let favoriteFolders = DatabaseManager.shared.getFavoriteFolders()
        let folderPaths = favoriteFolders.map { $0.folder.path }
        
        // Also add common system folders that might be used
        var allPaths = folderPaths
        
        if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            allPaths.append(desktop.path)
        }
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            allPaths.append(downloads.path)
        }
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            allPaths.append(documents.path)
        }
        
        // Remove duplicates
        let uniquePaths = Array(Set(allPaths))
        
        print("🔐 [Permissions] Requesting access to \(uniquePaths.count) folders")
        
        for path in uniquePaths {
            requestAccess(to: path)
        }
        
        print("🔐 [Permissions] Folder access check complete")
    }
    
    private func requestAccess(to path: String) {
        let url = URL(fileURLWithPath: path)
        
        do {
            // This triggers the permission dialog if needed
            _ = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            print("   ✅ Access granted: \(url.lastPathComponent)")
        } catch {
            print("   ❌ Access denied or error: \(url.lastPathComponent) - \(error.localizedDescription)")
        }
    }
}
