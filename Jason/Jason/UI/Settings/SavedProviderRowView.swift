//
//  SavedProviderRowView.swift
//  Jason
//
//  Created by Timothy Velberg on 29/04/2026.
//  Row representing an enabled provider inside EditRingView's provider list.
//

import SwiftUI

struct SavedProviderRowView: View {
    let provider: ProviderConfig
    @Binding var instanceSettings: [String: String]
    let isPanelMode: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 16))
                .foregroundColor(.white)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                    .font(.body)
                    .fontWeight(.medium)

                Text(settingsSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "trash")
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Remove provider")
        }
        .padding(.vertical, 8)
    }

    // MARK: - Settings Summary

    private var settingsSummary: String {
        let definitions = ProviderInstanceSettingsRegistry.settings(for: provider.type)
        let parts: [String] = definitions.compactMap { definition in
            guard let value = instanceSettings[definition.key] else { return nil }
            let display = displayName(for: definition.key, value: value)
            return "\(definition.label): \(display)"
        }
        return parts.isEmpty ? provider.description : parts.joined(separator: " · ")
    }

    private func displayName(for key: String, value: String) -> String {
        switch key {
        case "displayMode":
            return ProviderDisplayMode(rawValue: value)?.displayName ?? value
        case "appDisplayMode":
            return AppDisplayMode(rawValue: value)?.displayName ?? value
        default:
            return value
        }
    }
}
