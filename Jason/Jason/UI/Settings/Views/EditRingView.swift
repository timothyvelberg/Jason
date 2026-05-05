//
//  EditRingView.swift
//  Jason
//
//  Ring configuration creation and editing interface.
//

import SwiftUI
import AppKit

struct EditRingView: View {
    @Environment(\.dismiss) var dismiss

    let configuration: StoredRingConfiguration?
    let bundleId: String?
    let onSave: () -> Void

    init(configuration: StoredRingConfiguration?, bundleId: String? = nil, onSave: @escaping () -> Void) {
        self.configuration = configuration
        self.bundleId = bundleId
        self.onSave = onSave
    }

    // MARK: - Form State

    @State private var name: String = ""
    @State private var triggers: [TriggerFormConfig] = []
    @State private var showAddTriggerSheet = false
    @State private var ringRadius: String = "80"
    @State private var centerHoleRadius: String = "56"
    @State private var iconSize: String = "32"
    @State private var startAngle: Double = 0.0
    @State private var panelProviderType: String? = nil
    @State private var isPanelMode: Bool = false
    @State private var showAddProviderSheet = false
    @State private var providers: [ProviderConfig] = []
    @State private var errorMessage: String?

    var isCreating: Bool { configuration == nil }

    // MARK: - Default Providers

    private static let defaultProviders: [ProviderConfig] = [
        ProviderConfig(type: "CombinedAppsProvider",        name: "Apps",               description: "Running and favorite applications",           isEnabled: false, displayMode: .parent),
        ProviderConfig(type: "FavoriteFilesProvider",        name: "Favorite Files",     description: "Quick access to favorite files",               isEnabled: false, displayMode: .parent),
        ProviderConfig(type: "FavoriteFolderProvider",       name: "Finder Logic",       description: "Browse folders and recent locations",          isEnabled: false, displayMode: .parent),
        ProviderConfig(type: "ContextProvider",              name: "Context Provider",   description: "Shortcut for your individual apps",            isEnabled: false, displayMode: .parent),
        ProviderConfig(type: "ClipboardHistoryProvider",     name: "Clipboard History",  description: "Access previously copied text",                isEnabled: false, displayMode: .parent),
        ProviderConfig(type: "RemindersProvider",            name: "Reminders",          description: "Quick task list with add and complete",         isEnabled: false, displayMode: .parent),
        ProviderConfig(type: "CalendarProvider",             name: "Calendar",           description: "Show today's calendar items",                  isEnabled: false, displayMode: .parent),
        ProviderConfig(type: "FocusedWindowSwitcherProvider",name: "Window Switcher",    description: "List of Windows of current focused app",        isEnabled: false, displayMode: .parent),
        ProviderConfig(type: "SystemActionsProvider",        name: "System Actions",     description: "Lock, Sleep, Logout, etc.",                    isEnabled: false, displayMode: .parent),
        ProviderConfig(type: "WindowManagementProvider",     name: "Window Management",  description: "Resize and position windows",                  isEnabled: false, displayMode: .parent),
        ProviderConfig(type: "ShortcutExecuteProvider",      name: "Keyboard Shortcuts", description: "Execute keyboard shortcuts (Copy, Paste, etc.)",isEnabled: false, displayMode: .parent),
    ]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            formContent
            Divider()
            footer
        }
        .frame(width: 600, height: 800)
        .onAppear { loadConfiguration() }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Text(isCreating ? "Create New Instance" : "Edit Instance")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
            Button(isCreating ? "Create" : "Save") { saveRing() }
                .buttonStyle(.borderedProminent)
                .disabled(!isFormValid)
        }
        .padding()
    }

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                typeSection
                nameSection
                triggersSection
                providersSection
            }
            .padding()
        }
    }

    // MARK: - Section: Type

    private var typeSection: some View {
        SectionBox {
            Text("1. Type of Instance")
                .font(.headline)
                .padding(.vertical, 8)
        } content: {
            HStack(spacing: 16) {
                instanceTypeCard(
                    icon: "circle.grid.cross",
                    title: "Ring",
                    subtitle: "Hosts multiple providers",
                    isSelected: !isPanelMode
                ) {
                    isPanelMode = false
                    panelProviderType = nil
                }

                instanceTypeCard(
                    icon: "rectangle.stack",
                    title: "Panel",
                    subtitle: "Hosts a single provider",
                    isSelected: isPanelMode
                ) {
                    isPanelMode = true
                    panelProviderType = providers.first(where: { $0.isEnabled })?.type
                }
            }
            .padding(12)
        }
    }

    private func instanceTypeCard(
        icon: String,
        title: String,
        subtitle: String,
        isSelected: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        VStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0))
                .frame(height: 120)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.4))
                )

            Text(title)
                .font(.title3)
                .fontWeight(.semibold)

            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue.opacity(0.5) : Color.secondary.opacity(0.2),
                        lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    // MARK: - Section: Name

    private var nameSection: some View {
        SectionBox {
            Text("2. Name of Instance")
                .font(.headline)
                .padding(.vertical, 8)
        } content: {
            TextField("Ring Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onAppear { NSApp.keyWindow?.makeFirstResponder(nil) }
                .padding(12)
        }
    }

    // MARK: - Section: Triggers

    private var triggersSection: some View {
        SectionBox {
            HStack {
                Text("3. Triggers")
                    .font(.headline)
                    .padding(.vertical, 8)
                Spacer()
                Button(action: { showAddTriggerSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("Add trigger")
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                if triggers.isEmpty {
                    emptyTriggersPlaceholder
                } else {
                    VStack(spacing: 8) {
                        ForEach(triggers) { trigger in
                            TriggerRowView(trigger: trigger) {
                                withAnimation { triggers.removeAll { $0.id == trigger.id } }
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .sheet(isPresented: $showAddTriggerSheet) {
            AddTriggerSheet(existingTriggers: triggers) { newTrigger in
                withAnimation { triggers.append(newTrigger) }
            }
        }
    }

    private var emptyTriggersPlaceholder: some View {
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
    }

    // MARK: - Section: Providers

    private var providersSection: some View {
        SectionBox {
            HStack {
                Text("4. Content Providers")
                    .font(.headline)
                    .padding(.vertical, 8)
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
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                if savedProviderIndices.isEmpty {
                    emptyProvidersPlaceholder
                } else {
                    List {
                        ForEach(savedProviderIndices, id: \.self) { index in
                            SavedProviderRowView(
                                provider: providers[index],
                                displayMode: $providers[index].displayMode,
                                isPanelMode: isPanelMode,
                                onRemove: {
                                    withAnimation { removeProvider(type: providers[index].type) }
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
            .padding(12)
        }
        .sheet(isPresented: $showAddProviderSheet) {
            AddProviderSheet(
                availableProviders: availableProviders,
                isPanelMode: isPanelMode
            ) { type, displayMode in
                withAnimation { addProvider(type: type, displayMode: displayMode) }
            }
        }
    }

    private var emptyProvidersPlaceholder: some View {
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
        isPanelMode ? providers : providers.filter { !$0.isEnabled }
    }

    private var canAddMoreProviders: Bool {
        isPanelMode ? panelProviderType == nil : providers.contains { !$0.isEnabled }
    }

    private func addProvider(type: String, displayMode: ProviderDisplayMode) {
        guard let index = providers.firstIndex(where: { $0.type == type }) else { return }
        if isPanelMode { panelProviderType = type } else { providers[index].isEnabled = true }
        providers[index].displayMode = displayMode
    }

    private func removeProvider(type: String) {
        guard let index = providers.firstIndex(where: { $0.type == type }) else { return }
        if isPanelMode { panelProviderType = nil } else { providers[index].isEnabled = false }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !triggers.isEmpty &&
        triggers.allSatisfy { $0.isValid } &&
        (isPanelMode ? panelProviderType != nil : providers.contains { $0.isEnabled })
    }

    // MARK: - Load

    private func loadConfiguration() {
        guard let config = configuration else {
            providers = Self.defaultProviders
            triggers = []
            isPanelMode = false
            panelProviderType = nil
            return
        }

        name             = config.name
        ringRadius       = String(Int(config.ringRadius))
        centerHoleRadius = String(Int(config.centerHoleRadius))
        iconSize         = String(Int(config.iconSize))
        startAngle       = config.startAngle
        triggers         = config.triggers.map { TriggerFormConfig(from: $0) }

        var savedByType: [String: (order: Int, displayMode: ProviderDisplayMode)] = [:]
        for p in config.providers {
            let mode = ProviderDisplayMode(rawValue: p.displayMode ?? "parent") ?? .parent
            savedByType[p.providerType] = (p.order, mode)
        }

        var enabled: [(ProviderConfig, Int)] = []
        var disabled: [ProviderConfig] = []

        for defaultProvider in Self.defaultProviders {
            if let saved = savedByType[defaultProvider.type] {
                var p = defaultProvider
                p.isEnabled = true
                p.displayMode = saved.displayMode
                enabled.append((p, saved.order))
            } else {
                disabled.append(defaultProvider)
            }
        }

        enabled.sort { $0.1 < $1.1 }
        providers = enabled.map { $0.0 } + disabled

        if config.presentationMode == .panel {
            isPanelMode = true
            panelProviderType = providers.first(where: { $0.isEnabled })?.type
        } else {
            isPanelMode = false
            panelProviderType = nil
        }
    }

    // MARK: - Save

    private func saveRing() {
        print("🔍 [SaveRing] About to save \(triggers.count) trigger(s)")
        errorMessage = nil

        guard let radiusValue = Double(ringRadius),
              let holeValue   = Double(centerHoleRadius),
              let iconValue   = Double(iconSize) else {
            errorMessage = "Invalid numeric values"
            return
        }

        let triggerData = triggers.map { t -> (type: String, keyCode: UInt16?, modifierFlags: UInt, buttonNumber: Int32?, swipeDirection: String?, fingerCount: Int?, isHoldMode: Bool, isModifierHoldMode: Bool, autoExecuteOnRelease: Bool) in
            (
                type:                t.triggerType.rawValue,
                keyCode:             t.triggerType == .keyboard ? t.keyCode : nil,
                modifierFlags:       t.modifierFlags,
                buttonNumber:        t.triggerType == .mouse    ? t.buttonNumber : nil,
                swipeDirection:      t.triggerType == .trackpad ? t.swipeDirection.rawValue : nil,
                fingerCount:         t.triggerType == .trackpad ? t.fingerCount : nil,
                isHoldMode:          t.isHoldMode,
                isModifierHoldMode:  t.isModifierHoldMode,
                autoExecuteOnRelease:t.autoExecuteOnRelease
            )
        }

        let shortcutDisplay = triggers.first?.displayDescription ?? "No trigger"

        var providerData: [(type: String, order: Int, displayMode: String?, angle: Double?)] = []
        var order = 1
        for p in providers {
            if isPanelMode { guard p.type == panelProviderType else { continue } }
            else           { guard p.isEnabled               else { continue } }
            providerData.append((p.type, order, p.displayMode.rawValue, nil))
            order += 1
        }

        let configManager = RingConfigurationManager.shared

        do {
            if isCreating {
                let newConfig = try configManager.createConfiguration(
                    name:               name.trimmingCharacters(in: .whitespaces),
                    shortcut:           shortcutDisplay,
                    ringRadius:         radiusValue,
                    centerHoleRadius:   holeValue,
                    iconSize:           iconValue,
                    startAngle:         startAngle,
                    presentationMode:   isPanelMode ? .panel : .ring,
                    bundleId:           bundleId,
                    triggers:           triggerData,
                    providers:          providerData
                )
                print("[EditRing] Created '\(newConfig.name)' with \(newConfig.triggers.count) trigger(s)")

            } else {
                guard let config = configuration else {
                    errorMessage = "Configuration not found"
                    return
                }

                try configManager.updateConfiguration(
                    id:               config.id,
                    name:             name.trimmingCharacters(in: .whitespaces),
                    shortcut:         shortcutDisplay,
                    ringRadius:       radiusValue,
                    centerHoleRadius: holeValue,
                    iconSize:         iconValue,
                    startAngle:       startAngle,
                    presentationMode: isPanelMode ? .panel : .ring
                )

                for trigger  in config.triggers  { try configManager.removeTrigger(id: trigger.id) }
                for trigger  in triggers         { _ = try configManager.addTrigger(toRing: config.id, triggerType: trigger.triggerType.rawValue, keyCode: trigger.triggerType == .keyboard ? trigger.keyCode : nil, modifierFlags: trigger.modifierFlags, buttonNumber: trigger.triggerType == .mouse ? trigger.buttonNumber : nil, swipeDirection: trigger.triggerType == .trackpad ? trigger.swipeDirection.rawValue : nil, fingerCount: trigger.triggerType == .trackpad ? trigger.fingerCount : nil, isHoldMode: trigger.isHoldMode, isModifierHoldMode: trigger.isModifierHoldMode, autoExecuteOnRelease: trigger.autoExecuteOnRelease) }
                for provider in config.providers { try configManager.removeProvider(id: provider.id) }
                for p        in providerData    { _ = try configManager.addProvider(toRing: config.id, providerType: p.type, order: p.order, angle: p.angle, config: p.displayMode.map { ["displayMode": $0] }) }

                print("[EditRing] Updated ring (ID: \(config.id)) with \(triggers.count) trigger(s)")
            }

            onSave()
            dismiss()

        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
            print("[EditRing] Save failed: \(error)")
        }
    }
}

// MARK: - Preview

#Preview {
    EditRingView(configuration: nil, onSave: {})
}
