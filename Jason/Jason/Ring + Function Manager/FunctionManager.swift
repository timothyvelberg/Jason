//
//  FunctionManager.swift
//  Jason
//
//  Created by Timothy Velberg on 31/07/2025.
//

import Foundation
import AppKit
import SwiftUI

class FunctionManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published var rings: [RingState] = [] {
        didSet {
            if structuralChangeDetected(from: oldValue, to: rings) {
                print("🔄 [Cache] Structural change detected - invalidating cache")
                lastRingsHash = 0
                cachedConfigurations = []
            } else {
                print("✅ [Cache] No structural change - preserving cache (likely sliceConfig update)")
            }
        }
    }
    @Published var activeRingLevel: Int = 0
    @Published var ringResetTrigger: UUID = UUID()
    @Published var isLoadingFolder: Bool = false
    
    // MARK: - Internal State (accessed by extensions)
    
    var rootNodes: [FunctionNode] = []
    var navigationStack: [FunctionNode] = []
    var providers: [FunctionProvider] = []
    var providerConfigurations: [String: ProviderConfiguration] = [:]
    
    var maxItems: Int { configCalculator.maxItems }
    
    // MARK: - Private State
    
    private(set) var favoriteAppsProvider: FavoriteAppsProvider?
    
    private let configCalculator: RingConfigurationCalculator
    
    // MARK: - Cache for Ring Configurations
    
    private var cachedConfigurations: [RingConfiguration] = []
    private var lastRingsHash: Int = 0
    
    // MARK: - Initialization
    
    init(
        ringThickness: CGFloat,
        centerHoleRadius: CGFloat,
        iconSize: CGFloat,
        startAngle: CGFloat = 0.0
    ) {
        self.configCalculator = RingConfigurationCalculator(
            ringThickness: ringThickness,
            centerHoleRadius: centerHoleRadius,
            iconSize: iconSize,
            startAngle: startAngle
        )
        
        self.providers = []
        let appsProvider = FavoriteAppsProvider()
        self.favoriteAppsProvider = appsProvider
        
        print("🎯 [FunctionManager] Initialized with:")
        print("   - Ring Thickness: \(ringThickness)px")
        print("   - Icon Size: \(iconSize)px")
    }
    
    // MARK: - Computed Properties for UI
    
    var ringConfigurations: [RingConfiguration] {
        let currentHash = rings.map { $0.nodes.count }.reduce(0, ^) ^
                         activeRingLevel ^
                         rings.compactMap { $0.selectedIndex }.reduce(0, ^)
        
        if currentHash != lastRingsHash || cachedConfigurations.isEmpty {
            cachedConfigurations = configCalculator.calculateRingConfigurations(rings: rings)
            lastRingsHash = currentHash
            
            let configs = cachedConfigurations
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                for (index, config) in configs.enumerated() {
                    if index < self.rings.count {
                        self.rings[index].sliceConfig = config.sliceConfig
                    }
                }
            }
        }
        
        return cachedConfigurations
    }
    
    // MARK: - Hit Testing
    
    func getItemAt(position: CGPoint, centerPoint: CGPoint) -> (ringLevel: Int, itemIndex: Int, node: FunctionNode)? {
        let angle = RingGeometry.calculateAngle(from: centerPoint, to: position)
        let distance = RingGeometry.calculateDistance(from: centerPoint, to: position)
        
        guard let ringLevel = getRingLevel(at: distance) else {
            print("📍 Position at distance \(distance) is not in any ring")
            return nil
        }
        
        guard ringLevel < rings.count else { return nil }
        let nodes = rings[ringLevel].nodes
        guard !nodes.isEmpty else { return nil }
        
        let configs = ringConfigurations
        guard ringLevel < configs.count else { return nil }
        let sliceConfig = configs[ringLevel].sliceConfig
        
        if !sliceConfig.isFullCircle {
            if !RingGeometry.isAngleInSlice(angle, sliceConfig: sliceConfig) {
                print("📍 Angle \(angle)° is outside the slice")
                return nil
            }
        }

        let itemIndex = RingGeometry.getItemIndex(for: angle, sliceConfig: sliceConfig, itemCount: nodes.count)
        
        guard itemIndex >= 0, itemIndex < nodes.count else {
            print("📍 Invalid item index: \(itemIndex)")
            return nil
        }
        
        let node = nodes[itemIndex]
        print("📍 Found item at position: ring=\(ringLevel), index=\(itemIndex), name='\(node.name)'")
        
        return (ringLevel, itemIndex, node)
    }
    
    /// Determine which ring level a given distance falls into
    private func getRingLevel(at distance: CGFloat) -> Int? {
        let configs = ringConfigurations
        
        for config in configs {
            let ringInnerRadius = config.startRadius
            let ringOuterRadius = config.startRadius + config.thickness
            
            if distance >= ringInnerRadius && distance <= ringOuterRadius {
                return config.level
            }
        }
        
        if rings.count > 0 && distance > 0 {
            print("📍 Distance \(distance) is beyond all rings, treating as active ring \(activeRingLevel)")
            return activeRingLevel
        }
        
        return nil
    }
    
    // MARK: - State Management
    
    func reset() {
        navigationStack.removeAll()
        rings.removeAll()
        activeRingLevel = 0
        ringResetTrigger = UUID()
        cachedConfigurations.removeAll()
        lastRingsHash = 0
        print("FunctionManager state reset")
    }
    
    func rebuildRings() {
        rings.removeAll()
        
        let currentNodes = navigationStack.isEmpty ? rootNodes : (navigationStack.last?.children ?? [])
        
        guard !currentNodes.isEmpty else { return }
        
        let truncatedNodes = Array(currentNodes.prefix(maxItems))
        if currentNodes.count > maxItems {
            print("✂️ [rebuildRings] Truncated Ring 0 from \(currentNodes.count) to \(truncatedNodes.count) items")
        }
        
        rings.append(RingState(
            nodes: truncatedNodes,
            providerId: nil,
            contentIdentifier: nil
        ))
        
        if let ring0 = rings.first,
           let selectedIndex = ring0.selectedIndex,
           selectedIndex < ring0.nodes.count {
            let selectedNode = ring0.nodes[selectedIndex]
            if selectedNode.isBranch, let children = selectedNode.children, !children.isEmpty {
                let providerId = selectedNode.providerId
                let contentIdentifier = selectedNode.metadata?["folderURL"] as? String
                
                rings.append(RingState(
                    nodes: children,
                    providerId: providerId,
                    contentIdentifier: contentIdentifier
                ))
            }
        }
        
        print("Rebuilt rings: \(rings.count) ring(s)")
    }
    
    // MARK: - Structural Change Detection
    
    private func structuralChangeDetected(from oldRings: [RingState], to newRings: [RingState]) -> Bool {
        if oldRings.count != newRings.count {
            return true
        }
        
        for (index, newRing) in newRings.enumerated() {
            guard index < oldRings.count else { return true }
            let oldRing = oldRings[index]
            
            if oldRing.nodes.count != newRing.nodes.count {
                return true
            }
            
            if oldRing.hoveredIndex != newRing.hoveredIndex {
                return true
            }
            
            if oldRing.selectedIndex != newRing.selectedIndex {
                return true
            }
            
            if oldRing.isCollapsed != newRing.isCollapsed {
                return true
            }
            
            if oldRing.providerId != newRing.providerId ||
               oldRing.contentIdentifier != newRing.contentIdentifier {
                return true
            }
        }
        
        return false
    }
}
