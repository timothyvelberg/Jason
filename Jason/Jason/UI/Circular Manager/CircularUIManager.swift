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

class CircularUIManager: ObservableObject, UIManager {
    // MARK: - Published Properties
    
    @Published var isVisible: Bool = false
    @Published var mousePosition: CGPoint = .zero
    @Published var isInCloseZone: Bool = false
    
    // Drag support
    @Published var currentDragProvider: DragProvider?
    @Published var dragStartPoint: CGPoint?
    @Published var triggerDirection: RotationDirection? = nil
    
    // MARK: - Internal Properties
    
    var draggedNode: FunctionNode?
    var panelMouseMonitor: Any?
    var hasLeftCloseZone: Bool = false
    
    var overlayWindow: OverlayWindow?
    var combinedAppsProvider: CombinedAppsProvider?
    var favoriteFilesProvider: FavoriteFilesProvider?
    var functionManager: FunctionManager?
    var mouseTracker: MouseTracker?
    var gestureManager: GestureManager?
    var panelActionHandler: PanelActionHandler?
    
    var centerPoint: CGPoint = .zero
    var previousApp: NSRunningApplication?
    var isIntentionallySwitching: Bool = false
    
    var isInHoldMode: Bool = false
    var inputCoordinator: InputCoordinator?
    
    var listPanelManager: ListPanelManager?
    var activeTrigger: TriggerConfiguration?
    
    // MARK: - Configuration
    
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
        print("CircularUIManager deallocated - removed observers")
        
        if let monitor = panelMouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    func teardown() {
        print("[CircularUIManager-\(configId)] teardown() called")
        
        // 1. Hide if visible
        if isVisible {
            hide()
        }
        
        // 2. Break the retain cycle: NSHostingView -> CircularUIView -> @ObservedObject self
        // Break retain cycle and release callbacks
        overlayWindow?.contentView = nil
        overlayWindow?.onLostFocus = nil
        overlayWindow?.onScrollBack = nil
        overlayWindow?.onSearchToggle = nil
        overlayWindow?.onEscapePressed = nil
        overlayWindow?.orderOut(nil)
        
        // 3. Remove notification observer (don't rely on deinit)
        NotificationCenter.default.removeObserver(self)
        
        // 4. Remove mouse monitor
        if let monitor = panelMouseMonitor {
            NSEvent.removeMonitor(monitor)
            panelMouseMonitor = nil
        }
        
        // 5. Clean up FunctionManager (providers, nodes, caches)
        if let fm = functionManager {
            // Refresh providers to clear any internal caches
            for provider in fm.providers {
                provider.clearCache()
            }
            // Reset clears rings, navigation stack, cached configs
            fm.reset()
            // Clear what reset() misses
            fm.rootNodes.removeAll()
            fm.providers.removeAll()
            fm.providerConfigurations.removeAll()
        }
        
        // 6. Stop folder watchers owned by this instance's providers
        // (We'll address this more precisely in a later step)
        
        // 7. Nil out sub-objects to release their memory
        functionManager = nil
        mouseTracker = nil
        gestureManager = nil
        inputCoordinator = nil
        listPanelManager = nil
        panelActionHandler = nil
        overlayWindow = nil
        combinedAppsProvider = nil
        favoriteFilesProvider = nil
        
        print("[CircularUIManager-\(configId)] teardown complete")
    }
    
    // MARK: - Provider Update Handler

    @objc private func handleProviderUpdate(_ notification: Notification) {
        guard let updateInfo = ProviderUpdateInfo.from(notification) else {
            print("Invalid provider update notification")
            return
        }
        if let folderPath = updateInfo.folderPath {
            print("   Folder: \(folderPath)")
        }
        
        // Only update if UI is visible
        guard isVisible else {
            return
        }
        
        // Check if this provider is currently displayed in any ring
        guard let functionManager = functionManager else {
            print("   No FunctionManager")
            return
        }
        
        let needsUpdate = checkIfProviderIsVisible(
            providerId: updateInfo.providerId,
            contentIdentifier: updateInfo.folderPath
        )
        
        if needsUpdate {
            print("   Provider is visible - performing surgical update")
            functionManager.updateRing(
                providerId: updateInfo.providerId,
                contentIdentifier: updateInfo.folderPath
            )
        } else {
            print("   Provider not currently visible - ignoring")
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
                    print("   Found matching provider in Ring \(index)")
                    return true
                }
                
                // If content identifier specified, check it too
                if ring.contentIdentifier == contentIdentifier {
                    print("   Found matching provider + content in Ring \(index): \(contentIdentifier ?? "")")
                    return true
                }
            }
            
            // For mixed rings (providerId is nil), check individual nodes
            // This handles Ring 0 in direct mode where multiple providers' content is mixed
            // BUT: Only match actual content nodes, not category wrappers
            if ring.providerId == nil {
                let hasMatchingNode = ring.nodes.contains { node in
                    node.providerId == providerId && node.type != .category
                }
                if hasMatchingNode {
                    print("   Found provider '\(providerId)' in mixed Ring \(index) (via node check)")
                    return true
                }
            }
        }
        
        return false
    }
    
    // MARK: - Accessor for Configuration
    
    var ringConfiguration: StoredRingConfiguration {
        return configuration
    }
}
