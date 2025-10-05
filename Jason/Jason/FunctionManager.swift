//
//  FunctionManager.swift
//  Jason
//
//  Created by Timothy Velberg on 31/07/2025.
//

import Foundation
import AppKit
import SwiftUI

// MARK: - FunctionItem

struct FunctionItem {
    let id: String
    let name: String
    let icon: NSImage
    let action: () -> Void
}

// MARK: - FunctionManager

class FunctionManager: ObservableObject {
    @Published var currentFunctionList: [FunctionItem] = []
    @Published var selectedFunctionIndex: Int = 0
    
    private var appSwitcher: AppSwitcherManager?
    
    init(appSwitcher: AppSwitcherManager) {
        self.appSwitcher = appSwitcher
        print("FunctionManager initialized")
    }
    
    func loadFunctions() {
        // Load from app switcher provider
        if let appSwitcher = appSwitcher {
            currentFunctionList = appSwitcher.runningApps.map { app in
                FunctionItem(
                    id: "\(app.processIdentifier)",
                    name: app.localizedName ?? "Unknown",
                    icon: app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!,
                    action: {
                        appSwitcher.switchToApp(app)
                    }
                )
            }
            print("Loaded \(currentFunctionList.count) functions")
        }
    }
    
    func loadMockFunctions() {
        currentFunctionList = (1...8).map { index in
            FunctionItem(
                id: "mock-\(index)",
                name: "Function \(index)",
                icon: NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage(),
                action: {
                    print("Mock function \(index) executed")
                }
            )
        }
        
        print("Loaded \(currentFunctionList.count) mock functions for testing")
    }
    
    func selectFunction(at index: Int) {
        guard index >= 0, index < currentFunctionList.count else { return }
        selectedFunctionIndex = index
        print("Selected function at index \(index): \(currentFunctionList[index].name)")
    }
}
