//
//  PreviewPanelView.swift
//  Jason
//
//  Created by Timothy Velberg on 27/02/2026.
//  Preview panel view for displaying image or text content
//  alongside the active list panel.
//

import SwiftUI
import AppKit

// MARK: - Preview Panel View

struct PreviewPanelView: View {
    let content: PreviewContent
    let config: PanelConfig
    let title: String

    private var cornerRadius: CGFloat { 12 }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: PanelConfig.titleHeight)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 1)
            }

            contentView
        }
        .frame(width: config.previewPanelWidth)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.black.opacity(0.33))
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    @ViewBuilder
    private var contentView: some View {
        switch content {
        case .image(let image):
            ImagePreviewView(image: image, config: config)
        case .text(let text):
            TextPreviewView(text: text, config: config)
        case .unsupported:
            UnsupportedPreviewView()
        }
    }
}

// MARK: - Image Preview

struct ImagePreviewView: View {
    let image: NSImage
    let config: PanelConfig

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: config.previewPanelWidth)
            .frame(maxHeight: config.previewPanelMaxHeight - PanelConfig.titleHeight)
            .padding(12)
    }
}

// MARK: - Text Preview

struct TextPreviewView: View {
    let text: String
    let config: PanelConfig

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(maxHeight: config.previewPanelMaxHeight - PanelConfig.titleHeight)
    }
}

// MARK: - Unsupported Preview

struct UnsupportedPreviewView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "eye.slash")
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.4))

            Text("No preview available")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}
