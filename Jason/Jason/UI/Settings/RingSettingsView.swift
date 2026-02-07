//
//  RingsSettingsView.swift
//  Jason
//
//  Settings view for managing ring configurations.
//  Shows a list of all rings with ability to add, edit, test, and delete.
//

import SwiftUI

struct RingsSettingsView: View {
    @State private var configurations: [StoredRingConfiguration] = []
    @State private var showingEditor: Bool = false
    @State private var editingConfig: StoredRingConfiguration?
    @State private var showingDeleteConfirmation: Bool = false
    @State private var configToDelete: StoredRingConfiguration?
    
    var body: some View {
        VStack(spacing: 0) {
            if configurations.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "circle.grid.cross")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No instances configured")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Instances are circular launchers activated by keyboard shortcuts")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Button {
                        addNewConfiguration()
                    } label: {
                        Label("Add Instance", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(configurations) { config in
                        RingConfigurationRow(
                            config: config,
                            onEdit: {
                                editingConfig = config
                                showingEditor = true
                            },
                            onTest: {
                                testRing(config)
                            },
                            onDelete: {
                                configToDelete = config
                                showingDeleteConfirmation = true
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .contextMenu {
                            Button("Edit...") {
                                editingConfig = config
                                showingEditor = true
                            }
                            
                            Button("Test") {
                                testRing(config)
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
                .listStyle(.inset)
            }
            
            Divider()
            
            HStack {
                Button {
                    addNewConfiguration()
                } label: {
                    Label("Add Instance", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
                
                Text("\(configurations.count) instance(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .onAppear {
            loadConfigurations()
        }
        .sheet(isPresented: $showingEditor) {
            EditRingView(configuration: editingConfig, onSave: {
                loadConfigurations()
                CircularUIInstanceManager.shared.syncWithConfigurations()
                CircularUIInstanceManager.shared.registerInputTriggers()
            })
        }
        .alert("Delete Instance?", isPresented: $showingDeleteConfirmation) {
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
    
    // MARK: - Actions
    
    private func loadConfigurations() {
        RingConfigurationManager.shared.loadConfigurations()
        configurations = RingConfigurationManager.shared.getAllConfigurations()
        
        print("🔧 [RingsSettings] Loaded \(configurations.count) configuration(s)")
        
        CircularUIInstanceManager.shared.syncWithConfigurations()
        CircularUIInstanceManager.shared.stopHotkeyMonitoring()
        CircularUIInstanceManager.shared.registerInputTriggers()
        CircularUIInstanceManager.shared.startHotkeyMonitoring()
    }
    
    private func addNewConfiguration() {
        editingConfig = nil
        showingEditor = true
    }
    
    private func duplicateConfiguration(_ config: StoredRingConfiguration) {
        // TODO: Implement duplication via database
        print("📋 Duplicate configuration: \(config.name)")
    }
    
    private func deleteConfiguration(_ config: StoredRingConfiguration) {
        print("🗑️ Deleting configuration: \(config.name)")
        
        CircularUIInstanceManager.shared.removeInstance(forConfigId: config.id)
        
        do {
            try RingConfigurationManager.shared.deleteConfiguration(id: config.id)
            print("✅ Deleted ring configuration: \(config.name)")
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

// MARK: - Ring Configuration Row

struct RingConfigurationRow: View {
    let config: StoredRingConfiguration
    let onEdit: () -> Void
    let onTest: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(config.isActive ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 10, height: 10)
            
            Image(systemName: "circle.grid.3x3.fill")
                .font(.system(size: 20))
                .foregroundColor(.blue)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(config.name)
                    .font(.body)
                    .fontWeight(.medium)
                
                HStack(spacing: 8) {
                    Text(config.shortcutDescription)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue)
                        .cornerRadius(4)
                    
                    Text("\(config.providerCount) provider(s)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !config.isActive {
                        Text("Inactive")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(3)
                    }
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button(action: onTest) {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundColor(.green)
                }
                .buttonStyle(.borderless)
                .help("Test instance")
                
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)
                .help("Edit instance")
                
                Button(action: onDelete) {
                    Image(systemName: "trash.circle.fill")
                        .font(.title3)
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("Delete instance")
            }
        }
        .padding(.vertical, 4)
    }
}
