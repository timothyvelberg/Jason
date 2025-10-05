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

// MARK: - FunctionCategory

struct FunctionCategory {
    let id: String
    let name: String
    let icon: NSImage
    let functions: [FunctionItem]
}

// MARK: - FunctionManager

class FunctionManager: ObservableObject {
    @Published var categories: [FunctionCategory] = []
    @Published var selectedCategoryIndex: Int = 0
    @Published var selectedFunctionIndex: Int = 0
    @Published var isShowingCategories: Bool = true
    
    private var appSwitcher: AppSwitcherManager?
    
    // Computed property for current display list
    var currentFunctionList: [FunctionItem] {
        if isShowingCategories {
            return categoriesToFunctionItems()
        } else {
            guard categories.indices.contains(selectedCategoryIndex) else { return [] }
            return categories[selectedCategoryIndex].functions
        }
    }
    
    // Computed property for current selection index
    var currentSelectedIndex: Int {
        return isShowingCategories ? selectedCategoryIndex : selectedFunctionIndex
    }
    
    init(appSwitcher: AppSwitcherManager) {
        self.appSwitcher = appSwitcher
        print("FunctionManager initialized")
    }
    
    private func categoriesToFunctionItems() -> [FunctionItem] {
        return categories.map { category in
            FunctionItem(
                id: category.id,
                name: category.name,
                icon: category.icon,
                action: {
                    self.openCategory()
                }
            )
        }
    }
    
    func loadFunctions() {
        guard let appSwitcher = appSwitcher else { return }
        
        let appFunctions = appSwitcher.runningApps.map { app in
            FunctionItem(
                id: "\(app.processIdentifier)",
                name: app.localizedName ?? "Unknown",
                icon: app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!,
                action: {
                    appSwitcher.switchToApp(app)
                }
            )
        }
        
        categories = [
            FunctionCategory(
                id: "apps",
                name: "Applications",
                icon: NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage(),
                functions: appFunctions
            )
        ]
        
        print("Loaded \(categories.count) categories with \(appFunctions.count) functions")
    }
    
    func loadMockFunctions() {
        let category1Functions = (1...4).map { index in
            FunctionItem(
                id: "cat1-func-\(index)",
                name: "Cat1 Function \(index)",
                icon: NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil) ?? NSImage(),
                action: { print("Cat1 Function \(index) executed") }
            )
        }
        
        let category2Functions = (1...3).map { index in
            FunctionItem(
                id: "cat2-func-\(index)",
                name: "Cat2 Function \(index)",
                icon: NSImage(systemSymbolName: "heart.fill", accessibilityDescription: nil) ?? NSImage(),
                action: { print("Cat2 Function \(index) executed") }
            )
        }
        
        let category3Functions = (1...5).map { index in
            FunctionItem(
                id: "cat3-func-\(index)",
                name: "Cat3 Function \(index)",
                icon: NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil) ?? NSImage(),
                action: { print("Cat3 Function \(index) executed") }
            )
        }
        
        let category4Functions = (1...6).map { index in
            FunctionItem(
                id: "cat4-func-\(index)",
                name: "Cat4 Function \(index)",
                icon: NSImage(systemSymbolName: "square.fill", accessibilityDescription: nil) ?? NSImage(),
                action: { print("Cat4 Function \(index) executed") }
            )
        }
        
        let category5Functions = (1...3).map { index in
            FunctionItem(
                id: "cat5-func-\(index)",
                name: "Cat5 Function \(index)",
                icon: NSImage(systemSymbolName: "triangle.fill", accessibilityDescription: nil) ?? NSImage(),
                action: { print("Cat5 Function \(index) executed") }
            )
        }
        
        let category6Functions = (1...4).map { index in
            FunctionItem(
                id: "cat6-func-\(index)",
                name: "Cat6 Function \(index)",
                icon: NSImage(systemSymbolName: "diamond.fill", accessibilityDescription: nil) ?? NSImage(),
                action: { print("Cat6 Function \(index) executed") }
            )
        }
        
        categories = [
            FunctionCategory(
                id: "category-1",
                name: "Category 1",
                icon: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage(),
                functions: category1Functions
            ),
            FunctionCategory(
                id: "category-2",
                name: "Category 2",
                icon: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage(),
                functions: category2Functions
            ),
            FunctionCategory(
                id: "category-3",
                name: "Category 3",
                icon: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage(),
                functions: category3Functions
            ),
            FunctionCategory(
                id: "category-4",
                name: "Category 4",
                icon: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage(),
                functions: category4Functions
            ),
            FunctionCategory(
                id: "category-5",
                name: "Category 5",
                icon: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage(),
                functions: category5Functions
            ),
            FunctionCategory(
                id: "category-6",
                name: "Category 6",
                icon: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage(),
                functions: category6Functions
            )
        ]
        
        print("Loaded \(categories.count) mock categories for testing")
    }
    
    func openCategory() {
        isShowingCategories = false
        selectedFunctionIndex = 0
        print("Opened category: \(categories[selectedCategoryIndex].name)")
    }
    
    func closeCategory() {
        isShowingCategories = true
        selectedFunctionIndex = 0
        print("Closed category, back to category view")
    }
    
    func selectFunction(at index: Int) {
        guard index >= 0, index < currentFunctionList.count else { return }
        
        if isShowingCategories {
            selectedCategoryIndex = index
        } else {
            selectedFunctionIndex = index
        }
        
        print("Selected at index \(index): \(currentFunctionList[index].name)")
    }
}
