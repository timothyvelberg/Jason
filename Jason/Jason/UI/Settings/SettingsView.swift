//
//  SettingsView.swift
//  Jason
//
//  Created by Timothy Velberg on 24/11/2025.
//

import SwiftUI

// MARK: - Settings Section

enum SettingsSection: String, CaseIterable, Identifiable {
    case rings = "Rings"
    case favorites = "Favorites"
    case general = "General"
    case advanced = "Advanced"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .rings: return "circle.grid.3x3.fill"
        case .favorites: return "star.fill"
        case .general: return "gearshape.fill"
        case .advanced: return "wrench.and.screwdriver.fill"
        }
    }
    
    var description: String {
        switch self {
        case .rings: return "Configure ring layouts and triggers"
        case .favorites: return "Manage favorite folders, files, and apps"
        case .general: return "App behavior and preferences"
        case .advanced: return "Developer tools and diagnostics"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @StateObject private var instanceManager = CircularUIInstanceManager.shared
    @State private var selectedSection: SettingsSection? = .rings
    @State private var showAdvanced: Bool = false
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(selection: $selectedSection) {
                ForEach(SettingsSection.allCases.filter { section in
                    // Hide Advanced unless enabled
                    section != .advanced || showAdvanced
                }) { section in
                    NavigationLink(value: section) {
                        Label(section.rawValue, systemImage: section.icon)
                    }
                }
                
                // Toggle for Advanced section (at bottom of sidebar)
                Divider()
                    .padding(.vertical, 8)
                
                Toggle(isOn: $showAdvanced) {
                    Label("Show Advanced", systemImage: "eye")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .toggleStyle(.checkbox)
                .padding(.horizontal, 4)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        } detail: {
            // Detail pane
            if let section = selectedSection {
                sectionContent(for: section)
            } else {
                ContentUnavailableView(
                    "Select a Section",
                    systemImage: "sidebar.left",
                    description: Text("Choose a category from the sidebar")
                )
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
    
    // MARK: - Section Content
    
    @ViewBuilder
    private func sectionContent(for section: SettingsSection) -> some View {
        switch section {
        case .rings:
            RingsSettingsView()
            
        case .favorites:
            FavoritesSettingsSection(instanceManager: instanceManager)
            
        case .general:
            GeneralSettingsView()
            
        case .advanced:
            AdvancedSettingsView(instanceManager: instanceManager)
        }
    }
}

// MARK: - Favorites Settings Section

struct FavoritesSettingsSection: View {
    @ObservedObject var instanceManager: CircularUIInstanceManager
    @State private var selectedFavoriteType: FavoriteType = .folders
    
    enum FavoriteType: String, CaseIterable, Identifiable {
        case folders = "Folders"
        case files = "Files"
        case apps = "Apps"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .folders: return "folder.fill"
            case .files: return "doc.fill"
            case .apps: return "app.fill"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("Favorite Type", selection: $selectedFavoriteType) {
                ForEach(FavoriteType.allCases) { type in
                    Label(type.rawValue, systemImage: type.icon)
                        .tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            Divider()
            
            // Content based on selection
            Group {
                switch selectedFavoriteType {
                case .folders:
                    if let instance = instanceManager.getFirstInstance() {
                        FavoritesSettingsView(circularUI: instance)
                    } else {
                        noInstanceView
                    }
                    
                case .files:
                    if let instance = instanceManager.getFirstInstance(),
                       let filesProvider = instance.favoriteFilesProvider {
                        FavoriteFilesSettingsView(filesProvider: filesProvider)
                    } else {
                        noInstanceView
                    }
                    
                case .apps:
                    if let instance = instanceManager.getFirstInstance(),
                       let appsProvider = instance.functionManager?.favoriteAppsProvider {
                        FavoriteAppsSettingsView(appsProvider: appsProvider)
                    } else {
                        noInstanceView
                    }
                }
            }
        }
        .navigationTitle("Favorites")
    }
    
    private var noInstanceView: some View {
        ContentUnavailableView(
            "No Ring Instance",
            systemImage: "circle.dashed",
            description: Text("Create a ring configuration first")
        )
    }
}

// MARK: - General Settings View

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("playSounds") private var playSounds = false
    
    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                Toggle("Show Menu Bar Icon", isOn: $showMenuBarIcon)
            }
            
            Section("Feedback") {
                Toggle("Play Sounds", isOn: $playSounds)
            }
            
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Build")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}

// MARK: - Advanced Settings View (Developer Tools)

struct AdvancedSettingsView: View {
    @ObservedObject var instanceManager: CircularUIInstanceManager
    @State private var selectedConfigId: Int?
    @State private var availableConfigs: [StoredRingConfiguration] = []
    
    var body: some View {
        Form {
            Section("Instance Management") {
                HStack {
                    Text("Active Instances")
                    Spacer()
                    Text("\(instanceManager.instances.count)")
                        .foregroundColor(.secondary)
                }
                
                Button("Refresh Instances") {
                    instanceManager.syncWithConfigurations()
                }
                
                Button("Hide All Rings") {
                    instanceManager.hideAll()
                }
                
                Button("Print Debug Info") {
                    instanceManager.printDebugInfo()
                }
            }
            
            Section("Ring Testing") {
                Picker("Configuration", selection: $selectedConfigId) {
                    Text("Select a ring...").tag(nil as Int?)
                    ForEach(availableConfigs) { config in
                        Text(config.name).tag(config.id as Int?)
                    }
                }
                
                Button("Test Ring") {
                    if let configId = selectedConfigId {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            CircularUIInstanceManager.shared.show(configId: configId)
                        }
                    }
                }
                .disabled(selectedConfigId == nil)
            }
            
            Section("Data Management") {
                Button("Create Example Configurations") {
                    FirstLaunchConfiguration.createExampleConfigurations()
                    loadConfigurations()
                }
                
                Button("Reload Configurations") {
                    loadConfigurations()
                }
            }
            
            Section("Diagnostics") {
                Button("Copy Debug Log to Clipboard") {
                    // TODO: Implement log export
                    print("📋 Debug log copy requested")
                }
            }
            Section("List Panel Testing") {
                Button("Test Ring → Panel") {
                    if let instance = instanceManager.getFirstInstance() {
                        instance.showTestRingForPanelIntegration()
                    }
                }
                
                Button("Show Test Panel at Mouse") {
                    if let instance = instanceManager.getFirstInstance() {
                        CircularUIInstanceManager.shared.show(configId: instance.configId)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            let mousePos = NSEvent.mouseLocation
                            instance.listPanelManager?.showTestPanel(at: mousePos)
                        }
                    }
                }
                
                Button("Test Panel Cascading") {
                    if let instance = instanceManager.getFirstInstance() {
                        CircularUIInstanceManager.shared.show(configId: instance.configId)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            let mousePos = NSEvent.mouseLocation
                            instance.listPanelManager?.showTestPanel(at: mousePos)
                        }
                    }
                }
                
                Button("Hide Panel") {
                    if let instance = instanceManager.getFirstInstance() {
                        instance.listPanelManager?.hide()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Advanced")
        .onAppear {
            loadConfigurations()
        }
    }
    
    private func loadConfigurations() {
        RingConfigurationManager.shared.loadConfigurations()
        availableConfigs = RingConfigurationManager.shared.getAllConfigurations()
    }
}

// MARK: - Preview

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
#endif
