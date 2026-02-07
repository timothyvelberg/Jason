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
        case snippets = "Snippets"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .folders: return "folder.fill"
            case .files: return "doc.fill"
            case .apps: return "app.fill"
            case .snippets: return "pencil.line"
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
                    if let instance = instanceManager.instances.values
                        .compactMap({ $0 as? CircularUIManager })
                        .first(where: {
                            $0.functionManager?.providers.contains(where: { $0 is FavoriteFolderProvider }) ?? false
                        }) {
                        FavoriteFoldersViews()
                    } else {
                        noProviderView(for: "Favorite Folders", providerType: "FavoriteFolderProvider")
                    }
                    
                case .files:
                    if let filesProvider = instanceManager.instances.values
                        .compactMap({ $0 as? CircularUIManager })
                        .compactMap({ $0.favoriteFilesProvider })
                        .first {
                        FavoriteFilesSettingsView(filesProvider: filesProvider)
                    } else {
                        noProviderView(for: "Favorite Files", providerType: "FavoriteFilesProvider")
                    }
                    
                case .apps:
                    if let appsProvider = instanceManager.instances.values
                        .compactMap({ $0 as? CircularUIManager })
                        .compactMap({ $0.functionManager?.favoriteAppsProvider })
                        .first {
                        FavoriteAppsSettingsView(appsProvider: appsProvider)
                    } else {
                        noProviderView(for: "Favorite Apps", providerType: "CombinedAppsProvider")
                    }
                case .snippets:
                    SnippetsSettingsView()
                }
            }
        }
        .navigationTitle("Favorites")
    }
    
    // Replace noInstanceView with this more informative version:
    private func noProviderView(for name: String, providerType: String) -> some View {
        ContentUnavailableView(
            "No \(name) Provider",
            systemImage: "circle.dashed",
            description: Text("Add \(providerType) to a ring configuration to manage \(name.lowercased())")
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
