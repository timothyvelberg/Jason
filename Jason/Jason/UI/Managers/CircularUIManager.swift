//
//  CircularUIManager.swift
//  Jason
//
//  Created by Timothy Velberg on 31/07/2025.
//

import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

class CircularUIManager: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var mousePosition: CGPoint = .zero
    
    // Drag support
    @Published var currentDragProvider: DragProvider?
    @Published var dragStartPoint: CGPoint?
    @Published var triggerDirection: RotationDirection? = nil
    
    private var draggedNode: FunctionNode?
    private var panelMouseMonitor: Any?
    
    var overlayWindow: OverlayWindow?
    private(set) var combinedAppsProvider: CombinedAppsProvider?
    var favoriteFilesProvider: FavoriteFilesProvider?
    var functionManager: FunctionManager?
    private var mouseTracker: MouseTracker?
    private var gestureManager: GestureManager?
    
    private var centerPoint: CGPoint = .zero
    var previousApp: NSRunningApplication?
    private var isIntentionallySwitching: Bool = false
    
    var isInAppSwitcherMode: Bool = false
    var isInHoldMode: Bool = false
    
    var listPanelManager: ListPanelManager?
    
    // MARK: - Configuration (Phase 3 Refactoring)
    
    /// Ring configuration for this instance
    private let configuration: StoredRingConfiguration
    
    /// Configuration ID for identification
    let configId: Int
    
    // MARK: - Initializer
    
    /// Initialize CircularUIManager with a ring configuration
    /// Each CircularUIManager instance is tied to a specific ring configuration
    init(configuration: StoredRingConfiguration) {
        self.configuration = configuration
        self.configId = configuration.id
        
        print("[CircularUIManager] initialized")
        
        commonInit()
    }
    
    /// Common initialization logic shared by both initializers
    private func commonInit() {
        // Connect scroll handler
        overlayWindow?.onScrollBack = { [weak self] in
            self?.handleScrollBack()
        }
        
        QuickLookManager.shared.onVisibilityChanged = { [weak self] isShowing in
            if isShowing {
                // QuickLook is showing - lower our window
                self?.overlayWindow?.lowerWindowLevel()
            } else {
                // QuickLook is hidden - restore our window
                self?.overlayWindow?.restoreWindowLevel()
            }
        }
        
        // Register for provider update notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProviderUpdate(_:)),
            name: .providerContentUpdated,
            object: nil
        )
        
        print("Registered for provider update notifications")
    }
    
    deinit {
        // Clean up notification observer
        NotificationCenter.default.removeObserver(self)
        print("🧹 CircularUIManager deallocated - removed observers")
        
        if let monitor = panelMouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    
    
    // MARK: - Provider Update Handler

    @objc private func handleProviderUpdate(_ notification: Notification) {
        guard let updateInfo = ProviderUpdateInfo.from(notification) else {
            print("❌ Invalid provider update notification")
            return
        }
        
        print("📢 [CircularUIManager-\(configId)] Received update for provider: \(updateInfo.providerId)")
        if let folderPath = updateInfo.folderPath {
            print("   Folder: \(folderPath)")
        }
        
        // Only update if UI is visible
        guard isVisible else {
            print("   ⏭️ UI not visible - ignoring update")
            return
        }
        
        // Check if this provider is currently displayed in any ring
        guard let functionManager = functionManager else {
            print("   ❌ No FunctionManager")
            return
        }
        
        let needsUpdate = checkIfProviderIsVisible(
            providerId: updateInfo.providerId,
            contentIdentifier: updateInfo.folderPath
        )
        
        if needsUpdate {
            print("   ✅ Provider is visible - performing surgical update")
            functionManager.updateRing(
                providerId: updateInfo.providerId,
                contentIdentifier: updateInfo.folderPath
            )
        } else {
            print("   ⏭️ Provider not currently visible - ignoring")
        }
    }

    /// Check if a provider is currently visible in any ring
    private func checkIfProviderIsVisible(providerId: String, contentIdentifier: String?) -> Bool {
        guard let functionManager = functionManager else { return false }
        
        // Check all active rings
        for (index, ring) in functionManager.rings.enumerated() {
            // Check if ring matches this provider
            if ring.providerId == providerId {
                // If no content identifier specified, provider match is enough
                if contentIdentifier == nil {
                    print("   🎯 Found matching provider in Ring \(index)")
                    return true
                }
                
                // If content identifier specified, check it too
                if ring.contentIdentifier == contentIdentifier {
                    print("   🎯 Found matching provider + content in Ring \(index): \(contentIdentifier ?? "")")
                    return true
                }
            }
            
            // 🆕 For mixed rings (providerId is nil), check individual nodes
            // This handles Ring 0 in direct mode where multiple providers' content is mixed
            // BUT: Only match actual content nodes, not category wrappers
            if ring.providerId == nil {
                let hasMatchingNode = ring.nodes.contains { node in
                    node.providerId == providerId && node.type != .category
                }
                if hasMatchingNode {
                    print("   🎯 Found provider '\(providerId)' in mixed Ring \(index) (via node check)")
                    return true
                }
            }
        }
        
        return false
    }
    
    func setup() {
        // Create FunctionManager with configuration values
        self.functionManager = FunctionManager(
            ringThickness: CGFloat(configuration.ringRadius),
            centerHoleRadius: CGFloat(configuration.centerHoleRadius),
            iconSize: CGFloat(configuration.iconSize),
            startAngle: CGFloat(configuration.startAngle)
        )
        print("   ✅ FunctionManager initialized with config values")
        
        // Create ListPanelManager
        self.listPanelManager = ListPanelManager()
        print("   ✅ ListPanelManager initialized")
        
        // Create provider factory
        let factory = ProviderFactory(
            circularUIManager: self,
            appSwitcherManager: AppSwitcherManager.shared
        )
        
        // Create providers from configuration
        print("🎯 [Setup] Loading providers from configuration")
        print("   Configuration: \(configuration.name)")
        print("   Providers: \(configuration.providers.count)")
        
        let providers = factory.createProviders(from: configuration)
        
        // Helper to normalize provider names for matching
        // Converts both "CombinedAppsProvider" (class name) and "combined-apps" (providerId) to same form
        func normalizeProviderName(_ name: String) -> String {
            return name
                .replacingOccurrences(of: "Provider", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "-", with: "")
                .lowercased()
        }
        
        print("📋 [Setup] Available config providerTypes: \(configuration.providers.map { $0.providerType })")

        // Register all providers with their configurations
        for provider in providers {
            // Look up this provider's configuration by matching normalized names
            let normalizedProviderId = normalizeProviderName(provider.providerId)
            
            print("🔍 [Setup] Matching '\(provider.providerId)' → normalized: '\(normalizedProviderId)'")

            
            let providerConfig = configuration.providers.first { config in
                let normalizedConfigType = normalizeProviderName(config.providerType)
                return normalizedConfigType == normalizedProviderId
            }
            
            if let config = providerConfig {
                functionManager?.registerProvider(provider, configuration: config)
                print("   ✅ Registered '\(provider.providerName)' (providerId: \(provider.providerId)) with config")
                print("      displayMode: \(config.effectiveDisplayMode)")
            } else {
                functionManager?.registerProvider(provider, configuration: nil)
                print("   ⚠️ Registered '\(provider.providerName)' (providerId: \(provider.providerId)) WITHOUT config")
                print("      Available configs: \(configuration.providers.map { $0.providerType }.joined(separator: ", "))")
            }
            
            // Store references for specific provider types
            if let combinedApps = provider as? CombinedAppsProvider {
                self.combinedAppsProvider = combinedApps
            }
            if let favoriteFiles = provider as? FavoriteFilesProvider {
                self.favoriteFilesProvider = favoriteFiles
            }
        }
        
        print("   ✅ Registered \(providers.count) provider(s)")

        if let functionManager = functionManager {
            self.mouseTracker = MouseTracker(functionManager: functionManager)
            
            mouseTracker?.onExecuteAction = { [weak self] in
                self?.hide()
            }
            
            mouseTracker?.onPieHover = { [weak functionManager] pieIndex in
                if let functionManager = functionManager, let pieIndex = pieIndex {
                    functionManager.hoverNode(ringLevel: functionManager.activeRingLevel, index: pieIndex)
                }
            }
            mouseTracker?.onCollapse = { [weak self] in
                self?.listPanelManager?.hide()
            }
            
            mouseTracker?.onReturnedInsideBoundary = { [weak self] in
                self?.listPanelManager?.hide()
            }
            
            mouseTracker?.isMouseInPanel = { [weak self] in
                guard let self = self else { return false }
                let mousePos = NSEvent.mouseLocation
                return self.listPanelManager?.isInPanelZone(point: mousePos) ?? false
            }
            
            mouseTracker?.onExpandToPanel = { [weak self] node, angle, ringCenter, ringOuterRadius in
                guard let self = self else { return }
                
                // Extract identity from node
                let providerId = node.providerId
                let contentIdentifier = node.metadata?["folderURL"] as? String ?? node.previewURL?.path
                
                // Check if children already loaded
                if let children = node.children, !children.isEmpty {
                    self.listPanelManager?.show(
                        title: node.name,
                        items: children,
                        ringCenter: ringCenter,
                        ringOuterRadius: ringOuterRadius,
                        angle: angle,
                        providerId: providerId,
                        contentIdentifier: contentIdentifier,
                        screen: self.overlayWindow?.currentScreen
                    )
                    self.mouseTracker?.pauseUntilMovement()
                    return
                }
                
                // Children not loaded - check if we can load dynamically
                guard node.needsDynamicLoading,
                      let providerId = node.providerId,
                      let provider = self.functionManager?.providers.first(where: { $0.providerId == providerId }) else {
                    print("📋 [ExpandToPanel] Node '\(node.name)' has no children and can't load dynamically")
                    return
                }
                
                // Load children asynchronously
                Task {
                    let children = await provider.loadChildren(for: node)
                    
                    guard !children.isEmpty else {
                        print("📋 [ExpandToPanel] No children loaded for: \(node.name)")
                        return
                    }
                    
                    // Show panel on main thread
                    await MainActor.run {
                        self.listPanelManager?.show(
                            title: node.name,
                            items: children,
                            ringCenter: ringCenter,
                            ringOuterRadius: ringOuterRadius,
                            angle: angle,
                            providerId: providerId,
                            contentIdentifier: contentIdentifier,
                            screen: self.overlayWindow?.currentScreen
                        )
                        self.mouseTracker?.pauseUntilMovement()
                    }
                }
            }
            
            // Wire panel item click callbacks
            listPanelManager?.onItemLeftClick = { [weak self] node, modifiers in
                self?.handlePanelItemLeftClick(node: node, modifiers: modifiers)
            }

            listPanelManager?.onItemRightClick = { [weak self] node, modifiers in
                self?.handlePanelItemRightClick(node: node, modifiers: modifiers)
            }
            
            listPanelManager?.onContextAction = { [weak self] actionNode, modifiers in
                self?.handlePanelContextAction(actionNode: actionNode, modifiers: modifiers)
            }
            
            listPanelManager?.onItemHover = { [weak self] node, level, rowIndex in
                guard let self = self, let node = node else {
                    return
                }
                
                // Only cascade for folders
                guard node.type == .folder else {
                    self.listPanelManager?.popToLevel(level)
                    return
                }
                
                // Check if this node's panel is already showing at level+1
                if let existingPanel = self.listPanelManager?.panel(at: level + 1),
                   existingPanel.sourceNodeId == node.id {
                    self.listPanelManager?.popToLevel(level + 1)
                    return
                }
                
                // Extract identity from node
                let providerId = node.providerId
                let contentIdentifier = node.metadata?["folderURL"] as? String ?? node.previewURL?.path
                
                // Check if children already loaded
                if let children = node.children, !children.isEmpty {

                    self.listPanelManager?.pushPanel(
                        title: node.name,
                        items: children,
                        fromPanelAtLevel: level,
                        sourceNodeId: node.id,
                        sourceRowIndex: rowIndex,
                        providerId: providerId,
                        contentIdentifier: contentIdentifier,
                        contextActions: node.contextActions
                    )
                    return
                }
                
                // Children not loaded - check if we can load dynamically
                guard node.needsDynamicLoading,
                      let providerId = node.providerId,
                      let provider = self.functionManager?.providers.first(where: { $0.providerId == providerId }) else {
                    self.listPanelManager?.popToLevel(level)
                    return
                }
                
                // Load children asynchronously
                Task {
                    let children = await provider.loadChildren(for: node)
                    
                    guard !children.isEmpty else {
                        print("📋 [Panel] No children loaded for: \(node.name)")
                        return
                    }
                    
                    // Push panel on main thread
                    await MainActor.run {
                        self.listPanelManager?.pushPanel(
                            title: node.name,
                            items: children,
                            fromPanelAtLevel: level,
                            sourceNodeId: node.id,
                            sourceRowIndex: rowIndex,
                            providerId: providerId,
                            contentIdentifier: contentIdentifier,
                            contextActions: node.contextActions
                        )
                    }
                }
            }
            
            // Wire panel content reload callback
            listPanelManager?.onReloadContent = { [weak self] providerId, contentIdentifier in
                guard let self = self,
                      let provider = self.functionManager?.providers.first(where: { $0.providerId == providerId }) else {
                    print("❌ [Panel Reload] Provider '\(providerId)' not found")
                    return []
                }
                
                // Create a minimal node to call loadChildren
                // Provider extracts folderURL from metadata
                let reloadNode = FunctionNode(
                    id: "reload-\(contentIdentifier ?? "unknown")",
                    name: "reload",
                    type: .folder,
                    icon: NSImage(),
                    metadata: contentIdentifier != nil ? ["folderURL": contentIdentifier!] : nil,
                    providerId: providerId
                )
                
                print("🔄 [Panel Reload] Reloading content for '\(contentIdentifier ?? "unknown")'")
                let freshChildren = await provider.loadChildren(for: reloadNode)
                print("🔄 [Panel Reload] Got \(freshChildren.count) items")
                
                return freshChildren
            }

            self.gestureManager = GestureManager()
            
            gestureManager?.onGesture = { [weak self] event in
                guard let self = self else { return }
                
                switch event.type {
                case .click(.left):
                    self.handleLeftClick(event: event)
                case .click(.right):
                    self.handleRightClick(event: event)
                case .click(.middle):
                    self.handleMiddleClick(event: event)
                case .dragStarted:
                    self.handleDragStart(event: event)
                default:
                    break
                }
            }
            
            // Wire mouse movement for panel sliding
            panelMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
                guard let self = self,
                      let panelManager = self.listPanelManager,
                      panelManager.isVisible else {
                    return event
                }
                
                let mousePosition = NSEvent.mouseLocation
                panelManager.handleMouseMove(at: mousePosition)
                
                return event
            }
        }
        
        setupOverlayWindow()
    }
    
    // MARK: - Gesture Handlers (Click, Drag, Scroll)
    
    private func handleLeftClick(event: GestureManager.GestureEvent) {
        // Check if click is inside the panel
        if let panelManager = listPanelManager {
            if let result = panelManager.handleLeftClick(at: event.position) {
                print("🖱️ [Left Click] Panel item: '\(result.node.name)' at level \(result.level)")
                handlePanelItemLeftClick(node: result.node, modifiers: event.modifierFlags, fromLevel: result.level)
                return
            }
        }
        
        guard let functionManager = functionManager else { return }
        
        guard let (ringLevel, index, node) = functionManager.getItemAt(position: event.position, centerPoint: centerPoint) else {
                    // Check if click was in close zone
                    let distance = hypot(event.position.x - centerPoint.x, event.position.y - centerPoint.y)
                    if distance < FunctionManager.closeZoneRadius {
                        print("🎯 [Left Click] In close zone - closing UI")
                        hide()
                    } else {
                        print("⚠️ Left-click not on any item")
                    }
                    return
                }
        
        print("🖱️ [Left Click] On item: '\(node.name)' at ring \(ringLevel), index \(index)")
        
        // Resolve behavior based on current modifier flags
        let behavior = node.onLeftClick.resolve(with: event.modifierFlags)
        
        switch behavior {
        case .execute(let action):
            action()
            hide()
        case .executeKeepOpen(let action):
            action()
        case .expand:
            functionManager.expandCategory(ringLevel: ringLevel, index: index, openedByClick: true)
        case .navigateInto:
            print("📂 Navigating into folder: '\(node.name)'")
            functionManager.navigateIntoFolder(ringLevel: ringLevel, index: index)
        case .launchRing(let configId):
            print("🚀 [Left Click] Launching ring config \(configId)")
            print("🚀 [Left Click] Launching ring config \(configId) from item '\(node.name)' (id: \(node.id))")
            hide()  // Hide current ring first
            
            // Small delay to ensure clean transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                CircularUIInstanceManager.shared.show(configId: configId)
            }
        case .drag(let provider):
            // Handle click behavior based on explicit declaration
            switch provider.clickBehavior {
            case .execute(let action):
                action()
                hide()
            case .navigate:
                print("📂 Navigating into draggable folder: '\(node.name)'")
                functionManager.navigateIntoFolder(ringLevel: ringLevel, index: index)
            case .none:
                break
            }
        default:
            break
        }
    }
    
    private func handleDragStart(event: GestureManager.GestureEvent) {
        // 1. Check if drag started inside a panel FIRST
        if let panelManager = listPanelManager {
            if let result = panelManager.handleDragStart(at: event.position) {
                print("🖱️ [Drag Start] On panel item: '\(result.node.name)' at level \(result.level)")
                
                // Stop tracking during drag
                mouseTracker?.stopTrackingMouse()
                gestureManager?.stopMonitoring()
                print("⏸️ Mouse tracking paused for panel drag operation")
                
                // Copy provider and update modifier flags
                var provider = result.dragProvider
                provider.modifierFlags = event.modifierFlags
                
                // Add this after setting up the provider, before calling onDragStarted:
                provider.onDragSessionBegan = { [weak self] in
                    DispatchQueue.main.async {
                        self?.overlayWindow?.orderOut(nil)
                    }
                }
                
                // Wrap completion to hide UI after drag
                let originalCompletion = provider.onDragCompleted
                provider.onDragCompleted = { [weak self] success in
                    originalCompletion?(success)
                    DispatchQueue.main.async {
                        print("🏁 Panel drag completed - hiding UI")
                        self?.hide()
                    }
                }
                
                self.currentDragProvider = provider
                self.dragStartPoint = event.position
                self.draggedNode = result.node
                
                print("✅ Panel drag initialized for: \(result.node.name)")
                print("   Files: \(provider.fileURLs.map { $0.lastPathComponent }.joined(separator: ", "))")
                
                provider.onDragStarted?()
                return
            }
        }
        
        // 2. Fall through to ring check
        guard let functionManager = functionManager else { return }
        
        guard let (ringLevel, index, node) = functionManager.getItemAt(position: event.position, centerPoint: centerPoint) else {
            print("⚠️ Drag start not on any item")
            return
        }
        
        print("🖱️ [Drag Start] On ring item: '\(node.name)' at ring \(ringLevel), index \(index)")
        
        // Check if the node is draggable (resolve with current modifiers)
        let behavior = node.onLeftClick.resolve(with: event.modifierFlags)
        
        if case .drag(var provider) = behavior {
            // Stop mouse tracking during drag
            mouseTracker?.stopTrackingMouse()
            gestureManager?.stopMonitoring()
            print("⏸️ Mouse tracking paused for drag operation")
            
            // Store modifier flags at drag start
            provider.modifierFlags = event.modifierFlags
            
            // Wrap the original onDragCompleted to hide UI after drag
            let originalCompletion = provider.onDragCompleted
            provider.onDragCompleted = { [weak self] success in
                originalCompletion?(success)
                DispatchQueue.main.async {
                    print("🏁 Drag completed - hiding UI")
                    self?.hide()
                }
            }
            
            self.currentDragProvider = provider
            self.dragStartPoint = event.position
            self.draggedNode = node
            
            print("✅ Ring drag initialized for: \(node.name)")
            print("   Files: \(provider.fileURLs.map { $0.lastPathComponent }.joined(separator: ", "))")
            print("   Modifiers: \(event.modifierFlags)")
            
            provider.onDragStarted?()
        } else {
            print("⚠️ Node is not draggable")
        }
    }
    
    private func handleScroll(delta: CGFloat) {
        guard let functionManager = functionManager else { return }
        
        if delta > 0 {
            // Scroll up/away = Navigate deeper
            let hoveredRingLevel = functionManager.activeRingLevel
            if let hoveredIndex = functionManager.rings[hoveredRingLevel].hoveredIndex {
                
                let node = functionManager.rings[hoveredRingLevel].nodes[hoveredIndex]
                
                // Get current modifier flags
                let currentModifiers = NSEvent.modifierFlags
                
                // Resolve behavior based on modifiers
                let behavior = node.onBoundaryCross.resolve(with: currentModifiers)
                
                switch behavior {
                case .navigateInto:
                    print("📜 Scroll detected - navigating into folder")
                    functionManager.navigateIntoFolder(ringLevel: hoveredRingLevel, index: hoveredIndex)
                    mouseTracker?.pauseUntilMovement()
                    
                case .expand:
                    print("📜 Scroll detected - expanding category")
                    functionManager.expandCategory(ringLevel: hoveredRingLevel, index: hoveredIndex, openedByClick: true)
                    mouseTracker?.pauseUntilMovement()
                    
                default:
                    break
                }
            }
        } else if delta < 0 {
            // Scroll down/toward = Go back
            handleScrollBack()
        }
    }
    
    func handleScrollBack() {
        guard let functionManager = functionManager else { return }
        
        // Go back one level
        let currentLevel = functionManager.activeRingLevel
        if currentLevel > 0 {
            print("📜 Scroll back detected - collapsing to ring \(currentLevel - 1)")
            functionManager.collapseToRing(level: currentLevel - 1)
            mouseTracker?.pauseUntilMovement()
        }
    }
    
    private func handleRightClick(event: GestureManager.GestureEvent) {
        if let panelManager = listPanelManager, panelManager.handleRightClick(at: event.position) {
            print("🖱️ [Right Click] Handled by panel")
            return
        }
        
        guard let functionManager = functionManager else { return }
        
        // Use position-based detection instead of hoveredIndex
        guard let (ringLevel, index, node) = functionManager.getItemAt(position: event.position, centerPoint: centerPoint) else {
            print("⚠️ Right-click not on any item")
            return
        }
        
        print("🖱️ [Right Click] On item: '\(node.name)' at ring \(ringLevel), index \(index)")
        
        // Resolve behavior based on current modifier flags
        let behavior = node.onRightClick.resolve(with: event.modifierFlags)
        
        switch behavior {
        case .expand:
            functionManager.expandCategory(ringLevel: ringLevel, index: index, openedByClick: true)
            // Pause mouse tracking to prevent immediate collapse
            mouseTracker?.pauseUntilMovement()
            
        case .navigateInto:
            print("📂 Navigating into folder: '\(node.name)'")
            functionManager.navigateIntoFolder(ringLevel: ringLevel, index: index)
            // Pause mouse tracking to prevent immediate collapse
            mouseTracker?.pauseUntilMovement()
            
        case .launchRing(let configId):
            print("🚀 [Right Click] Launching ring config \(configId)")
            hide()  // Hide current ring first
            
            // Small delay to ensure clean transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                CircularUIInstanceManager.shared.show(configId: configId)
            }
            
        case .execute(let action):
            action()
            hide()
            
        case .executeKeepOpen(let action):
            action()
            
        default:
            break
        }
    }
    
    private func handleMiddleClick(event: GestureManager.GestureEvent) {
        guard let functionManager = functionManager else { return }
        
        // Use position-based detection instead of hoveredIndex
        guard let (ringLevel, index, node) = functionManager.getItemAt(position: event.position, centerPoint: centerPoint) else {
            print("⚠️ Middle-click not on any item")
            return
        }
        
        print("🖱️ [Middle Click] On item: '\(node.name)' at ring \(ringLevel), index \(index)")
        
        // Check if node is previewable - if so, show preview instead of executing action
        if node.isPreviewable, let previewURL = node.previewURL {
            print("👁️ [Middle Click] Node is previewable - showing Quick Look")
            QuickLookManager.shared.togglePreview(for: previewURL)
            return
        }
        
        // Otherwise, execute the middle-click action (resolve with modifiers)
        let behavior = node.onMiddleClick.resolve(with: event.modifierFlags)
        
        switch behavior {
        case .execute(let action):
            action()
            hide()
        case .executeKeepOpen(let action):
            action()
        case .launchRing(let configId):
            print("🚀 [Middle Click] Launching ring config \(configId)")
            hide()  // Hide current ring first
            
            // Small delay to ensure clean transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                CircularUIInstanceManager.shared.show(configId: configId)
            }
        default:
            break
        }
    }
    
    // MARK: - Panel Item Handlers

    private func handlePanelItemLeftClick(node: FunctionNode, modifiers: NSEvent.ModifierFlags) {
        handlePanelItemLeftClick(node: node, modifiers: modifiers, fromLevel: 0)
    }

    private func handlePanelItemLeftClick(node: FunctionNode, modifiers: NSEvent.ModifierFlags, fromLevel level: Int) {
        print("🖱️ [Panel Left Click] On item: '\(node.name)' at level \(level)")
        
        let behavior = node.onLeftClick.resolve(with: modifiers)
        
        switch behavior {
        case .execute(let action):
            action()
            hide()
            
        case .executeKeepOpen(let action):
            action()
            
        case .expand, .navigateInto:
            // Check if we should cascade to panel
            guard let children = node.children, !children.isEmpty else {
                print("📋 [Panel] Node '\(node.name)' has no children")
                return
            }
            
            // Cascade: push new panel to the right
            listPanelManager?.pushPanel(
                title: node.name,
                items: children,
                fromPanelAtLevel: level,
                sourceNodeId: node.id,
                contextActions: node.contextActions
            )
            
        case .launchRing(let configId):
            print("🚀 [Panel] Launching ring config \(configId)")
            hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                CircularUIInstanceManager.shared.show(configId: configId)
            }
            
        case .drag(let provider):
            switch provider.clickBehavior {
            case .execute(let action):
                action()
                hide()
            case .navigate:
                if let children = node.children, !children.isEmpty {
                    listPanelManager?.pushPanel(
                        title: node.name,
                        items: children,
                        fromPanelAtLevel: level,
                        sourceNodeId: node.id,
                        contextActions: node.contextActions
                    )
                }
            case .none:
                break
            }
            
        case .doNothing:
            break
        }
    }
    
    private func handlePanelContextAction(actionNode: FunctionNode, modifiers: NSEvent.ModifierFlags) {
        print("🖱️ [Panel Context Action] '\(actionNode.name)'")
        
        // Context actions typically use onLeftClick for their action
        let behavior = actionNode.onLeftClick.resolve(with: modifiers)
        
        switch behavior {
        case .execute(let action):
            action()
            hide()
            
        case .executeKeepOpen(let action):
            action()
            
        case .launchRing(let configId):
            print("🚀 [Panel Context] Launching ring config \(configId)")
            hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                CircularUIInstanceManager.shared.show(configId: configId)
            }
            
        default:
            print("⚠️ [Panel Context] Unhandled behavior for '\(actionNode.name)'")
        }
    }

    private func handlePanelItemRightClick(node: FunctionNode, modifiers: NSEvent.ModifierFlags) {
        print("🖱️ [Panel Right Click] On item: '\(node.name)'")
        
        let behavior = node.onRightClick.resolve(with: modifiers)
        
        switch behavior {
        case .execute(let action):
            action()
            hide()
            
        case .executeKeepOpen(let action):
            action()
            
        case .expand:
            // Show context actions if available
            if let contextActions = node.contextActions, !contextActions.isEmpty {
                print("📋 [Panel] Expanding context actions for '\(node.name)'")
                if let manager = listPanelManager {
                    manager.show(
                        title: node.name,
                        items: contextActions,
                        ringCenter: manager.currentRingCenter,
                        ringOuterRadius: manager.currentRingOuterRadius,
                        angle: manager.currentAngle,
                        screen: self.overlayWindow?.currentScreen
                    )
                }
            }
            
        case .launchRing(let configId):
            print("🚀 [Panel Right Click] Launching ring config \(configId)")
            hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                CircularUIInstanceManager.shared.show(configId: configId)
            }
            
        default:
            break
        }
    }
    
    // MARK: - Overlay Window Setup
    
    private func setupOverlayWindow() {
        overlayWindow = OverlayWindow()
        
        guard let functionManager = functionManager else {
            print("FunctionManager not initialized")
            return
        }
        
        overlayWindow?.onLostFocus = { [weak self] in
            guard let self = self else { return }
            
            // Close QuickLook when focus is lost
            QuickLookManager.shared.hidePreview()
            
            self.hide()
        }
        
        let contentView = CircularUIView(
            circularUI: self,
            functionManager: functionManager,
            listPanelManager: self.listPanelManager!
        )
        overlayWindow?.contentView = NSHostingView(rootView: contentView)
    }
    
    // MARK: - Preview Handler

    func handlePreviewRequest() {
        guard let functionManager = functionManager else { return }
        
        // If QuickLook is already showing, just close it
        if QuickLookManager.shared.isShowing {
            print("👁️ [Preview] QuickLook is already open - closing it")
            QuickLookManager.shared.hidePreview()
            return
        }
        
        let activeRingLevel = functionManager.activeRingLevel
        guard activeRingLevel < functionManager.rings.count else {
            print("⚠️ No active ring for preview")
            return
        }
        
        guard let hoveredIndex = functionManager.rings[activeRingLevel].hoveredIndex else {
            print("⚠️ No item currently hovered for preview")
            return
        }
        
        guard hoveredIndex < functionManager.rings[activeRingLevel].nodes.count else {
            print("⚠️ Invalid hovered index for preview")
            return
        }
        
        let node = functionManager.rings[activeRingLevel].nodes[hoveredIndex]
        
        // Check if node is previewable
        guard node.isPreviewable, let previewURL = node.previewURL else {
            print("⚠️ Node '\(node.name)' is not previewable")
            return
        }
        
        print("👁️ [Preview] Showing Quick Look for: \(node.name)")
        QuickLookManager.shared.showPreview(for: previewURL)
    }
    
    // MARK: - App Switcher Mode Handlers
    
    /// Execute the hovered item when releasing hold mode (if auto-execute is enabled)
    func executeHoveredItemIfInHoldMode() {
        // Only execute in hold mode AND if auto-execute is enabled
        guard isInHoldMode else {
            print("⏭️ [HoldMode] Not in hold mode - skipping auto-execute")
            return
        }
        
        // Check if auto-execute is enabled for this configuration
        guard configuration.autoExecuteOnRelease else {
            print("⏭️ [HoldMode] Auto-execute disabled for this ring - skipping")
            return
        }
        
        guard let functionManager = functionManager else {
            print("❌ [HoldMode] No FunctionManager")
            return
        }
        
        // Get the active ring
        let activeRingLevel = functionManager.activeRingLevel
        guard activeRingLevel < functionManager.rings.count else {
            print("❌ [HoldMode] Invalid ring level: \(activeRingLevel)")
            return
        }
        
        let ring = functionManager.rings[activeRingLevel]
        
        // Check if there's a hovered item
        guard let hoveredIndex = ring.hoveredIndex else {
            print("⏭️ [HoldMode] No item currently hovered - skipping auto-execute")
            return
        }
        
        guard hoveredIndex < ring.nodes.count else {
            print("❌ [HoldMode] Invalid hovered index: \(hoveredIndex)")
            return
        }
        
        let selectedNode = ring.nodes[hoveredIndex]
        
        print("✅ [HoldMode] Hold released - auto-executing: \(selectedNode.name)")
        
        // Execute the item's left click action (resolve with no modifiers since key/button was just released)
        let behavior = selectedNode.onLeftClick.resolve(with: [])
        
        switch behavior {
        case .execute(let action):
            action()
            // Note: hide() will be called after this method returns
        case .executeKeepOpen(let action):
            action()
            // Note: hide() will be called after this method returns (we don't honor keepOpen in hold mode)
        default:
            print("⚠️ [HoldMode] Selected node doesn't have execute action")
        }
    }
    
    func handleCtrlReleaseInAppSwitcher() {
        guard isInAppSwitcherMode else { return }
        
        print("⌨️ [App Switcher] Ctrl released - switching to hovered app")
        
        guard let functionManager = functionManager else {
            print("❌ No FunctionManager")
            exitAppSwitcherMode()
            hide()
            return
        }
        
        // We should be in Ring 1 (apps ring)
        guard functionManager.activeRingLevel == 1,
              functionManager.rings.count > 1 else {
            print("❌ Not in apps ring (level: \(functionManager.activeRingLevel))")
            exitAppSwitcherMode()
            hide()
            return
        }
        
        let ring = functionManager.rings[1]
        
        guard let hoveredIndex = ring.hoveredIndex else {
            print("❌ No app currently hovered")
            exitAppSwitcherMode()
            hide()
            return
        }
        
        let selectedNode = ring.nodes[hoveredIndex]
        
        print("✅ Ctrl released - switching to app: \(selectedNode.name)")
        
        // Execute the app's left click action (resolve with no modifiers since Ctrl was just released)
        let behavior = selectedNode.onLeftClick.resolve(with: [])
        
        switch behavior {
        case .execute(let action):
            action()
            exitAppSwitcherMode()
            hide()
        default:
            print("⚠️ Selected node doesn't have execute action")
            exitAppSwitcherMode()
            hide()
        }
    }

    private func exitAppSwitcherMode() {
        if isInAppSwitcherMode {
            print("🚪 Exiting app switcher mode")
        }
        isInAppSwitcherMode = false
    }
    
    // MARK: - Show Methods

    /// Show the UI at the root level (Ring 0)
    func show(triggerDirection: RotationDirection? = nil) {
        show(expandingCategory: nil, triggerDirection: triggerDirection)
    }

    /// Show the UI already expanded to a specific category
    /// - Parameter providerId: The ID of the provider to expand (e.g., "app-switcher"), or nil to show Ring 0
    func show(expandingCategory providerId: String?, triggerDirection: RotationDirection? = nil) {

        guard let functionManager = functionManager else {
            print("FunctionManager not initialized")
            return
        }
        
        // Store trigger direction for animation
        self.triggerDirection = triggerDirection
        print("🔄 [CircularUIManager] triggerDirection set to: \(String(describing: triggerDirection))")

        
        // 🆕 Refresh badge cache before loading functions
        DockBadgeReader.shared.forceRefresh()
        
        // 🆕 ADDED: Register as the active CircularUIManager
        print("🔗 [CircularUIManager-\(configId)] Registering as active instance with AppSwitcherManager")
        AppSwitcherManager.shared.activeCircularUIManager = self
        
        // Save the currently active app BEFORE we show our UI
        previousApp = NSWorkspace.shared.frontmostApplication
        if let prevApp = previousApp {
            print("💾 Saved previous app: \(prevApp.localizedName ?? "Unknown")")
        }
        
        // Load functions (and optionally expand to a category)
        if let providerId = providerId {
            print("🎯 [CircularUIManager] Showing UI expanded to: \(providerId)")
            functionManager.loadAndExpandToCategory(providerId: providerId)
            
            // IMPORTANT: Tell MouseTracker we're starting at Ring 0 (even though Ring 1 is active)
            // This way, when user moves back to Ring 0, it will collapse
            mouseTracker?.ringLevelAtPause = 0
        } else {
            functionManager.loadFunctions()
        }
        
        guard !functionManager.rings.isEmpty && !functionManager.rings[0].nodes.isEmpty else {
            print("No functions to display")
            return
        }
        
        mousePosition = NSEvent.mouseLocation
        centerPoint = mousePosition
        isVisible = true
        overlayWindow?.showOverlay(at: mousePosition)
        
        mouseTracker?.startTrackingMouse()
        gestureManager?.startMonitoring()
        
        if let providerId = providerId {
            print("   Expanded to category: \(providerId)")
        }
        print("   Active ring level: \(functionManager.activeRingLevel)")
        print("   Total rings: \(functionManager.rings.count)")
    }
    
    // MARK: - Hide Method

    func hide() {
        // Stop mouse monitor FIRST to prevent blocking permission dialogs
        pauseMouseMonitor()
        
        if isInHoldMode {
            executeHoveredItemIfInHoldMode()
        }
        
        mouseTracker?.stopTrackingMouse()
        gestureManager?.stopMonitoring()
        
        isVisible = false
        overlayWindow?.hideOverlay()
        
        // Exit app switcher mode when hiding
        exitAppSwitcherMode()
        
        // Exit hold mode when hiding (prevents double-hide on key release)
        isInHoldMode = false
        
        // Unregister as the active CircularUIManager
        if AppSwitcherManager.shared.activeCircularUIManager === self {
            print("🔓 [CircularUIManager-\(configId)] Unregistering as active instance")
            AppSwitcherManager.shared.activeCircularUIManager = nil
        }
        
        // Only restore previous app if we're NOT intentionally switching
        if !isIntentionallySwitching {
            if let prevApp = previousApp, prevApp.isTerminated == false {
                print("🔄 Restoring focus to: \(prevApp.localizedName ?? "Unknown")")
                prevApp.activate()
            }
        } else {
            print("⏭️ Skipping restore - intentionally switching apps")
        }
        
        // Reset all state for clean slate on next show
        functionManager?.reset()
        listPanelManager?.hide()
        
        // Close any open preview
        QuickLookManager.shared.hidePreview()
        previousApp = nil
        isIntentionallySwitching = false
        
        print("Hiding circular UI")
    }
    
    /// Temporarily ignore focus changes (used during app quit/launch to prevent unwanted UI hiding)
    func ignoreFocusChangesTemporarily(duration: TimeInterval = 0.5) {
        overlayWindow?.ignoreFocusChangesTemporarily(duration: duration)
    }
    
    func hideAndSwitchTo(app: NSRunningApplication) {
        // Set flag to prevent hide() from restoring previous app
        isIntentionallySwitching = true
        
        // Hide the UI (this will trigger onLostFocus -> hide())
        mouseTracker?.stopTrackingMouse()
        gestureManager?.stopMonitoring()
        
        isVisible = false
        overlayWindow?.hideOverlay()
        
        print("🎯 Switching to selected app: \(app.localizedName ?? "Unknown")")
        
        // Activate the app AFTER setting the flag
        app.activate()
        
        // Note: hide() will be called by onLostFocus, and it will see our flag
        print("Switching to app (hide() will clean up)")
    }
    
    // MARK: - Test Ring → Panel Integration

    func showTestRingForPanelIntegration() {
        guard let functionManager = functionManager else {
            print("❌ [Test] FunctionManager not initialized")
            return
        }
        
        let mockFolderContents: [FunctionNode] = [
            createMockFileNode(name: "document.pdf", utType: .pdf),
            createMockFileNode(name: "notes.txt", utType: .plainText),
            createMockFileNode(name: "image.jpg", utType: .jpeg),
            createMockFileNode(name: "spreadsheet.xlsx", utType: .spreadsheet),
            createMockFolderNode(name: "Subfolder"),
        ]
        
        weak var weakSelf = self
        
        // Test with 8 items
        let names = ["Documents", "Downloads", "Screenshots", "Projects", "Music", "Videos", "Desktop", "Archive"]
        let itemCount = names.count
        let anglePerItem = 360.0 / Double(itemCount)
        
        let folderNodes: [FunctionNode] = names.enumerated().map { index, name in
            let angle = Double(index) * anglePerItem
            return createMockFolderNode(name: name) {
                weakSelf?.showPanelForFolder(title: name, contents: mockFolderContents, atAngle: angle)
            }
        }
        
        functionManager.loadTestNodes(folderNodes)
        
        mousePosition = NSEvent.mouseLocation
        centerPoint = mousePosition
        isVisible = true
        overlayWindow?.showOverlay(at: mousePosition)
        
        mouseTracker?.startTrackingMouse()
        gestureManager?.startMonitoring()
        
        print("🧪 [Test] Showing test ring with \(itemCount) items, \(anglePerItem)° per item")
    }

    private func showPanelForFolder(title: String,contents: [FunctionNode], atAngle angle: Double) {
        guard let functionManager = functionManager else { return }
        
        // Get ring geometry
        let ringCenter = mousePosition  // Ring is centered at mouse position
        let configs = functionManager.ringConfigurations
        guard let ring0Config = configs.first else { return }
        
        let ringOuterRadius = ring0Config.startRadius + ring0Config.thickness
        
        listPanelManager?.show(
            title: title,
            items: contents,
            ringCenter: ringCenter,
            ringOuterRadius: ringOuterRadius,
            angle: angle
        )
        
        print("📋 [Test] Panel triggered at angle \(angle)°")
    }

    private func createMockFolderNode(name: String, onTap: (() -> Void)? = nil) -> FunctionNode {
        let icon = NSWorkspace.shared.icon(for: .folder)
        
        let interaction: ModifierAwareInteraction
        if let action = onTap {
            interaction = ModifierAwareInteraction(base: .executeKeepOpen(action))
        } else {
            interaction = ModifierAwareInteraction(base: .doNothing)
        }
        
        return FunctionNode(
            id: "test-folder-\(name)",
            name: name,
            type: .folder,
            icon: icon,
            onLeftClick: interaction,
            onBoundaryCross: interaction
        )
    }

    private func createMockFileNode(name: String, utType: UTType) -> FunctionNode {
        let icon = NSWorkspace.shared.icon(for: utType)
        
        return FunctionNode(
            id: "test-file-\(name)",
            name: name,
            type: .file,
            icon: icon
        )
    }

    func pauseMouseMonitor() {
        if let monitor = panelMouseMonitor {
            NSEvent.removeMonitor(monitor)
            panelMouseMonitor = nil
            print("⏸️ [MouseMonitor] Paused")
        }
    }

    func resumeMouseMonitor() {
        guard panelMouseMonitor == nil else { return }
        
        panelMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self = self,
                  self.isVisible,
                  let panelManager = self.listPanelManager,
                  panelManager.isVisible else {
                return event
            }
            
            let mousePosition = NSEvent.mouseLocation
            panelManager.handleMouseMove(at: mousePosition)
            
            return event
        }
        print("▶️ [MouseMonitor] Resumed")
    }
}
