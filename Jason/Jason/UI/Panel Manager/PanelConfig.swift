//
//  PanelConfig.swift
//  Jason
//
//  Created by Timothy Velberg on 06/02/2026.
//  Centralized configuration for panel appearance and layout.
//  Providers can supply custom configs to control panel dimensions.
//

import Foundation

struct PanelConfig {
    
    // MARK: - Configurable Properties
    
    /// Maximum lines of text per row (drives row height)
    var lineLimit: Int = 1
    
    /// Panel width in points
    var panelWidth: CGFloat = 260
    
    /// Maximum number of visible rows before scrolling
    var maxVisibleItems: Int = 10
    
    // MARK: - Constants (not configurable per-provider)
    
    static let titleHeight: CGFloat = 40
    static let padding: CGFloat = 8
    static let cascadeSlideDistance: CGFloat = 30
    
    // MARK: - Derived Properties
    
    /// Row height derived from line limit
    var rowHeight: CGFloat {
        let baseHeight: CGFloat = 32
        let extraPerLine: CGFloat = 16
        return baseHeight + CGFloat(max(0, lineLimit - 1)) * extraPerLine
    }
    
    // MARK: - Default
    
    static let `default` = PanelConfig()
}
