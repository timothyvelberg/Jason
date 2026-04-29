//
//  View+Conditional.swift
//  Jason
//
//  Created by Timothy Velberg on 29/04/2026.
//  Conditional view modifier used across settings and editor views.
//

import SwiftUI

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
