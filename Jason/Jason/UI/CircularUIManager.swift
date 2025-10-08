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
    
    private var overlayWindow: OverlayWindow?
    private var appSwitcher: AppSwitcherManager?
    var functionManager: FunctionManager?
    private var mouseTracker: MouseTracker?
    
    init() {
        print("CircularUIManager initialized")
    }
    
    func setup(with appSwitcher: AppSwitcherManager) {
        self.appSwitcher = appSwitcher
        
        // Create FunctionManager with providers
        self.functionManager = FunctionManager()
        
        // Register AppSwitcher as a provider
        functionManager?.registerProvider(appSwitcher)
        
        // Register mock provider for testing (shows alongside real apps)
        functionManager?.registerProvider(MockFunctionProvider())
        
        if let functionManager = functionManager {
            self.mouseTracker = MouseTracker(functionManager: functionManager)
            
            mouseTracker?.onPieHover = { [weak functionManager] pieIndex in
                guard let pieIndex = pieIndex, let fm = functionManager else { return }
                
                let ringLevel = fm.activeRingLevel
                
                guard ringLevel < fm.rings.count else { return }
                let nodes = fm.rings[ringLevel].nodes
                
                if nodes.indices.contains(pieIndex) {
                    let node = nodes[pieIndex]
                    let type = node.isLeaf ? "FUNCTION" : "CATEGORY"
                    print("🎯 [RING \(ringLevel)] Hovering: index=\(pieIndex), name='\(node.name)', type=\(type)")
                    print("   hoveredIndex=\(fm.rings[ringLevel].hoveredIndex ?? -1), selectedIndex=\(fm.rings[ringLevel].selectedIndex ?? -1)")
                }
            }
        }
        
        setupOverlayWindow()
    }
    
    private func setupOverlayWindow() {
        guard let functionManager = functionManager else { return }
        
        overlayWindow = OverlayWindow()
        
        let contentView = CircularUIView(
            circularUI: self,
            functionManager: functionManager
        )
        overlayWindow?.contentView = NSHostingView(rootView: contentView)
        
        print("Overlay window created and configured")
    }
    
    func show() {
        guard let functionManager = functionManager else {
            print("FunctionManager not initialized")
            return
        }
        
        functionManager.loadFunctions()
        
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
        
        if !hasValidData {
            print("No valid function data, loading mock data for testing")
            functionManager.loadMockFunctions()
        }
        
        guard !functionManager.currentFunctionList.isEmpty else {
            print("No functions to display")
            return
        }
        
        mousePosition = NSEvent.mouseLocation
        isVisible = true
        overlayWindow?.showOverlay(at: mousePosition)
        
        mouseTracker?.startTrackingMouse()
        
        print("Showing circular UI at position: \(mousePosition)")
    }
    
    func hide() {
        mouseTracker?.stopTrackingMouse()
        
        isVisible = false
        overlayWindow?.hideOverlay()
        
        // Reset all state for clean slate on next show
        functionManager?.reset()
        
        print("Hiding circular UI")
    }
    
    func executeSelectedFunction() {
        guard let functionManager = functionManager else { return }
        functionManager.executeSelected()
    }
}
