//
//  ListPanelManager.swift
//  Jason
//
//  Manages state and logic for the list panel UI.
//  Supports stack-based cascading panels (column view).
//

import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - List Panel Manager

class ListPanelManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published var panelStack: [PanelState] = []
    @Published var hoveredRow: [Int: Int] = [:]
    
    // MARK: - Keyboard Navigation State

    /// Which panel level is currently active (has keyboard focus)
    @Published var activePanelLevel: Int = 0

    /// Keyboard-selected row per panel level
    @Published var keyboardSelectedRow: [Int: Int] = [:]

    /// Whether keyboard is currently driving selection (vs mouse)
    var isKeyboardDriven: Bool {
        inputCoordinator?.inputMode == .keyboard
    }
    
    // MARK: - Type-Ahead Search State (internal for extension access)

    /// Buffer for type-ahead search
    var searchBuffer: String = ""

    /// Timer to reset search buffer
    var searchBufferTimer: DispatchWorkItem?

    /// Timeout before search buffer resets (seconds)
    let searchTimeout: Double = 0.5
    
    // MARK: - Sliding Configuration
    
    /// How much of the previous panel stays visible when overlapped
    let peekWidth: CGFloat = 75
    
    /// How far across the row (0-1) before triggering slide
    let slideThreshold: CGFloat = 0.75
    
    // MARK: - Computed Properties
    
    var isVisible: Bool {
        !panelStack.isEmpty
    }
    
    /// First panel's position (for backward compatibility)
    var position: CGPoint {
        panelStack.first?.position ?? .zero
    }
    
    /// First panel's items (for backward compatibility)
    var items: [FunctionNode] {
        panelStack.first?.items ?? []
    }
    
    /// Resolve a provider by ID (injected by owning manager)
    var findProvider: ((String) -> (any FunctionProvider)?)?
    
    /// Expanded item ID for first panel (for backward compatibility with binding)
    var expandedItemId: String? {
        get { panelStack.first?.expandedItemId }
        set {
            guard !panelStack.isEmpty else { return }
            panelStack[0].expandedItemId = newValue
        }
    }
    
    /// Callback when user submits text in input mode (e.g., add todo)
    var onAddItem: ((String, NSEvent.ModifierFlags) -> Void)?
    
    // MARK: - Dynamic Load State
    
    /// Current in-flight dynamic load task (cancelled when hover changes)
    var dynamicLoadTask: Task<Void, Never>?
    
    /// Debounce timer for dynamic folder loading (prevents loading during fast scrolling)
    var dynamicLoadDebounce: DispatchWorkItem?
    
    
    // MARK: - Ring Context (internal for extension access)
    
    /// Current ring context (stored for cascading position calculations)
    private(set) var currentRingCenter: CGPoint = .zero
    private(set) var currentRingOuterRadius: CGFloat = 0
    private(set) var currentAngle: Double = 0
    var currentScreen: NSScreen?
    
    weak var inputCoordinator: InputCoordinator?

    // MARK: - Pending Panel (waiting for arming)

    private var pendingPanel: (
        title: String,
        items: [FunctionNode],
        fromLevel: Int,
        sourceNodeId: String,
        sourceRowIndex: Int?,
        providerId: String?,
        contentIdentifier: String?,
        contextActions: [FunctionNode]?
    )?
    
    /// Track which node ID is currently being loaded for each panel level
    /// Used to discard stale async completions when user has moved to a different row
    var currentlyHoveredNodeId: [Int: String] = [:]
    
    // MARK: - Callbacks (wired by CircularUIManager)
    
    var onItemLeftClick: ((FunctionNode, NSEvent.ModifierFlags) -> Void)?
    var onItemRightClick: ((FunctionNode, NSEvent.ModifierFlags) -> Void)?
    var onContextAction: ((FunctionNode, NSEvent.ModifierFlags) -> Void)?
    
    /// Callback to reload content for a panel
    var onReloadContent: ((String, String?) async -> [FunctionNode])?
    
    /// Callback when user exits beyond panel level 0 (back to ring)
    var onExitToRing: (() -> Void)?
    
    // MARK: - Scroll State Tracking
    
    /// Panels currently being scrolled (suppress hover during scroll)
    private var scrollingPanels: Set<Int> = []
    
    /// Debounce timers per panel level
    private var scrollDebounceTimers: [Int: DispatchWorkItem] = [:]
    
    /// How long to wait after scroll stops before re-enabling hover (seconds)
    private let scrollDebounceDelay: Double = 0.1
    
    // MARK: - Initialization

    init() {
        // Register for provider update notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProviderUpdate(_:)),
            name: .providerContentUpdated,
            object: nil
        )
        print("[ListPanelManager] Initialized - registered for provider updates")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        print("[ListPanelManager] Deallocated - removed observers")
    }
    
    // MARK: - Row Height Updates
    
    /// Update measured row heights for a panel (called from SwiftUI view)
    func updateRowHeights(_ heights: [CGFloat], forLevel level: Int) {
        guard let index = panelStack.firstIndex(where: { $0.level == level }) else { return }
        panelStack[index].rowHeights = heights
    }
    
    // MARK: - Provider Update Handler

    @objc private func handleProviderUpdate(_ notification: Notification) {
        guard let updateInfo = ProviderUpdateInfo.from(notification) else {
            print("[ListPanelManager] Invalid provider update notification")
            return
        }
        if let folderPath = updateInfo.folderPath {
            print("   Folder: \(folderPath)")
        }
        
        // Check if any panel matches this update
        guard let matchingIndex = panelStack.firstIndex(where: { panel in
            guard panel.providerId == updateInfo.providerId else { return false }
            
            // If folderPath specified, must match contentIdentifier
            if let folderPath = updateInfo.folderPath {
                return panel.contentIdentifier == folderPath
            }
            
            // No folderPath specified - provider match is enough
            return true
        }) else {
            return
        }
        
        let matchingPanel = panelStack[matchingIndex]
        print("   Found matching panel at level \(matchingPanel.level): '\(matchingPanel.title)'")
        
        // Close any child panels
        if matchingIndex < panelStack.count - 1 {
            let childCount = panelStack.count - matchingIndex - 1
            print("   Closing \(childCount) child panel(s)")
            popToLevel(matchingPanel.level)
        }
        
        // Reload content
        guard let onReloadContent = onReloadContent,
              let providerId = matchingPanel.providerId else {
            print("   No reload callback or providerId - cannot refresh")
            return
        }
        
        let contentIdentifier = matchingPanel.contentIdentifier
        
        Task {
            let freshItems = await onReloadContent(providerId, contentIdentifier)
            
            await MainActor.run {
                // Find the panel again (stack may have changed)
                guard let currentIndex = self.panelStack.firstIndex(where: { $0.id == matchingPanel.id }) else {
                    print("   Panel no longer exists - skipping update")
                    return
                }
                
                print("   Updating panel with \(freshItems.count) items (was \(self.panelStack[currentIndex].items.count))")
                if freshItems.count != self.panelStack[currentIndex].items.count {
                    self.panelStack[currentIndex].rowHeights = []
                }
                self.panelStack[currentIndex].items = freshItems
            }
        }
    }
    
    /// Wire standard panel callbacks that are identical across all UI managers.
    /// Manager-specific callbacks (onExitToRing, onAddItem, etc.) remain wired individually.
    func wireStandardCallbacks(handler: PanelActionHandler, providers: [any FunctionProvider]) {
        onItemLeftClick = { [weak handler] node, modifiers in
            handler?.handleLeftClick(node: node, modifiers: modifiers, fromLevel: 0)
        }
        
        onItemRightClick = { [weak handler] node, modifiers in
            handler?.handleRightClick(node: node, modifiers: modifiers)
        }
        
        onContextAction = { [weak handler] actionNode, modifiers in
            handler?.handleContextAction(actionNode: actionNode, modifiers: modifiers)
        }
        
        onReloadContent = { [weak self] providerId, contentIdentifier in
            guard let self = self,
                  let provider = self.findProvider?(providerId) else {
                print("[Panel Reload] Provider '\(providerId)' not found")
                return []
            }
            
            let reloadNode = FunctionNode(
                id: "reload-\(contentIdentifier ?? "unknown")",
                name: "reload",
                type: .folder,
                icon: NSImage(),
                metadata: contentIdentifier != nil ? ["folderURL": contentIdentifier!] : nil,
                providerId: providerId
            )
            
            print("[Panel Reload] Reloading content for '\(contentIdentifier ?? "unknown")'")
            let freshChildren = await provider.loadChildren(for: reloadNode)
            print("[Panel Reload] Got \(freshChildren.count) items")
            
            return freshChildren
        }
        
        // Wire add item for mutable providers
         onAddItem = { [weak self, weak handler] text, modifiers in
             guard let self = self else { return }
             
             guard let panel = self.panelStack.first(where: { $0.level == 0 }),
                   let providerId = panel.providerId,
                   let provider = self.findProvider?(providerId) as? any MutableListProvider else { return }
             
             provider.addItem(title: text)
             self.refreshPanelItems(at: 0)
             
             if !modifiers.contains(.command) {
                 handler?.hideUI?()
             }
         }
         
         // Wire items changed notifications for all mutable providers
         for provider in providers {
             if var mutableProvider = provider as? any MutableListProvider {
                 mutableProvider.onItemsChanged = { [weak self] in
                     self?.refreshPanelItems(at: 0)
                 }
             }
         }
    }
    
    // MARK: - Scroll State
    
    /// Check if a panel is currently scrolling
    func isPanelScrolling(_ level: Int) -> Bool {
        scrollingPanels.contains(level)
    }
    
    /// Handle item hover with scroll-suppression logic (called from view)
    func handleViewHover(node: FunctionNode?, level: Int, rowIndex: Int?) {
        // Suppress hover events while panel is scrolling
        if isPanelScrolling(level) {
            return
        }
        
        // Reset to mouse-driven selection when mouse hovers in panel
        resetToMouseMode()
        
        // Update hovered row for this level
        hoveredRow[level] = rowIndex
        
        // Track which node is currently hovered at this level
        if let node = node {
            currentlyHoveredNodeId[level] = node.id
        } else {
            currentlyHoveredNodeId.removeValue(forKey: level)
        }
        
        // Call the cascading logic directly (not through callback)
        handleItemHover(node: node, level: level, rowIndex: rowIndex ?? 0)
    }
    
    /// Handle scroll state changes from a panel
    func handleScrollStateChanged(isScrolling: Bool, forLevel level: Int) {
        if isScrolling {
            // Scrolling started - close any child panels and clear hover tracking
            scrollingPanels.insert(level)
            currentlyHoveredNodeId.removeValue(forKey: level)  // Clear stale hover
            popToLevel(level)
            print("[Scroll] Level \(level) scrolling - closed child panels")
        } else {
            // Scrolling stopped - re-enable hover
            scrollingPanels.remove(level)
            print("[Scroll] Level \(level) scroll stopped - hover re-enabled")
        }
    }
    
    /// Handle hover over panel header - clears child state
    func handleHeaderHover(level: Int) {
        // Clear hover tracking for this level
        currentlyHoveredNodeId.removeValue(forKey: level)
        
        // Clear pending panel if it was for this level
        if let pending = pendingPanel, pending.fromLevel == level {
            pendingPanel = nil
            print("[Header] Cleared pending panel for level \(level)")
        }
        
        // Reset arming for this panel
        if let index = panelStack.firstIndex(where: { $0.level == level }) {
            if panelStack[index].areChildrenArmed {
                panelStack[index].areChildrenArmed = false
                print("[Header] Reset arming for level \(level)")
            }
        }
        
        // Close any child panels
        let childCount = panelStack.filter { $0.level > level }.count
        if childCount > 0 {
            popToLevel(level)
            print("[Header] Closed \(childCount) child panel(s)")
        }
    }
    
    // MARK: - Scroll Offset Updates
    
    /// Update scroll offset for a panel at the given level
    func updateScrollOffset(_ offset: CGFloat, forLevel level: Int) {
        guard let index = panelStack.firstIndex(where: { $0.level == level }) else {
            return
        }
        
        let currentOffset = panelStack[index].scrollOffset
        if abs(currentOffset - offset) > 0.5 {
            panelStack[index].scrollOffset = offset
        }
    }
    
    /// Refresh panel items at the given level by re-querying the provider.
    func refreshPanelItems(at level: Int) {
        guard let panel = panelStack.first(where: { $0.level == level }) else {
            print("[ListPanelManager] refreshPanelItems: no panel at level \(level)")
            return
        }
        guard let providerId = panel.providerId else {
            print("[ListPanelManager] refreshPanelItems: panel has no providerId")
            return
        }
        guard let provider = findProvider?(providerId) else {
            print("[ListPanelManager] refreshPanelItems: provider '\(providerId)' not found")
            return
        }
        
        let freshItems = provider.provideFunctions()
        
        // Unwrap category wrapper if provider returns a single category with children
        let items: [FunctionNode]
        if freshItems.count == 1, freshItems[0].type == .category, let children = freshItems[0].children {
            items = children
        } else {
            items = freshItems
        }
        
        if let index = panelStack.firstIndex(where: { $0.level == level }) {
            if items.count != panelStack[index].items.count {
                panelStack[index].rowHeights = []
            }
            panelStack[index].items = items
        }
        
    }
    
    // MARK: - Estimated Panel Height (before measurement)
    
    /// Estimate panel height using baseRowHeight (for initial positioning before SwiftUI measures)
    private func estimatedPanelHeight(itemCount: Int, config: PanelConfig) -> CGFloat {
        let visibleCount = min(itemCount, config.maxVisibleItems)
        return PanelConfig.titleHeight + CGFloat(visibleCount) * config.baseRowHeight + ((PanelConfig.padding * 2) + PanelConfig.padding / 2)
    }
    
    // MARK: - Show Panel (from Ring)
    
    /// Show a panel as an extension of a ring item
    // MARK: - Show Panel (from Ring)

    /// Show a panel as an extension of a ring item
    func show(
        title: String,
        items: [FunctionNode],
        ringCenter: CGPoint,
        ringOuterRadius: CGFloat,
        angle: Double,
        providerId: String? = nil,
        contentIdentifier: String? = nil,
        screen: NSScreen? = nil,
        typingMode: TypingMode = .typeAhead,
        config: PanelConfig = .default,
        mainRing: (center: CGPoint, outerRadius: CGFloat, thickness: CGFloat)?
    ) {
        // Store ring context for cascading
        self.currentAngle = angle
        self.currentRingCenter = ringCenter
        self.currentRingOuterRadius = ringOuterRadius
        self.currentScreen = screen ?? NSScreen.main
        
        // Calculate position using config dimensions
        let position = calculatePanelPosition(
            fromRing: (center: ringCenter, outerRadius: ringOuterRadius, angle: angle),
            config: config,
            itemCount: items.count,
            mainRing: mainRing
        )
        
        // Use estimated height for boundary check (measurements come later)
        let panelHeight = estimatedPanelHeight(itemCount: items.count, config: config)

        // Constrain to screen boundaries (left, top, bottom only)
        let constrainedPosition = constrainToScreenBounds(position: position, panelWidth: config.panelWidth, panelHeight: panelHeight)
        
        print("[ListPanelManager] Showing panel at angle \(angle)°")
        print("   Items: \(items.count)")
        print("   Panel center: \(position)")
        print("   Config: width=\(config.panelWidth), maxVisible=\(config.maxVisibleItems), lineLimit=\(config.lineLimit)")
        if mainRing != nil {
            print("   Main ring geometry provided - accounting for nested rings")
        }
        
        // Clear any existing panels and push new one
        panelStack = [
            PanelState(
                title: title,
                items: items,
                position: constrainedPosition,
                level: 0,
                sourceNodeId: nil,
                sourceRowIndex: nil,
                spawnAngle: angle,
                contextActions: nil,
                config: config,
                providerId: providerId,
                contentIdentifier: contentIdentifier,
                expandedItemId: nil,
                isOverlapping: false,
                scrollOffset: 0,
                typingMode: typingMode,
                activeTypingMode: typingMode
            )
        ]
    }
    /// Show panel at a specific position (for standalone panels)
    func show(
        title: String,
        items: [FunctionNode],
        at position: CGPoint,
        screen: NSScreen? = nil,
        providerId: String? = nil,
        typingMode: TypingMode = .typeAhead,
        config: PanelConfig = .default
    ) {
        print("[ListPanelManager] Showing panel with \(items.count) items at \(position)")
        print("   Config: width=\(config.panelWidth), maxVisible=\(config.maxVisibleItems), lineLimit=\(config.lineLimit)")
        
        // Store screen reference
        self.currentScreen = screen ?? NSScreen.main
        
        // Use estimated height for constraint checking
        let panelHeight = estimatedPanelHeight(itemCount: items.count, config: config)
        
        // Constrain position to screen bounds
        let constrainedPosition = constrainToScreenBounds(
            position: position,
            panelWidth: config.panelWidth,
            panelHeight: panelHeight
        )
        
        panelStack = [
            PanelState(
                title: title,
                items: items,
                position: constrainedPosition,
                level: 0,
                sourceNodeId: nil,
                sourceRowIndex: nil,
                spawnAngle: nil,
                contextActions: nil,
                config: config,
                providerId: providerId,
                contentIdentifier: nil,
                expandedItemId: nil,
                isOverlapping: false,
                scrollOffset: 0,
                typingMode: typingMode,
                activeTypingMode: typingMode
            )
        ]
        
        // Set initial keyboard state
        activePanelLevel = 0
        keyboardSelectedRow[0] = 0
    }
    
    // MARK: - Mouse Movement Tracking

    func handleMouseMove(at point: CGPoint) {
        // Let InputCoordinator decide if this movement should switch to mouse mode
        if let coordinator = inputCoordinator {
            let didSwitch = coordinator.handleMouseMoved(to: point)
            if didSwitch {
                resetToMouseMode()
            } else if coordinator.inputMode == .keyboard {
                // Still in keyboard mode - don't process mouse hover
                return
            }
        } else {
            // Fallback: old behavior if no coordinator
            resetToMouseMode()
        }
        
        // Track hover state for each panel (check topmost first)
        var pointHandled = false
        for panel in panelStack.reversed() {
            let level = panel.level
            let panelBounds = currentBounds(for: panel)
            
            // Check if mouse is in this panel
            if !pointHandled && panelBounds.contains(point) {
                pointHandled = true
                
                // Check if in header area
                let distanceFromTop = panelBounds.maxY - point.y
                if distanceFromTop < PanelConfig.contentTopInset {
                    // In header - clear hover for this level
                    if hoveredRow[level] != nil {
                        hoveredRow[level] = nil
                    }
                    continue
                }
                
                // Calculate which row using variable heights
                let relativeY = panelBounds.maxY - point.y - PanelConfig.contentTopInset
                let scrollAdjustedY = relativeY + panel.scrollOffset
                let rowIndex = panel.rowIndex(atContentOffset: scrollAdjustedY)
                
                if let rowIndex = rowIndex, rowIndex >= 0 && rowIndex < panel.items.count {
                    // Valid row - update hover if changed
                    if hoveredRow[level] != rowIndex {
                        hoveredRow[level] = rowIndex
                        
                        // Suppress hover callback while scrolling
                        if !isPanelScrolling(level) {
                            let node = panel.items[rowIndex]
                            currentlyHoveredNodeId[level] = node.id
                            handleItemHover(node: node, level: level, rowIndex: rowIndex)
                        }
                    }
                } else {
                    // Outside rows (e.g., padding area)
                    if hoveredRow[level] != nil {
                        hoveredRow[level] = nil
                    }
                }
            } else {
                // Mouse not in this panel (or handled by panel on top) - clear hover
                if hoveredRow[level] != nil {
                    hoveredRow[level] = nil
                }
            }
        }
        
        // Check for arming on panels that might have pending children
        for index in panelStack.indices {
            let panel = panelStack[index]
            
            // Check if there's a pending panel for this level
            if let pending = pendingPanel,
               pending.fromLevel == panel.level,
               let sourceRowIndex = pending.sourceRowIndex {
                // Get the row bounds for the pending row
                if let sourceBounds = rowBounds(forPanel: panel, rowIndex: sourceRowIndex) {
                    if sourceBounds.contains(point) {
                        let progress = (point.x - sourceBounds.minX) / sourceBounds.width
                        
                        // Check for arming
                        if !panelStack[index].areChildrenArmed && progress < slideThreshold {
                            panelStack[index].areChildrenArmed = true
                            print("[Slide] Panel level \(panel.level) children now ARMED")
                            
                            // Spawn the pending panel
                            let p = pending
                            pendingPanel = nil
                            actuallyPushPanel(
                                title: p.title,
                                items: p.items,
                                fromPanelAtLevel: p.fromLevel,
                                sourceNodeId: p.sourceNodeId,
                                sourceRowIndex: p.sourceRowIndex,
                                providerId: p.providerId,
                                contentIdentifier: p.contentIdentifier,
                                contextActions: p.contextActions
                            )
                        }
                    }
                }
            }
            
            // Find child panel (level + 1) for overlap logic
            guard let childIndex = panelStack.firstIndex(where: { $0.level == panel.level + 1 }),
                  let sourceRowIndex = panelStack[childIndex].sourceRowIndex else {
                continue
            }
            
            // Get the source row bounds
            guard let sourceBounds = rowBounds(forPanel: panel, rowIndex: sourceRowIndex) else {
                continue
            }
            
            // Check if mouse is in the source row
            if sourceBounds.contains(point) {
                let progress = (point.x - sourceBounds.minX) / sourceBounds.width
                
                // Armed - normal threshold logic applies
                let shouldOverlap = progress > slideThreshold
                
                if panelStack[childIndex].isOverlapping != shouldOverlap {
                    panelStack[childIndex].isOverlapping = shouldOverlap
                    print("📋 [Slide] Panel level \(panelStack[childIndex].level) isOverlapping: \(shouldOverlap)")
                    
                    if shouldOverlap {
                        activePanelLevel = panelStack[childIndex].level
                        if hoveredRow[activePanelLevel] == nil {
                            hoveredRow[activePanelLevel] = 0
                        }
                    } else {
                        activePanelLevel = panel.level
                    }
                    print("[Slide] Active panel now level \(activePanelLevel)")
                }
            }
        }
    }
    
    // MARK: - Push Panel (Cascading)

    /// Push a new panel from an existing panel (cascade to the right)
    func pushPanel(
        title: String,
        items: [FunctionNode],
        fromPanelAtLevel level: Int,
        sourceNodeId: String,
        sourceRowIndex: Int? = nil,
        providerId: String? = nil,
        contentIdentifier: String? = nil,
        contextActions: [FunctionNode]? = nil
    ) {
        // Check if this is a stale async completion (user has moved to different row)
        if let currentHovered = currentlyHoveredNodeId[level], currentHovered != sourceNodeId {
            print("[ListPanelManager] Discarding stale panel '\(title)' - user moved to different row")
            return
        }
        
        // Find the source panel
        guard let sourcePanel = panelStack.first(where: { $0.level == level }) else {
            print("[ListPanelManager] Cannot find panel at level \(level)")
            return
        }
        
        // Check if parent is armed for child spawning
        guard let sourceIndex = panelStack.firstIndex(where: { $0.level == level }) else { return }
        
        if !panelStack[sourceIndex].areChildrenArmed {
            // Not armed yet - store as pending
            if let rowIndex = sourceRowIndex {
                pendingPanel = (title, items, level, sourceNodeId, rowIndex, providerId, contentIdentifier, contextActions)
                print("[ListPanelManager] Panel '\(title)' PENDING - waiting for arming")
            }
            return
        }
        
        // Armed - proceed with push
        actuallyPushPanel(
            title: title,
            items: items,
            fromPanelAtLevel: level,
            sourceNodeId: sourceNodeId,
            sourceRowIndex: sourceRowIndex,
            providerId: providerId,
            contentIdentifier: contentIdentifier,
            contextActions: contextActions
        )
    }

    /// Internal: actually push the panel (called after arming check passes)
    private func actuallyPushPanel(
        title: String,
        items: [FunctionNode],
        fromPanelAtLevel level: Int,
        sourceNodeId: String,
        sourceRowIndex: Int? = nil,
        providerId: String? = nil,
        contentIdentifier: String? = nil,
        contextActions: [FunctionNode]? = nil
    ) {
        // Find the source panel
        guard let sourcePanel = panelStack.first(where: { $0.level == level }) else {
            print("[ListPanelManager] Cannot find panel at level \(level)")
            return
        }
        
        // Pop any panels above this level first
        popToLevel(level)
        
        // Child panels inherit the source panel's config
        let config = sourcePanel.config
        
        // Calculate position: to the right of source panel
        let sourceBounds = sourcePanel.bounds
        let gap: CGFloat = 8
        
        let newPanelWidth = config.panelWidth
        let newPanelHeight = estimatedPanelHeight(itemCount: items.count, config: config)
        
        // New panel's left edge aligns with source panel's right edge + gap
        let newX = sourceBounds.maxX + gap + (newPanelWidth / 2)
        
        // Calculate Y position based on source row's VISUAL position
        let newY: CGFloat
        if let rowIndex = sourceRowIndex {
            // Calculate the visual Y of the source row using accumulated heights
            let rowTopOffset = sourcePanel.yOffsetForRow(rowIndex)
            let rowHeight = sourcePanel.heightForRow(rowIndex)
            
            // How far this row is scrolled: its logical top minus scroll offset
            let visualOffset = rowTopOffset - sourcePanel.scrollOffset
            let visibleContentHeight = sourcePanel.visibleContentHeight
            
            if visualOffset >= 0 && visualOffset < visibleContentHeight {
                print("[Push] Row \(rowIndex) visible at offset \(visualOffset)")
            } else {
                print("[Push] Row \(rowIndex) out of visible range")
            }
            
            // Clamp to visible area
            let clampedOffset = max(0, min(visualOffset, visibleContentHeight - rowHeight))
            
            // Calculate Y: row center in screen coordinates
            let rowCenterY = sourceBounds.maxY - PanelConfig.contentTopInset - clampedOffset - (rowHeight / 2)
            
            // Align new panel top with source row
            newY = rowCenterY - (newPanelHeight / 2) + (rowHeight / 2) + PanelConfig.contentTopInset - config.estimatedRowHeight
        } else {
            newY = sourceBounds.midY
        }
        
        let newPosition = CGPoint(x: newX, y: newY)
        // Constrain to screen boundaries (left, top, bottom only)
        let constrainedPosition = constrainToScreenBounds(position: newPosition, panelWidth: newPanelWidth, panelHeight: newPanelHeight)
        let inheritedTypingMode = sourcePanel.typingMode
        
        let newPanel = PanelState(
            title: title,
            items: items,
            position: constrainedPosition,
            level: level + 1,
            sourceNodeId: sourceNodeId,
            sourceRowIndex: sourceRowIndex,
            spawnAngle: nil,
            contextActions: contextActions,
            config: config,
            providerId: providerId,
            contentIdentifier: contentIdentifier,
            expandedItemId: nil,
            areChildrenArmed: false,
            isOverlapping: false,
            scrollOffset: 0,
            typingMode: inheritedTypingMode,
            activeTypingMode: inheritedTypingMode
        )
        
        panelStack.append(newPanel)
        
        print("[ListPanelManager] Pushed panel '\(title)' at level \(level + 1)")
    }

    func popToLevel(_ level: Int) {
        let before = panelStack.count
        
        // Cancel any in-flight dynamic load
        cancelDynamicLoad()
        
        // Clean up scroll state and hover tracking for panels being popped
        for panel in panelStack where panel.level > level {
            scrollDebounceTimers[panel.level]?.cancel()
            scrollDebounceTimers.removeValue(forKey: panel.level)
            scrollingPanels.remove(panel.level)
            currentlyHoveredNodeId.removeValue(forKey: panel.level)
            hoveredRow.removeValue(forKey: panel.level)
        }
        
        panelStack.removeAll { $0.level > level }
        let removed = before - panelStack.count
        if removed > 0 {
            print("[ListPanelManager] Popped \(removed) panel(s), now at level \(level)")
            
            // Reset activePanelLevel if we popped below it
            if activePanelLevel > level {
                activePanelLevel = level
                print("[ListPanelManager] Reset activePanelLevel to \(level)")
            }
        }
        
        // Clear pending if it was for a level we're popping
        if let pending = pendingPanel, pending.fromLevel > level {
            pendingPanel = nil
        }
    }
    
    // MARK: - Hide / Clear
    
    /// Hide all panels
    func hide() {
        guard isVisible else { return }
        print("[ListPanelManager] Hiding all panels")
        panelStack.removeAll()
        pendingPanel = nil
        
        // Cancel any in-flight dynamic load
        cancelDynamicLoad()
        
        // Reset keyboard navigation state
        activePanelLevel = 0
        keyboardSelectedRow.removeAll()
        currentlyHoveredNodeId.removeAll()
        
        resetTypeAheadSearch()
        
        // Clean up screen reference
        currentScreen = nil
        
        // Clean up scroll state
        for (_, timer) in scrollDebounceTimers {
            timer.cancel()
        }
        scrollDebounceTimers.removeAll()
        scrollingPanels.removeAll()
        
        // Clean up hover tracking
        currentlyHoveredNodeId.removeAll()
        
        keyboardSelectedRow.removeAll()
    }
    
    /// Alias for hide (clearer intent)
    func clear() {
        hide()
    }
    
    // MARK: - Position Calculation
    
    /// Get the current position for a panel (accounting for overlap state)
    func currentPosition(for panel: PanelState) -> CGPoint {
        guard panel.isOverlapping else {
            // Not overlapping, but ancestors might be shifted - need to adjust
            if panel.level > 0,
               let parentPanel = panelStack.first(where: { $0.level == panel.level - 1 }) {
                let parentOriginalX = parentPanel.position.x
                let parentCurrentPos = currentPosition(for: parentPanel)
                let parentShift = parentCurrentPos.x - parentOriginalX
                
                // Only shift if there's actually a difference
                if abs(parentShift) > 0.1 {
                    return CGPoint(x: panel.position.x + parentShift, y: panel.position.y)
                }
            }
            return panel.position
        }
        
        // Panel is overlapping - calculate position relative to parent's CURRENT position
        guard let parentPanel = panelStack.first(where: { $0.level == panel.level - 1 }) else {
            return panel.position
        }
        
        // Get parent's current position (recursive - handles chain of overlaps)
        let parentCurrentPos = currentPosition(for: parentPanel)
        
        // Calculate parent's current left edge using parent's config width
        let parentCurrentLeftEdge = parentCurrentPos.x - (parentPanel.config.panelWidth / 2)
        
        // Overlapping X: parent's current left edge + peekWidth + half of THIS panel's width
        let overlappingX = parentCurrentLeftEdge + peekWidth + (panel.config.panelWidth / 2)
        
        return CGPoint(x: overlappingX, y: panel.position.y)
    }
    
    // MARK: - Bounds Calculation

    func currentBounds(for panel: PanelState) -> NSRect {
        let currentPos = currentPosition(for: panel)
        var centerY = currentPos.y
        
        // Adjust for top-anchored search resizing
        if panel.isSearchActive, let anchorHeight = panel.searchAnchorHeight {
            centerY = currentPos.y + ((anchorHeight - panel.panelHeight) / 2)
        }
        
        return NSRect(
            x: currentPos.x - panel.config.panelWidth / 2,
            y: centerY - panel.panelHeight / 2,
            width: panel.config.panelWidth,
            height: panel.panelHeight
        )
    }

    /// Calculate the screen bounds of a specific row in a panel
    /// Uses accumulated row heights for accurate variable-height positioning
    func rowBounds(forPanel panel: PanelState, rowIndex: Int) -> NSRect? {
        guard rowIndex >= 0 && rowIndex < panel.items.count else { return nil }
        
        let panelBounds = currentBounds(for: panel)
        let rowHeight = panel.heightForRow(rowIndex)
        let rowTopOffset = panel.yOffsetForRow(rowIndex)
        
        // Calculate the logical position of this row, then adjust for scroll
        let logicalRowTop = panelBounds.maxY - PanelConfig.contentTopInset - rowTopOffset
        
        // Scroll offset: positive when scrolled down (content moved up)
        let visibleRowTop = logicalRowTop + panel.scrollOffset
        let visibleRowBottom = visibleRowTop - rowHeight
        
        // Check if row is actually visible in the panel's scroll area
        let scrollAreaTop = panelBounds.maxY - PanelConfig.contentTopInset
        let scrollAreaBottom = panelBounds.minY + PanelConfig.contentBottomInset
        
        // Row must be at least partially visible
        if visibleRowTop < scrollAreaBottom || visibleRowBottom > scrollAreaTop {
            return nil  // Row is scrolled out of view
        }
        
        // Row X spans the panel width (with some padding)
        let horizontalPadding: CGFloat = 4
        let rowLeft = panelBounds.minX + horizontalPadding
        let rowRight = panelBounds.maxX - horizontalPadding
        
        return NSRect(
            x: rowLeft,
            y: visibleRowBottom,
            width: rowRight - rowLeft,
            height: rowHeight
        )
    }
    
    // MARK: - Panel Position from Ring
    
    /// Calculate panel position when spawning from a ring node
    func calculatePanelPosition(
        fromRing ring: (center: CGPoint, outerRadius: CGFloat, angle: Double),
        config: PanelConfig,
        itemCount: Int,
        mainRing: (center: CGPoint, outerRadius: CGFloat, thickness: CGFloat)? = nil
    ) -> CGPoint {
        
        
        let angle = ring.angle
        let angleInRadians = (angle - 90) * (.pi / 180)
        
        print("🎯 [PanelPosition FULL Debug]")
        print("   Angle: \(angle)°")
        print("   Received ring.outerRadius: \(ring.outerRadius)")
        if let mainRing = mainRing {
            print("   Received mainRing.outerRadius: \(mainRing.outerRadius)")
            print("   Received mainRing.thickness: \(mainRing.thickness)")
        }
        
        // Gap between ring edge and panel
        let gapFromRing: CGFloat = 8

        // Icons are positioned differently for Ring 0 vs child rings
        let iconRadius: CGFloat = 32
        let actualRingEdge: CGFloat

        if mainRing == nil {
            // Ring 0: Icons are at the center of the thickness, subtract the difference
            // Actual edge = outerRadius - (thickness/2 - iconSize/2) = outerRadius - 24
            actualRingEdge = ring.outerRadius
        } else {
            // Ring 1+: Use current formula (works correctly)
            actualRingEdge = ring.outerRadius + iconRadius
        }

        let baseRadius = actualRingEdge

        if let mainRing = mainRing {
            print("   [PanelPosition] Nested ring detected - main ring outerRadius: \(mainRing.outerRadius)")
            print("   [PanelPosition] Using active ring actual edge: \(baseRadius)")
        } else {
            print("   [PanelPosition] Single ring - using actual edge: \(baseRadius)")
        }
        
        // Calculate anchor point at actual ring edge
        let anchorRadius = baseRadius + gapFromRing
        let anchorX = ring.center.x + anchorRadius * cos(angleInRadians)
        let anchorY = ring.center.y - anchorRadius * sin(angleInRadians)
        
        print("   Anchor radius: \(anchorRadius)")
        print("   Anchor point: (\(anchorX), \(anchorY))")
        
        // Estimate panel dimensions
        let itemCountClamped = min(itemCount, config.maxVisibleItems)
        let panelHeight = CGFloat(itemCountClamped) * config.baseRowHeight + ((PanelConfig.padding * 2) + PanelConfig.padding / 2)
        let panelWidth = config.panelWidth
        
        // Panel center: anchor point + half-dimensions in angle direction
        let panelX = anchorX + (panelWidth / 2) * cos(angleInRadians)
        let panelY = anchorY + (panelHeight / 2) * -sin(angleInRadians)
        
        print("   Panel width: \(panelWidth), height: \(panelHeight)")
        print("   Final panel position: (\(panelX), \(panelY))")
        
        return CGPoint(x: panelX, y: panelY)
    }
    
    // MARK: - Screen Boundary Constraints

    /// Constrain panel position to screen boundaries (left, top, bottom only - NOT right)
    func constrainToScreenBounds(position: CGPoint, panelWidth: CGFloat, panelHeight: CGFloat) -> CGPoint {
        // Use the screen where panels are being displayed (set in show())
        let screen = currentScreen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else {
            return position
        }
        
        var constrainedX = position.x
        var constrainedY = position.y
        
        let halfWidth = panelWidth / 2
        let halfHeight = panelHeight / 2
        
        // Left boundary: panel's left edge can't go past screen's left edge
        let minX = visibleFrame.minX + halfWidth
        if constrainedX < minX {
            constrainedX = minX
        }
        
        // Bottom boundary: panel's bottom edge can't go past screen's bottom edge
        let minY = visibleFrame.minY + halfHeight
        if constrainedY < minY {
            constrainedY = minY
        }
        
        // Top boundary: panel's top edge can't go past screen's top edge
        let maxY = visibleFrame.maxY - halfHeight
        if constrainedY > maxY {
            constrainedY = maxY
        }
        
        // RIGHT boundary: intentionally NOT constrained
        
        return CGPoint(x: constrainedX, y: constrainedY)
    }
}
