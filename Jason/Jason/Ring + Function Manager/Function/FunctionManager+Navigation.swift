//
//  FunctionManager+Navigation.swift
//  Jason
//
//  Created by Timothy Velberg on 29/11/2025.
//

import Foundation

extension FunctionManager {
    
    // MARK: - Navigation
    
    func navigateInto(_ node: FunctionNode) {
        guard node.isBranch else {
            print("Cannot navigate into leaf node: \(node.name)")
            return
        }
        navigationStack.append(node)
        activeRingLevel = 0
        rebuildRings()
        print("Navigated into: \(node.name), depth: \(navigationStack.count)")
    }
    
    func navigateBack() {
        guard !navigationStack.isEmpty else {
            print("Already at root level")
            return
        }
        let previous = navigationStack.removeLast()
        activeRingLevel = 0
        rebuildRings()
        print("Navigated back from: \(previous.name), depth: \(navigationStack.count)")
    }
    
    // MARK: - Ring Interaction
    
    func hoverNode(ringLevel: Int, index: Int) {
        guard rings.indices.contains(ringLevel) else { return }
        guard rings[ringLevel].nodes.indices.contains(index) else { return }

        let node = rings[ringLevel].nodes[index]
        
        // Spacers are dead zones - clear hover and exit
        if node.type == .spacer {
            return
        }

        // Early return if already hovering this node
        if rings[ringLevel].hoveredIndex == index {
            return
        }
        
        // Call onHoverExit on previously hovered node
        if let prevIndex = rings[ringLevel].hoveredIndex,
           prevIndex != index,
           rings[ringLevel].nodes.indices.contains(prevIndex) {
            let prevNode = rings[ringLevel].nodes[prevIndex]
            prevNode.onHoverExit?()
        }
        
        rings[ringLevel].hoveredIndex = index
        
        // Call onHover on newly hovered node
        node.onHover?()
    }
    
    func selectNode(ringLevel: Int, index: Int) {
        guard rings.indices.contains(ringLevel) else { return }
        guard rings[ringLevel].nodes.indices.contains(index) else { return }
        
        rings[ringLevel].selectedIndex = index
        rings[ringLevel].hoveredIndex = index
        
        let node = rings[ringLevel].nodes[index]
        print("Selected ring \(ringLevel), index \(index): \(node.name)")
    }
    
    // MARK: - Category Expansion
    
    func expandCategory(ringLevel: Int, index: Int, openedByClick: Bool = false) {
        
        guard rings.indices.contains(ringLevel) else {
            print("Invalid ring level: \(ringLevel)")
            return
        }
        guard rings[ringLevel].nodes.indices.contains(index) else {
            print("Invalid node index: \(index) for ring level: \(ringLevel)")
            return
        }
        
        let node = rings[ringLevel].nodes[index]
        
        // Use displayedChildren which respects maxDisplayedChildren limit
        let displayedChildren = node.displayedChildren
        
        // Truncate to maxItems to prevent ghost items in child rings
        let truncatedChildren = Array(displayedChildren.prefix(maxItems))
        if displayedChildren.count > maxItems {
            print("   Truncated children from \(displayedChildren.count) to \(truncatedChildren.count) items")
        }
        
        print("   - displayedChildren count: \(truncatedChildren.count)")
        
        guard !truncatedChildren.isEmpty else {
            print("Cannot expand non-category or empty category: \(node.name)")
            return
        }
        
        // Select the node at this level
        rings[ringLevel].selectedIndex = index
        rings[ringLevel].hoveredIndex = index
        
        // Remove any rings beyond this level
        if ringLevel + 1 < rings.count {
            rings.removeSubrange((ringLevel + 1)...)
        }
        
        // Get context from the node
        let providerId = node.providerId
        let contentIdentifier = node.metadata?["folderURL"] as? String
        
        // Add new ring with displayed children and context tracking
        rings.append(RingState(
            nodes: truncatedChildren,
            isCollapsed: false,
            openedByClick: openedByClick,
            providerId: providerId,
            contentIdentifier: contentIdentifier
        ))
        activeRingLevel = ringLevel + 1
        
        print("Expanded category '\(node.name)' at ring \(ringLevel), created ring \(ringLevel + 1) with \(truncatedChildren.count) nodes (providerId: \(providerId ?? "nil"), contentId: \(contentIdentifier ?? "nil"))")
    }
    
    func loadAndExpandToCategory(providerId: String) {
        print("[FunctionManager] Loading and expanding to category: \(providerId)")
        
        // First, load all functions normally
        loadFunctions()
        
        // Verify we have a Ring 0
        guard !rings.isEmpty, !rings[0].nodes.isEmpty else {
            print("No Ring 0 available after loading")
            return
        }
        
        // Find the node with matching ID in Ring 0
        guard let index = rings[0].nodes.firstIndex(where: { $0.id == providerId }) else {
            print("Provider '\(providerId)' not found in Ring 0")
            print("   Available providers: \(rings[0].nodes.map { $0.id }.joined(separator: ", "))")
            return
        }
        
        let node = rings[0].nodes[index]
        
        // Verify it's expandable
        guard node.isBranch, !node.displayedChildren.isEmpty else {
            print("Provider '\(providerId)' is not expandable or has no children")
            return
        }
        
        print("Found provider '\(node.name)' at index \(index) with \(node.displayedChildren.count) children")
        
        // Expand this category with openedByClick: true
        // This makes it behave like a right-click context menu - stable until boundary cross
        expandCategory(ringLevel: 0, index: index, openedByClick: true)
        
        print("Successfully expanded to '\(node.name)' - now at Ring \(activeRingLevel)")
    }
    
    // MARK: - Folder Navigation
    
    func navigateIntoFolder(ringLevel: Int, index: Int) {
        print("navigateIntoFolder called: ringLevel=\(ringLevel), index=\(index)")
        
        if isLoadingFolder {
            print("Already loading a folder - ignoring navigation request")
            return
        }
        
        guard rings.indices.contains(ringLevel) else {
            print("Invalid ring level: \(ringLevel)")
            return
        }
        guard rings[ringLevel].nodes.indices.contains(index) else {
            print("Invalid node index: \(index) for ring level: \(ringLevel)")
            return
        }
        
        let node = rings[ringLevel].nodes[index]
        
        Task { @MainActor in
            isLoadingFolder = true
            
            let childrenToDisplay: [FunctionNode]
            
            if node.needsDynamicLoading {
                print("Node '\(node.name)' needs dynamic loading")
                
                guard let providerId = node.providerId else {
                    print("Node '\(node.name)' needs dynamic loading but has no providerId")
                    isLoadingFolder = false
                    return
                }
                
                guard let provider = providers.first(where: { $0.providerId == providerId }) else {
                    print("Provider '\(providerId)' not found")
                    isLoadingFolder = false
                    return
                }
                
                print("Loading children from provider '\(provider.providerName)'")
                childrenToDisplay = await provider.loadChildren(for: node)
                print("Loaded \(childrenToDisplay.count) children dynamically")
                
            } else {
                childrenToDisplay = node.displayedChildren
            }
            
            guard !childrenToDisplay.isEmpty else {
                print("Cannot navigate into empty folder: \(node.name)")
                isLoadingFolder = false
                return
            }
            
            // Truncate to maxItems to prevent ghost items
            let truncatedChildren = Array(childrenToDisplay.prefix(maxItems))
            if childrenToDisplay.count > maxItems {
                print("   Truncated folder children from \(childrenToDisplay.count) to \(truncatedChildren.count) items")
            }
            
            // Bounds check after async work
            guard rings.indices.contains(ringLevel),
                  rings[ringLevel].nodes.indices.contains(index) else {
                print("Ring or index out of bounds after async load - rings may have changed")
                isLoadingFolder = false
                return
            }
            
            rings[ringLevel].selectedIndex = index
            rings[ringLevel].hoveredIndex = index
            
            // Mark current ring as collapsed (if it's not Ring 0)
            if ringLevel > 0 {
                rings[ringLevel].isCollapsed = true
                print("Collapsed ring \(ringLevel)")
            }
            
            // Remove any rings beyond this level
            if ringLevel + 1 < rings.count {
                let removed = rings.count - (ringLevel + 1)
                rings.removeSubrange((ringLevel + 1)...)
                print("Removed \(removed) ring(s) beyond level \(ringLevel)")
            }
            
            // Add new ring with children
            let providerId = node.providerId
            let contentIdentifier = node.metadata?["folderURL"] as? String
            rings.append(RingState(
                nodes: truncatedChildren,
                isCollapsed: false,
                openedByClick: true,
                providerId: providerId,
                contentIdentifier: contentIdentifier
            ))
            
            activeRingLevel = ringLevel + 1
            isLoadingFolder = false
        }
    }
    
    func collapseToRing(level: Int) {
        guard level >= 0, level < rings.count else { return }
        
        // Uncollapse the target ring (we're returning to it)
        if level > 0 {
            rings[level].isCollapsed = false
            print("Uncollapsed ring \(level) - returning to normal size")
        }
        
        // Remove all rings after the specified level
        if level + 1 < rings.count {
            let removed = rings.count - (level + 1)
            rings.removeSubrange((level + 1)...)
            activeRingLevel = level
            print("Collapsed \(removed) ring(s), now at ring \(level)")
        }
    }
}
