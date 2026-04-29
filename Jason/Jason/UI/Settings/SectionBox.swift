//
//  SectionBox.swift
//  Jason
//
//  Created by Timothy Velberg on 29/04/2026.
//  Lightweight labeled section container used in EditRingView.
//

import SwiftUI

struct SectionBox<Label: View, Content: View>: View {
    let label: () -> Label
    let content: () -> Content

    init(
        @ViewBuilder label: @escaping () -> Label,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.label = label
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            label()
            content()
        }
    }
}
