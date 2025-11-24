//
//  RingsSettingsView.swift
//  Jason
//
//  Settings view for managing ring configurations.
//  Shows a list of all rings with ability to add, edit, and delete.
//

import SwiftUI

struct RingsSettingsView: View {
    @State private var configurations: [StoredRingConfiguration] = []
    @State private var selectedConfigId: Int?
    @State private var showingEditor: Bool = false
    @State private var editingConfig: StoredRingConfiguration?
    @State private var showingDeleteConfirmation: Bool = false
    @State private var configToDelete: StoredRingConfiguration?
    
    var body: some View {
        HSplitView {
            // Left: Ring list
            ringListView
                .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
            
            // Right: Preview and quick info
            ringDetailView
                .frame(minWidth: 300)
        }
        .navigationTitle("Rings")
        .onAppear {
            loadConfigurations()
        }
        .sheet(isPresented: $showingEditor) {
            // Use existing EditRingView for editing (nil config = create new)
            EditRingView(configuration: editingConfig, onSave: {
                loadConfigurations()
                // Re-sync instances after edit
                CircularUIInstanceManager.shared.syncWithConfigurations()
                CircularUIInstanceManager.shared.registerInputTriggers()
            })
        }
        .alert("Delete Ring?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let config = configToDelete {
                    deleteConfiguration(config)
                }
            }
        } message: {
            if let config = configToDelete {
                Text("Are you sure you want to delete '\(config.name)'? This cannot be undone.")
            }
        }
    }
    
    // MARK: - Ring List View
    
    private var ringListView: some View {
        VStack(spacing: 0) {
            // List of rings
            List(selection: $selectedConfigId) {
                ForEach(configurations) { config in
                    RingListRow(
                        config: config,
                        isSelected: selectedConfigId == config.id
                    )
                    .tag(config.id)
                    .contextMenu {
                        Button("Edit...") {
                            editingConfig = config
                            showingEditor = true
                        }
                        
                        Divider()
                        
                        Button("Duplicate") {
                            duplicateConfiguration(config)
                        }
                        
                        Divider()
                        
                        Button("Delete", role: .destructive) {
                            configToDelete = config
                            showingDeleteConfirmation = true
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            
            Divider()
            
            // Bottom toolbar
            HStack {
                Button(action: addNewConfiguration) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add new ring")
                
                Button(action: {
                    if let id = selectedConfigId,
                       let config = configurations.first(where: { $0.id == id }) {
                        configToDelete = config
                        showingDeleteConfirmation = true
                    }
                }) {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selectedConfigId == nil)
                .help("Delete selected ring")
                
                Spacer()
                
                Text("\(configurations.count) ring(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(8)
        }
    }
    
    // MARK: - Ring Detail View
    
    private var ringDetailView: some View {
        Group {
            if let id = selectedConfigId,
               let config = configurations.first(where: { $0.id == id }) {
                RingDetailPanel(
                    config: config,
                    onEdit: {
                        editingConfig = config
                        showingEditor = true
                    },
                    onTest: {
                        testRing(config)
                    }
                )
            } else {
                ContentUnavailableView(
                    "No Ring Selected",
                    systemImage: "circle.dashed",
                    description: Text("Select a ring from the list or create a new one")
                )
            }
        }
    }
    
    // MARK: - Actions
    
    private func loadConfigurations() {
        RingConfigurationManager.shared.loadConfigurations()
        configurations = RingConfigurationManager.shared.getAllConfigurations()
        
        // Select first if nothing selected
        if selectedConfigId == nil, let first = configurations.first {
            selectedConfigId = first.id
        }
    }
    
    private func addNewConfiguration() {
        // Open editor with nil config = create new ring
        editingConfig = nil
        showingEditor = true
    }
    
    private func duplicateConfiguration(_ config: StoredRingConfiguration) {
        // TODO: Implement duplication via database
        print("📋 Duplicate configuration: \(config.name)")
    }
    
    private func deleteConfiguration(_ config: StoredRingConfiguration) {
        print("🗑️ Deleting configuration: \(config.name)")
        
        // Remove from instance manager first
        CircularUIInstanceManager.shared.removeInstance(forConfigId: config.id)
        
        // Delete from database
        do {
            try RingConfigurationManager.shared.deleteConfiguration(id: config.id)
            print("✅ Deleted ring configuration: \(config.name)")
        } catch {
            print("❌ Failed to delete: \(error)")
        }
        
        // Re-register triggers (to remove the deleted one)
        CircularUIInstanceManager.shared.registerInputTriggers()
        
        // Reload list
        loadConfigurations()
        
        // Clear selection if we deleted the selected item
        if selectedConfigId == config.id {
            selectedConfigId = configurations.first?.id
        }
    }
    
    private func testRing(_ config: StoredRingConfiguration) {
        // Delay to allow settings window to get out of the way
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            CircularUIInstanceManager.shared.show(configId: config.id)
        }
    }
}

// MARK: - Ring List Row

struct RingListRow: View {
    let config: StoredRingConfiguration
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(config.isActive ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(config.name)
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .regular)
                
                Text(config.shortcutDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Provider count badge
            Text("\(config.providerCount)")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(4)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Ring Detail Panel

struct RingDetailPanel: View {
    let config: StoredRingConfiguration
    let onEdit: () -> Void
    let onTest: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Preview
            VStack(spacing: 12) {
                Text("Preview")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                RingPreviewView(configuration: config, previewSize: 220)
            }
            .padding()
            .background(Color.black.opacity(0.03))
            .cornerRadius(12)
            
            // Quick Info
            GroupBox("Configuration") {
                VStack(alignment: .leading, spacing: 8) {
                    infoRow("Name", value: config.name)
                    infoRow("Trigger", value: config.shortcutDescription)
                    infoRow("Status", value: config.isActive ? "Active" : "Inactive")
                    
                    Divider()
                    
                    infoRow("Ring Thickness", value: "\(Int(config.ringRadius)) px")
                    infoRow("Center Hole", value: "\(Int(config.centerHoleRadius)) px")
                    infoRow("Icon Size", value: "\(Int(config.iconSize)) px")
                    
                    Divider()
                    
                    infoRow("Providers", value: "\(config.providerCount)")
                    
                    if !config.providers.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(config.sortedProviders) { provider in
                                HStack {
                                    Text("•")
                                        .foregroundColor(.secondary)
                                    Text(formatProviderName(provider.providerType))
                                        .font(.caption)
                                }
                                .padding(.leading, 8)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Action Buttons
            HStack(spacing: 12) {
                Button("Edit...") {
                    onEdit()
                }
                .buttonStyle(.bordered)
                
                Button("Test Ring") {
                    onTest()
                }
                .buttonStyle(.borderedProminent)
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
        .font(.callout)
    }
    
    private func formatProviderName(_ type: String) -> String {
        // Convert provider type to readable name
        // e.g., "favorite-folders" -> "Favorite Folders"
        return type
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}

// MARK: - Preview

#if DEBUG
struct RingsSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        RingsSettingsView()
            .frame(width: 600, height: 500)
    }
}
#endif
