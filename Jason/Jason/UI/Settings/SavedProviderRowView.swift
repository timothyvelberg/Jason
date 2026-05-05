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
    @Binding var displayMode: ProviderDisplayMode
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

                Text(provider.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !isPanelMode {
                Picker("", selection: $displayMode) {
                    ForEach(ProviderDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            Button(action: onRemove) {
                Image(systemName: "trash")
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Remove provider")
        }
        .padding(.vertical, 8)
    }
}
