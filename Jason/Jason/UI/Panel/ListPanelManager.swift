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

// MARK: - Panel State

struct PanelState: Identifiable {
    let id: UUID = UUID()
    let title: String
    var items: [FunctionNode]
    let position: CGPoint
    let level: Int                    // 0 = from ring, 1+ = from panel
    let sourceNodeId: String?         // Which node spawned this panel
    let sourceRowIndex: Int?
    let spawnAngle: Double?
    let contextActions: [FunctionNode]?
    
    
    //Identity tracking for updates
    let providerId: String?
    let contentIdentifier: String?    // Folder path for folder content
    
    var expandedItemId: String?       // Which row has context actions showing
    var areChildrenArmed: Bool = false
    var isOverlapping: Bool = false
    var scrollOffset: CGFloat = 0     // Track scroll position for accurate row positioning
    
   
    
    // Panel dimensions (constants for now, could be configurable)
    static let panelWidth: CGFloat = 260
    static let rowHeight: CGFloat = 32
    static let titleHeight: CGFloat = 40
    static let maxVisibleItems: Int = 10
    static let padding: CGFloat = 8
    static let cascadeSlideDistance: CGFloat = 30

    
    /// Calculate panel height based on item count
    var panelHeight: CGFloat {
        let itemCount = min(items.count, Self.maxVisibleItems)
        return Self.titleHeight + CGFloat(itemCount) * Self.rowHeight + Self.padding
    }
    
    /// Panel bounds in screen coordinates
    var bounds: NSRect {
        NSRect(
            x: position.x - Self.panelWidth / 2,
            y: position.y - panelHeight / 2,
            width: Self.panelWidth,
            height: panelHeight
        )
    }
}

// MARK: - List Panel Manager

class ListPanelManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published var panelStack: [PanelState] = []
    @Published var hoveredRow: [Int: Int] = [:]
    
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
    
    /// Expanded item ID for first panel (for backward compatibility with binding)
    var expandedItemId: String? {
        get { panelStack.first?.expandedItemId }
        set {
            guard !panelStack.isEmpty else { return }
            panelStack[0].expandedItemId = newValue
        }
    }
    
    /// Current ring context (stored for cascading position calculations)
    private(set) var currentRingCenter: CGPoint = .zero
    private(set) var currentRingOuterRadius: CGFloat = 0
    private(set) var currentAngle: Double = 0
    
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
    private var currentlyHoveredNodeId: [Int: String] = [:]
    
    // MARK: - Callbacks (wired by CircularUIManager)
    
    var onItemLeftClick: ((FunctionNode, NSEvent.ModifierFlags) -> Void)?
    var onItemRightClick: ((FunctionNode, NSEvent.ModifierFlags) -> Void)?
    var onContextAction: ((FunctionNode, NSEvent.ModifierFlags) -> Void)?
    var onItemHover: ((FunctionNode?, Int, Int?) -> Void)?
    
    /// Callback to reload content for a panel
    var onReloadContent: ((String, String?) async -> [FunctionNode])?
    
    
    // MARK: - Initialization

    init() {
        // Register for provider update notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProviderUpdate(_:)),
            name: .providerContentUpdated,
            object: nil
        )
        print("📋 [ListPanelManager] Initialized - registered for provider updates")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        print("📋 [ListPanelManager] Deallocated - removed observers")
    }
    
    // MARK: - Provider Update Handler

    @objc private func handleProviderUpdate(_ notification: Notification) {
        guard let updateInfo = ProviderUpdateInfo.from(notification) else {
            print("❌ [ListPanelManager] Invalid provider update notification")
            return
        }
        
        print("📢 [ListPanelManager] Received update for provider: \(updateInfo.providerId)")
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
            print("   ⏭️ No matching panel found - ignoring")
            return
        }
        
        let matchingPanel = panelStack[matchingIndex]
        print("   ✅ Found matching panel at level \(matchingPanel.level): '\(matchingPanel.title)'")
        
        // Close any child panels
        if matchingIndex < panelStack.count - 1 {
            let childCount = panelStack.count - matchingIndex - 1
            print("   🗑️ Closing \(childCount) child panel(s)")
            popToLevel(matchingPanel.level)
        }
        
        // Reload content
        guard let onReloadContent = onReloadContent,
              let providerId = matchingPanel.providerId else {
            print("   ❌ No reload callback or providerId - cannot refresh")
            return
        }
        
        let contentIdentifier = matchingPanel.contentIdentifier
        
        Task {
            let freshItems = await onReloadContent(providerId, contentIdentifier)
            
            await MainActor.run {
                // Find the panel again (stack may have changed)
                guard let currentIndex = self.panelStack.firstIndex(where: { $0.id == matchingPanel.id }) else {
                    print("   ⚠️ Panel no longer exists - skipping update")
                    return
                }
                
                print("   🔄 Updating panel with \(freshItems.count) items (was \(self.panelStack[currentIndex].items.count))")
                self.panelStack[currentIndex].items = freshItems
            }
        }
    }
    
    // MARK: - Scroll State Tracking
    
    /// Panels currently being scrolled (suppress hover during scroll)
    private var scrollingPanels: Set<Int> = []
    
    /// Debounce timers per panel level
    private var scrollDebounceTimers: [Int: DispatchWorkItem] = [:]
    
    /// How long to wait after scroll stops before re-enabling hover (seconds)
    private let scrollDebounceDelay: Double = 0.1
    
    /// Check if a panel is currently scrolling
    func isPanelScrolling(_ level: Int) -> Bool {
        scrollingPanels.contains(level)
    }
    
    /// Handle item hover with scroll-suppression logic
    func handleItemHover(node: FunctionNode?, level: Int, rowIndex: Int?) {
        // Suppress hover events while panel is scrolling
        if isPanelScrolling(level) {
            print("📜 [Hover] Suppressed - panel \(level) is scrolling")
            return
        }
        
        // Track which node is currently hovered at this level
        if let node = node {
            currentlyHoveredNodeId[level] = node.id
        } else {
            currentlyHoveredNodeId.removeValue(forKey: level)
        }
        
        // Forward to the actual handler
        onItemHover?(node, level, rowIndex)
    }
    
    /// Handle scroll state changes from a panel
    func handleScrollStateChanged(isScrolling: Bool, forLevel level: Int) {
        if isScrolling {
            // Scrolling started - close any child panels and clear hover tracking
            scrollingPanels.insert(level)
            currentlyHoveredNodeId.removeValue(forKey: level)  // Clear stale hover
            popToLevel(level)
            print("📜 [Scroll] Level \(level) scrolling - closed child panels")
        } else {
            // Scrolling stopped - re-enable hover
            scrollingPanels.remove(level)
            print("📜 [Scroll] Level \(level) scroll stopped - hover re-enabled")
        }
    }
    
    /// Handle hover over panel header - clears child state
    func handleHeaderHover(level: Int) {
        // Clear hover tracking for this level
        currentlyHoveredNodeId.removeValue(forKey: level)
        
        // Clear pending panel if it was for this level
        if let pending = pendingPanel, pending.fromLevel == level {
            pendingPanel = nil
            print("📋 [Header] Cleared pending panel for level \(level)")
        }
        
        // Reset arming for this panel
        if let index = panelStack.firstIndex(where: { $0.level == level }) {
            if panelStack[index].areChildrenArmed {
                panelStack[index].areChildrenArmed = false
                print("📋 [Header] Reset arming for level \(level)")
            }
        }
        
        // Close any child panels
        let childCount = panelStack.filter { $0.level > level }.count
        if childCount > 0 {
            popToLevel(level)
            print("📋 [Header] Closed \(childCount) child panel(s)")
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
    
    // MARK: - Show Panel (from Ring)
    
    /// Show a panel as an extension of a ring item
    func show(
        title: String,
        items: [FunctionNode],
        ringCenter: CGPoint,
        ringOuterRadius: CGFloat,
        angle: Double,
        panelWidth: CGFloat = PanelState.panelWidth,
        providerId: String? = nil,
        contentIdentifier: String? = nil
    ) {
        // Store ring context for cascading
        self.currentAngle = angle
        self.currentRingCenter = ringCenter
        self.currentRingOuterRadius = ringOuterRadius
        
        // Calculate position
        let position = calculatePanelPosition(
            fromRing: (center: ringCenter, outerRadius: ringOuterRadius, angle: angle),
            panelWidth: panelWidth,
            itemCount: items.count
        )
        
        // Calculate panel height for boundary check
        let itemCountClamped = min(items.count, PanelState.maxVisibleItems)
        let panelHeight = PanelState.titleHeight + CGFloat(itemCountClamped) * PanelState.rowHeight + PanelState.padding

        // Constrain to screen boundaries (left, top, bottom only)
        let constrainedPosition = constrainToScreenBounds(position: position, panelWidth: panelWidth, panelHeight: panelHeight)
        
        print("📋 [ListPanelManager] Showing panel at angle \(angle)°")
        print("   Items: \(items.count)")
        print("   Panel center: \(position)")
        
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
                providerId: providerId,
                contentIdentifier: contentIdentifier,
                expandedItemId: nil,
                isOverlapping: false,
                scrollOffset: 0
            )
        ]
    }
    
    /// Show panel at a specific position (for testing)
    func show(title: String, items: [FunctionNode], at position: CGPoint) {
        print("📋 [ListPanelManager] Showing panel with \(items.count) items")
        panelStack = [
            PanelState(
                title: title,
                items: items,
                position: position,
                level: 0,
                sourceNodeId: nil,
                sourceRowIndex: nil,
                spawnAngle: nil,
                contextActions: nil,
                providerId: nil,
                contentIdentifier: nil,
                expandedItemId: nil,
                isOverlapping: false,
                scrollOffset: 0
            )
        ]
    }
    
    // MARK: - Bounds Calculation

    /// Get the current bounds for a panel (accounting for overlap state)
    func currentBounds(for panel: PanelState) -> NSRect {
        let currentPos = currentPosition(for: panel)
        return NSRect(
            x: currentPos.x - PanelState.panelWidth / 2,
            y: currentPos.y - panel.panelHeight / 2,
            width: PanelState.panelWidth,
            height: panel.panelHeight
        )
    }

    /// Calculate the screen bounds of a specific row in a panel
    /// Accounts for scroll offset to return the VISIBLE position of the row
    func rowBounds(forPanel panel: PanelState, rowIndex: Int) -> NSRect? {
        guard rowIndex >= 0 && rowIndex < panel.items.count else { return nil }
        
        let panelBounds = currentBounds(for: panel)
        
        // Calculate the logical position of this row (as if not scrolled)
        // Then adjust for scroll offset
        let logicalRowTop = panelBounds.maxY - (PanelState.padding / 2) - PanelState.titleHeight - (CGFloat(rowIndex) * PanelState.rowHeight)
        
        // Scroll offset is positive when scrolled down (content moved up)
        // So visible row position = logical position + scrollOffset
        let visibleRowTop = logicalRowTop + panel.scrollOffset
        let visibleRowBottom = visibleRowTop - PanelState.rowHeight
        
        // Check if row is actually visible in the panel's scroll area
        let scrollAreaTop = panelBounds.maxY - (PanelState.padding / 2) - PanelState.titleHeight
        let scrollAreaBottom = panelBounds.minY + (PanelState.padding / 2)
        
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
            height: PanelState.rowHeight
        )
    }
    
    // MARK: - Mouse Movement Tracking

    func handleMouseMove(at point: CGPoint) {
        // DEBUG
        for panel in panelStack {
            let bounds = currentBounds(for: panel)
            print("🔍 [Hover] Panel \(panel.level) isOverlapping:\(panel.isOverlapping) bounds: x=\(Int(bounds.minX))-\(Int(bounds.maxX)) | mouse.x=\(Int(point.x))")
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
                if distanceFromTop < PanelState.titleHeight + (PanelState.padding / 2) {
                    // In header - clear hover for this level
                    if hoveredRow[level] != nil {
                        hoveredRow[level] = nil
                    }
                    continue
                }
                
                // Calculate which row (if any)
                let relativeY = panelBounds.maxY - point.y - (PanelState.padding / 2) - PanelState.titleHeight
                let scrollAdjustedY = relativeY + panel.scrollOffset
                let rowIndex = Int(scrollAdjustedY / PanelState.rowHeight)
                
                if rowIndex >= 0 && rowIndex < panel.items.count {
                    // Valid row - update hover if changed
                    if hoveredRow[level] != rowIndex {
                        hoveredRow[level] = rowIndex
                        
                        // Suppress hover callback while scrolling
                        if !isPanelScrolling(level) {
                            let node = panel.items[rowIndex]
                            currentlyHoveredNodeId[level] = node.id
                            onItemHover?(node, level, rowIndex)
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
                            print("📋 [Slide] Panel level \(panel.level) children now ARMED")
                            
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
                
                // Update if changed
                if panelStack[childIndex].isOverlapping != shouldOverlap {
                    panelStack[childIndex].isOverlapping = shouldOverlap
                    print("📋 [Slide] Panel level \(panelStack[childIndex].level) isOverlapping: \(shouldOverlap)")
                }
            }
        }
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
        
        // Calculate parent's current left edge
        let parentCurrentLeftEdge = parentCurrentPos.x - (PanelState.panelWidth / 2)
        
        // Overlapping X: parent's current left edge + peekWidth + half panel width
        let overlappingX = parentCurrentLeftEdge + peekWidth + (PanelState.panelWidth / 2)
        
        return CGPoint(x: overlappingX, y: panel.position.y)
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
            print("📋 [ListPanelManager] Discarding stale panel '\(title)' - user moved to different row")
            return
        }
        
        // Find the source panel
        guard let sourcePanel = panelStack.first(where: { $0.level == level }) else {
            print("❌ [ListPanelManager] Cannot find panel at level \(level)")
            return
        }
        
        // Check if parent is armed for child spawning
        guard let sourceIndex = panelStack.firstIndex(where: { $0.level == level }) else { return }
        
        if !panelStack[sourceIndex].areChildrenArmed {
            // Not armed yet - store as pending
            if let rowIndex = sourceRowIndex {
                pendingPanel = (title, items, level, sourceNodeId, rowIndex, providerId, contentIdentifier, contextActions)
                print("📋 [ListPanelManager] Panel '\(title)' PENDING - waiting for arming")
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
            print("❌ [ListPanelManager] Cannot find panel at level \(level)")
            return
        }
        
        // Pop any panels above this level first
        popToLevel(level)
        
        // Calculate position: to the right of source panel
        let sourceBounds = sourcePanel.bounds
        let gap: CGFloat = 8
        
        let newPanelWidth = PanelState.panelWidth
        let itemCount = min(items.count, PanelState.maxVisibleItems)
        let newPanelHeight = CGFloat(itemCount) * PanelState.rowHeight + PanelState.padding + PanelState.titleHeight
        
        // New panel's left edge aligns with source panel's right edge + gap
        let newX = sourceBounds.maxX + gap + (newPanelWidth / 2)
        
        // Calculate Y position based on source row's VISUAL position
        // Use scroll offset to determine where the row actually appears on screen
        let newY: CGFloat
        if let rowIndex = sourceRowIndex {
            // Calculate visual row index from scroll offset
            let scrolledRows = Int(sourcePanel.scrollOffset / PanelState.rowHeight)
            let visualRowIndex = rowIndex - scrolledRows
            
            if visualRowIndex >= 0 && visualRowIndex < PanelState.maxVisibleItems {
                print("📜 [Push] Row \(rowIndex) → visual row \(visualRowIndex) (scrolled \(scrolledRows))")
            } else {
                print("📜 [Push] Row \(rowIndex) out of visible range (scrolled \(scrolledRows))")
            }
            
            // Clamp visual row to visible range
            let clampedVisualRow = max(0, min(visualRowIndex, PanelState.maxVisibleItems - 1))
            
            // Calculate Y using visual row index
            let rowCenterY = sourceBounds.maxY - (PanelState.padding / 2) - PanelState.titleHeight - (CGFloat(clampedVisualRow) * PanelState.rowHeight) - (PanelState.rowHeight / 2)
            
            // Align new panel so its first row aligns with the source row
            newY = rowCenterY - (newPanelHeight / 2) + (PanelState.rowHeight / 2) + (PanelState.padding / 2) + PanelState.titleHeight - PanelState.rowHeight
        } else {
            newY = sourceBounds.midY
        }
        
        let newPosition = CGPoint(x: newX, y: newY)
        // Constrain to screen boundaries (left, top, bottom only)
        let constrainedPosition = constrainToScreenBounds(position: newPosition, panelWidth: newPanelWidth, panelHeight: newPanelHeight)
        
        let newPanel = PanelState(
            title: title,
            items: items,
            position: constrainedPosition,
            level: level + 1,
            sourceNodeId: sourceNodeId,
            sourceRowIndex: sourceRowIndex,
            spawnAngle: nil,
            contextActions: contextActions,
            providerId: providerId,
            contentIdentifier: contentIdentifier,
            expandedItemId: nil,
            areChildrenArmed: false,
            isOverlapping: false,
            scrollOffset: 0
        )
        
        panelStack.append(newPanel)
        
        print("📋 [ListPanelManager] Pushed panel '\(title)' at level \(level + 1)")
        print("   Items: \(items.count)")
        print("   Position: \(newPosition)")
        print("   Source row: \(sourceRowIndex ?? -1)")
    }

    func popToLevel(_ level: Int) {
        let before = panelStack.count
        
        // Clean up scroll state and hover tracking for panels being popped
        for panel in panelStack where panel.level > level {
            scrollDebounceTimers[panel.level]?.cancel()
            scrollDebounceTimers.removeValue(forKey: panel.level)
            scrollingPanels.remove(panel.level)
            currentlyHoveredNodeId.removeValue(forKey: panel.level)
        }
        
        panelStack.removeAll { $0.level > level }
        let removed = before - panelStack.count
        if removed > 0 {
            print("📋 [ListPanelManager] Popped \(removed) panel(s), now at level \(level)")
        }
        
        // Clear pending if it was for a level we're popping
        if let pending = pendingPanel, pending.fromLevel > level {
            pendingPanel = nil
        }
    }
    
    // MARK: - Position Calculation
    
    private func calculatePanelPosition(
        fromRing ring: (center: CGPoint, outerRadius: CGFloat, angle: Double),
        panelWidth: CGFloat,
        itemCount: Int
    ) -> CGPoint {
        let angle = ring.angle
        let angleInRadians = (angle - 90) * (.pi / 180)
        
        // Gap between ring edge and panel
        let gapFromRing: CGFloat = 8
        
        // Calculate anchor point at ring edge
        let anchorRadius = ring.outerRadius + gapFromRing
        let anchorX = ring.center.x + anchorRadius * cos(angleInRadians)
        let anchorY = ring.center.y - anchorRadius * sin(angleInRadians)
        
        // Calculate panel height
        let itemCountClamped = min(itemCount, PanelState.maxVisibleItems)
        let panelHeight = CGFloat(itemCountClamped) * PanelState.rowHeight + PanelState.padding
        
        // Base offset: half-dimensions in angle direction
        let offsetX = (panelWidth / 2) * cos(angleInRadians)
        let offsetY = (panelHeight / 2) * -sin(angleInRadians)
        
        // Diagonal factor: peaks at 45°, 135°, 225°, 315° (0 at cardinal angles)
        let angleWithinQuadrant = angle.truncatingRemainder(dividingBy: 90)
        let diagonalFactor = sin(angleWithinQuadrant * 2 * .pi / 180)
        
        // Extra offset for diagonal angles (18% extra at peak)
        let extraFactor: CGFloat = 0.18 * CGFloat(diagonalFactor)
        let extraOffsetX = extraFactor * panelWidth * cos(angleInRadians)
        let extraOffsetY = extraFactor * panelHeight * -sin(angleInRadians)
        
        let panelX = anchorX + offsetX + extraOffsetX
        let panelY = anchorY + offsetY + extraOffsetY
        
        return CGPoint(x: panelX, y: panelY)
    }
    
    // MARK: - Hide / Clear
    
    /// Hide all panels
    func hide() {
        guard isVisible else { return }
        print("📋 [ListPanelManager] Hiding all panels")
        panelStack.removeAll()
        pendingPanel = nil
        
        // Clean up scroll state
        for (_, timer) in scrollDebounceTimers {
            timer.cancel()
        }
        scrollDebounceTimers.removeAll()
        scrollingPanels.removeAll()
        
        // Clean up hover tracking
        currentlyHoveredNodeId.removeAll()
    }
    
    /// Alias for hide (clearer intent)
    func clear() {
        hide()
    }
    
    // MARK: - Hit Testing
    
    /// Check if a point is inside ANY panel
    func contains(point: CGPoint) -> Bool {
        panelStack.contains { currentBounds(for: $0).contains(point) }
    }
    
    /// Check if point is in the panel zone (any panel OR gaps between)
    func isInPanelZone(point: CGPoint) -> Bool {
        guard !panelStack.isEmpty else { return false }
        
        var minX = CGFloat.infinity
        var minY = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var maxY = -CGFloat.infinity
        
        for panel in panelStack {
            let bounds = currentBounds(for: panel)  // ← Changed from panel.bounds
            minX = min(minX, bounds.minX)
            minY = min(minY, bounds.minY)
            maxX = max(maxX, bounds.maxX)
            maxY = max(maxY, bounds.maxY)
        }
        
        let combinedBounds = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return combinedBounds.contains(point)
    }
    
    /// Find which panel level contains the point (nil if none)
    func panelLevel(at point: CGPoint) -> Int? {
        // Check from rightmost to leftmost (higher levels first)
        for panel in panelStack.reversed() {
            if currentBounds(for: panel).contains(point) {
                return panel.level
            }
        }
        return nil
    }
    
    /// Get the panel at a specific level
    func panel(at level: Int) -> PanelState? {
        panelStack.first { $0.level == level }
    }
    
    /// Left edge of leftmost panel (for ring boundary detection)
    var leftmostPanelEdge: CGFloat? {
        panelStack.first.map { $0.bounds.minX }
    }
    
    // MARK: - Right Click Handling
    
    /// Handle right-click at position, returns true if handled
    func handleRightClick(at point: CGPoint) -> Bool {
        // Find which panel was clicked
        guard let level = panelLevel(at: point),
              let panelIndex = panelStack.firstIndex(where: { $0.level == level }) else {
            return false
        }
        
        let panel = panelStack[panelIndex]
        let bounds = currentBounds(for: panel)
        
        // Calculate which row was clicked (accounting for title and scroll)
        let relativeY = bounds.maxY - point.y - (PanelState.padding / 2) - PanelState.titleHeight
        
        // Adjust for scroll: relativeY is in visual space, need to convert to logical row index
        let scrollAdjustedY = relativeY + panel.scrollOffset
        let rowIndex = Int(scrollAdjustedY / PanelState.rowHeight)
        
        guard rowIndex >= 0 && rowIndex < panel.items.count else {
            print("📋 [Panel] Right-click outside rows")
            panelStack[panelIndex].expandedItemId = nil
            return true
        }
        
        let clickedItem = panel.items[rowIndex]
        print("📋 [Panel \(level)] Right-click on row \(rowIndex): '\(clickedItem.name)'")
        
        // Toggle expanded state
        if panelStack[panelIndex].expandedItemId == clickedItem.id {
            panelStack[panelIndex].expandedItemId = nil
        } else {
            panelStack[panelIndex].expandedItemId = clickedItem.id
        }
        
        return true
    }
    
    /// Handle left-click at position, returns the clicked item and panel level if inside a panel
    func handleLeftClick(at point: CGPoint) -> (node: FunctionNode, level: Int)? {
        // Find which panel was clicked
        guard let level = panelLevel(at: point),
              let panelIndex = panelStack.firstIndex(where: { $0.level == level }) else {
            return nil
        }
        
        let panel = panelStack[panelIndex]
        let bounds = currentBounds(for: panel)
        
        // Check if click is in title bar area
        let distanceFromTop = bounds.maxY - point.y
        if distanceFromTop < PanelState.titleHeight + (PanelState.padding / 2) {
            return nil  // Let SwiftUI handle title bar clicks
        }
        
        // Calculate which row was clicked (accounting for title and scroll)
        let relativeY = bounds.maxY - point.y - (PanelState.padding / 2) - PanelState.titleHeight
        
        // Adjust for scroll: relativeY is in visual space, need to convert to logical row index
        let scrollAdjustedY = relativeY + panel.scrollOffset
        let rowIndex = Int(scrollAdjustedY / PanelState.rowHeight)
        
        guard rowIndex >= 0 && rowIndex < panel.items.count else {
            return nil
        }
        
        let clickedItem = panel.items[rowIndex]
        
        // NEW: If this row is expanded (showing context actions), let SwiftUI handle the click
        if panel.expandedItemId == clickedItem.id {
            print("📋 [Panel] Click on expanded row - letting SwiftUI handle context actions")
            return nil
        }
        
        // Collapse any expanded row in this panel
        panelStack[panelIndex].expandedItemId = nil
        
        return (clickedItem, level)
    }
    
    /// Handle drag start at position, returns the node and its DragProvider if draggable
    func handleDragStart(at point: CGPoint) -> (node: FunctionNode, dragProvider: DragProvider, level: Int)? {
        // Find which panel was clicked
        guard let level = panelLevel(at: point),
              let panelIndex = panelStack.firstIndex(where: { $0.level == level }) else {
            return nil
        }
        
        let panel = panelStack[panelIndex]
        let bounds = currentBounds(for: panel)
        
        // Calculate which row was clicked (accounting for title and scroll)
        let relativeY = bounds.maxY - point.y - (PanelState.padding / 2) - PanelState.titleHeight
        
        // Adjust for scroll: relativeY is in visual space, need to convert to logical row index
        let scrollAdjustedY = relativeY + panel.scrollOffset
        let rowIndex = Int(scrollAdjustedY / PanelState.rowHeight)
        
        guard rowIndex >= 0 && rowIndex < panel.items.count else {
            return nil
        }
        
        let node = panel.items[rowIndex]
        
        // Check if node is draggable (resolve with current modifiers)
        let behavior = node.onLeftClick.resolve(with: NSEvent.modifierFlags)
        
        if case .drag(let provider) = behavior {
            return (node, provider, level)
        }
        
        return nil
    }
    
    // MARK: - Test Helpers
    
    /// Show panel with sample test data
    func showTestPanel(at position: CGPoint = NSEvent.mouseLocation) {
        let testItems: [FunctionNode] = [
            createTestFolderWithChildren(name: "Documents"),
            createTestFolderWithChildren(name: "Screenshots"),
            createTestFileNode(name: "report.pdf", utType: .pdf),
            createTestFileNode(name: "notes.txt", utType: .plainText),
            createTestFolderWithChildren(name: "Projects"),
        ]
        
        show(title: "Test Panel", items: testItems, at: position)
    }
    
    private func createTestFolderWithChildren(name: String, depth: Int = 0) -> FunctionNode {
        let icon = NSWorkspace.shared.icon(for: .folder)
        
        // Create nested children (limit depth to prevent infinite recursion)
        let children: [FunctionNode]
        if depth < 3 {
            children = [
                createTestFolderWithChildren(name: "Subfolder A", depth: depth + 1),
                createTestFolderWithChildren(name: "Subfolder B", depth: depth + 1),
                createTestFileNode(name: "file1.txt", utType: .plainText),
                createTestFileNode(name: "file2.pdf", utType: .pdf),
            ]
        } else {
            // At max depth, only files
            children = [
                createTestFileNode(name: "file1.txt", utType: .plainText),
                createTestFileNode(name: "file2.pdf", utType: .pdf),
            ]
        }
        
        return FunctionNode(
            id: UUID().uuidString,
            name: name,
            type: .folder,
            icon: icon,
            children: children,
            childDisplayMode: .panel,
            onLeftClick: ModifierAwareInteraction(base: .navigateInto)
        )
    }

    private func createTestFileNode(name: String, utType: UTType) -> FunctionNode {
        let icon = NSWorkspace.shared.icon(for: utType)
        
        return FunctionNode(
            id: UUID().uuidString,
            name: name,
            type: .file,
            icon: icon,
            onLeftClick: ModifierAwareInteraction(base: .execute {
                print("🧪 [Test] Would open: \(name)")
            })
        )
    }
    
    // MARK: - Screen Boundary Constraints

    /// Constrain panel position to screen boundaries (left, top, bottom only - NOT right)
    private func constrainToScreenBounds(position: CGPoint, panelWidth: CGFloat, panelHeight: CGFloat) -> CGPoint {
        // Get current screen (use main screen as fallback)
        let screen = NSScreen.main ?? NSScreen.screens.first
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
        // Panels flow left-to-right; if they go off-screen, user should reposition ring
        
        return CGPoint(x: constrainedX, y: constrainedY)
    }
}
