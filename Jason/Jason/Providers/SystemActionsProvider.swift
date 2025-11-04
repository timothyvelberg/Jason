//
//  SystemActionsProvider.swift
//  Jason
//
//  Created by Timothy Velberg on 19/10/2025.
//

import Foundation
import AppKit

class SystemActionsProvider: ObservableObject, FunctionProvider {
    
    // MARK: - FunctionProvider Protocol
    
    var providerId: String {
        return "system-functions"
    }
    
    var providerName: String {
        return "System"
    }
    
    var providerIcon: NSImage {
        return NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: nil) ?? NSImage()
    }
    
    // MARK: - Initialization
    
    init() {
        print("⚙️ SystemFunctionsProvider initialized")
    }
    
    // MARK: - FunctionProvider Methods
    
    func provideFunctions() -> [FunctionNode] {
        let systemNodes = [
            // Mission Control
            FunctionNode(
                id: "mission-control",
                name: "Mission Control",
                icon: NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: nil) ?? NSImage(),
                preferredLayout: nil,
                showLabel: true,
                onLeftClick: ModifierAwareInteraction(base: .execute {
                    SystemActions.showMissionControl()
                }),
                onRightClick: ModifierAwareInteraction(base: .doNothing),
                onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                onBoundaryCross: ModifierAwareInteraction(base: .execute {
                    SystemActions.showMissionControl()
                })
            ),
            
            // Show Desktop
            FunctionNode(
                id: "show-desktop",
                name: "Show Desktop",
                icon: NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil) ?? NSImage(),
                preferredLayout: nil,
                showLabel: true,
                onLeftClick: ModifierAwareInteraction(base: .execute {
                    SystemActions.showDesktop()
                }),
                onRightClick: ModifierAwareInteraction(base:  .doNothing),
                onMiddleClick: ModifierAwareInteraction(base:  .doNothing),
                onBoundaryCross: ModifierAwareInteraction(base: .execute {
                    SystemActions.showDesktop()
                })
            )
        ]
        
        // Return as a single category node
        return [
            FunctionNode(
                id: providerId,
                name: providerName,
                icon: providerIcon,
                children: systemNodes,
                preferredLayout: .partialSlice,
                slicePositioning: .center,
                onLeftClick: ModifierAwareInteraction(base: .expand),
                onRightClick: ModifierAwareInteraction(base: .expand),
                onMiddleClick: ModifierAwareInteraction(base: .expand),
                onBoundaryCross: ModifierAwareInteraction(base: .expand),
            )
        ]
    }
    
    func refresh() {
        // Nothing to refresh for system functions
        print("⚙️ [SystemFunctionsProvider] Refresh called (no-op)")
    }
}
