//
//  RingManagementView.swift
//  Jason
//
//  Ring configuration management interface
//

import SwiftUI

struct RingManagementView: View {
    @Environment(\.dismiss) var dismiss
    @State private var configurations: [StoredRingConfiguration] = []
    @State private var showingEditSheet = false
    @State private var editingConfiguration: StoredRingConfiguration?
    @State private var showingDeleteConfirmation = false
    @State private var configToDelete: StoredRingConfiguration?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Manage Rings")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            Divider()
            
            // Ring List
            if configurations.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(configurations) { config in
                            RingConfigurationRow(
                                configuration: config,
                                onEdit: {
                                    editConfiguration(config)
                                },
                                onDelete: {
                                    confirmDelete(config)
                                }
                            )
                            Divider()
                        }
                    }
                    .padding()
                }
            }
            
            Divider()
            
            // Footer
            HStack {
                Button(action: addRing) {
                    Label("Add Ring", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Text("\(configurations.count) ring(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .frame(width: 700, height: 600)
        .onAppear {
            loadConfigurations()
        }
        .sheet(isPresented: $showingEditSheet) {
            EditRingView(configuration: editingConfiguration) {
                // Reload configurations after save
                loadConfigurations()
            }
        }
        .alert("Delete Ring Configuration?", isPresented: $showingDeleteConfirmation, presenting: configToDelete) { config in
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteConfiguration(config)
            }
        } message: { config in
            Text("Are you sure you want to delete '\(config.name)'? This action cannot be undone.")
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "circle.grid.cross")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No rings configured")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Rings are circular launchers activated by keyboard shortcuts")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
    private func loadConfigurations() {
        // Load all configurations (both active and inactive)
        RingConfigurationManager.shared.loadConfigurations()
        configurations = RingConfigurationManager.shared.getAllConfigurations()
        
        print("🔧 [RingManagement] Loaded \(configurations.count) configuration(s)")
        
        // Sync instances with updated configurations
        CircularUIInstanceManager.shared.syncWithConfigurations()
        
        // CRITICAL: Stop monitoring before re-registering shortcuts
        // This ensures the event handler closures pick up the new registrations
        CircularUIInstanceManager.shared.stopHotkeyMonitoring()
        
        // Re-register shortcuts to pick up any new hotkeys
        CircularUIInstanceManager.shared.registerInputTriggers()
        
        // Restart monitoring with fresh closures
        CircularUIInstanceManager.shared.startHotkeyMonitoring()
        
        print("   ✅ Synced instances and shortcuts")
    }
    
    private func addRing() {
        editingConfiguration = nil
        showingEditSheet = true
        print("➕ [RingManagement] Opening create ring sheet")
    }
    
    private func editConfiguration(_ config: StoredRingConfiguration) {
        editingConfiguration = config
        showingEditSheet = true
        print("✏️ [RingManagement] Opening edit sheet for '\(config.name)'")
    }
    
    private func confirmDelete(_ config: StoredRingConfiguration) {
        configToDelete = config
        showingDeleteConfirmation = true
        print("⚠️ [RingManagement] Confirming delete for '\(config.name)'")
    }
    
    private func deleteConfiguration(_ config: StoredRingConfiguration) {
        print("🗑️ [RingManagement] Deleting '\(config.name)' (ID: \(config.id))")
        
        do {
            try RingConfigurationManager.shared.deleteConfiguration(id: config.id)
            print("   ✅ Configuration deleted")
            
            // Reload configurations
            loadConfigurations()
            
        } catch {
            print("   ❌ Failed to delete configuration: \(error)")
            // Could add error alert here if needed
        }
    }
}

// MARK: - Ring Configuration Row

struct RingConfigurationRow: View {
    let configuration: StoredRingConfiguration
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Active indicator
            Circle()
                .fill(configuration.isActive ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 10, height: 10)
            
            // Ring icon
            Image(systemName: "circle.grid.3x3.fill")
                .font(.system(size: 20))
                .foregroundColor(.blue)
                .frame(width: 24)
            
            // Ring info
            VStack(alignment: .leading, spacing: 4) {
                Text(configuration.name)
                    .font(.body)
                    .fontWeight(.medium)
                
                HStack(spacing: 8) {
                    // Shortcut badge
                    Text(configuration.shortcut)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue)
                        .cornerRadius(4)
                    
                    // Provider count
                    Text("\(configuration.providers.count) provider(s)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Status
                    if !configuration.isActive {
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
            
            // Action buttons
            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14))
                }
                .buttonStyle(.bordered)
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Preview

#Preview {
    RingManagementView()
}
