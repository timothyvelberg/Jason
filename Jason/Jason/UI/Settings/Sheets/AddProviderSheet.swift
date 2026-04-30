//
//  AddProviderSheet.swift
//  Jason
//
//  Created by Timothy Velberg on 29/04/2026.
//  Sheet for selecting and adding a content provider to a ring or panel instance.
//

import SwiftUI

struct AddProviderSheet: View {
    @Environment(\.dismiss) var dismiss

    let availableProviders: [ProviderConfig]
    let isPanelMode: Bool
    let onAdd: (String, ProviderDisplayMode) -> Void

    @State private var selectedType: String? = nil
    @State private var displayMode: ProviderDisplayMode = .parent

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
                            .onTapGesture { selectedType = provider.type }
                        }
                    }

                    // Display mode — ring mode only, shown once a provider is selected
                    if !isPanelMode && selectedType != nil {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Display Mode")
                                .font(.body)
                                .fontWeight(.medium)
                            Text("Parent shows this provider as a slice in the ring. Direct shows its contents immediately.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Picker("", selection: $displayMode) {
                                ForEach(ProviderDisplayMode.allCases, id: \.self) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)
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
                        onAdd(type, displayMode)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedType == nil)
            }
            .padding()
        }
        .frame(width: 480, height: 500)
    }
}
