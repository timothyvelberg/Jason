//
//  RingPreviewView.swift
//  Jason
//
//  A self-contained preview component that renders a ring visualization
//  using mock data based on actual providers. Used in settings screens
//  to show live previews as users adjust ring geometry.
//

import SwiftUI
import AppKit

struct RingPreviewView: View {
    // MARK: - Geometry Inputs
    
    let centerHoleRadius: CGFloat
    let ringRadius: CGFloat
    let iconSize: CGFloat
    
    // MARK: - Provider Configuration
    
    /// Providers to generate mock content for
    var providers: [ProviderConfiguration] = []
    
    // MARK: - Layout Inputs (with defaults)
    
    var layoutStyle: LayoutStyle = .fullCircle
    var slicePositioning: SlicePositioning = .startClockwise
    var selectedIndex: Int? = nil
    
    // MARK: - Preview Configuration
    
    /// Target size for the preview (the view will scale to fit)
    var previewSize: CGFloat = 200
    
    // MARK: - Computed Properties
    
    /// The actual ring diameter based on geometry
    private var ringDiameter: CGFloat {
        (centerHoleRadius + ringRadius) * 2
    }
    
    /// Scale factor to fit ring within preview size
    private var scaleFactor: CGFloat {
        // Add some padding so the ring doesn't touch edges
        let targetSize = previewSize - 20
        return min(targetSize / ringDiameter, 1.0)
    }
    
    /// Generate mock nodes based on providers
    private var mockNodes: [FunctionNode] {
        if providers.isEmpty {
            // Fallback to generic icons if no providers
            return RingPreviewView.generateGenericNodes(count: 6)
        }
        return RingPreviewView.generateProviderNodes(for: providers)
    }
    
    /// Build slice configuration based on layout settings
    private var sliceConfig: PieSliceConfig {
        let itemCount = mockNodes.count
        let itemAngle = 360.0 / Double(max(itemCount, 1))
        
        switch layoutStyle {
        case .fullCircle:
            return PieSliceConfig.fullCircle(
                itemCount: itemCount,
                anglePerItem: itemAngle,
                positioning: slicePositioning
            )
        case .partialSlice:
            // For preview, center partial slice at top (270°)
            return PieSliceConfig.partialSlice(
                itemCount: itemCount,
                centeredAt: 270,
                defaultItemAngle: 30,
                positioning: slicePositioning
            )
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Background to show the preview bounds
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.05))
                .frame(width: previewSize, height: previewSize)
            
            // The actual ring preview
            RingView(
                startRadius: centerHoleRadius,
                thickness: ringRadius,
                nodes: mockNodes,
                selectedIndex: selectedIndex,
                shouldDimOpacity: false,
                sliceConfig: sliceConfig,
                iconSize: iconSize,
                triggerDirection: nil
            )
            .scaleEffect(scaleFactor)
            .frame(width: previewSize, height: previewSize)
        }
        .frame(width: previewSize, height: previewSize)
    }
    
    // MARK: - Provider-Based Mock Generation
    
    /// Mock content definitions for each provider type
    private static let providerMockContent: [String: [(symbol: String, name: String, type: FunctionNodeType)]] = [
        "CombinedAppsProvider": [
            ("app.fill", "Safari", .app),
            ("app.fill", "Finder", .app),
            ("app.fill", "Mail", .app),
        ],
        "FavoriteFilesProvider": [
            ("doc.fill", "Document", .file),
            ("photo.fill", "Image", .file),
        ],
        "FavoriteFolderProvider": [
            ("folder.fill", "Downloads", .folder),
            ("folder.fill", "Documents", .folder),
            ("folder.fill", "Desktop", .folder),
        ],
        "SystemActionsProvider": [
            ("lock.fill", "Lock", .action),
            ("moon.fill", "Sleep", .action),
        ],
        "WindowManagementProvider": [
            ("rectangle.lefthalf.filled", "Left Half", .action),
            ("rectangle.righthalf.filled", "Right Half", .action),
        ],
    ]
    
    /// Generate mock nodes for the configured providers
    static func generateProviderNodes(for providers: [ProviderConfiguration]) -> [FunctionNode] {
        var nodes: [FunctionNode] = []
        var nodeIndex = 0
        
        for provider in providers.sorted(by: { $0.order < $1.order }) {
            // Get mock content for this provider type
            let mockContent = providerMockContent[provider.providerType] ?? [
                ("questionmark.circle", provider.providerType, .action)
            ]
            
            // Check display mode - direct mode shows items, parent mode shows category
            let isDirectMode = provider.effectiveDisplayMode == .direct
            
            if isDirectMode {
                // Direct mode: show individual items from this provider
                for item in mockContent {
                    let icon = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.name)
                        ?? NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: "Unknown")!
                    
                    nodes.append(FunctionNode(
                        id: "preview-\(nodeIndex)",
                        name: item.name,
                        type: item.type,
                        icon: icon,
                        onLeftClick: ModifierAwareInteraction(base: .doNothing)
                    ))
                    nodeIndex += 1
                }
            } else {
                // Parent mode: show a single category icon
                // Use .action type for preview (not .category which requires children)
                let categoryIcon = categoryIcon(for: provider.providerType)
                let categoryName = categoryName(for: provider.providerType)
                
                let icon = NSImage(systemSymbolName: categoryIcon, accessibilityDescription: categoryName)
                    ?? NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: "Unknown")!
                
                nodes.append(FunctionNode(
                    id: "preview-\(nodeIndex)",
                    name: categoryName,
                    type: .action,  // Use .action for preview (avoids DEBUG assertion)
                    icon: icon,
                    onLeftClick: ModifierAwareInteraction(base: .doNothing)
                ))
                nodeIndex += 1
            }
        }
        
        return nodes
    }
    
    /// Get category icon for a provider type
    private static func categoryIcon(for providerType: String) -> String {
        switch providerType {
        case "CombinedAppsProvider": return "square.grid.2x2.fill"
        case "FavoriteFilesProvider": return "doc.on.doc.fill"
        case "FavoriteFolderProvider": return "folder.fill"
        case "SystemActionsProvider": return "gearshape.fill"
        case "WindowManagementProvider": return "uiwindow.split.2x1"
        default: return "circle.fill"
        }
    }
    
    /// Get category name for a provider type
    private static func categoryName(for providerType: String) -> String {
        switch providerType {
        case "CombinedAppsProvider": return "Apps"
        case "FavoriteFilesProvider": return "Files"
        case "FavoriteFolderProvider": return "Folders"
        case "SystemActionsProvider": return "System"
        case "WindowManagementProvider": return "Windows"
        default: return providerType
        }
    }
    
    /// Generate generic fallback nodes
    static func generateGenericNodes(count: Int) -> [FunctionNode] {
        let symbols = ["star.fill", "heart.fill", "bolt.fill", "flag.fill", "bell.fill", "tag.fill"]
        let names = ["Item 1", "Item 2", "Item 3", "Item 4", "Item 5", "Item 6"]
        
        return (0..<min(count, symbols.count)).map { index in
            let icon = NSImage(systemSymbolName: symbols[index], accessibilityDescription: names[index])
                ?? NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: "Unknown")!
            
            return FunctionNode(
                id: "preview-\(index)",
                name: names[index],
                type: .action,
                icon: icon,
                onLeftClick: ModifierAwareInteraction(base: .doNothing)
            )
        }
    }
}

// MARK: - Convenience Initializers

extension RingPreviewView {
    /// Initialize from a StoredRingConfiguration (uses actual providers)
    init(configuration: StoredRingConfiguration, previewSize: CGFloat = 200) {
        self.centerHoleRadius = CGFloat(configuration.centerHoleRadius)
        self.ringRadius = CGFloat(configuration.ringRadius)
        self.iconSize = CGFloat(configuration.iconSize)
        self.providers = configuration.providers
        self.previewSize = previewSize
        self.layoutStyle = .fullCircle
        self.slicePositioning = .startClockwise
        self.selectedIndex = nil
    }
}

// MARK: - Preview Provider

#if DEBUG
struct RingPreviewView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 30) {
            // No providers - shows generic icons
            RingPreviewView(
                centerHoleRadius: 60,
                ringRadius: 80,
                iconSize: 32
            )
            
            // With mock providers - shows provider-specific icons
            RingPreviewView(
                centerHoleRadius: 60,
                ringRadius: 80,
                iconSize: 32,
                providers: [
                    ProviderConfiguration(id: 1, providerType: "CombinedAppsProvider", order: 1, parentItemAngle: nil, config: nil),
                    ProviderConfiguration(id: 2, providerType: "FavoriteFolderProvider", order: 2, parentItemAngle: nil, config: nil),
                ]
            )
        }
        .padding()
        .background(Color.gray.opacity(0.1))
    }
}
#endif
