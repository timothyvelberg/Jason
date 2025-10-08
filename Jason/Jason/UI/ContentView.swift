//
//  ContentView.swift
//  Jason
//
//  Created by Timothy Velberg on 31/07/2025.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var appSwitcher = AppSwitcherManager()
    @StateObject private var circularUI = CircularUIManager()
    
    var body: some View {
        Group {
            if !appSwitcher.hasAccessibilityPermission {
                PermissionRequestView(appSwitcher: appSwitcher, circularUI: circularUI)
            } else if appSwitcher.isVisible {
                AppSwitcherView(appSwitcher: appSwitcher)
            } else {
                MinimalView(circularUI: circularUI)
            }
        }
        .onAppear {
            print("🚀 ContentView appeared")
            circularUI.setup(with: appSwitcher)
        }
        .onDisappear {
            print("👋 ContentView disappeared - stopping services")
            appSwitcher.stopAutoRefresh()
        }
    }
}

// MARK: - Permission Request View

struct PermissionRequestView: View {
    let appSwitcher: AppSwitcherManager
    @ObservedObject var circularUI: CircularUIManager
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            
            Text("Accessibility Permission Required")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Jason needs Accessibility permission to detect global keyboard shortcuts (Ctrl+2) and function as an app switcher.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(spacing: 10) {
                Text("To grant permission:")
                    .fontWeight(.medium)
                
                Text("1. Click 'Open System Preferences' below")
                Text("2. Find 'Jason' in the list")
                Text("3. Check the box next to 'Jason'")
                Text("4. Come back and click 'Check Again'")
            }
            .font(.system(size: 14))
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            HStack(spacing: 15) {
                Button("Open System Preferences") {
                    appSwitcher.openAccessibilityPreferences()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Check Again") {
                    appSwitcher.checkAccessibilityPermission()
                }
                .buttonStyle(.bordered)
            }
            
            // Development testing buttons
            Divider()
                .padding(.vertical, 10)
            
            Text("Development Testing")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 10) {
                Button("Test Circular UI") {
                    circularUI.show()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Hide") {
                    circularUI.hide()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(30)
        .frame(maxWidth: 500)
    }
}

// MARK: - Minimal Hidden View

struct MinimalView: View {
    @ObservedObject var circularUI: CircularUIManager
    
    var body: some View {
        VStack(spacing: 10) {
            Text("Jason App Switcher")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Test Circular UI") {
                circularUI.show()
            }
            .buttonStyle(.borderedProminent)
            
            Button("Hide Circular UI") {
                circularUI.hide()
            }
            .buttonStyle(.bordered)
        }
        .frame(width: 200, height: 100)
    }
}

// MARK: - App Switcher View

struct AppSwitcherView: View {
    @ObservedObject var appSwitcher: AppSwitcherManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HeaderView(appSwitcher: appSwitcher)
            AppListView(appSwitcher: appSwitcher)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 10)
    }
}

// MARK: - Header View

struct HeaderView: View {
    let appSwitcher: AppSwitcherManager
    
    var body: some View {
        HStack {
            Text("Running Applications")
                .font(.title)
            
            Spacer()
            
            Button("Hide") {
                appSwitcher.hideAppSwitcher()
            }
            .buttonStyle(.bordered)
            
            Text("\(appSwitcher.runningApps.count) apps")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 10)
    }
}

// MARK: - App List View

struct AppListView: View {
    @ObservedObject var appSwitcher: AppSwitcherManager
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(Array(appSwitcher.runningApps.enumerated()), id: \.element.processIdentifier) { index, app in
                    AppRowView(
                        app: app,
                        isSelected: index == appSwitcher.selectedAppIndex,
                        onTap: { appSwitcher.switchToApp(app) }
                    )
                }
            }
        }
    }
}

// MARK: - App Row View

struct AppRowView: View {
    let app: NSRunningApplication
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack {
            // App icon
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(app.localizedName ?? "Unknown")
                    .font(.headline)
                
                Text(app.bundleIdentifier ?? "Unknown ID")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Status indicators
            if app.isActive {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
            }
            
            if app.isHidden {
                Image(systemName: "eye.slash")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(strokeColor, lineWidth: 2)
        )
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return Color.blue.opacity(0.3) // Selected app
        } else if app.isActive {
            return Color.green.opacity(0.1) // Active app
        } else {
            return Color.clear
        }
    }
    
    private var strokeColor: Color {
        if isSelected {
            return Color.blue // Selected app border
        } else if app.isActive {
            return Color.green.opacity(0.5) // Active app border
        } else {
            return Color.clear
        }
    }
}
