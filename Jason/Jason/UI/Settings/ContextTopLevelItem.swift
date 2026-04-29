//
//  ContextTopLevelItem.swift
//  Jason
//
//  Created by Timothy Velberg on 29/04/2026.
//  A top-level item in a shortcut list — either a group or an ungrouped shortcut.
//  Shared between EditContextInstanceSheet (editable) and
//  ContextShortcutsSettingsView (read-only summary).
//

import Foundation

enum ContextTopLevelItem: Identifiable {
    case group(ContextShortcutGroup)
    case ungroupedShortcut(ContextShortcut)

    var id: String {
        switch self {
        case .group(let g):            return "group-\(g.id)"
        case .ungroupedShortcut(let s): return "shortcut-\(s.id)"
        }
    }

    var sortOrder: Int {
        switch self {
        case .group(let g):            return g.sortOrder
        case .ungroupedShortcut(let s): return s.sortOrder
        }
    }
}
