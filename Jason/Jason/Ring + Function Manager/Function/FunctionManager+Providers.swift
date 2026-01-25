//
//  FunctionManager+Providers.swift
//  Jason
//
//  Created by Timothy Velberg on 29/11/2025.
//

import Foundation

extension FunctionManager {
    
    // MARK: - Provider Management
    
    func registerProvider(_ provider: FunctionProvider, configuration: ProviderConfiguration? = nil) {
        providers.append(provider)
        
        if let config = configuration {
            providerConfigurations[provider.providerId] = config
            print("Registered provider: \(provider.providerName) (displayMode: \(config.effectiveDisplayMode))")
        } else {
            print("Registered provider: \(provider.providerName)")
        }
    }
    
    func removeProvider(withId id: String) {
        providers.removeAll { $0.providerId == id }
        providerConfigurations.removeValue(forKey: id)
        print("🗑️ Removed provider: \(id)")
    }
    
    // MARK: - Data Loading
    
    func loadFunctions() {
        // Refresh all providers to get latest data
        for provider in providers {
            provider.refresh()
        }
        
        // Collect functions from all providers with spacer insertion
        var allNodes: [FunctionNode] = []
        var firstDirectModeProviderId: String? = nil
        var lastDirectModeProviderId: String? = nil
        
        for provider in providers {
            let providerNodes = provider.provideFunctions()
            let transformedNodes = applyDisplayMode(providerNodes, providerId: provider.providerId)
            
            // Check if this provider is in direct mode
            let isDirectMode = providerConfigurations[provider.providerId]?.effectiveDisplayMode == .direct
            
            // Determine if we should insert a spacer
            // Spacer goes between two direct-mode providers that both contributed nodes
            if isDirectMode && !transformedNodes.isEmpty {
                if let lastProviderId = lastDirectModeProviderId {
                    // Insert spacer between previous direct-mode provider and this one
                    let spacer = FunctionNode.spacer(afterProvider: lastProviderId)
                    allNodes.append(spacer)
                    print("➕ [Spacer] Inserted between '\(lastProviderId)' and '\(provider.providerId)'")
                }
                
                // Track first direct-mode provider for wrap-around spacer
                if firstDirectModeProviderId == nil {
                    firstDirectModeProviderId = provider.providerId
                }
                lastDirectModeProviderId = provider.providerId
            } else if !isDirectMode {
                // Category mode resets the chain (no spacer before categories)
                lastDirectModeProviderId = nil
            }
            
            allNodes.append(contentsOf: transformedNodes)
        }
        
        // Add wrap-around spacer if we have multiple direct-mode providers
        // This separates the last provider's items from the first provider's items in the circular layout
        if let firstId = firstDirectModeProviderId,
           let lastId = lastDirectModeProviderId,
           firstId != lastId {
            let spacer = FunctionNode.spacer(afterProvider: lastId)
            allNodes.append(spacer)
            print("➕ [Spacer] Inserted after '\(lastId)' (wrap-around to '\(firstId)')")
        }
        
        rootNodes = allNodes
        rebuildRings()
    }
    
    // MARK: - Display Mode Transformation
    
    /// Transform provider output based on display mode configuration
    func applyDisplayMode(
        _ nodes: [FunctionNode],
        providerId: String
    ) -> [FunctionNode] {
        
        print("🔍 [DisplayMode] Called for providerId: \(providerId), hasConfig: \(providerConfigurations[providerId] != nil)")

        
        guard let providerConfig = providerConfigurations[providerId] else {
            return nodes
        }
        
        let displayMode = providerConfig.effectiveDisplayMode
        
        guard displayMode == .direct else {
            return nodes
        }
        
        // Direct mode: Extract children from category nodes
        let transformedNodes = nodes.flatMap { node -> [FunctionNode] in
            guard node.type == .category else {
                return [node]
            }
            
            if let children = node.children, !children.isEmpty {
                print("🔄 [DisplayMode] Extracting \(children.count) children from category '\(node.name)' (provider: \(providerId))")
                
                return children.map { child in
                    if child.providerId != providerId {
                        return child.withProviderId(providerId)
                    }
                    return child
                }
            } else {
                print("⚠️ [DisplayMode] Category '\(node.name)' has no children in direct mode (provider: \(providerId))")
                return [node]
            }
        }
        
        return transformedNodes
    }
    
    // MARK: - Surgical Ring Updates
    
    /// Update a specific ring with fresh data from its provider
    func updateRing(providerId: String, contentIdentifier: String? = nil) {
        print("🔄 [updateRing] Looking for ring with providerId: \(providerId), contentId: \(contentIdentifier ?? "nil")")
        
        guard let provider = providers.first(where: { $0.providerId == providerId }) else {
            print("❌ Provider '\(providerId)' not found")
            return
        }
        
        for (level, ring) in rings.enumerated() {
            let providerMatches: Bool
            if ring.providerId == providerId {
                providerMatches = true
            } else if ring.providerId == nil {
                providerMatches = ring.nodes.contains { node in
                    node.providerId == providerId && node.type != .category
                }
            } else {
                providerMatches = false
            }
            
            let contentMatches = contentIdentifier == nil || ring.contentIdentifier == contentIdentifier
            
            if providerMatches && contentMatches {
                print("✅ Found matching ring at level \(level)")
                
                if level + 1 < rings.count {
                    print("🗑️ Closing \(rings.count - level - 1) child ring(s) before update")
                    collapseToRing(level: level)
                }
                
                provider.refresh()
                
                if level == 0 {
                    updateRing0(provider: provider, providerId: providerId)
                } else {
                    updateChildRing(level: level, provider: provider, providerId: providerId, contentIdentifier: contentIdentifier)
                }
                
                return
            }
        }
        
        print("⚠️ No matching ring found for providerId: \(providerId), contentId: \(contentIdentifier ?? "nil")")
    }
    
    // MARK: - Private Update Helpers
    
    private func updateRing0(provider: FunctionProvider, providerId: String) {
        let providerNodes = provider.provideFunctions()
        let updatedRootNodes = applyDisplayMode(providerNodes, providerId: providerId)
        
        let providerOrder = providers.map { $0.providerId }
        
        // First pass: collect all non-spacer nodes in provider order
        var newRing0Nodes: [FunctionNode] = []
        
        for orderedProviderId in providerOrder {
            if orderedProviderId == providerId {
                newRing0Nodes.append(contentsOf: updatedRootNodes)
            } else {
                // Filter out spacers - we'll re-add them after
                let existingNodes = rings[0].nodes.filter {
                    $0.providerId == orderedProviderId && $0.type != .spacer
                }
                newRing0Nodes.append(contentsOf: existingNodes)
                print("   🔍 Provider '\(orderedProviderId)': found \(existingNodes.count) existing nodes")
            }
        }
        
        // Second pass: re-insert spacers between direct-mode providers
        var nodesWithSpacers: [FunctionNode] = []
        var firstDirectModeProviderId: String? = nil
        var lastDirectModeProviderId: String? = nil
        
        for orderedProviderId in providerOrder {
            let isDirectMode = providerConfigurations[orderedProviderId]?.effectiveDisplayMode == .direct
            let providerNodes = newRing0Nodes.filter { $0.providerId == orderedProviderId }
            
            if isDirectMode && !providerNodes.isEmpty {
                if let lastProviderId = lastDirectModeProviderId {
                    let spacer = FunctionNode.spacer(afterProvider: lastProviderId)
                    nodesWithSpacers.append(spacer)
                    print("   ➕ [Spacer] Re-inserted between '\(lastProviderId)' and '\(orderedProviderId)'")
                }
                
                if firstDirectModeProviderId == nil {
                    firstDirectModeProviderId = orderedProviderId
                }
                lastDirectModeProviderId = orderedProviderId
            } else if !isDirectMode {
                lastDirectModeProviderId = nil
            }
            
            nodesWithSpacers.append(contentsOf: providerNodes)
        }
        
        // Add wrap-around spacer if needed
        if let firstId = firstDirectModeProviderId,
           let lastId = lastDirectModeProviderId,
           firstId != lastId {
            let spacer = FunctionNode.spacer(afterProvider: lastId)
            nodesWithSpacers.append(spacer)
            print("   ➕ [Spacer] Re-inserted after '\(lastId)' (wrap-around to '\(firstId)')")
        }
        
        let processedNodes = applyRing0OverflowIfNeeded(nodesWithSpacers)
        
        rings[0].nodes = processedNodes
        rings[0].hoveredIndex = nil
        rings[0].selectedIndex = nil
        
        print("✅ Updated Ring 0: replaced nodes from provider '\(providerId)'")
    }
    
    private func updateChildRing(level: Int, provider: FunctionProvider, providerId: String, contentIdentifier: String?) {
        guard level > 0, level - 1 < rings.count else {
            print("❌ Cannot find parent ring for level \(level)")
            return
        }
        
        let parentRing = rings[level - 1]
        guard let selectedIndex = parentRing.selectedIndex,
              selectedIndex < parentRing.nodes.count else {
            print("❌ No selected node in parent ring")
            return
        }
        
        let freshRootNodes = provider.provideFunctions()
        
        if level == 1 && !freshRootNodes.isEmpty {
            let freshParentNode = freshRootNodes[0]
            
            if let parentIndex = rings[0].nodes.firstIndex(where: { $0.providerId == providerId }) {
                print("🔄 Updating Ring 0's '\(freshParentNode.name)' node with fresh children")
                rings[0].nodes[parentIndex] = freshParentNode
            }
            
            if freshParentNode.needsDynamicLoading {
                Task { @MainActor in
                    let loadedNodes = await provider.loadChildren(for: freshParentNode)
                    
                    guard level < self.rings.count,
                          self.rings[level].providerId == providerId,
                          self.rings[level].contentIdentifier == contentIdentifier else {
                        print("⚠️ Ring changed during async load - ignoring update")
                        return
                    }
                    
                    let truncatedNodes = Array(loadedNodes.prefix(self.maxItems))
                    if loadedNodes.count > self.maxItems {
                        print("   ✂️ Truncated Ring \(level) from \(loadedNodes.count) to \(truncatedNodes.count) items")
                    }
                    
                    self.rings[level].nodes = truncatedNodes
                    self.rings[level].hoveredIndex = nil
                    self.rings[level].selectedIndex = nil
                    
                    print("✅ Updated Ring \(level) with \(truncatedNodes.count) dynamically loaded nodes")
                }
            } else {
                let freshNodes = freshParentNode.displayedChildren
                
                let truncatedNodes = Array(freshNodes.prefix(maxItems))
                if freshNodes.count > maxItems {
                    print("   ✂️ Truncated Ring \(level) from \(freshNodes.count) to \(truncatedNodes.count) items")
                }
                
                rings[level].nodes = truncatedNodes
                rings[level].hoveredIndex = nil
                rings[level].selectedIndex = nil
                
                print("✅ Updated Ring \(level) with \(truncatedNodes.count) nodes")
            }
        } else {
            print("⚠️ Cannot get fresh parent node for Ring \(level)")
        }
    }
}

