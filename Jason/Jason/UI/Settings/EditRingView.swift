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
    @State private var triggerType: TriggerType = .keyboard
    @State private var recordedKeyCode: UInt16?
    @State private var recordedModifierFlags: UInt?
    @State private var recordedButtonNumber: Int32?
    @State private var swipeDirection: SwipeDirection = .up
    @State private var fingerCount: Int = 3
    @State private var swipeModifierFlags: UInt = 0
    @State private var isHoldMode: Bool = false
    @State private var autoExecuteOnRelease: Bool = true
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
                                Text("Trigger Type:")
                                    .font(.body)
                                
                                Picker("", selection: $triggerType) {
                                    Text("Keyboard").tag(TriggerType.keyboard)
                                    Text("Mouse").tag(TriggerType.mouse)
                                    Text("Trackpad").tag(TriggerType.trackpad)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 400)
                                
                                // Show appropriate recorder based on trigger type
                                if triggerType == .keyboard {
                                    KeyboardShortcutRecorder(
                                        keyCode: $recordedKeyCode,
                                        modifierFlags: $recordedModifierFlags
                                    )
                                    
                                    Text("Click the button and press your desired key combination")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else if triggerType == .mouse {
                                    MouseButtonRecorder(
                                        buttonNumber: $recordedButtonNumber,
                                        modifierFlags: $recordedModifierFlags
                                    )
                                    
                                    Text("Click the button and then click your mouse button (middle, back, or forward)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    // Trackpad gesture picker
                                    TrackpadGesturePicker(
                                        direction: $swipeDirection,
                                        fingerCount: $fingerCount,
                                        modifierFlags: $swipeModifierFlags
                                    )
                                    
                                    Text("Select finger count, swipe direction, and optional modifier keys")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                // Hold mode toggle
                                Divider()
                                    .padding(.vertical, 4)
                                
                                Toggle("Hold to show (release to hide)", isOn: $isHoldMode)
                                    .help("When enabled, UI appears while key/button is held and disappears when released. When disabled, UI toggles on each press.")
                                
                                // Auto-execute toggle (only show when hold mode is enabled)
                                if isHoldMode {
                                    Toggle("Auto-execute on release", isOn: $autoExecuteOnRelease)
                                        .padding(.leading, 20)  // Indent to show it's related to hold mode
                                        .help("When enabled, releasing the hold key executes the hovered item without clicking. Perfect for app switching.")
                                }
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
        let hasValidTrigger: Bool
        if triggerType == .keyboard {
            hasValidTrigger = recordedKeyCode != nil && recordedModifierFlags != nil
        } else if triggerType == .mouse {
            hasValidTrigger = recordedButtonNumber != nil
        } else {
            // Trackpad always valid (has default direction and finger count, modifiers optional)
            hasValidTrigger = true
        }
        
        return !name.trimmingCharacters(in: .whitespaces).isEmpty &&
               !ringRadius.isEmpty &&
               !centerHoleRadius.isEmpty &&
               !iconSize.isEmpty &&
               hasValidTrigger &&
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
        
        // Load trigger based on type
        if config.triggerType == "keyboard" {
            triggerType = .keyboard
            recordedKeyCode = config.keyCode
            recordedModifierFlags = config.modifierFlags
        } else if config.triggerType == "mouse" {
            triggerType = .mouse
            recordedButtonNumber = config.buttonNumber
            recordedModifierFlags = config.modifierFlags
        } else if config.triggerType == "trackpad" || config.triggerType == "swipe" {
            // Support both "trackpad" (new) and "swipe" (legacy)
            triggerType = .trackpad
            if let dir = config.swipeDirection {
                swipeDirection = SwipeDirection(rawValue: dir) ?? .up
            }
            fingerCount = config.fingerCount ?? 3  // Default to 3 for legacy data
            swipeModifierFlags = config.modifierFlags ?? 0
        }
        
        isHoldMode = config.isHoldMode
        autoExecuteOnRelease = config.autoExecuteOnRelease
        
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
    
    
    private func formatTrackpadGesture(direction: String, fingerCount: Int, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        let directionSymbol: String
        switch direction.lowercased() {
        case "up": directionSymbol = "↑ \(fingerCount)-Finger Swipe Up"
        case "down": directionSymbol = "↓ \(fingerCount)-Finger Swipe Down"
        case "left": directionSymbol = "← \(fingerCount)-Finger Swipe Left"
        case "right": directionSymbol = "→ \(fingerCount)-Finger Swipe Right"
        default: directionSymbol = "\(fingerCount)-Finger Swipe \(direction)"
        }
        
        parts.append(directionSymbol)
        
        return parts.joined()
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
        
        // Validate and extract trigger data based on type
        let keyCode: UInt16?
        let modifierFlags: UInt?
        let buttonNumber: Int32?
        let shortcutDisplay: String
        
        let swipeDir: String?
        
        if triggerType == .keyboard {
            // Validate keyboard shortcut
            guard let kc = recordedKeyCode,
                  let mf = recordedModifierFlags else {
                errorMessage = "Please record a keyboard shortcut"
                return
            }
            keyCode = kc
            modifierFlags = mf
            buttonNumber = nil
            swipeDir = nil
            shortcutDisplay = formatShortcut(keyCode: kc, modifiers: mf)
            
        } else if triggerType == .mouse {
            // Validate mouse button
            guard let bn = recordedButtonNumber else {
                errorMessage = "Please record a mouse button"
                return
            }
            keyCode = nil
            modifierFlags = recordedModifierFlags
            buttonNumber = bn
            swipeDir = nil
            shortcutDisplay = formatMouseButton(buttonNumber: bn, modifiers: modifierFlags ?? 0)
        } else {
            // Trackpad gesture
            keyCode = nil
            modifierFlags = swipeModifierFlags
            buttonNumber = nil
            swipeDir = swipeDirection.rawValue
            shortcutDisplay = formatTrackpadGesture(direction: swipeDirection.rawValue, fingerCount: fingerCount, modifiers: swipeModifierFlags)
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
                    triggerType: triggerType.rawValue,
                    keyCode: keyCode,
                    modifierFlags: modifierFlags,
                    buttonNumber: buttonNumber,
                    swipeDirection: swipeDir,
                    fingerCount: triggerType == .trackpad ? fingerCount : nil,
                    isHoldMode: isHoldMode,
                    autoExecuteOnRelease: autoExecuteOnRelease,
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
                
                // Step 1: Update configuration with ALL trigger parameters
                try configManager.updateConfiguration(
                    id: config.id,
                    name: name.trimmingCharacters(in: .whitespaces),
                    shortcut: shortcutDisplay,
                    ringRadius: radiusValue,
                    centerHoleRadius: holeValue,
                    iconSize: iconValue,
                    triggerType: triggerType.rawValue,
                    keyCode: keyCode,
                    modifierFlags: modifierFlags,
                    buttonNumber: buttonNumber,
                    swipeDirection: swipeDir,
                    fingerCount: triggerType == .trackpad ? fingerCount : nil,
                    isHoldMode: isHoldMode,
                    autoExecuteOnRelease: autoExecuteOnRelease
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
    
    /// Format a mouse button for display
    func formatMouseButton(buttonNumber: Int32, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        // Convert button number to readable name
        let buttonName: String
        switch buttonNumber {
        case 2:
            buttonName = "Button 3 (Middle)"
        case 3:
            buttonName = "Button 4 (Back)"
        case 4:
            buttonName = "Button 5 (Forward)"
        default:
            buttonName = "Button \(buttonNumber + 1)"
        }
        
        parts.append(buttonName)
        
        return parts.joined()
    }
}

// MARK: - Preview

#Preview {
    EditRingView(configuration: nil, onSave: {})
}

// MARK: - Trigger Type

enum TriggerType: String {
    case keyboard
    case mouse
    case trackpad
}

enum SwipeDirection: String, CaseIterable {
    case up
    case down
    case left
    case right
    
    var displayName: String {
        switch self {
        case .up: return "↑ Swipe Up"
        case .down: return "↓ Swipe Down"
        case .left: return "← Swipe Left"
        case .right: return "→ Swipe Right"
        }
    }
}


// MARK: - Trackpad Gesture Picker

struct TrackpadGesturePicker: View {
    @Binding var direction: SwipeDirection
    @Binding var fingerCount: Int
    @Binding var modifierFlags: UInt
    
    @State private var useCommand = false
    @State private var useControl = false
    @State private var useOption = false
    @State private var useShift = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Finger count picker
            HStack {
                Text("Fingers:")
                    .frame(width: 80, alignment: .leading)
                
                Picker("", selection: $fingerCount) {
                    Text("3 Fingers").tag(3)
                    Text("4 Fingers").tag(4)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            
            // Direction picker
            HStack {
                Text("Direction:")
                    .frame(width: 80, alignment: .leading)
                
                Picker("", selection: $direction) {
                    ForEach(SwipeDirection.allCases, id: \.self) { dir in
                        Text(dir.displayName).tag(dir)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)
            }
            
            // Modifier keys
            VStack(alignment: .leading, spacing: 6) {
                Text("Modifiers (optional):")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    Toggle("⌘ Command", isOn: $useCommand)
                    Toggle("⌃ Control", isOn: $useControl)
                }
                HStack(spacing: 12) {
                    Toggle("⌥ Option", isOn: $useOption)
                    Toggle("⇧ Shift", isOn: $useShift)
                }
            }
            .padding(.leading, 20)
            
            // Display current gesture
            HStack {
                Text("Gesture:")
                    .frame(width: 80, alignment: .leading)
                Text(formatDisplay())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .onChange(of: useCommand) { _, _ in updateModifierFlags() }
        .onChange(of: useControl) { _, _ in updateModifierFlags() }
        .onChange(of: useOption) { _, _ in updateModifierFlags() }
        .onChange(of: useShift) { _, _ in updateModifierFlags() }
        .onAppear {
            // Initialize modifier toggles from binding
            let flags = NSEvent.ModifierFlags(rawValue: modifierFlags)
            useCommand = flags.contains(.command)
            useControl = flags.contains(.control)
            useOption = flags.contains(.option)
            useShift = flags.contains(.shift)
        }
    }
    
    private func updateModifierFlags() {
        var flags: UInt = 0
        if useCommand { flags |= NSEvent.ModifierFlags.command.rawValue }
        if useControl { flags |= NSEvent.ModifierFlags.control.rawValue }
        if useOption { flags |= NSEvent.ModifierFlags.option.rawValue }
        if useShift { flags |= NSEvent.ModifierFlags.shift.rawValue }
        modifierFlags = flags
    }
    
    private func formatDisplay() -> String {
        var parts: [String] = []
        
        if useControl { parts.append("⌃") }
        if useOption { parts.append("⌥") }
        if useShift { parts.append("⇧") }
        if useCommand { parts.append("⌘") }
        
        // Add finger count and direction
        let fingerText = "\(fingerCount)-Finger"
        parts.append("\(fingerText) \(direction.displayName)")
        
        return parts.joined()
    }
}

// MARK: - Mouse Button Recorder

struct MouseButtonRecorder: View {
    @Binding var buttonNumber: Int32?
    @Binding var modifierFlags: UInt?
    @State private var isRecording = false
    @State private var eventTap: CFMachPort?
    @State private var runLoopSource: CFRunLoopSource?
    @State private var handler: MouseButtonRecorderHandler?  // Keep handler alive
    
    var displayText: String {
        if isRecording {
            return "Click mouse button..."
        } else if let buttonNumber = buttonNumber {
            return formatDisplay(buttonNumber: buttonNumber, modifiers: modifierFlags ?? 0)
        } else {
            return "Click to record"
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }) {
                HStack {
                    Image(systemName: isRecording ? "record.circle.fill" : "computermouse")
                        .foregroundColor(isRecording ? .red : .blue)
                    
                    Text(displayText)
                        .frame(minWidth: 120, alignment: .leading)
                        .foregroundColor(isRecording ? .secondary : .primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Color.red.opacity(0.1) : Color.gray.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.red : Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            
            if buttonNumber != nil {
                Button(action: clearButton) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear mouse button")
            }
        }
    }
    
    // MARK: - Recording
    
    private func startRecording() {
        isRecording = true
        
        // Create event tap for mouse button events
        let eventMask = (1 << CGEventType.otherMouseDown.rawValue)
        
        let callback: CGEventTapCallBack = { (proxy, type, event, refcon) in
            // Extract self from refcon
            let handler = Unmanaged<MouseButtonRecorderHandler>.fromOpaque(refcon!).takeUnretainedValue()
            handler.handleMouseEvent(event: event, type: type)
            return Unmanaged.passRetained(event)
        }
        
        // Create and retain handler
        let newHandler = MouseButtonRecorderHandler(
            buttonNumber: $buttonNumber,
            modifierFlags: $modifierFlags,
            isRecording: $isRecording,
            stopRecordingCallback: { [self] in
                self.stopRecording()
            }
        )
        handler = newHandler  // Store in @State to keep it alive
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(newHandler).toOpaque()
        ) else {
            print("❌ [MouseRecorder] Failed to create event tap - check Accessibility permissions")
            isRecording = false
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        print("🖱️ [MouseRecorder] Recording started")
    }
    
    private func stopRecording() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
        handler = nil  // Release handler
        isRecording = false
        print("🖱️ [MouseRecorder] Recording stopped")
    }
    
    private func clearButton() {
        buttonNumber = nil
        modifierFlags = nil
        print("🖱️ [MouseRecorder] Mouse button cleared")
    }
    
    // MARK: - Formatting
    
    private func formatDisplay(buttonNumber: Int32, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        let buttonName: String
        switch buttonNumber {
        case 2: buttonName = "Button 3 (Middle)"
        case 3: buttonName = "Button 4 (Back)"
        case 4: buttonName = "Button 5 (Forward)"
        default: buttonName = "Button \(buttonNumber + 1)"
        }
        
        parts.append(buttonName)
        
        return parts.joined()
    }
}


// MARK: - Swipe Gesture Picker


// MARK: - Mouse Button Recorder Handler

class MouseButtonRecorderHandler {
    var buttonNumber: Binding<Int32?>
    var modifierFlags: Binding<UInt?>
    var isRecording: Binding<Bool>
    var stopRecordingCallback: (() -> Void)?
    
    init(buttonNumber: Binding<Int32?>, modifierFlags: Binding<UInt?>, isRecording: Binding<Bool>, stopRecordingCallback: (() -> Void)? = nil) {
        self.buttonNumber = buttonNumber
        self.modifierFlags = modifierFlags
        self.isRecording = isRecording
        self.stopRecordingCallback = stopRecordingCallback
    }
    
    func handleMouseEvent(event: CGEvent, type: CGEventType) {
        guard isRecording.wrappedValue else { return }
        
        // Get button number and current modifier flags
        let btn = event.getIntegerValueField(.mouseEventButtonNumber)
        
        // Get current modifier flags
        let cgFlags = event.flags
        var mods: UInt = 0
        
        if cgFlags.contains(.maskCommand) { mods |= NSEvent.ModifierFlags.command.rawValue }
        if cgFlags.contains(.maskControl) { mods |= NSEvent.ModifierFlags.control.rawValue }
        if cgFlags.contains(.maskAlternate) { mods |= NSEvent.ModifierFlags.option.rawValue }
        if cgFlags.contains(.maskShift) { mods |= NSEvent.ModifierFlags.shift.rawValue }
        
        print("🖱️ [MouseRecorder] Captured button \(btn), modifiers: \(mods)")
        
        // Save the captured values
        DispatchQueue.main.async { [weak self] in
            self?.buttonNumber.wrappedValue = Int32(btn)
            self?.modifierFlags.wrappedValue = mods
            self?.isRecording.wrappedValue = false
            self?.stopRecordingCallback?()
        }
    }
}
