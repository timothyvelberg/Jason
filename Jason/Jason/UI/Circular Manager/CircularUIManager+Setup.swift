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
        
        self.listPanelManager = ListPanelManager()
        listPanelManager?.findProvider = { [weak self] providerId in
            self?.functionManager?.providers.first { $0.providerId == providerId }
        }
        
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
        
        let providers = factory.createProviders(from: ringConfiguration)

        // Register all providers with their configurations
        for provider in providers {
            // Look up this provider's configuration by matching normalized names
            let normalizedProviderId = ProviderFactory.normalizeProviderName(provider.providerId)

            let providerConfig = ringConfiguration.providers.first { config in
                let normalizedConfigType = ProviderFactory.normalizeProviderName(config.providerType)
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
        mouseTracker?.circularUIManager = self
        
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
            
            // Resolve typing mode and panel config from provider
            let provider = providerId.flatMap { pid in
                self.functionManager?.providers.first(where: { $0.providerId == pid })
            }
            let typingMode: TypingMode = provider?.defaultTypingMode ?? .typeAhead
            let panelConfig: PanelConfig = provider?.panelConfig ?? .default
            
            print("[ExpandToPanel] node: '\(node.name)', providerId: \(providerId ?? "nil"), typingMode: \(typingMode)")
            
            // Check if we're spawning from a nested ring (need to pass main ring geometry)
            let mainRingGeometry: (center: CGPoint, outerRadius: CGFloat, thickness: CGFloat)?
            if let functionManager = self.functionManager,
               functionManager.rings.count > 1,
               let ring0Config = functionManager.ringConfigurations.first {
                // We have multiple rings - pass Ring 0's geometry including thickness
                let ring0OuterRadius = ring0Config.startRadius + ring0Config.thickness
                mainRingGeometry = (ringCenter, ring0OuterRadius, ring0Config.thickness)
                print("[ExpandToPanel] Detected nested ring - passing Ring 0 geometry (outerRadius: \(ring0OuterRadius), thickness: \(ring0Config.thickness))")
            } else {
                mainRingGeometry = nil
            }

            // Resolve panel items: prefer fresh data from provider, fall back to cached children
            let panelItems: [FunctionNode]
            if let providerId = providerId, let provider = provider, provider is any MutableListProvider {
                let fresh = provider.provideFunctions()
                if fresh.count == 1, fresh[0].type == .category, let c = fresh[0].children {
                    panelItems = c
                } else {
                    panelItems = fresh
                }
            } else if let children = node.children, !children.isEmpty {
                panelItems = children
            } else {
                panelItems = []
            }

            if !panelItems.isEmpty {
                self.listPanelManager?.show(
                    title: node.name,
                    items: panelItems,
                    ringCenter: ringCenter,
                    ringOuterRadius: ringOuterRadius,
                    angle: angle,
                    providerId: providerId,
                    contentIdentifier: contentIdentifier,
                    screen: self.overlayWindow?.currentScreen,
                    typingMode: typingMode,
                    config: panelConfig,
                    mainRing: mainRingGeometry
                )
                self.inputCoordinator?.focusPanel(level: 0)
                self.listPanelManager?.activateInputModeIfNeeded(for: providerId, atLevel: 0)
                self.mouseTracker?.pauseUntilMovement()
                return
            }
            
            // No items resolved - check if we can load dynamically
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
                        typingMode: typingMode,
                        config: provider.panelConfig,
                        mainRing: mainRingGeometry
                    )
                    self.inputCoordinator?.focusPanel(level: 0)
                    self.listPanelManager?.activateInputModeIfNeeded(for: providerId, atLevel: 0)
                    self.mouseTracker?.pauseUntilMovement()
                }
            }
        }
    }
    
    // MARK: - Gesture Manager Setup
    
    private func setupGestureManager() {
        self.gestureManager = GestureManager()
        
        gestureManager?.onGesture = { [weak self] event in
            guard let self = self else { return }
            
            switch event.type {
            case .mouseDown(.left):
                self.handleMouseDown(event: event)
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

        // Wire standard callbacks (click handling + reload)
        listPanelManager?.wireStandardCallbacks(handler: handler, providers: functionManager?.providers ?? [])
        
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
            guard let self = self else { return event }
            guard let panelManager = self.listPanelManager else { return event }
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
