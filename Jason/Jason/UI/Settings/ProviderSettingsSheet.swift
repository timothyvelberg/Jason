//
//  ProviderSettingsSheet.swift
//  Jason
//
//  Created by Timothy Velberg on 11/03/2026.

import SwiftUI

struct ProviderSettingsSheet: View {
    let definitions: [ProviderSettingDefinition]
    let onSave: ([String: String]) -> Void
    let onDismiss: () -> Void

    @State private var values: [String: String]

    init(
        definitions: [ProviderSettingDefinition],
        currentValues: [String: String],
        onSave: @escaping ([String: String]) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.definitions = definitions
        self.onSave = onSave
        self.onDismiss = onDismiss
        _values = State(initialValue: currentValues)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Provider Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Settings rows
            Form {
                ForEach(definitions, id: \.key) { definition in
                    switch definition.type {
                    case .boolean:
                        Toggle(definition.label, isOn: Binding(
                            get: { values[definition.key] == "true" },
                            set: { values[definition.key] = $0 ? "true" : "false" }
                        ))

                    case .options(let opts):
                        Picker(definition.label, selection: Binding(
                            get: { values[definition.key] ?? definition.defaultValue },
                            set: { values[definition.key] = $0 }
                        )) {
                            ForEach(opts, id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal)

            Spacer()

            Divider()

            // Footer
            HStack {
                Button("Cancel", action: onDismiss)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    onSave(values)
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 400, height: 250)
    }
}
