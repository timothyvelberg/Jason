//
//  FolderVisitTracker.swift
//  Jason
//
//  Created by Timothy Velberg on 01/03/2026.

import Foundation

class FolderVisitTracker {
    
    private var visitCounts: [String: Int] = [:]
    private(set) var promotedPaths: Set<String> = []
    
    let promotionThreshold = 3
    
    /// Record a visit. Returns true if this visit triggered promotion.
    func recordVisit(for path: String) -> Bool {
        let count = (visitCounts[path] ?? 0) + 1
        visitCounts[path] = count
        
        guard count >= promotionThreshold, !promotedPaths.contains(path) else {
            return false
        }
        
        promotedPaths.insert(path)
        return true
    }
    
    func isPromoted(_ path: String) -> Bool {
        return promotedPaths.contains(path)
    }
    
    func visitCount(for path: String) -> Int {
        return visitCounts[path] ?? 0
    }
}
