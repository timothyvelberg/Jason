//
//  CircularUIManager.swift
//  Jason
//
//  Created by Timothy Velberg on 31/07/2025.
//

import Foundation
import AppKit
import SwiftUI

class CircularUIManager: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var mousePosition: CGPoint = .zero
    
    // Drag support
    @Published var currentDragProvider: DragProvider?
    @Published var dragStartPoint: CGPoint?
    private var draggedNode: FunctionNode?
    
    var overlayWindow: OverlayWindow?
    private(set) var appSwitcher: AppSwitcherManager?
    private(set) var combinedAppsProvider: CombinedAppsProvider?
    var favoriteFilesProvider: FavoriteFilesProvider?
    var functionManager: FunctionManager?
    private var mouseTracker: MouseTracker?
    private var gestureManager: GestureManager?
    
    private var centerPoint: CGPoint = .zero
    private var previousApp: NSRunningApplication?
    private var isIntentionallySwitching: Bool = false
    
    var isInAppSwitcherMode: Bool = false
    var isInHoldMode: Bool = false
    
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
    }
    
    // MARK: - Provider Update Handler

    @objc private func handleProviderUpdate(_ notification: Notification) {
        guard let updateInfo = ProviderUpdateInfo.from(notification) else {
            print("❌ Invalid provider update notification")
            return
        }
        
        print("📢 [CircularUIManager] Received update for provider: \(updateInfo.providerId)")
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
        }
        
        return false
    }
    
    /// Check if a provider is currently visible in any ring
    private func checkIfProviderIsVisible(providerId: String, folderPath: String?) -> Bool {
        guard let functionManager = functionManager else { return false }
        
        // Check all active rings
        for (index, ring) in functionManager.rings.enumerated() {
            for node in ring.nodes {
                // Check if this node belongs to the updated provider
                
                // For FinderLogic: check folderPath in metadata
                if providerId == "finder-windows", let folderPath = folderPath {
                    if let metadata = node.metadata,
                       let nodeFolderPath = metadata["folderURL"] as? String,
                       nodeFolderPath == folderPath {
                        print("   🎯 Found matching folder in Ring \(index): \(folderPath)")
                        return true
                    }
                }
                
                // For AppSwitcher: check node ID prefix
                if providerId == "app-switcher" && node.id.hasPrefix("app-") {
                    print("   🎯 Found app switcher content in Ring \(index)")
                    return true
                }
                
                // Add more provider-specific checks here as needed
            }
        }
        
        return false
    }
    
    func setup() {
        // Create AppSwitcherManager internally (still needed for MRU tracking and app management)
        let appSwitcher = AppSwitcherManager()
        self.appSwitcher = appSwitcher
        
        appSwitcher.circularUIManager = self
        
        // Create FunctionManager with configuration values
        self.functionManager = FunctionManager(
            ringThickness: CGFloat(configuration.ringRadius),
            centerHoleRadius: CGFloat(configuration.centerHoleRadius),
            iconSize: CGFloat(configuration.iconSize)
        )
        print("   ✅ FunctionManager initialized with config values")
        
        // Create provider factory
        let factory = ProviderFactory(
            circularUIManager: self,
            appSwitcherManager: appSwitcher
        )
        
        // Create providers from configuration
        print("🎯 [Setup] Loading providers from configuration")
        print("   Configuration: \(configuration.name)")
        print("   Providers: \(configuration.providers.count)")
        
        let providers = factory.createProviders(from: configuration)
        
        // Helper to normalize provider names for matching
        // Handles both "CombinedAppsProvider" (database) and "combined-apps" (providerId)
        func normalizeProviderName(_ name: String) -> String {
            // Convert camelCase/PascalCase to lowercase kebab-case
            // "CombinedAppsProvider" -> "combinedappsprovider"
            // "combined-apps" -> "combinedapps"
            return name
                .replacingOccurrences(of: "Provider", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "-", with: "")
                .lowercased()
        }
        
        // Register all providers with their configurations
        for provider in providers {
            // Look up this provider's configuration by matching normalized names
            let normalizedProviderId = normalizeProviderName(provider.providerId)
            
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
        }
        
        setupOverlayWindow()
    }
    
    // MARK: - Gesture Handlers (Click, Drag, Scroll)
    
    private func handleLeftClick(event: GestureManager.GestureEvent) {
        guard let functionManager = functionManager else { return }
        
        // Use position-based detection instead of hoveredIndex
        guard let (ringLevel, index, node) = functionManager.getItemAt(position: event.position, centerPoint: centerPoint) else {
            print("⚠️ Left-click not on any item")
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
        case .drag(let provider):
            // Execute onClick if provided
            if let onClick = provider.onClick {
                onClick()
                hide()
            }
        default:
            break
        }
    }
    
    private func handleDragStart(event: GestureManager.GestureEvent) {
        guard let functionManager = functionManager else { return }
        
        // Use position-based detection instead of hoveredIndex
        guard let (ringLevel, index, node) = functionManager.getItemAt(position: event.position, centerPoint: centerPoint) else {
            print("⚠️ Drag start not on any item")
            return
        }
        
        print("🖱️ [Drag Start] On item: '\(node.name)' at ring \(ringLevel), index \(index)")
        
        // Check if the node is draggable (resolve with current modifiers)
        let behavior = node.onLeftClick.resolve(with: event.modifierFlags)
        
        if case .drag(var provider) = behavior {
            // Store modifier flags at drag start
            provider.modifierFlags = event.modifierFlags
            
            self.currentDragProvider = provider
            self.dragStartPoint = event.position
            self.draggedNode = node
            
            print("✅ Drag initialized for: \(node.name)")
            print("   Files: \(provider.fileURLs.map { $0.lastPathComponent }.joined(separator: ", "))")
            print("   Modifiers: \(event.modifierFlags)")
            
            // Call onDragStarted if provided
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
                    mouseTracker?.pauseAfterScroll()
                    
                case .expand:
                    print("📜 Scroll detected - expanding category")
                    functionManager.expandCategory(ringLevel: hoveredRingLevel, index: hoveredIndex, openedByClick: true)
                    mouseTracker?.pauseAfterScroll()
                    
                default:
                    break
                }
            }
        } else if delta < 0 {
            // Scroll down/toward = Go back
            handleScrollBack()
        }
    }
    
    private func handleScrollBack() {
        guard let functionManager = functionManager else { return }
        
        // Go back one level
        let currentLevel = functionManager.activeRingLevel
        if currentLevel > 0 {
            print("📜 Scroll back detected - collapsing to ring \(currentLevel - 1)")
            functionManager.collapseToRing(level: currentLevel - 1)
            mouseTracker?.pauseAfterScroll()
        }
    }
    
    private func handleRightClick(event: GestureManager.GestureEvent) {
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
            mouseTracker?.pauseAfterScroll()
            
        case .navigateInto:
            print("📂 Navigating into folder: '\(node.name)'")
            functionManager.navigateIntoFolder(ringLevel: ringLevel, index: index)
            // Pause mouse tracking to prevent immediate collapse
            mouseTracker?.pauseAfterScroll()
            
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
            functionManager: functionManager
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
    func show() {
        show(expandingCategory: nil)
    }

    /// Show the UI already expanded to a specific category
    /// - Parameter providerId: The ID of the provider to expand (e.g., "app-switcher"), or nil to show Ring 0
    func show(expandingCategory providerId: String?) {
        guard let functionManager = functionManager else {
            print("FunctionManager not initialized")
            return
        }
        
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
        
        // Check if we have any actual content (leaf nodes or branches with children)
        let hasValidData: Bool = {
            guard functionManager.rings.count > 0 else { return false }
            guard !functionManager.rings[0].nodes.isEmpty else { return false }
            
            // Check if any root node has content
            for node in functionManager.rings[0].nodes {
                if node.isLeaf {
                    return true  // Has at least one executable function
                } else if node.childCount > 0 {
                    return true  // Has at least one category with children
                }
            }
            return false
        }()
        
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
        
        print("✅ Showing circular UI at position: \(mousePosition)")
        if let providerId = providerId {
            print("   Expanded to category: \(providerId)")
        }
        print("   Active ring level: \(functionManager.activeRingLevel)")
        print("   Total rings: \(functionManager.rings.count)")
    }
    
    // MARK: - Hide Method

    func hide() {
        mouseTracker?.stopTrackingMouse()
        gestureManager?.stopMonitoring()
        
        isVisible = false
        overlayWindow?.hideOverlay()
        
        // Exit app switcher mode when hiding
        exitAppSwitcherMode()
        
        // 🆕 Exit hold mode when hiding (prevents double-hide on key release)
        isInHoldMode = false
        
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
}
