//
//  ContentSettingsView.swift
//  Jason
//
//  Created by Timothy Velberg on 07/02/2026.
//

import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case instance = "Instances"
    case apps = "Apps"
    case folders = "Folders"
    case files = "Files"
    case snippets = "Snippets"
    case calendar = "Calendar"
    case reminder = "Reminder"
    
    case settings = "Settings"
    
    var id: String { rawValue }
}

struct ContentSettingsView: View {
    @State private var selectedTab: SettingsTab = .instance
    @State private var isSetupComplete = false
    
    private let instanceManager = CircularUIInstanceManager.shared
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Text(tab.rawValue)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .frame(width: 200)
            
            Divider()
            
            // Detail
            Group {
                switch selectedTab {
                case .instance:
                    RingsSettingsView()
                case .folders:
                    FavoriteFoldersViews()
                case .files:
                    FavoriteFilesSettingsView()
                case .apps:
                    FavoriteAppsSettingsView()
                case .snippets:
                    SnippetsSettingsView()
                case .calendar:
                    CalendarSettingsView()
                case .reminder:
                    RemindersSettingsView()
                case .settings:
                    Text("Settings")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            setupApplication()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsWindow)) { notification in
            if let tab = notification.userInfo?["selectedTab"] as? SettingsTab {
                selectedTab = tab
            }
        }
    }
    
    // MARK: - Application Setup
    
    private func setupApplication() {
        print("[ContentSettingsView] Application setup starting...")
        
        // Step 1: Ensure default configuration exists (first launch)
        FirstLaunchConfiguration.ensureDefaultConfiguration()
        
        // Step 2: Load active configurations
        let configManager = RingConfigurationManager.shared
        configManager.loadActiveConfigurations()
        let activeConfigs = configManager.getActiveConfigurations()
        
        print("   Found \(activeConfigs.count) active configuration(s)")
        
        // Step 3: Create CircularUIManager instances
        instanceManager.createInstances(for: activeConfigs)
        
        // Step 4: Register shortcuts
        CircularUIInstanceManager.shared.registerInputTriggers()
        
        // Step 5: Start monitoring
        CircularUIInstanceManager.shared.startHotkeyMonitoring()
        
        // Step 6: Setup each instance
        for (_, instance) in instanceManager.instances {
            instance.setup()
        }
        
        print("   Setup complete - \(instanceManager.instances.count) instance(s) ready")
        
        // Mark setup as complete
        isSetupComplete = true
    }
}
