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
    
    // Callbacks for interactions
    var onItemLeftClick: ((FunctionNode, NSEvent.ModifierFlags) -> Void)?
    var onItemRightClick: ((FunctionNode, NSEvent.ModifierFlags) -> Void)?
    var onContextAction: ((FunctionNode, NSEvent.ModifierFlags) -> Void)?
    var onItemHover: ((FunctionNode?, Int?) -> Void)?
    
    // Expanded state from manager
    @Binding var expandedItemId: String?
    
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
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ListPanelRow(
                            item: item,
                            iconSize: iconSize,
                            rowHeight: rowHeight,
                            isHovered: hoveredItemId == item.id,
                            isExpanded: expandedItemId == item.id,
                            onLeftClick: { modifiers in
                                expandedItemId = nil
                                onItemLeftClick?(item, modifiers)
                            },
                            onRightClick: { modifiers in
                                onItemRightClick?(item, modifiers)
                            },
                            onContextAction: { action, modifiers in
                                expandedItemId = nil
                                onContextAction?(action, modifiers)
                            }
                        )
                        .onHover { hovering in
                            if hovering {
                                if expandedItemId != nil && expandedItemId != item.id {
                                    expandedItemId = nil
                                }
                                hoveredItemId = item.id
                                onItemHover?(item, index)
                            } else {
                                hoveredItemId = nil
                            }
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
    let isExpanded: Bool
    
    // Click callbacks
    var onLeftClick: ((NSEvent.ModifierFlags) -> Void)?
    var onRightClick: ((NSEvent.ModifierFlags) -> Void)?
    var onContextAction: ((FunctionNode, NSEvent.ModifierFlags) -> Void)?
    
    private var isFolder: Bool {
        item.type == .folder
    }
    
    private var hasContextActions: Bool {
        guard let actions = item.contextActions else { return false }
        return !actions.isEmpty
    }
    
    private var contextActionIconSize: CGFloat { 16 }
    
    var body: some View {
        HStack(spacing: 10) {
            // Icon
            Image(nsImage: item.icon)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
            
            // Name (always visible, truncates when expanded)
            Text(item.name)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
            
            Spacer()
            
            // Context actions (visible when expanded via right-click)
            if isExpanded && hasContextActions {
                contextActionsView
            }
            
            // Folder indicator (chevron) - hide when expanded
            if isFolder && !isExpanded {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: rowHeight)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered || isExpanded ? Color.white.opacity(0.15) : Color.clear)
        )
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
    
    // Break out context actions to simplify type checking
    @ViewBuilder
    private var contextActionsView: some View {
        HStack(spacing: 8) {
            ForEach(item.contextActions!) { action in
                Button {
                    onContextAction?(action, NSEvent.modifierFlags)
                } label: {
                    Image(nsImage: action.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: contextActionIconSize, height: contextActionIconSize)
                        .opacity(0.85)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
        }
    }
}
