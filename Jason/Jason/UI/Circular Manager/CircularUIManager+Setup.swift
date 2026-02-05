//
//  CircularUIManager+Setup.swift
//  Jason
//
//  Created by Timothy Velberg on 29/01/2026.

import Foundation
import AppKit
import SwiftUI

extension CircularUIManager {
    
    func setup() {
        // Create FunctionManager with configuration values
        self.functionManager = FunctionManager(
            ringThickness: CGFloat(ringConfiguration.ringRadius),
            centerHoleRadius: CGFloat(ringConfiguration.centerHoleRadius),
            iconSize: CGFloat(ringConfiguration.iconSize),
            startAngle: CGFloat(ringConfiguration.startAngle)
        )
        print("   FunctionManager initialized with config values")
        
        // Create ListPanelManager
        self.listPanelManager = ListPanelManager()
        print("   ListPanelManager initialized")
        
        // Create InputCoordinator
        self.inputCoordinator = InputCoordinator()
        print("   InputCoordinator initialized")
        
        // Create PanelActionHandler
        self.panelActionHandler = PanelActionHandler()
        panelActionHandler?.listPanelManager = listPanelManager
        panelActionHandler?.findProvider = { [weak self] providerId in
            self?.functionManager?.providers.first { $0.providerId == providerId }
        }
        panelActionHandler?.hideUI = { [weak self] in
            self?.hide()
        }
        print("   PanelActionHandler initialized")
        
        // Create provider factory
        let factory = ProviderFactory(
            circularUIManager: self,
            appSwitcherManager: AppSwitcherManager.shared
        )
        
        // Create providers from configuration
        print("   [Setup] Loading providers from configuration")
        print("   Configuration: \(ringConfiguration.name)")
        print("   Providers: \(ringConfiguration.providers.count)")
        
        let providers = factory.createProviders(from: ringConfiguration)
        
        // Helper to normalize provider names for matching
        // Converts both "CombinedAppsProvider" (class name) and "combined-apps" (providerId) to same form
        func normalizeProviderName(_ name: String) -> String {
            return name
                .replacingOccurrences(of: "Provider", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "-", with: "")
                .lowercased()
        }
        
        print("[Setup] Available config providerTypes: \(ringConfiguration.providers.map { $0.providerType })")

        // Register all providers with their configurations
        for provider in providers {
            // Look up this provider's configuration by matching normalized names
            let normalizedProviderId = normalizeProviderName(provider.providerId)
            
            print("[Setup] Matching '\(provider.providerId)' → normalized: '\(normalizedProviderId)'")

            let providerConfig = ringConfiguration.providers.first { config in
                let normalizedConfigType = normalizeProviderName(config.providerType)
                return normalizedConfigType == normalizedProviderId
            }
            
            if let config = providerConfig {
                functionManager?.registerProvider(provider, configuration: config)
                print("      Registered '\(provider.providerName)' (providerId: \(provider.providerId)) with config")
                print("      displayMode: \(config.effectiveDisplayMode)")
            } else {
                functionManager?.registerProvider(provider, configuration: nil)
                print("      Registered '\(provider.providerName)' (providerId: \(provider.providerId)) WITHOUT config")
                print("      Available configs: \(ringConfiguration.providers.map { $0.providerType }.joined(separator: ", "))")
            }
            
            // Store references for specific provider types
            if let combinedApps = provider as? CombinedAppsProvider {
                self.combinedAppsProvider = combinedApps
            }
            if let favoriteFiles = provider as? FavoriteFilesProvider {
                self.favoriteFilesProvider = favoriteFiles
            }
        }
        
        print("   Registered \(providers.count) provider(s)")

        setupMouseTracker()
        setupGestureManager()
        setupPanelCallbacks()
        setupOverlayWindow()
    }
    
    // MARK: - Mouse Tracker Setup
    
    private func setupMouseTracker() {
        guard let functionManager = functionManager else { return }
        
        self.mouseTracker = MouseTracker(functionManager: functionManager)
        
        mouseTracker?.inputCoordinator = inputCoordinator
        listPanelManager?.inputCoordinator = inputCoordinator
        
        mouseTracker?.onExecuteAction = { [weak self] in
            self?.hide()
        }
        
        mouseTracker?.onPieHover = { [weak self, weak functionManager] pieIndex in
            guard let self = self else { return }
            if self.shouldIgnoreRingMouseEvents() { return }
            
            if let functionManager = functionManager, let pieIndex = pieIndex {
                functionManager.hoverNode(ringLevel: functionManager.activeRingLevel, index: pieIndex)
            }
        }
        
        mouseTracker?.onCollapse = { [weak self] in
            guard let self = self else { return }
            if self.shouldIgnoreRingMouseEvents() { return }
            
            self.listPanelManager?.hide()
        }
        
        mouseTracker?.onReturnedInsideBoundary = { [weak self] in
            guard let self = self else { return }
            if self.shouldIgnoreRingMouseEvents() { return }
            
            self.listPanelManager?.hide()
        }
        
        mouseTracker?.isMouseInPanel = { [weak self] in
            guard let self = self else { return false }
            let mousePos = NSEvent.mouseLocation
            return self.listPanelManager?.isInPanelZone(point: mousePos) ?? false
        }
        
        mouseTracker?.onExpandToPanel = { [weak self] node, angle, ringCenter, ringOuterRadius in
            guard let self = self else { return }
            if self.shouldIgnoreRingMouseEvents() { return }
            
            // Extract identity from node
            let providerId = node.providerId
            let contentIdentifier = node.metadata?["folderURL"] as? String ?? node.previewURL?.path
            
            let typingMode: TypingMode = {
                if let pid = providerId,
                   let provider = self.functionManager?.providers.first(where: { $0.providerId == pid }) {
                    return provider.defaultTypingMode
                }
                return .typeAhead
            }()
            
            print("[ExpandToPanel] node: '\(node.name)', providerId: \(providerId ?? "nil"), typingMode: \(typingMode)")

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
                    screen: self.overlayWindow?.currentScreen,
                    typingMode: typingMode
                )
                self.inputCoordinator?.focusPanel(level: 0)
                self.activateInputModeIfNeeded(for: providerId, atLevel: 0)
                self.mouseTracker?.pauseUntilMovement()
                return
            }
            
            // Children not loaded - check if we can load dynamically
            guard node.needsDynamicLoading,
                  let providerId = node.providerId,
                  let provider = self.functionManager?.providers.first(where: { $0.providerId == providerId }) else {
                print("[ExpandToPanel] Node '\(node.name)' has no children and can't load dynamically")
                return
            }
            
            // Load children asynchronously
            Task {
                let children = await provider.loadChildren(for: node)
                
                guard !children.isEmpty else {
                    print("[ExpandToPanel] No children loaded for: \(node.name)")
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
                        screen: self.overlayWindow?.currentScreen,
                        typingMode: typingMode
                    )
                    self.inputCoordinator?.focusPanel(level: 0)
                    self.activateInputModeIfNeeded(for: providerId, atLevel: 0)
                    self.mouseTracker?.pauseUntilMovement()
                }
            }
        }
    }
    
    private func activateInputModeIfNeeded(for providerId: String?, atLevel level: Int) {
        guard let providerId = providerId,
              let provider = functionManager?.providers.first(where: { $0.providerId == providerId }),
              provider.defaultTypingMode == .input,
              let index = listPanelManager?.panelStack.firstIndex(where: { $0.level == level }) else { return }
        
        listPanelManager?.panelStack[index].typingMode = .input
        listPanelManager?.panelStack[index].activeTypingMode = .input
        listPanelManager?.panelStack[index].isSearchActive = true
        listPanelManager?.panelStack[index].searchAnchorHeight = listPanelManager?.panelStack[index].panelHeight
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
            case .click(.middle):
                self.handleMiddleClick(event: event)
            case .dragStarted:
                self.handleDragStart(event: event)
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
                self.activateInputModeIfNeeded(for: providerId, atLevel: level + 1)
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
                    print("[Panel] No children loaded for: \(node.name)")
                    await MainActor.run {
                        self.listPanelManager?.popToLevel(level)
                    }
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
                    self.activateInputModeIfNeeded(for: providerId, atLevel: level + 1)
                }
            }
        }
        
        // Wire panel content reload callback
        listPanelManager?.onReloadContent = { [weak self] providerId, contentIdentifier in
            guard let self = self,
                  let provider = self.functionManager?.providers.first(where: { $0.providerId == providerId }) else {
                print("[Panel Reload] Provider '\(providerId)' not found")
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
            
            print("[Panel Reload] Reloading content for '\(contentIdentifier ?? "unknown")'")
            let freshChildren = await provider.loadChildren(for: reloadNode)
            print("[Panel Reload] Got \(freshChildren.count) items")
            
            return freshChildren
        }
        
        // Wire add item callback (used by TodoListProvider and similar)
        listPanelManager?.onAddItem = { [weak self, weak handler] text, modifiers in
            guard let self = self,
                  let todoProvider = self.functionManager?.providers.first(where: { $0 is TodoListProvider }) as? TodoListProvider else { return }
            
            todoProvider.addTodo(title: text)
            handler?.refreshPanelItems(at: 0)
            
            if !modifiers.contains(.command) {
                self.hide()
            }
        }
        
        // Wire todo change notifications
        if let todoProvider = self.functionManager?.providers.first(where: { $0 is TodoListProvider }) as? TodoListProvider {
            todoProvider.onTodoChanged = { [weak handler] in
                handler?.refreshPanelItems(at: 0)
            }
        }
        
        listPanelManager?.onExitToRing = { [weak self] in
            guard let self = self, let functionManager = self.functionManager else { return }
            
            // Clear panels
            self.listPanelManager?.hide()
            
            // Set focus back to ring
            self.inputCoordinator?.focusRing(level: functionManager.activeRingLevel)
            
            print("[CircularUIManager] Keyboard exit to ring level \(functionManager.activeRingLevel)")
        }
        
        // Wire mouse movement for panel sliding
        panelMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self = self else {
                print("[panelMouseMonitor] ⚠️ self is nil")
                return event
            }
            guard let panelManager = self.listPanelManager else {
                print("[panelMouseMonitor] ⚠️ listPanelManager is nil")
                return event
            }
            guard panelManager.isVisible else {
                return event
            }
            
            let mousePosition = NSEvent.mouseLocation
            panelManager.handleMouseMove(at: mousePosition)
            
            return event
        }
    }
    
    // MARK: - Overlay Window Setup
    
    func setupOverlayWindow() {
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
        overlayWindow?.onSearchToggle = { [weak self] in
            self?.listPanelManager?.activateSearch()
        }

        overlayWindow?.onEscapePressed = { [weak self] in
            return self?.listPanelManager?.handleSearchEscape() ?? false
        }
        
        let contentView = CircularUIView(
            circularUI: self,
            functionManager: functionManager,
            listPanelManager: self.listPanelManager!
        )
        overlayWindow?.contentView = NSHostingView(rootView: contentView)
    }
    
    // MARK: - Helper
    
    func shouldIgnoreRingMouseEvents() -> Bool {
        guard let panelManager = listPanelManager else { return false }
        return panelManager.isVisible && panelManager.isKeyboardDriven
    }
}
