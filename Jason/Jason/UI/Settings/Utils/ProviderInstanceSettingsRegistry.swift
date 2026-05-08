//
//  ProviderInstanceSettingsRegistry.swift
//  Jason
//
//  Created by Timothy Velberg on 08/05/2026.
//
//  Maps provider type strings to their instance-level setting definitions.
//  Used by AddProviderSheet to render per-provider options dynamically.
//

import Foundation

struct ProviderInstanceSettingsRegistry {

    // MARK: - Registry

    private static let registry: [String: [ProviderSettingDefinition]] = [
        "CombinedAppsProvider": [
            ProviderSettingDefinition(
                key: "displayMode",
                label: "Display Mode",
                type: .options(["parent", "direct"]),
                defaultValue: "direct"
            ),
            ProviderSettingDefinition(
                key: "appDisplayMode",
                label: "App Filter",
                type: .options(AppDisplayMode.allCases.map { $0.rawValue }),
                defaultValue: AppDisplayMode.all.rawValue
            )
        ]
    ]

    // MARK: - Default display mode entry (for all other providers)

    static let displayModeSetting = ProviderSettingDefinition(
        key: "displayMode",
        label: "Display Mode",
        type: .options(["parent", "direct"]),
        defaultValue: "parent"
    )

    // MARK: - Public Interface

    /// Returns instance-level setting definitions for the given provider type.
    /// All providers get at least the display mode setting.
    static func settings(for providerType: String) -> [ProviderSettingDefinition] {
        return registry[providerType] ?? [displayModeSetting]
    }

    /// Returns the default instance settings for a provider type.
    static func defaultSettings(for providerType: String) -> [String: String] {
        return Dictionary(
            uniqueKeysWithValues: settings(for: providerType).map { ($0.key, $0.defaultValue) }
        )
    }
}
