//
//  PanelConfig.swift
//  Jason
//
//  Centralized configuration for panel appearance and layout.
//  Providers can supply custom configs to control panel dimensions.
//

import Foundation

struct PanelConfig {
    
    // MARK: - Configurable Properties
    
    /// Maximum lines of text per row (caps how tall a row can grow)
    var lineLimit: Int = 1
    
    /// Panel width in points
    var panelWidth: CGFloat = 260
    
    /// Maximum number of visible rows before scrolling
    var maxVisibleItems: Int = 10
    
    /// Width of the preview panel
    var previewPanelWidth: CGFloat = 320

    /// Maximum height of the preview panel
    var previewPanelMaxHeight: CGFloat = 400
    
    /// Padding above the scroll content (between title bar and first row)
    static let scrollTopPadding: CGFloat = 8
    
    /// Estimated rendered row height including view padding.
    /// Used as fallback when measured heights aren't available yet.
    var estimatedRowHeight: CGFloat { 36.0 }

    /// Padding below the scroll content
    static let scrollBottomPadding: CGFloat = 8

    /// Total distance from panel's bottom edge to where scroll content ends
    static var contentBottomInset: CGFloat { (padding / 2) + scrollBottomPadding }

    /// Total distance from panel's top edge to where scroll content begins
    static var contentTopInset: CGFloat { (padding / 2) + titleHeight + scrollTopPadding }
    
    
    
    // MARK: - Constants (not configurable per-provider)
    
    static let titleHeight: CGFloat = 56
    static let padding: CGFloat = 0
    static let cascadeSlideDistance: CGFloat = 30
    
    // MARK: - Derived Properties
    
    /// Minimum row height (single line). Rows grow from this when text wraps.
    var baseRowHeight: CGFloat { 32 }
    
    /// Maximum row height based on line limit
    var maxRowHeight: CGFloat {
        let extraPerLine: CGFloat = 16
        return baseRowHeight + CGFloat(max(0, lineLimit - 1)) * extraPerLine
    }
    
    // MARK: - Default
    
    static let `default` = PanelConfig()
}
