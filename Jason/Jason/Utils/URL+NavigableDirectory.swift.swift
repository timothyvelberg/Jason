//
//  URL+NavigableDirectory.swift.swift
//  Jason
//
//  Created by Timothy Velberg on 18/01/2026.
//

import Foundation
import AppKit

extension URL {
    /// Returns true if this URL points to a directory that should be navigable (not a package like .app, .bundle, etc.)
    var isNavigableDirectory: Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: self.path, isDirectory: &isDirectory) else {
            return false
        }
        
        guard isDirectory.boolValue else {
            return false
        }
        
        // Packages (.app, .bundle, etc.) should not be navigable
        let isPackage = NSWorkspace.shared.isFilePackage(atPath: self.path)
        return !isPackage
    }
}
