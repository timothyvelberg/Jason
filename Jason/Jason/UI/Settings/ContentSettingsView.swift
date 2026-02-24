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
    
    var icon: String {
        switch self {
        case .instance:  return "core_settings_menu_instance"
        case .apps:      return "core_settings_menu_apps"
        case .folders:   return "core_settings_menu_folders"
        case .files:     return "core_settings_menu_files"
        case .snippets:  return "core_settings_menu_snippets"
        case .calendar:  return "core_settings_menu_calendar"
        case .reminder:  return "core_settings_menu_reminders"
        case .settings:  return "core_settings_menu_settings"
        }
    }
}

struct ContentSettingsView: View {
    @State private var selectedTab: SettingsTab = .instance
    @State private var isSetupComplete = false
    
    private let instanceManager = CircularUIInstanceManager.shared
    
    var body: some View {
        
        HStack(spacing: 0) {
            List(selection: $selectedTab) {
                Section {
                    ForEach(SettingsTab.allCases) { tab in
                        Label {
                            Text(tab.rawValue)
                                .font(.system(size: 14))
                        } icon: {
                            Image(tab.icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                        }
                        .tag(tab)
                    }
                } header: {
                    Image("core_logo")
                        .resizable()
                        .frame(width: 48, height: 48)
                        .padding(.top, 48)
                        .padding(.bottom, 16)
                        .frame(maxWidth: .infinity)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
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
