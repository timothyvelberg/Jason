//
//  ProviderDisplayMode.swift
//  Jason
//
//  Created by Timothy Velberg on 29/04/2026.
//  Display mode for a content provider within a ring or panel instance.
//

import Foundation

enum ProviderDisplayMode: String, CaseIterable {
    case parent
    case direct

    var displayName: String {
        switch self {
        case .parent: return "Parent"
        case .direct: return "Direct"
        }
    }
}
