//
//  SettingsTab.swift
//  Jason
//
//  Created by Timothy Velberg on 25/02/2026.

import Foundation

enum SettingsTab: String, CaseIterable, Identifiable {
    case instance = "Instances"
    case apps = "Apps"
    case folders = "Folders"
    case files = "Files"
    case snippets = "Snippets"
    case calendar = "Calendar"
    case reminder = "Reminder"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .instance:  return "core_settings_menu_instance"
        case .apps:      return "core_settings_menu_apps"
        case .folders:   return "core_settings_menu_folders"
        case .files:     return "core_settings_menu_files"
        case .snippets:  return "core_settings_menu_snippets"
        case .calendar:  return "core_settings_menu_calendar"
        case .reminder:  return "core_settings_menu_reminders"
        case .settings:  return "core_settings_menu_settings"
        }
    }
}
