//
//  AddContextInstanceSheet.swift
//  Jason
//
//  Created by Timothy Velberg on 25/04/2026.
//  Lightweight sheet for creating a new context-scoped ring instance.
//  Ring mode and ContextProvider are set automatically.
//

import SwiftUI

struct AddContextInstanceSheet: View {
    @Environment(\.dismiss) var dismiss

    let bundleId: String
    let onSave: () -> Void

    @State private var name: String = ""
    @State private var triggers: [TriggerFormConfig] = []
    @State private var showAddTriggerSheet = false
    @State private var errorMessage: String?
    @State private var appIcon: NSImage?

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !triggers.isEmpty &&
        triggers.allSatisfy { $0.isValid }
    }

    var body: some View {
        VStack(spacing: 0) {

            // Header
            HStack {
                if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                }
                Text("New Instance")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.headline)
                        TextField("e.g. Basic, Shapes, Text", text: $name)
                            .textFieldStyle(.roundedBorder)
                        Text("Identifies this instance in the Shortcuts tab.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Trigger
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Trigger")
                                .font(.headline)
                            Spacer()
                            Button(action: { showAddTriggerSheet = true }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                            .help("Add trigger")
                        }

                        if triggers.isEmpty {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Image(systemName: "keyboard.badge.ellipsis")
                                        .font(.system(size: 32))
                                        .foregroundColor(.secondary.opacity(0.5))
                                    Text("No trigger configured")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("Add a keyboard shortcut, mouse button, or trackpad gesture")
                                        .font(.caption2)
                                        .foregroundColor(.secondary.opacity(0.8))
                                }
                                .padding(.vertical, 20)
                                Spacer()
                            }
                        } else {
                            VStack(spacing: 8) {
                                ForEach(triggers) { trigger in
                                    TriggerRowView(trigger: trigger) {
                                        withAnimation {
                                            triggers.removeAll { $0.id == trigger.id }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .sheet(isPresented: $showAddTriggerSheet) {
                        AddTriggerSheet(existingTriggers: triggers) { newTrigger in
                            withAnimation {
                                triggers.append(newTrigger)
                            }
                        }
                    }

                    // Error
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
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
                Button("Create") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 480, height: 420)
    }

    // MARK: - Save

    private func save() {
        errorMessage = nil

        let shortcutDisplay = triggers.first?.displayDescription ?? "No trigger"

        let triggerData: [(type: String, keyCode: UInt16?, modifierFlags: UInt, buttonNumber: Int32?, swipeDirection: String?, fingerCount: Int?, isHoldMode: Bool, isModifierHoldMode: Bool, autoExecuteOnRelease: Bool)] = triggers.map { trigger in
            (
                type: trigger.triggerType.rawValue,
                keyCode: trigger.triggerType == .keyboard ? trigger.keyCode : nil,
                modifierFlags: trigger.modifierFlags,
                buttonNumber: trigger.triggerType == .mouse ? trigger.buttonNumber : nil,
                swipeDirection: trigger.triggerType == .trackpad ? trigger.swipeDirection.rawValue : nil,
                fingerCount: trigger.triggerType == .trackpad ? trigger.fingerCount : nil,
                isHoldMode: trigger.isHoldMode,
                isModifierHoldMode: trigger.isModifierHoldMode,
                autoExecuteOnRelease: trigger.autoExecuteOnRelease
            )
        }

        let providerData: [(type: String, order: Int, displayMode: String?, angle: Double?)] = [
            ("ContextProvider", 1, "parent", nil)
        ]

        do {
            _ = try RingConfigurationManager.shared.createConfiguration(
                name: name.trimmingCharacters(in: .whitespaces),
                shortcut: shortcutDisplay,
                ringRadius: 80,
                centerHoleRadius: 56,
                iconSize: 32,
                startAngle: 0,
                presentationMode: .ring,
                bundleId: bundleId,
                triggers: triggerData,
                providers: providerData
            )
            print("✅ [AddContextInstanceSheet] Created instance '\(name)' for \(bundleId)")
            onSave()
            dismiss()
        } catch {
            errorMessage = "Failed to create instance: \(error.localizedDescription)"
            print("❌ [AddContextInstanceSheet] \(error)")
        }
    }
}
