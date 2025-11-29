//
//  RingState.swift
//  Jason
//
//  Created by Timothy Velberg on 29/11/2025.
//

import Foundation

/// Represents the state of a single ring in the circular UI
struct RingState {
    var nodes: [FunctionNode]
    var hoveredIndex: Int?
    var selectedIndex: Int?
    var isCollapsed: Bool = false
    var openedByClick: Bool = false
    
    // Track what this ring represents
    var providerId: String?           // Which provider owns this content
    var contentIdentifier: String?    // For folders: folderPath, for apps: nil
    
    // Preserve slice configuration to prevent unwanted layout changes
    var sliceConfig: PieSliceConfig?
    
    init(nodes: [FunctionNode],
         isCollapsed: Bool = false,
         openedByClick: Bool = false,
         providerId: String? = nil,
         contentIdentifier: String? = nil,
         sliceConfig: PieSliceConfig? = nil) {
        self.nodes = nodes
        self.hoveredIndex = nil
        self.selectedIndex = nil
        self.isCollapsed = isCollapsed
        self.openedByClick = openedByClick
        self.providerId = providerId
        self.contentIdentifier = contentIdentifier
        self.sliceConfig = sliceConfig
    }
}
