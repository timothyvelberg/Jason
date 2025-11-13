//
//  EditRingView.swift
//  Jason
//
//  Ring configuration creation and editing interface
//

import SwiftUI
import AppKit

struct EditRingView: View {
    @Environment(\.dismiss) var dismiss
    
    // Configuration being edited (nil for new ring)
    let configuration: StoredRingConfiguration?
    let onSave: () -> Void
    
    // Form fields
    @State private var name: String = ""
    @State private var selectedShortcut: ShortcutOption = .ctrlShiftD
    @State private var ringRadius: String = "80"
    @State private var centerHoleRadius: String = "56"
    @State private var iconSize: String = "32"
    @State private var isActive: Bool = true
    
    // Provider selection
    @State private var includeCombinedApps: Bool = true
    @State private var combinedAppsMode: ProviderDisplayMode = .parent
    @State private var includeFavoriteFiles: Bool = false
    @State private var favoriteFilesMode: ProviderDisplayMode = .parent
    @State private var includeFinderLogic: Bool = false
    @State private var finderLogicMode: ProviderDisplayMode = .parent
    @State private var includeSystemActions: Bool = false
    @State private var systemActionsMode: ProviderDisplayMode = .parent
    
    @State private var errorMessage: String?
    
    var isCreating: Bool {
        configuration == nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isCreating ? "Create New Ring" : "Edit Ring")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            
            Divider()
            
            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // Basic Settings
                    GroupBox(label: Label("Basic Settings", systemImage: "gear")) {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Ring Name", text: $name)
                                .textFieldStyle(.roundedBorder)
                            
                            HStack {
                                Text("Keyboard Shortcut:")
                                    .frame(width: 140, alignment: .leading)
                                
                                Picker("", selection: $selectedShortcut) {
                                    ForEach(ShortcutOption.allCases) { option in
                                        Text(option.displayName).tag(option)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 180)
                                
                                Text(selectedShortcut.displayName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.2))
                                    .cornerRadius(4)
                            }
                            
                            Toggle("Active on Launch", isOn: $isActive)
                                .help("New rings are active by default. Toggle active/inactive in the management view after creation.")
                                .disabled(true)
                        }
                        .padding(12)
                    }
                    
                    // Ring Geometry
                    GroupBox(label: Label("Ring Geometry", systemImage: "circle.grid.3x3")) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Ring Radius:")
                                    .frame(width: 140, alignment: .leading)
                                TextField("", text: $ringRadius)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                Text("px")
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                Text("Center Hole Radius:")
                                    .frame(width: 140, alignment: .leading)
                                TextField("", text: $centerHoleRadius)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                Text("px")
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                Text("Icon Size:")
                                    .frame(width: 140, alignment: .leading)
                                TextField("", text: $iconSize)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                Text("px")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(12)
                    }
                    
                    // Providers
                    GroupBox(label: Label("Content Providers", systemImage: "square.stack.3d.up.fill")) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Select which content sources to include in this ring:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ProviderRow(
                                name: "Combined Apps",
                                description: "Running and favorite applications",
                                isIncluded: $includeCombinedApps,
                                displayMode: $combinedAppsMode
                            )
                            
                            ProviderRow(
                                name: "Favorite Files",
                                description: "Quick access to favorite files",
                                isIncluded: $includeFavoriteFiles,
                                displayMode: $favoriteFilesMode
                            )
                            
                            ProviderRow(
                                name: "Finder Logic",
                                description: "Browse folders and recent locations",
                                isIncluded: $includeFinderLogic,
                                displayMode: $finderLogicMode
                            )
                            
                            ProviderRow(
                                name: "System Actions",
                                description: "Lock, Sleep, Logout, etc.",
                                isIncluded: $includeSystemActions,
                                displayMode: $systemActionsMode
                            )
                        }
                        .padding(12)
                    }
                    
                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal, 12)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button(isCreating ? "Create" : "Save") {
                    saveRing()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isFormValid)
            }
            .padding()
        }
        .frame(width: 600, height: 700)
        .onAppear {
            loadConfiguration()
        }
    }
    
    // MARK: - Validation
    
    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !ringRadius.isEmpty &&
        !centerHoleRadius.isEmpty &&
        !iconSize.isEmpty &&
        hasAtLeastOneProvider
    }
    
    private var hasAtLeastOneProvider: Bool {
        includeCombinedApps || includeFavoriteFiles || includeFinderLogic || includeSystemActions
    }
    
    // MARK: - Actions
    
    private func loadConfiguration() {
        guard let config = configuration else { return }
        
        // Load existing configuration for editing
        name = config.name
        ringRadius = String(Int(config.ringRadius))
        centerHoleRadius = String(Int(config.centerHoleRadius))
        iconSize = String(Int(config.iconSize))
        isActive = config.isActive
        
        // Match shortcut
        selectedShortcut = ShortcutOption.allCases.first { option in
            option.keyCode == config.keyCode && option.modifierFlags == config.modifierFlags
        } ?? .ctrlShiftD
        
        // Load providers
        for provider in config.providers {
            switch provider.providerType {
            case "CombinedAppsProvider":
                includeCombinedApps = true
                combinedAppsMode = ProviderDisplayMode(rawValue: provider.displayMode ?? "parent") ?? .parent
            case "FavoriteFilesProvider":
                includeFavoriteFiles = true
                favoriteFilesMode = ProviderDisplayMode(rawValue: provider.displayMode ?? "parent") ?? .parent
            case "FinderLogic":
                includeFinderLogic = true
                finderLogicMode = ProviderDisplayMode(rawValue: provider.displayMode ?? "parent") ?? .parent
            case "SystemActionsProvider":
                includeSystemActions = true
                systemActionsMode = ProviderDisplayMode(rawValue: provider.displayMode ?? "parent") ?? .parent
            default:
                break
            }
        }
    }
    
    private func saveRing() {
        errorMessage = nil
        
        // Validate numeric fields
        guard let radiusValue = Double(ringRadius),
              let holeValue = Double(centerHoleRadius),
              let iconValue = Double(iconSize) else {
            errorMessage = "Invalid numeric values"
            return
        }
        
        // Build providers array
        var providers: [(type: String, order: Int, displayMode: String?, angle: Double?)] = []
        var order = 1
        
        if includeCombinedApps {
            providers.append(("CombinedAppsProvider", order, combinedAppsMode.rawValue, nil))
            order += 1
        }
        
        if includeFavoriteFiles {
            providers.append(("FavoriteFilesProvider", order, favoriteFilesMode.rawValue, nil))
            order += 1
        }
        
        if includeFinderLogic {
            providers.append(("FinderLogic", order, finderLogicMode.rawValue, nil))
            order += 1
        }
        
        if includeSystemActions {
            providers.append(("SystemActionsProvider", order, systemActionsMode.rawValue, nil))
            order += 1
        }
        
        // Save to database
        let configManager = RingConfigurationManager.shared
        
        do {
            if isCreating {
                // Create new configuration
                let newConfig = try configManager.createConfiguration(
                    name: name.trimmingCharacters(in: .whitespaces),
                    shortcut: selectedShortcut.displayName,
                    ringRadius: radiusValue,
                    centerHoleRadius: holeValue,
                    iconSize: iconValue,
                    keyCode: selectedShortcut.keyCode,
                    modifierFlags: selectedShortcut.modifierFlags,
                    providers: providers
                )
                
                // Note: New configurations are active by default
                // TODO: Add toggle active/inactive functionality in management view
                
                print("✅ [EditRing] Created new ring: '\(newConfig.name)' (active: \(newConfig.isActive))")
            } else {
                // Update existing configuration
                guard let config = configuration else {
                    errorMessage = "Configuration not found"
                    return
                }
                
                // Step 1: Update basic configuration
                try configManager.updateConfiguration(
                    id: config.id,
                    name: name.trimmingCharacters(in: .whitespaces),
                    shortcut: selectedShortcut.displayName,
                    ringRadius: radiusValue,
                    centerHoleRadius: holeValue,
                    iconSize: iconValue,
                    keyCode: selectedShortcut.keyCode,
                    modifierFlags: selectedShortcut.modifierFlags
                )
                
                // Step 2: Remove all existing providers
                for provider in config.providers {
                    try configManager.removeProvider(id: provider.id)
                }
                
                // Step 3: Add new providers
                for provider in providers {
                    // Build config dictionary for displayMode
                    var providerConfig: [String: Any]? = nil
                    if let displayMode = provider.displayMode {
                        providerConfig = ["displayMode": displayMode]
                    }
                    
                    _ = try configManager.addProvider(
                        toRing: config.id,
                        providerType: provider.type,
                        order: provider.order,
                        angle: provider.angle,
                        config: providerConfig
                    )
                }
                
                print("✅ [EditRing] Updated ring (ID: \(config.id))")
            }
            
            onSave()
            dismiss()
            
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
            print("❌ [EditRing] Save failed: \(error)")
        }
    }
}

// MARK: - Provider Row

struct ProviderRow: View {
    let name: String
    let description: String
    @Binding var isIncluded: Bool
    @Binding var displayMode: ProviderDisplayMode
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $isIncluded) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.body)
                        .fontWeight(.medium)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if isIncluded {
                HStack {
                    Text("Display Mode:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 90, alignment: .leading)
                    
                    Picker("", selection: $displayMode) {
                        ForEach(ProviderDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                .padding(.leading, 20)
            }
        }
    }
}

// MARK: - Display Mode Enum

enum ProviderDisplayMode: String, CaseIterable {
    case parent
    case direct
    
    var displayName: String {
        switch self {
        case .parent: return "Parent"
        case .direct: return "Direct"
        }
    }
}

// MARK: - Shortcut Options

enum ShortcutOption: String, CaseIterable, Identifiable {
    case ctrlShiftD
    case ctrlShiftA
    case ctrlShiftF
    case ctrlShiftE
    case ctrlShiftQ
    case ctrlShiftW
    case ctrlShiftS
    case ctrlShiftR
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .ctrlShiftD: return "Ctrl+Shift+D"
        case .ctrlShiftA: return "Ctrl+Shift+A"
        case .ctrlShiftF: return "Ctrl+Shift+F"
        case .ctrlShiftE: return "Ctrl+Shift+E"
        case .ctrlShiftQ: return "Ctrl+Shift+Q"
        case .ctrlShiftW: return "Ctrl+Shift+W"
        case .ctrlShiftS: return "Ctrl+Shift+S"
        case .ctrlShiftR: return "Ctrl+Shift+R"
        }
    }
    
    var keyCode: UInt16 {
        switch self {
        case .ctrlShiftD: return 2   // D
        case .ctrlShiftA: return 0   // A
        case .ctrlShiftF: return 3   // F
        case .ctrlShiftE: return 14  // E
        case .ctrlShiftQ: return 12  // Q
        case .ctrlShiftW: return 13  // W
        case .ctrlShiftS: return 1   // S
        case .ctrlShiftR: return 15  // R
        }
    }
    
    var modifierFlags: UInt {
        NSEvent.ModifierFlags([.control, .shift]).rawValue
    }
}

// MARK: - Preview

#Preview {
    EditRingView(configuration: nil, onSave: {})
}
