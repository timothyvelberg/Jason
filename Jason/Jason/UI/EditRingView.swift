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
    @State private var recordedKeyCode: UInt16?
    @State private var recordedModifierFlags: UInt?
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
    @State private var includeWindowManagement: Bool = false
    @State private var windowManagementMode: ProviderDisplayMode = .parent
    
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
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Keyboard Shortcut:")
                                    .font(.body)
                                
                                KeyboardShortcutRecorder(
                                    keyCode: $recordedKeyCode,
                                    modifierFlags: $recordedModifierFlags
                                )
                                
                                Text("Click the button and press your desired key combination")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
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
                            
                            ProviderRow(
                                name: "Window Management",
                                description: "Resize and position windows",
                                isIncluded: $includeWindowManagement,
                                displayMode: $windowManagementMode
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
        recordedKeyCode != nil &&
        recordedModifierFlags != nil &&
        hasAtLeastOneProvider
    }
    
    private var hasAtLeastOneProvider: Bool {
        includeCombinedApps || includeFavoriteFiles || includeFinderLogic || includeSystemActions || includeWindowManagement
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
        
        // Load keyboard shortcut
        recordedKeyCode = config.keyCode
        recordedModifierFlags = config.modifierFlags
        
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
            case "WindowManagementProvider":
                includeWindowManagement = true
                windowManagementMode = ProviderDisplayMode(rawValue: provider.displayMode ?? "parent") ?? .parent
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
        
        // Validate shortcut is recorded
        guard let keyCode = recordedKeyCode,
              let modifierFlags = recordedModifierFlags else {
            errorMessage = "Please record a keyboard shortcut"
            return
        }
        
        // Generate shortcut display string
        let shortcutDisplay = formatShortcut(keyCode: keyCode, modifiers: modifierFlags)
        
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
        
        if includeWindowManagement {
            providers.append(("WindowManagementProvider", order, windowManagementMode.rawValue, nil))
            order += 1
        }
        
        // Save to database
        let configManager = RingConfigurationManager.shared
        
        do {
            if isCreating {
                // Create new configuration
                let newConfig = try configManager.createConfiguration(
                    name: name.trimmingCharacters(in: .whitespaces),
                    shortcut: shortcutDisplay,
                    ringRadius: radiusValue,
                    centerHoleRadius: holeValue,
                    iconSize: iconValue,
                    keyCode: keyCode,
                    modifierFlags: modifierFlags,
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
                    shortcut: shortcutDisplay,
                    ringRadius: radiusValue,
                    centerHoleRadius: holeValue,
                    iconSize: iconValue,
                    keyCode: keyCode,
                    modifierFlags: modifierFlags
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

// MARK: - Helper Methods for EditRingView

extension EditRingView {
    /// Format a shortcut for display
    func formatShortcut(keyCode: UInt16, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        parts.append(keyCodeToString(keyCode))
        
        return parts.joined()
    }
    
    /// Convert key code to string
    func keyCodeToString(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
        case 49: return "Space"
        default: return "[\(keyCode)]"
        }
    }
}

// MARK: - Preview

#Preview {
    EditRingView(configuration: nil, onSave: {})
}
