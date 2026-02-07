//
//  ListPanelView.swift
//  Jason
//
//  A custom list panel UI that matches the circular ring aesthetic.
//  Used for folder browsing and other list-based navigation.
//

import SwiftUI
import AppKit

// MARK: - Row Height Preference Key

/// Collects measured row heights from child views
struct RowHeightPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

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
    var onScrollOffsetChanged: ((CGFloat) -> Void)?
    var onScrollStateChanged: ((Bool) -> Void)?
    var onRowHeightsMeasured: (([CGFloat]) -> Void)?
    var contextActions: [FunctionNode]?
    var typingMode: TypingMode = .typeAhead

    
    // Expanded state from manager
    @Binding var expandedItemId: String?
    @Binding var isSearchActive: Bool
    @Binding var searchQuery: String
    var hoveredRowIndex: Int?
    var isKeyboardDriven: Bool = false

    
    // Configuration
    var config: PanelConfig = .default
    var iconSize: CGFloat = 20
    var cornerRadius: CGFloat = 12
    
    // State
    @State private var isScrolling: Bool = false
    @State private var lastScrollOffset: CGFloat = 0
    @State private var scrollDebounceTask: DispatchWorkItem? = nil
    @State private var measuredRowHeights: [Int: CGFloat] = [:]
    
    // Computed from config
    private var panelWidth: CGFloat { config.panelWidth }
    private var maxVisibleItems: Int { config.maxVisibleItems }
    private var titleHeight: CGFloat { PanelConfig.titleHeight }
    
    /// Scroll area height based on measured row heights
    private var scrollAreaHeight: CGFloat {
        let visibleCount = min(items.count, maxVisibleItems)
        var total: CGFloat = 0
        for i in 0..<visibleCount {
            total += measuredRowHeights[i] ?? config.baseRowHeight
        }
        return total
    }
    
    private var panelHeight: CGFloat {
        titleHeight + scrollAreaHeight + ((PanelConfig.padding * 2) + PanelConfig.padding / 2 )
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
                    if isSearchActive {
                        let placeholder = typingMode == .input ? "Add todo..." : "Search..."
                        TextField(placeholder, text: $searchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                    } else {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
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
                .padding(.horizontal, 16)
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
                                Group {
                                    if item.type == .sectionHeader {
                                        ListPanelSectionHeader(
                                            item: item,
                                            baseRowHeight: config.baseRowHeight
                                        )
                                    } else {
                                        ListPanelRow(
                                            item: item,
                                            iconSize: iconSize,
                                            baseRowHeight: config.baseRowHeight,
                                            lineLimit: config.lineLimit,
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
                                    }
                                }
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: RowHeightPreferenceKey.self,
                                            value: [index: geo.size.height]
                                        )
                                    }
                                )
                                .id(index)
                            }
                        }
                        .onPreferenceChange(RowHeightPreferenceKey.self) { heights in
                            var changed = false
                            for (index, height) in heights {
                                if measuredRowHeights[index] != height {
                                    measuredRowHeights[index] = height
                                    changed = true
                                }
                            }
                            if changed {
                                reportRowHeights()
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
                    .frame(maxHeight: scrollAreaHeight)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius - 2))
                    .padding(.horizontal, 4)
                    .padding(.bottom,8)
                    .padding(.top, 8)
                    .onChange(of: hoveredRowIndex) { oldIndex, newIndex in
                        // Auto-scroll only when KEYBOARD navigates outside visible area
                        guard isKeyboardDriven, let index = newIndex else { return }
                        
                        // Calculate visible range using accumulated heights
                        let scrollOffset = lastScrollOffset
                        var accumulated: CGFloat = 0
                        var firstVisibleRow = 0
                        for i in 0..<items.count {
                            let rowH = measuredRowHeights[i] ?? config.baseRowHeight
                            if accumulated + rowH > scrollOffset {
                                firstVisibleRow = i
                                break
                            }
                            accumulated += rowH
                        }
                        
                        accumulated = 0
                        var lastVisibleRow = items.count - 1
                        var visibleHeight: CGFloat = 0
                        for i in firstVisibleRow..<items.count {
                            let rowH = measuredRowHeights[i] ?? config.baseRowHeight
                            visibleHeight += rowH
                            if visibleHeight > scrollAreaHeight {
                                lastVisibleRow = i - 1
                                break
                            }
                            lastVisibleRow = i
                        }
                        
                        // Only scroll if selection is outside visible range
                        if index < firstVisibleRow {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(index, anchor: .top)
                            }
                        } else if index > lastVisibleRow {
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
    
    /// Build ordered array from measured heights and report to manager
    private func reportRowHeights() {
        var ordered: [CGFloat] = []
        for i in 0..<items.count {
            ordered.append(measuredRowHeights[i] ?? config.baseRowHeight)
        }
        onRowHeightsMeasured?(ordered)
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
            print("[View] '\(title)' scroll STARTED")
        }
        
        // Cancel existing debounce
        scrollDebounceTask?.cancel()
        
        // Set up debounce to detect scroll end
        let task = DispatchWorkItem { [self] in
            isScrolling = false
            onScrollStateChanged?(false)
            print("[View] '\(title)' scroll STOPPED")
        }
        scrollDebounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)
    }
}

struct ListPanelSectionHeader: View {
    let item: FunctionNode
    let baseRowHeight: CGFloat
    
    var body: some View {
        HStack {
            Text(item.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.45))
                .textCase(.uppercase)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - List Panel Row

struct ListPanelRow: View {
    let item: FunctionNode
    let iconSize: CGFloat
    let baseRowHeight: CGFloat
    let lineLimit: Int
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
        HStack(spacing: 16) {
            // Icon
            Image(nsImage: item.icon)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
            
            // Name
            Text(item.name)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .lineLimit(lineLimit)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
            
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
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(minHeight: baseRowHeight)
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
