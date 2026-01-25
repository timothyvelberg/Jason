//
//  ContentView.swift
//  Jason
//
//  Updated to use SettingsView for proper settings experience
//

import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var instanceManager = CircularUIInstanceManager.shared
    @State private var isSetupComplete = false
    
    var body: some View {
        Group {
            if isSetupComplete {
                SettingsView()
            } else {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(0.8)
                    
                    Text("Setting up...")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            setupApplication()
        }
    }
    
    private func setupApplication() {
        print("[ContentView] Application setup starting...")
        
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

// MARK: - Preview

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
