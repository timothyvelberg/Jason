//
//  PanelUIManager.swift
//  Jason
//
//  Created by Timothy Velberg on 29/01/2026.
//  Lightweight UI manager for standalone panel presentation.
//  Shows panels directly at mouse position without ring UI.
//

import Foundation
import AppKit
import SwiftUI

class PanelUIManager: ObservableObject, UIManager {
    
    // MARK: - UIManager Protocol Properties
    
    let configId: Int
    @Published var isVisible: Bool = false
    var isInHoldMode: Bool = false
    var activeTrigger: TriggerConfiguration?
    var listPanelManager: ListPanelManager?
    
    // MARK: - Internal Properties
    
    var overlayWindow: OverlayWindow?
    var inputCoordinator: InputCoordinator?
    var gestureManager: GestureManager?
    var panelActionHandler: PanelActionHandler?
    
    /// Providers for this panel
    var providers: [any FunctionProvider] = []
    
    /// Previous app for focus restoration
    var previousApp: NSRunningApplication?
    
    /// Flag to prevent restoring previous app when intentionally switching
    var isIntentionallySwitching: Bool = false
    
    /// Panel mouse monitor for hover tracking
    var panelMouseMonitor: Any?
    
    // MARK: - Configuration
    
    private let configuration: StoredRingConfiguration
    
    // MARK: - Initialization
    
    init(configuration: StoredRingConfiguration) {
        self.configuration = configuration
        self.configId = configuration.id
        
        print("[PanelUIManager-\(configId)] Initialized for '\(configuration.name)'")
    }
    
    deinit {
        if let monitor = panelMouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
        print("[PanelUIManager-\(configId)] Deallocated")
    }
    
    // MARK: - UIManager Protocol Methods
    
    func setup() {
        print("[PanelUIManager-\(configId)] Setting up...")
        
        // Create ListPanelManager
        self.listPanelManager = ListPanelManager()
        print("   ListPanelManager initialized")
        
        self.listPanelManager = ListPanelManager()
        listPanelManager?.findProvider = { [weak self] providerId in
            self?.providers.first { $0.providerId == providerId }
        }
        
        // Create InputCoordinator
        self.inputCoordinator = InputCoordinator()
        print("   InputCoordinator initialized")
        
        // Wire input coordinator to panel manager
        listPanelManager?.inputCoordinator = inputCoordinator
        
        // Create PanelActionHandler
        self.panelActionHandler = PanelActionHandler()
        panelActionHandler?.listPanelManager = listPanelManager
        panelActionHandler?.findProvider = { [weak self] providerId in
            self?.providers.first { $0.providerId == providerId }
        }
        panelActionHandler?.hideUI = { [weak self] in
            self?.hide()
        }
        print("   PanelActionHandler initialized")
        
        // Create providers
        setupProviders()
        
        // Setup gesture manager for clicks
        setupGestureManager()
        
        // Setup panel callbacks
        setupPanelCallbacks()
        
        // Setup overlay window
        setupOverlayWindow()
        
        print("[PanelUIManager-\(configId)] Setup complete")
    }
    
    func show(triggerDirection: RotationDirection? = nil) {
        print("[PanelUIManager-\(configId)] Showing panel...")
        
        // Save previous app
        previousApp = NSWorkspace.shared.frontmostApplication
        if let prevApp = previousApp {
            print("   Saved previous app: \(prevApp.localizedName ?? "Unknown")")
        }
        
        // Load items from providers
        let items = loadProviderItems()
        
        guard !items.isEmpty else {
            print("[PanelUIManager-\(configId)] No items to display")
            return
        }
        
        // Get mouse position
        let mousePosition = NSEvent.mouseLocation
        
        // Find screen containing mouse
        let screen = NSScreen.screens.first { screen in
            NSMouseInRect(mousePosition, screen.frame, false)
        } ?? NSScreen.main
        
        // Show overlay window
        isVisible = true
        overlayWindow?.showOverlay(at: mousePosition)
        
        // Determine typing mode from providers
        let typingMode: TypingMode = providers.first?.defaultTypingMode ?? .typeAhead
        let providerId: String? = providers.count == 1 ? providers.first?.providerId : nil

        // Show panel at mouse position
        listPanelManager?.show(
            title: configuration.name,
            items: items,
            at: mousePosition,
            screen: screen,
            providerId: providerId,
            typingMode: typingMode
        )
        
        // Start gesture monitoring
        gestureManager?.startMonitoring()
        
        // Start panel mouse monitor
        startPanelMouseMonitor()
        
        // Set initial focus to panel
        inputCoordinator?.focusPanel(level: 0)
        
        // Arm panel for keyboard navigation and auto-activate input mode
        if let index = listPanelManager?.panelStack.firstIndex(where: { $0.level == 0 }) {
            listPanelManager?.panelStack[index].areChildrenArmed = true
            
            if typingMode == .input {
                listPanelManager?.panelStack[index].isSearchActive = true
                listPanelManager?.panelStack[index].searchAnchorHeight = listPanelManager?.panelStack[index].panelHeight
                listPanelManager?.panelStack[index].activeTypingMode = .input
            }
        }
        
        // Set initial keyboard selection
        listPanelManager?.keyboardSelectedRow[0] = 0
        
        print("[PanelUIManager-\(configId)] Panel visible with \(items.count) items")
    }
    
    func hide() {
        print("[PanelUIManager-\(configId)] Hiding...")
        
        // Stop mouse monitor
        stopPanelMouseMonitor()
        
        // Execute hovered item if in hold mode
        if isInHoldMode {
            executeHoveredItemIfInHoldMode()
        }
        
        // Stop gesture monitoring
        gestureManager?.stopMonitoring()
        
        // Hide UI
        isVisible = false
        overlayWindow?.hideOverlay()
        listPanelManager?.hide()
        
        // Reset hold mode
        isInHoldMode = false
        
        // Restore previous app if not intentionally switching
        if !isIntentionallySwitching {
            if let prevApp = previousApp, !prevApp.isTerminated {
                print("   Restoring focus to: \(prevApp.localizedName ?? "Unknown")")
                prevApp.activate()
            }
        } else {
            print("   Skipping restore - intentionally switching")
        }
        
        // Reset state
        inputCoordinator?.reset()
        previousApp = nil
        isIntentionallySwitching = false
        
        print("[PanelUIManager-\(configId)] Hidden")
    }
    
    func ignoreFocusChangesTemporarily(duration: TimeInterval) {
        overlayWindow?.ignoreFocusChangesTemporarily(duration: duration)
    }
    
    // MARK: - Provider Setup
    
    private func setupProviders() {
        print("[PanelUIManager-\(configId)] Setting up providers...")
        
        let factory = ProviderFactory(
            circularUIManager: nil,
            appSwitcherManager: AppSwitcherManager.shared
        )
        
        providers = factory.createProviders(from: configuration)
        
        for provider in providers {
            print("   Registered provider: \(provider.providerName)")
        }
        
        print("   Total providers: \(providers.count)")
    }
    
    private func loadProviderItems() -> [FunctionNode] {
        var allItems: [FunctionNode] = []
        
        func normalizeProviderName(_ name: String) -> String {
            return name
                .replacingOccurrences(of: "Provider", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "-", with: "")
                .lowercased()
        }
        
        for provider in providers {
            let providerConfig = configuration.providers.first {
                normalizeProviderName($0.providerType) == normalizeProviderName(provider.providerId)
            }
            
            var items = provider.provideFunctions()
            
            // If display mode is direct and provider returns a category wrapper, unwrap it
            if providerConfig?.effectiveDisplayMode == .direct {
                if items.count == 1,
                   items[0].type == .category,
                   let children = items[0].children {
                    items = children
                    print("   Unwrapped category for \(provider.providerName): \(items.count) items")
                }
            }
            
            allItems.append(contentsOf: items)
            print("   \(provider.providerName): \(items.count) items")
        }
        
        return allItems
    }
    
    // MARK: - Gesture Manager Setup
    
    private func setupGestureManager() {
        self.gestureManager = GestureManager()
        
        gestureManager?.onGesture = { [weak self] event in
            guard let self = self else { return }
            
            switch event.type {
            case .click(.left):
                self.handleLeftClick(event: event)
            case .click(.right):
                self.handleRightClick(event: event)
            default:
                break
            }
        }
    }
    
    // MARK: - Panel Callbacks Setup
    
    private func setupPanelCallbacks() {
        guard let handler = panelActionHandler else { return }
        
        // Wire panel item click callbacks through shared handler
        listPanelManager?.onItemLeftClick = { [weak handler] node, modifiers in
            handler?.handleLeftClick(node: node, modifiers: modifiers, fromLevel: 0)
        }
        
        listPanelManager?.onItemRightClick = { [weak handler] node, modifiers in
            handler?.handleRightClick(node: node, modifiers: modifiers)
        }
        
        listPanelManager?.onContextAction = { [weak handler] actionNode, modifiers in
            handler?.handleContextAction(actionNode: actionNode, modifiers: modifiers)
        }
        
        listPanelManager?.onItemHover = { [weak self] node, level, rowIndex in
            guard let self = self, let node = node else { return }
            
            // Only cascade for folders
            guard node.type == .folder else {
                self.listPanelManager?.popToLevel(level)
                return
            }
            
            // Check if this node's panel is already showing
            if let existingPanel = self.listPanelManager?.panelStack.first(where: { $0.level == level + 1 }),
               existingPanel.sourceNodeId == node.id {
                self.listPanelManager?.popToLevel(level + 1)
                return
            }
            
            // Extract identity
            let providerId = node.providerId
            let contentIdentifier = node.metadata?["folderURL"] as? String ?? node.previewURL?.path
            
            // Load children if already available
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
            
            // Dynamic loading
            guard node.needsDynamicLoading,
                  let providerId = node.providerId,
                  let provider = self.providers.first(where: { $0.providerId == providerId }) else {
                self.listPanelManager?.popToLevel(level)
                return
            }
            
            Task {
                let children = await provider.loadChildren(for: node)
                
                guard !children.isEmpty else {
                    await MainActor.run {
                        self.listPanelManager?.popToLevel(level)
                    }
                    return
                }
                
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
        
        listPanelManager?.onReloadContent = { [weak self] providerId, contentIdentifier in
            guard let self = self,
                  let provider = self.providers.first(where: { $0.providerId == providerId }) else {
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
            
            return await provider.loadChildren(for: reloadNode)
        }
        
        listPanelManager?.onAddItem = { [weak self] text, modifiers in
            guard let self = self,
                  let todoProvider = self.providers.first(where: { $0 is TodoListProvider }) as? TodoListProvider else { return }
            
            todoProvider.addTodo(title: text)
            self.listPanelManager?.refreshPanelItems(at: 0)
            
            if !modifiers.contains(.command) {
                self.hide()
            }
        }

        if let todoProvider = self.providers.first(where: { $0 is TodoListProvider }) as? TodoListProvider {
            todoProvider.onTodoChanged = { [weak self] in
                self?.listPanelManager?.refreshPanelItems(at: 0)
            }
        }
        
        // Wire todo change notifications
        if let todoProvider = self.providers.first(where: { $0 is TodoListProvider }) as? TodoListProvider {
            todoProvider.onTodoChanged = { [weak handler] in
                handler?.refreshPanelItems(at: 0)
            }
        }
        
        listPanelManager?.onExitToRing = { [weak self] in
            self?.hide()
        }
    }
    
    // MARK: - Overlay Window Setup
    
    private func setupOverlayWindow() {
        overlayWindow = OverlayWindow()
        
        overlayWindow?.onLostFocus = { [weak self] in
            self?.hide()
        }
        
        overlayWindow?.onSearchToggle = { [weak self] in
            self?.listPanelManager?.activateSearch()
        }

        overlayWindow?.onEscapePressed = { [weak self] in
            return self?.listPanelManager?.handleSearchEscape() ?? false
        }
        
        guard let panelManager = listPanelManager else {
            print("[PanelUIManager] ListPanelManager not initialized")
            return
        }
        
        let contentView = PanelOnlyView(
            panelUIManager: self,
            listPanelManager: panelManager
        )
        overlayWindow?.contentView = NSHostingView(rootView: contentView)
    }
    
    // MARK: - Mouse Monitor
    
    private func startPanelMouseMonitor() {
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
    }
    
    private func stopPanelMouseMonitor() {
        if let monitor = panelMouseMonitor {
            NSEvent.removeMonitor(monitor)
            panelMouseMonitor = nil
        }
    }
    
    // MARK: - Click Handlers

    private func handleLeftClick(event: GestureManager.GestureEvent) {
        guard isVisible else { return }
        
        // Skip if context menu is open
        if listPanelManager?.panelStack.contains(where: { $0.expandedItemId != nil }) == true {
            for i in listPanelManager!.panelStack.indices {
                listPanelManager!.panelStack[i].expandedItemId = nil
            }
            return
        }
        
        if let result = listPanelManager?.handleLeftClick(at: NSEvent.mouseLocation) {
            print("[PanelUIManager] Left click on: '\(result.node.name)' at level \(result.level)")
            panelActionHandler?.handleLeftClick(node: result.node, modifiers: NSEvent.modifierFlags, fromLevel: result.level)
        } else {
            hide()
        }
    }

    private func handleRightClick(event: GestureManager.GestureEvent) {
        guard isVisible else { return }
        
        // Let ListPanelManager's hit testing handle the right-click toggle
        if let panelManager = listPanelManager, panelManager.handleRightClick(at: NSEvent.mouseLocation) {
            return
        }
        
        hide()
    }
    
    // MARK: - Hold Mode
    
    private func executeHoveredItemIfInHoldMode() {
        guard isInHoldMode else { return }
        
        let autoExecuteEnabled = activeTrigger?.autoExecuteOnRelease ?? true
        guard autoExecuteEnabled else {
            print("[PanelUIManager] Auto-execute disabled")
            return
        }
        
        guard let panelManager = listPanelManager else { return }
        
        let activeLevel = panelManager.activePanelLevel
        guard let panel = panelManager.panelStack.first(where: { $0.level == activeLevel }),
              let hoveredIndex = panelManager.keyboardSelectedRow[activeLevel] ?? panelManager.hoveredRow[activeLevel],
              hoveredIndex < panel.items.count else {
            print("[PanelUIManager] No item hovered for auto-execute")
            return
        }
        
        let selectedNode = panel.items[hoveredIndex]
        print("[PanelUIManager] Auto-executing: \(selectedNode.name)")
        
        let behavior = selectedNode.onLeftClick.resolve(with: [])
        
        switch behavior {
        case .execute(let action), .executeKeepOpen(let action):
            action()
        default:
            break
        }
    }
}
