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
    let title: String
    let items: [FunctionNode]
    
    // Callbacks for interactions
    var onItemLeftClick: ((FunctionNode, NSEvent.ModifierFlags) -> Void)?
    var onItemRightClick: ((FunctionNode, NSEvent.ModifierFlags) -> Void)?
    var onContextAction: ((FunctionNode, NSEvent.ModifierFlags) -> Void)?
    var onItemHover: ((FunctionNode?, Int?) -> Void)?
    var onHeaderHover: (() -> Void)?
    var onScrollOffsetChanged: ((CGFloat) -> Void)?  // Current scroll offset
    var onScrollStateChanged: ((Bool) -> Void)?  // true = scrolling started, false = stopped
    var contextActions: [FunctionNode]?

    
    // Expanded state from manager
    @Binding var expandedItemId: String?
    var hoveredRowIndex: Int?
    var isKeyboardDriven: Bool = false

    
    // Configuration
    var panelWidth: CGFloat = 260
    var rowHeight: CGFloat = 32
    var iconSize: CGFloat = 20
    var cornerRadius: CGFloat = 12
    var maxVisibleItems: Int = 10
    
    // State
    @State private var isScrolling: Bool = false
    @State private var lastScrollOffset: CGFloat = 0
    @State private var scrollDebounceTask: DispatchWorkItem? = nil
    
    // Computed
    private var titleHeight: CGFloat { 40 }
    
    private var panelHeight: CGFloat {
        let itemCount = min(items.count, maxVisibleItems)
        let contentHeight = CGFloat(itemCount) * rowHeight
        let padding: CGFloat = 8
        return titleHeight + contentHeight + padding
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
            VStack(spacing: 0) {
                // Title bar
                HStack {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Spacer()
                    
                    // Context actions for the source folder
                    if let actions = contextActions, !actions.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(actions) { action in
                                Button {
                                    onContextAction?(action, NSEvent.modifierFlags)
                                } label: {
                                    Image(nsImage: action.icon)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 16, height: 16)
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
                .padding(.horizontal, 14)
                .frame(height: titleHeight)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 1)
                }
                
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: needsScroll) {
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                ListPanelRow(
                                    item: item,
                                    iconSize: iconSize,
                                    rowHeight: rowHeight,
                                    isHovered: !isScrolling && hoveredRowIndex == index,
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
                                .id(index)  // Add ID for ScrollViewReader
                            }
                        }
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onChange(of: geo.frame(in: .named("panelScroll")).minY) { _, newValue in
                                        handleScrollChange(-newValue)
                                    }
                            }
                        )
                    }
                    .coordinateSpace(name: "panelScroll")
                    .frame(maxHeight: CGFloat(maxVisibleItems) * rowHeight)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius - 2))
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                    .onChange(of: hoveredRowIndex) { oldIndex, newIndex in
                        // Auto-scroll only when KEYBOARD navigates outside visible area
                        guard isKeyboardDriven, let index = newIndex else { return }
                        
                        // Calculate which rows are currently visible
                        let firstVisibleRow = Int(lastScrollOffset / rowHeight)
                        let lastVisibleRow = firstVisibleRow + maxVisibleItems - 1
                        
                        // Only scroll if selection is outside visible range
                        if index < firstVisibleRow {
                            // Selection went above visible area - scroll up
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(index, anchor: .top)
                            }
                        } else if index > lastVisibleRow {
                            // Selection went below visible area - scroll down
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(index, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: panelWidth, height: panelHeight)
    }
    
    private func handleScrollChange(_ newOffset: CGFloat) {
        let delta = abs(newOffset - lastScrollOffset)
        lastScrollOffset = newOffset
        
        // Always report offset changes for position tracking
        onScrollOffsetChanged?(newOffset)
        
        // Ignore tiny changes for scroll state (noise)
        guard delta > 1 else { return }
        
        // Start scrolling if not already
        if !isScrolling {
            isScrolling = true
            onScrollStateChanged?(true)
            print("📜 [View] '\(title)' scroll STARTED")
        }
        
        // Cancel existing debounce
        scrollDebounceTask?.cancel()
        
        // Set up debounce to detect scroll end
        let task = DispatchWorkItem { [self] in
            isScrolling = false
            onScrollStateChanged?(false)
            print("📜 [View] '\(title)' scroll STOPPED")
        }
        scrollDebounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)
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
            if isExpanded && hasContextActions && !isFolder {
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
