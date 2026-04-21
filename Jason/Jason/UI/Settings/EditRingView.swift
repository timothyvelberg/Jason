//
//  EditRingView.swift
//  Jason
//
//  Ring configuration creation and editing interface
//

import SwiftUI
import AppKit

// MARK: - Provider Config

struct RingProviderConfig: Identifiable, Equatable {
    let id = UUID()
    let type: String
    let name: String
    let description: String
    var isEnabled: Bool
    var displayMode: ProviderDisplayMode
    
    static func == (lhs: RingProviderConfig, rhs: RingProviderConfig) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Trigger Config (for form state)

struct TriggerFormConfig: Identifiable, Equatable {
    let id: UUID
    var triggerType: TriggerType
    var keyCode: UInt16?
    var modifierFlags: UInt
    var buttonNumber: Int32?
    var swipeDirection: SwipeDirection
    var fingerCount: Int
    var isHoldMode: Bool
    var autoExecuteOnRelease: Bool
    
    // For existing triggers loaded from DB
    var databaseId: Int?
    
    init(
        id: UUID = UUID(),
        triggerType: TriggerType = .keyboard,
        keyCode: UInt16? = nil,
        modifierFlags: UInt = 0,
        buttonNumber: Int32? = nil,
        swipeDirection: SwipeDirection = .up,
        fingerCount: Int = 3,
        isHoldMode: Bool = false,
        autoExecuteOnRelease: Bool = true,
        databaseId: Int? = nil
    ) {
        self.id = id
        self.triggerType = triggerType
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.buttonNumber = buttonNumber
        self.swipeDirection = swipeDirection
        self.fingerCount = fingerCount
        self.isHoldMode = isHoldMode
        self.autoExecuteOnRelease = autoExecuteOnRelease
        self.databaseId = databaseId
    }
    
    /// Create from a TriggerConfiguration (loaded from DB)
    init(from config: TriggerConfiguration) {
        self.id = UUID()
        self.databaseId = config.id
        self.modifierFlags = config.modifierFlags
        self.isHoldMode = config.isHoldMode
        self.autoExecuteOnRelease = config.autoExecuteOnRelease
        
        if config.triggerType == "keyboard" {
            self.triggerType = .keyboard
            self.keyCode = config.keyCode
            self.buttonNumber = nil
            self.swipeDirection = .up
            self.fingerCount = 3
        } else if config.triggerType == "mouse" {
            self.triggerType = .mouse
            self.keyCode = nil
            self.buttonNumber = config.buttonNumber
            self.swipeDirection = .up
            self.fingerCount = 3
        } else {
            self.triggerType = .trackpad
            self.keyCode = nil
            self.buttonNumber = nil
            self.swipeDirection = SwipeDirection(rawValue: config.swipeDirection ?? "up") ?? .up
            self.fingerCount = config.fingerCount ?? 3
        }
    }
    
    /// Display description
    var displayDescription: String {
        switch triggerType {
        case .keyboard:
            guard let keyCode = keyCode else { return "No key set" }
            return formatKeyboard(keyCode: keyCode, modifiers: modifierFlags)
        case .mouse:
            guard let buttonNumber = buttonNumber else { return "No button set" }
            return formatMouse(buttonNumber: buttonNumber, modifiers: modifierFlags)
        case .trackpad:
            return formatTrackpad(direction: swipeDirection, fingerCount: fingerCount, modifiers: modifierFlags)
        }
    }
    
    /// Whether this trigger has valid data
    var isValid: Bool {
        switch triggerType {
        case .keyboard:
            return keyCode != nil
        case .mouse:
            return buttonNumber != nil
        case .trackpad:
            return true // Always valid with defaults
        }
    }
    
    // MARK: - Formatting helpers
    
    private func formatKeyboard(keyCode: UInt16, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }
    
    private func formatMouse(buttonNumber: Int32, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        let buttonName: String
        switch buttonNumber {
        case 2: buttonName = "Middle Click"
        case 3: buttonName = "Back Button"
        case 4: buttonName = "Forward Button"
        default: buttonName = "Button \(buttonNumber + 1)"
        }
        
        parts.append(buttonName)
        return parts.joined()
    }
    
    private func formatTrackpad(direction: SwipeDirection, fingerCount: Int, modifiers: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        parts.append("\(fingerCount)-Finger \(direction.displayName)")
        return parts.joined()
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String {
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
        case 50: return "`"
        case 53: return "Esc"
        default: return "[\(keyCode)]"
        }
    }
}

struct EditRingView: View {
    @Environment(\.dismiss) var dismiss
    
    // Configuration being edited (nil for new ring)
    let configuration: StoredRingConfiguration?
    let onSave: () -> Void
    
    // Form fields
    @State private var name: String = ""
    @State private var triggers: [TriggerFormConfig] = []  // NEW: Array of triggers
    @State private var showAddTriggerSheet = false          // NEW: Sheet state
    @State private var ringRadius: String = "80"
    @State private var centerHoleRadius: String = "56"
    @State private var iconSize: String = "32"
    @State private var startAngle: Double = 0.0
    @State private var panelProviderType: String? = nil
    @State private var isPanelMode: Bool = false
    @State private var showAddProviderSheet = false
    
    // Provider selection - ordered array
    @State private var providers: [ProviderConfig] = []
    
    @State private var errorMessage: String?
    
    var isCreating: Bool {
        configuration == nil
    }
    
    // Default provider definitions
    private static let defaultProviders: [ProviderConfig] = [
        ProviderConfig(type: "CombinedAppsProvider", name: "Apps", description: "Running and favorite applications", isEnabled: false, displayMode: .parent),
        ProviderConfig(type: "FavoriteFilesProvider", name: "Favorite Files", description: "Quick access to favorite files", isEnabled: false, displayMode: .parent),
        ProviderConfig(type: "FavoriteFolderProvider", name: "Finder Logic", description: "Browse folders and recent locations", isEnabled: false, displayMode: .parent),
        ProviderConfig(type: "ContextProvider", name: "Context Provider", description: "Shortcut for your individual apps", isEnabled: false, displayMode: .parent),
        ProviderConfig(type: "ClipboardHistoryProvider", name: "Clipboard History", description: "Access previously copied text", isEnabled: false, displayMode: .parent),
        ProviderConfig(type: "RemindersProvider", name: "Reminders", description: "Quick task list with add and complete", isEnabled: false, displayMode: .parent),
        ProviderConfig(type: "CalendarProvider", name: "Calendar", description: "Show today's calendar items", isEnabled: false, displayMode: .parent),
        ProviderConfig(type: "FocusedWindowSwitcherProvider", name: "Window Switcher", description: "List of Windows of current focused app", isEnabled: false, displayMode: .parent),
        ProviderConfig(type: "SystemActionsProvider", name: "System Actions", description: "Lock, Sleep, Logout, etc.", isEnabled: false, displayMode: .parent),
        ProviderConfig(type: "WindowManagementProvider", name: "Window Management", description: "Resize and position windows", isEnabled: false, displayMode: .parent),
        ProviderConfig(type: "ShortcutExecuteProvider", name: "Keyboard Shortcuts", description: "Execute keyboard shortcuts (Copy, Paste, etc.)", isEnabled: false, displayMode: .parent)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isCreating ? "Create New Instance" : "Edit Instance")
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
                    
                    // 1. Type of Instance
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Ring or Panel")
                                        .font(.body)
                                        .fontWeight(.medium)
                                    Text("Set up multiple providers as a Ring, or a single provider as a Panel.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Picker("", selection: $isPanelMode) {
                                    Text("Ring").tag(false)
                                    Text("Panel").tag(true)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 140)
                                .onChange(of: isPanelMode) { _, newValue in
                                    if newValue {
                                        panelProviderType = providers.first(where: { $0.isEnabled })?.type
                                    } else {
                                        panelProviderType = nil
                                    }
                                }
                            }
                        }
                        .padding(12)
                    } label: {
                        Text("1. Type of Instance")
                            .font(.headline)
                            .padding(.bottom, 8)
                            .padding(.top, 8)
                    }
                    
                    // 2. Name of Instance
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Ring Name", text: $name)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(12)
                    } label: {
                        Text("2. Name of Instance")
                            .font(.headline)
                            .padding(.bottom, 8)
                            .padding(.top, 8)
                    }
                    
                    // 3. Triggers
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            if triggers.isEmpty {
                                HStack {
                                    Spacer()
                                    VStack(spacing: 8) {
                                        Image(systemName: "keyboard.badge.ellipsis")
                                            .font(.system(size: 32))
                                            .foregroundColor(.secondary.opacity(0.5))
                                        Text("No triggers configured")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("Add a keyboard shortcut, mouse button, or trackpad gesture")
                                            .font(.caption2)
                                            .foregroundColor(.secondary.opacity(0.8))
                                    }
                                    .padding(.vertical, 20)
                                    Spacer()
                                }
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(triggers) { trigger in
                                        TriggerRowView(trigger: trigger) {
                                            withAnimation {
                                                triggers.removeAll { $0.id == trigger.id }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(12)
                    } label: {
                        HStack {
                            Text("3. Triggers")
                                .font(.headline)
                                .padding(.bottom, 8)
                                .padding(.top, 8)
                            Spacer()
                            Button(action: { showAddTriggerSheet = true }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                            .help("Add trigger")
                        }
                    }
                    .sheet(isPresented: $showAddTriggerSheet) {
                        AddTriggerSheet(existingTriggers: triggers) { newTrigger in
                            withAnimation {
                                triggers.append(newTrigger)
                            }
                        }
                    }
                    
                    // 4. Providers
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            if savedProviderIndices.isEmpty {
                                HStack {
                                    Spacer()
                                    VStack(spacing: 8) {
                                        Image(systemName: "square.stack.3d.up")
                                            .font(.system(size: 32))
                                            .foregroundColor(.secondary.opacity(0.5))
                                        Text("No providers added")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("Add at least one provider to power this instance")
                                            .font(.caption2)
                                            .foregroundColor(.secondary.opacity(0.8))
                                    }
                                    .padding(.vertical, 20)
                                    Spacer()
                                }
                            } else {
                                List {
                                    ForEach(savedProviderIndices, id: \.self) { index in
                                        SavedProviderRowView(
                                            provider: providers[index],
                                            displayMode: $providers[index].displayMode,
                                            isPanelMode: isPanelMode,
                                            onRemove: {
                                                withAnimation {
                                                    removeProvider(type: providers[index].type)
                                                }
                                            }
                                        )
                                        .listRowInsets(EdgeInsets())
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                    }
                                    .onMove(perform: isPanelMode ? nil : moveSavedProvider)
                                }
                                .listStyle(.plain)
                                .scrollContentBackground(.hidden)
                                .scrollDisabled(true)
                                .frame(height: max(60, CGFloat(savedProviderIndices.count) * 48))
                            }
                        }
                    } label: {
                        HStack {
                            Text("4. Content Providers")
                                .font(.headline)
                                .padding(.bottom, 8)
                                .padding(.top, 8)
                            Spacer()
                            if canAddMoreProviders {
                                Button(action: { showAddProviderSheet = true }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.blue)
                                    }
                                .buttonStyle(.plain)
                                .help("Add provider")
                            }
                        }
                    }
                    .sheet(isPresented: $showAddProviderSheet) {
                        AddProviderSheet(
                            availableProviders: availableProviders,
                            isPanelMode: isPanelMode
                        ) { type, displayMode in
                            withAnimation {
                                addProvider(type: type, displayMode: displayMode)
                            }
                        }
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
        .frame(width: 600, height: 800)
        .onAppear {
            loadConfiguration()
        }
    }
    
    // MARK: - Provider Helpers

    private var savedProviderIndices: [Int] {
        if isPanelMode {
            return providers.indices.filter { providers[$0].type == panelProviderType }
        } else {
            return providers.indices.filter { providers[$0].isEnabled }
        }
    }
    
    private func moveSavedProvider(from source: IndexSet, to destination: Int) {
        var saved = savedProviderIndices.map { providers[$0] }
        saved.move(fromOffsets: source, toOffset: destination)
        let disabled = providers.filter { !$0.isEnabled }
        providers = saved + disabled
    }
    
    private var availableProviders: [ProviderConfig] {
        if isPanelMode {
            return providers
        } else {
            return providers.filter { !$0.isEnabled }
        }
    }

    private var canAddMoreProviders: Bool {
        if isPanelMode {
            return panelProviderType == nil
        }
        return providers.contains { !$0.isEnabled }
    }

    private func addProvider(type: String, displayMode: ProviderDisplayMode) {
        guard let index = providers.firstIndex(where: { $0.type == type }) else { return }
        if isPanelMode {
            panelProviderType = type
        } else {
            providers[index].isEnabled = true
        }
        providers[index].displayMode = displayMode
    }

    private func removeProvider(type: String) {
        guard let index = providers.firstIndex(where: { $0.type == type }) else { return }
        if isPanelMode {
            panelProviderType = nil
        } else {
            providers[index].isEnabled = false
        }
    }
    
    // MARK: - Provider Reordering
    
    private func moveProvider(from source: IndexSet, to destination: Int) {
        providers.move(fromOffsets: source, toOffset: destination)
    }
    
    // MARK: - Validation
    
    private var isFormValid: Bool {
        return !name.trimmingCharacters(in: .whitespaces).isEmpty &&
               !triggers.isEmpty &&
               triggers.allSatisfy { $0.isValid } &&
               (isPanelMode ? panelProviderType != nil : hasAtLeastOneProvider)
    }
    
    private var hasAtLeastOneProvider: Bool {
        providers.contains { $0.isEnabled }
    }
    
    // MARK: - Actions
    
    private func loadConfiguration() {
        if let config = configuration {
            // Load existing configuration for editing
            name = config.name
            ringRadius = String(Int(config.ringRadius))
            centerHoleRadius = String(Int(config.centerHoleRadius))
            iconSize = String(Int(config.iconSize))
            startAngle = config.startAngle
            
            // Load triggers from array
            triggers = config.triggers.map { TriggerFormConfig(from: $0) }
            
            // Build providers array from saved config
            var savedProvidersByType: [String: (order: Int, displayMode: ProviderDisplayMode)] = [:]
            for provider in config.providers {
                let displayMode = ProviderDisplayMode(rawValue: provider.displayMode ?? "parent") ?? .parent
                savedProvidersByType[provider.providerType] = (provider.order, displayMode)
            }
            
            var enabledProviders: [(ProviderConfig, Int)] = []
            var disabledProviders: [ProviderConfig] = []
            
            for defaultProvider in Self.defaultProviders {
                if let saved = savedProvidersByType[defaultProvider.type] {
                    var provider = defaultProvider
                    provider.isEnabled = true
                    provider.displayMode = saved.displayMode
                    enabledProviders.append((provider, saved.order))
                } else {
                    var provider = defaultProvider
                    provider.isEnabled = false
                    disabledProviders.append(provider)
                }
            }
            
            enabledProviders.sort { $0.1 < $1.1 }
            providers = enabledProviders.map { $0.0 } + disabledProviders
            
            // Set panel/ring mode
            if config.presentationMode == .panel {
                isPanelMode = true
                panelProviderType = providers.first(where: { $0.isEnabled })?.type
            } else {
                isPanelMode = false
                panelProviderType = nil
            }
            
        } else {
            // New ring - use defaults
            providers = Self.defaultProviders
            triggers = []
            isPanelMode = false
            panelProviderType = nil
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
        case "tap": directionSymbol = "\(fingerCount)-Finger Tap"
        case "add": directionSymbol = "\(fingerCount)-Finger Add"
        case "circleclockwise": directionSymbol = "↻ \(fingerCount)-Finger Circle Clockwise"
        case "circlecounterclockwise": directionSymbol = "↺ \(fingerCount)-Finger Circle Counter-Clockwise"
        case "twofingertapleft": directionSymbol = "👆← Two-Finger Tap Left"
        case "twofingertapright": directionSymbol = "→👆 Two-Finger Tap Right"
        default: directionSymbol = "\(fingerCount)-Finger Swipe \(direction)"
        }
        
        parts.append(directionSymbol)
        
        return parts.joined()
    }
    
    private func saveRing() {
        print("🔍 [SaveRing] About to save \(triggers.count) trigger(s)")
        
        errorMessage = nil
        
        // Validate numeric fields
        guard let radiusValue = Double(ringRadius),
              let holeValue = Double(centerHoleRadius),
              let iconValue = Double(iconSize) else {
            errorMessage = "Invalid numeric values"
            return
        }
        
        // Build triggers array for API
        let triggerData: [(type: String, keyCode: UInt16?, modifierFlags: UInt, buttonNumber: Int32?, swipeDirection: String?, fingerCount: Int?, isHoldMode: Bool, autoExecuteOnRelease: Bool)] = triggers.map { trigger in
            (
                type: trigger.triggerType.rawValue,
                keyCode: trigger.triggerType == .keyboard ? trigger.keyCode : nil,
                modifierFlags: trigger.modifierFlags,
                buttonNumber: trigger.triggerType == .mouse ? trigger.buttonNumber : nil,
                swipeDirection: trigger.triggerType == .trackpad ? trigger.swipeDirection.rawValue : nil,
                fingerCount: trigger.triggerType == .trackpad ? trigger.fingerCount : nil,
                isHoldMode: trigger.isHoldMode,
                autoExecuteOnRelease: trigger.autoExecuteOnRelease
            )
        }
        
        // Build shortcut display (first trigger, for legacy display)
        let shortcutDisplay = triggers.first?.displayDescription ?? "No trigger"
        
        // Build providers array from ordered, enabled providers
        var providerData: [(type: String, order: Int, displayMode: String?, angle: Double?)] = []
        var order = 1
        
        for provider in providers {
            if isPanelMode {
                guard provider.type == panelProviderType else { continue }
            } else {
                guard provider.isEnabled else { continue }
            }
            providerData.append((provider.type, order, provider.displayMode.rawValue, nil))
            order += 1
        }
        
        // Save to database
        let configManager = RingConfigurationManager.shared
        
        do {
            if isCreating {
                let newConfig = try configManager.createConfiguration(
                    name: name.trimmingCharacters(in: .whitespaces),
                    shortcut: shortcutDisplay,
                    ringRadius: radiusValue,
                    centerHoleRadius: holeValue,
                    iconSize: iconValue,
                    startAngle: startAngle,
                    presentationMode: isPanelMode ? .panel : .ring,
                    triggers: triggerData,
                    providers: providerData
                )
                
                print("✅ [EditRing] Created new ring: '\(newConfig.name)' with \(newConfig.triggers.count) trigger(s)")
            } else {
                guard let config = configuration else {
                    errorMessage = "Configuration not found"
                    return
                }
                
                // Step 1: Update ring properties
                try configManager.updateConfiguration(
                    id: config.id,
                    name: name.trimmingCharacters(in: .whitespaces),
                    shortcut: shortcutDisplay,
                    ringRadius: radiusValue,
                    centerHoleRadius: holeValue,
                    iconSize: iconValue,
                    startAngle: startAngle,
                    presentationMode: isPanelMode ? .panel : .ring
                )
                
                // Step 2: Remove all existing triggers
                for trigger in config.triggers {
                    try configManager.removeTrigger(id: trigger.id)
                }
                
                // Step 3: Add all triggers from form
                for trigger in triggers {
                    _ = try configManager.addTrigger(
                        toRing: config.id,
                        triggerType: trigger.triggerType.rawValue,
                        keyCode: trigger.triggerType == .keyboard ? trigger.keyCode : nil,
                        modifierFlags: trigger.modifierFlags,
                        buttonNumber: trigger.triggerType == .mouse ? trigger.buttonNumber : nil,
                        swipeDirection: trigger.triggerType == .trackpad ? trigger.swipeDirection.rawValue : nil,
                        fingerCount: trigger.triggerType == .trackpad ? trigger.fingerCount : nil,
                        isHoldMode: trigger.isHoldMode,
                        autoExecuteOnRelease: trigger.autoExecuteOnRelease
                    )
                }
                
                // Step 4: Remove all existing providers
                for provider in config.providers {
                    try configManager.removeProvider(id: provider.id)
                }
                
                // Step 5: Add new providers in order
                for provider in providerData {
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
                
                print("✅ [EditRing] Updated ring (ID: \(config.id)) with \(triggers.count) trigger(s)")
            }
            
            onSave()
            dismiss()
            
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
            print("❌ [EditRing] Save failed: \(error)")
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

// MARK: - Saved Provider Row

struct SavedProviderRowView: View {
    let provider: ProviderConfig
    @Binding var displayMode: ProviderDisplayMode
    let isPanelMode: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.bullet")
                .font(.system(size: 16))
                .foregroundColor(.white)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                    .font(.body)
                    .fontWeight(.medium)

                Text(provider.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !isPanelMode {
                Picker("", selection: $displayMode) {
                    ForEach(ProviderDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            Button(action: onRemove) {
                Image(systemName: "trash")
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Remove provider")
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Add Provider Sheet

struct AddProviderSheet: View {
    @Environment(\.dismiss) var dismiss

    let availableProviders: [ProviderConfig]
    let isPanelMode: Bool
    let onAdd: (String, ProviderDisplayMode) -> Void

    @State private var selectedType: String? = nil
    @State private var displayMode: ProviderDisplayMode = .parent

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Provider")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // Provider list
                    VStack(spacing: 4) {
                        ForEach(availableProviders) { provider in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(provider.name)
                                        .fontWeight(.medium)
                                    Text(provider.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if selectedType == provider.type {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedType == provider.type ? Color.blue.opacity(0.08) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedType == provider.type ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { selectedType = provider.type }
                        }
                    }

                    // Display mode — ring mode only, shown once a provider is selected
                    if !isPanelMode && selectedType != nil {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Display Mode")
                                .font(.body)
                                .fontWeight(.medium)
                            Text("Parent shows this provider as a slice in the ring. Direct shows its contents immediately.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Picker("", selection: $displayMode) {
                                ForEach(ProviderDisplayMode.allCases, id: \.self) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Add") {
                    if let type = selectedType {
                        onAdd(type, displayMode)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedType == nil)
            }
            .padding()
        }
        .frame(width: 480, height: 500)
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
    case tap
    case add
    case circleClockwise
    case circleCounterClockwise
    case twoFingerTapLeft
    case twoFingerTapRight
    
    var displayName: String {
        switch self {
        case .up: return "Swipe Up"
        case .down: return "Swipe Down"
        case .left: return "Swipe Left"
        case .right: return "Swipe Right"
        case .tap: return "Tap"
        case .add: return "Add Finger"
        case .circleClockwise: return "Circle ↻ (Clockwise)"
        case .circleCounterClockwise: return "Circle ↺ (Counter-Clockwise)"
        case .twoFingerTapLeft: return "Two-Finger Tap (←Left)"
        case .twoFingerTapRight: return "Two-Finger Tap (Right→)"
        }
    }
    
    var isCircle: Bool {
        return self == .circleClockwise || self == .circleCounterClockwise
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
    
    private func availableDirections() -> [SwipeDirection] {
        if fingerCount == 1 {
            // Single finger only supports circles
            return [.circleClockwise, .circleCounterClockwise]
        } else if fingerCount == 2 {
            // Two finger supports add and two-finger taps
            return [.twoFingerTapLeft, .twoFingerTapRight, .add]
        } else {
            return [.up, .down, .left, .right, .tap, .add]
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Finger count picker
            HStack {
                Text("Fingers:")
                    .frame(width: 80, alignment: .leading)
                
                Picker("", selection: $fingerCount) {
                    Text("1 Finger").tag(1)
                    Text("2 Fingers").tag(2)
                    Text("3 Fingers").tag(3)
                    Text("4 Fingers").tag(4)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                .onChange(of: fingerCount) { _, newValue in
                    print("🔍 [TrackpadPicker] fingerCount changed to \(newValue)")
                    print("   Current direction: \(direction.rawValue)")
                    print("   Available: \(availableDirections().map { $0.rawValue })")
                    
                    if !availableDirections().contains(direction) {
                        let newDirection = availableDirections().first ?? .add
                        print("   Resetting direction to: \(newDirection.rawValue)")
                        direction = newDirection
                    } else {
                        print("   Direction is valid, keeping it")
                    }
                }

                .onChange(of: direction) { _, newValue in
                    print("🔍 [TrackpadPicker] direction changed to: \(newValue.rawValue)")
                }
            }
            
            // Direction picker
            HStack {
                Text("Direction:")
                    .frame(width: 80, alignment: .leading)
                
                Picker("", selection: $direction) {
                    ForEach(availableDirections(), id: \.self) { dir in
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
        
        print("[MouseRecorder] Captured button \(btn), modifiers: \(mods)")
        
        // Save the captured values
        DispatchQueue.main.async { [weak self] in
            self?.buttonNumber.wrappedValue = Int32(btn)
            self?.modifierFlags.wrappedValue = mods
            self?.isRecording.wrappedValue = false
            self?.stopRecordingCallback?()
        }
    }
}


extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
