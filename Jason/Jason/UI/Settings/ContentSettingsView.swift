//
//  ContentSettingsView.swift
//  Jason
//
//  Created by Timothy Velberg on 07/02/2026.
//

import SwiftUI

struct ContentSettingsView: View {
    @State private var selectedTab: SettingsTab = .instance
    @State private var isSetupComplete = false
    @State private var showRestartAlert: Bool = false
    @State private var permissionManager = AccessibilityPermissionManager.shared

    private let instanceManager = CircularUIInstanceManager.shared

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selectedTab) {
                Section {
                    ForEach(SettingsTab.allCases) { tab in
                        Label {
                            HStack {
                                Text(tab.rawValue)
                                    .font(.system(size: 14))
                                Spacer()
                                if tab == .settings {
                                    permissionBadge
                                }
                            }
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
            .onChange(of: selectedTab) { _, newTab in
                if newTab == .settings && permissionManager.state == .grantedPendingRestart {
                    showRestartAlert = true
                }
            }

            Divider()

            Group {
                switch selectedTab {
                case .instance:   RingsSettingsView()
                case .folders:    FavoriteFoldersViews()
                case .files:      FavoriteFilesSettingsView()
                case .apps:       FavoriteAppsSettingsView()
                case .snippets:   SnippetsSettingsView()
                case .calendar:   CalendarSettingsView()
                case .reminder:   RemindersSettingsView()
                case .settings:   GeneralSettingsView()
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
        .alert("Restart Required", isPresented: $showRestartAlert) {
            Button("Restart Now") {
                NSApplication.shared.relaunch()
            }
        } message: {
            Text("Accessibility access has been granted. Jason needs to restart to activate hotkey monitoring.")
        }
    }

    // MARK: - Permission Badge

    @ViewBuilder
    private var permissionBadge: some View {
        switch permissionManager.state {
        case .notGranted:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.red)
        case .grantedPendingRestart:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.orange)
        case .active:
            EmptyView()
        }
    }

    // MARK: - Application Setup

    private func setupApplication() {
        print("[ContentSettingsView] Application setup starting...")
        FirstLaunchConfiguration.ensureDefaultConfiguration()
        let configManager = RingConfigurationManager.shared
        configManager.loadActiveConfigurations()
        let activeConfigs = configManager.getActiveConfigurations()
        print("   Found \(activeConfigs.count) active configuration(s)")
        instanceManager.createInstances(for: activeConfigs)
        CircularUIInstanceManager.shared.registerInputTriggers()
        CircularUIInstanceManager.shared.startHotkeyMonitoring()
        for (_, instance) in instanceManager.instances {
            instance.setup()
        }
        print("   Setup complete - \(instanceManager.instances.count) instance(s) ready")
        isSetupComplete = true
    }
}
