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
        
        // Initialize mouse tracker with function manager
        if let functionManager = functionManager {
            self.mouseTracker = MouseTracker(functionManager: functionManager)
            
            // Set up hover callback
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
        
        // Set the CircularUIView as the window's content
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
        
        // Load functions
        functionManager.loadFunctions()
        
        // If no functions, load mock data for testing
        if functionManager.currentFunctionList.isEmpty {
            print("No functions found, loading mock data for testing")
            functionManager.loadMockFunctions()
        }
        
        // Don't show if still no functions available
        guard !functionManager.currentFunctionList.isEmpty else {
            print("No functions to display")
            return
        }
        
        // Capture current mouse position
        mousePosition = NSEvent.mouseLocation
        isVisible = true
        overlayWindow?.showOverlay(at: mousePosition)
        
        // Start tracking mouse movement
        mouseTracker?.startTrackingMouse()
        
        print("Showing circular UI at position: \(mousePosition)")
    }
    
    func hide() {
        // Stop tracking mouse
        mouseTracker?.stopTrackingMouse()
        
        isVisible = false
        overlayWindow?.hideOverlay()
        print("Hiding circular UI")
    }
    
    func executeSelectedFunction() {
        guard let functionManager = functionManager else { return }
        
        let selectedIndex = functionManager.selectedFunctionIndex
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
