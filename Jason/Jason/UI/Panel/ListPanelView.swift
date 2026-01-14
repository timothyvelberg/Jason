//
//  ListPanelView.swift
//  Jason
//
//  Created by Timothy Velberg on 14/01/2026.
//  A custom list panel UI that matches the circular ring aesthetic.
//  Used for folder browsing and other list-based navigation.
//

import SwiftUI
import AppKit

// MARK: - List Panel Item

struct ListPanelItem: Identifiable {
    let id: String
    let name: String
    let icon: NSImage
    let isFolder: Bool
    
    init(id: String = UUID().uuidString, name: String, icon: NSImage, isFolder: Bool = false) {
        self.id = id
        self.name = name
        self.icon = icon
        self.isFolder = isFolder
    }
}

// MARK: - List Panel View

struct ListPanelView: View {
    let items: [ListPanelItem]
    
    // Configuration
    let panelWidth: CGFloat = 260
    let rowHeight: CGFloat = 32
    let iconSize: CGFloat = 20
    let cornerRadius: CGFloat = 12
    let maxVisibleItems: Int = 10
    
    // State
    @State private var hoveredItemId: String? = nil
    
    // Computed
    private var panelHeight: CGFloat {
        let itemCount = min(items.count, maxVisibleItems)
        let contentHeight = CGFloat(itemCount) * rowHeight
        let padding: CGFloat = 8 // Top + bottom padding
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
    let item: ListPanelItem
    let iconSize: CGFloat
    let rowHeight: CGFloat
    let isHovered: Bool
    
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
            if item.isFolder {
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
