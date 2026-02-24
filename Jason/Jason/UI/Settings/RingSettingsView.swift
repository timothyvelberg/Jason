//
//  RingsSettingsView.swift
//  Jason
//
//  Settings view for managing ring configurations.
//

import SwiftUI

struct RingsSettingsView: View {
    @State private var configurations: [StoredRingConfiguration] = []
    @State private var activeSheet: SheetConfig?
    @State private var showingDeleteConfirmation = false
    @State private var configToDelete: StoredRingConfiguration?
    
    private struct SheetConfig: Identifiable {
        let id: Int
        let configuration: StoredRingConfiguration?
    }
    
    var body: some View {
        SettingsListShell(
            title: "Instances",
            emptyIcon: "circle.grid.cross",
            emptyTitle: "No instances configured",
            emptySubtitle: "Instances are circular launchers activated by keyboard shortcuts",
            primaryLabel: "Add Instance",
            primaryAction: addNewConfiguration,
            secondaryLabel: nil,
            secondaryAction: nil,
            isEmpty: configurations.isEmpty
        ) {
            ForEach(configurations) { config in
                InstanceRow(config: config) {
                    activeSheet = SheetConfig(id: config.id, configuration: config)
                } onDelete: {
                    configToDelete = config
                    showingDeleteConfirmation = true
                } onTap: {
                    testRing(config)
                }
                .contextMenu {
                    Button("Edit...") {
                        activeSheet = SheetConfig(id: config.id, configuration: config)
                    }
                    Button("Test") { testRing(config) }
                    Divider()
                    Button("Duplicate") { duplicateConfiguration(config) }
                    Divider()
                    Button("Delete", role: .destructive) {
                        configToDelete = config
                        showingDeleteConfirmation = true
                    }
                }
            }
        }
        .onAppear { loadConfigurations() }
        .sheet(item: $activeSheet) { sheet in
            EditRingView(configuration: sheet.configuration, onSave: {
                loadConfigurations()
                CircularUIInstanceManager.shared.syncWithConfigurations()
                CircularUIInstanceManager.shared.registerInputTriggers()
            })
        }
        .alert("Delete Instance?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let config = configToDelete { deleteConfiguration(config) }
            }
        } message: {
            if let config = configToDelete {
                Text("Are you sure you want to delete '\(config.name)'? This cannot be undone.")
            }
        }
    }
    
    // MARK: - Actions
    
    private func loadConfigurations() {
        RingConfigurationManager.shared.loadConfigurations()
        configurations = RingConfigurationManager.shared.getAllConfigurations()
        CircularUIInstanceManager.shared.syncWithConfigurations()
        CircularUIInstanceManager.shared.stopHotkeyMonitoring()
        CircularUIInstanceManager.shared.registerInputTriggers()
        CircularUIInstanceManager.shared.startHotkeyMonitoring()
    }
    
    private func addNewConfiguration() {
        activeSheet = SheetConfig(id: -1, configuration: nil)
    }
    
    private func duplicateConfiguration(_ config: StoredRingConfiguration) {
        print("📋 Duplicate configuration: \(config.name)")
    }
    
    private func deleteConfiguration(_ config: StoredRingConfiguration) {
        CircularUIInstanceManager.shared.removeInstance(forConfigId: config.id)
        do {
            try RingConfigurationManager.shared.deleteConfiguration(id: config.id)
        } catch {
            print("❌ Failed to delete: \(error)")
        }
        CircularUIInstanceManager.shared.registerInputTriggers()
        loadConfigurations()
    }
    
    private func testRing(_ config: StoredRingConfiguration) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            CircularUIInstanceManager.shared.show(configId: config.id)
        }
    }
}

// MARK: - Instance Row

private struct InstanceRow: View {
    let config: StoredRingConfiguration
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onTap: () -> Void
    
    /// Replace the asset name logic once the Ring/Panel property on
    /// StoredRingConfiguration is confirmed.
    private var iconAsset: SettingsRowIcon {
        .asset("core_settings_menu_instance")
    }
    
    var body: some View {
        SettingsRow(
            icon: iconAsset,
            title: config.name,
            subtitle: config.shortcutDescription,
            showDragHandle: false,
            onEdit: onEdit,
            onDelete: onDelete,
            onTap: onTap,
            metadata: {
                if !config.isActive {
                    Text("Inactive")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(4)
                }
            }
        )
    }
}
