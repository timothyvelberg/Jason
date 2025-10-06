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
        self.functionManager = FunctionManager(appSwitcher: appSwitcher)
        
        if let functionManager = functionManager {
            self.mouseTracker = MouseTracker(functionManager: functionManager)
            
            mouseTracker?.onPieHover = { pieIndex in
                guard pieIndex != nil else { return }
                print("Hovering over function at index: \(String(describing: pieIndex))")
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
            guard !functionManager.rootNodes.isEmpty else { return false }
            
            // Check if any root node has content
            for node in functionManager.rootNodes {
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
        print("Hiding circular UI")
    }
    
    func executeSelectedFunction() {
        guard let functionManager = functionManager else { return }
        
        let selectedIndex = functionManager.selectedIndex
        let currentFunctions = functionManager.currentFunctionList
        
        guard currentFunctions.indices.contains(selectedIndex) else {
            print("Invalid function index: \(selectedIndex)")
            return
        }
        
        let selectedFunction = currentFunctions[selectedIndex]
        print("Executing function: \(selectedFunction.name)")
        selectedFunction.action()
    }
}
