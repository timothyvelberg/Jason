//
//  AddProviderSheet.swift
//  Jason
//
//  Created by Timothy Velberg on 29/04/2026.
//  Sheet for selecting and adding a content provider to a ring or panel instance.
//
//  Sheet for selecting and adding a content provider to a ring or panel instance.

import SwiftUI

struct AddProviderSheet: View {
    @Environment(\.dismiss) var dismiss

    let availableProviders: [ProviderConfig]
    let isPanelMode: Bool
    let onAdd: (String, [String: String]) -> Void

    @State private var selectedType: String? = nil
    @State private var instanceSettings: [String: String] = [:]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Provider")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // Provider list
                    VStack(spacing: 4) {
                        ForEach(availableProviders) { provider in
                            VStack(spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(provider.name)
                                            .fontWeight(.medium)
                                        Text(provider.description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if selectedType == provider.type {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedType == provider.type ? Color.blue.opacity(0.08) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedType == provider.type ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedType = provider.type
                                    instanceSettings = ProviderInstanceSettingsRegistry.defaultSettings(for: provider.type)
                                }

                                // Settings expand inline below this provider when selected
                                if selectedType == provider.type {
                                    let definitions = isPanelMode
                                        ? ProviderInstanceSettingsRegistry.settings(for: provider.type).filter { $0.key != "displayMode" }
                                        : ProviderInstanceSettingsRegistry.settings(for: provider.type)

                                    if !definitions.isEmpty {
                                        VStack(alignment: .trailing, spacing: 12) {
                                            ForEach(definitions, id: \.key) { definition in
                                                HStack {
                                                    Text(definition.label)
                                                        .font(.body)
                                                        .foregroundColor(.secondary)
                                                    Spacer()
                                                    instanceSettingControl(definition: definition)
                                                }
                                            }
                                        }
                                        .padding(16)
                                        .frame(maxWidth: .infinity)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.blue.opacity(0.04))
                                        )
                                        .padding(.top, 2)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Add") {
                    if let type = selectedType {
                        onAdd(type, instanceSettings)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedType == nil)
            }
            .padding()
        }
        .frame(width: 512, height: 512)
    }

    // MARK: - Setting Control

    @ViewBuilder
    private func instanceSettingControl(definition: ProviderSettingDefinition) -> some View {
        switch definition.type {
        case .boolean:
            let currentValue = instanceSettings[definition.key] ?? definition.defaultValue
            Menu {
                Button("On")  { instanceSettings[definition.key] = "true" }
                Button("Off") { instanceSettings[definition.key] = "false" }
            } label: {
                HStack(spacing: 4) {
                    Text(currentValue == "true" ? "On" : "Off")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

        case .options(let options):
            let currentValue = instanceSettings[definition.key] ?? definition.defaultValue
            let displayNames = optionDisplayNames(for: definition.key, options: options)
            Menu {
                ForEach(options, id: \.self) { option in
                    Button {
                        instanceSettings[definition.key] = option
                    } label: {
                        HStack {
                            Text(displayNames[option] ?? option)
                            if currentValue == option {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(displayNames[currentValue] ?? currentValue)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: - Display Name Helpers

    private func optionDisplayNames(for key: String, options: [String]) -> [String: String] {
        switch key {
        case "displayMode":
            return [
                "parent": ProviderDisplayMode.parent.displayName,
                "direct": ProviderDisplayMode.direct.displayName
            ]
        case "appDisplayMode":
            return Dictionary(
                uniqueKeysWithValues: AppDisplayMode.allCases.map { ($0.rawValue, $0.displayName) }
            )
        default:
            return [:]
        }
    }
}
