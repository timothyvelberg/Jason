//
//  ListPanelView.swift
//  Jason
//
//  A custom list panel UI that matches the circular ring aesthetic.
//  Used for folder browsing and other list-based navigation.
//

import SwiftUI
import AppKit

// MARK: - List Panel View

struct ListPanelView: View {
    let items: [FunctionNode]
    
    // Configuration
    var panelWidth: CGFloat = 260
    var rowHeight: CGFloat = 32
    var iconSize: CGFloat = 20
    var cornerRadius: CGFloat = 12
    var maxVisibleItems: Int = 10
    
    // State
    @State private var hoveredItemId: String? = nil
    
    // Computed
    private var panelHeight: CGFloat {
        let itemCount = min(items.count, maxVisibleItems)
        let contentHeight = CGFloat(itemCount) * rowHeight
        let padding: CGFloat = 8
        return contentHeight + padding
    }
    
    private var needsScroll: Bool {
        items.count > maxVisibleItems
    }
    
    var body: some View {
        ZStack {
            // Background layers (matching ring aesthetic)
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.black.opacity(0.33))
            
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.ultraThinMaterial)
            
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
            
            // Content
            ScrollView(.vertical, showsIndicators: needsScroll) {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        ListPanelRow(
                            item: item,
                            iconSize: iconSize,
                            rowHeight: rowHeight,
                            isHovered: hoveredItemId == item.id
                        )
                        .onHover { hovering in
                            hoveredItemId = hovering ? item.id : nil
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: CGFloat(maxVisibleItems) * rowHeight)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius - 2))
            .padding(4)
        }
        .frame(width: panelWidth, height: panelHeight)
    }
}

// MARK: - List Panel Row

struct ListPanelRow: View {
    let item: FunctionNode
    let iconSize: CGFloat
    let rowHeight: CGFloat
    let isHovered: Bool
    
    private var isFolder: Bool {
        item.type == .folder
    }
    
    var body: some View {
        HStack(spacing: 10) {
            // Icon
            Image(nsImage: item.icon)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
            
            // Name
            Text(item.name)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
            
            // Folder indicator (chevron)
            if isFolder {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.white.opacity(0.15) : Color.clear)
        )
        .padding(.horizontal, 4)
    }
}
