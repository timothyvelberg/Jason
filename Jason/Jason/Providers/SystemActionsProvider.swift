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
        return [
            // Mission Control
            FunctionNode(
                id: "mission-control",
                name: "Mission Control",
                type: .action,
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
                type: .action,
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
            ),
            FunctionNode(
                id: "browse-files-ring",
                name: "Browse Files",
                type: .action,
                icon: NSImage(systemSymbolName: "folder.circle", accessibilityDescription: nil) ?? NSImage(),
                preferredLayout: nil,
                showLabel: true,
                onLeftClick: ModifierAwareInteraction(base: .launchRing(configId: 4)),
                onRightClick: ModifierAwareInteraction(base: .doNothing),
                onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                onBoundaryCross: ModifierAwareInteraction(base: .doNothing),  // Don't auto-launch on hover
                onHover: {
                       print("🔍 HOVER: Browse Files launcher (configId: 4)")
                }
            ),
            
            FunctionNode(
                id: "launch-apps-ring",
                name: "Quick Apps",
                type: .action,
                icon: NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage(),
                preferredLayout: nil,
                showLabel: true,
                onLeftClick: ModifierAwareInteraction(base: .doNothing),
                onRightClick: ModifierAwareInteraction(base: .doNothing),
                onMiddleClick: ModifierAwareInteraction(base: .doNothing),
                onBoundaryCross: ModifierAwareInteraction(base: .launchRing(configId: 2)),
                onHover: {
                       print("🔍 HOVER: Browse Files launcher (configId: 2)")
                }
            )
        ]
    }
    
    func refresh() {
        // Nothing to refresh for system functions
        print("⚙️ [SystemFunctionsProvider] Refresh called (no-op)")
    }
}
