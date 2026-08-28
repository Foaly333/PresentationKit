//
//  PageThumbnailView.swift
//  PresentationUIKit
//
//  Seitenvorschau als Kachel – gemeinsam genutzt von Seitenleiste und
//  Grid-Overlay. Laedt ihr Thumbnail beim Erscheinen nach (Cache im ViewModel).
//

import PresentationCoreKit
import SwiftUI

struct PageThumbnailView: View {

    let page: any PresentationPage
    /// Anzeigenummer (1-basiert).
    let number: Int
    let isCurrent: Bool
    let width: CGFloat
    let viewModel: PresentationViewModel

    private var thumbnail: UIImage? { viewModel.thumbnails[page.id] }

    var body: some View {
        VStack(spacing: 4) {
            preview
                .frame(width: width, height: width * 3 / 4)
                .clipped()
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .bottomTrailing) { penBadge }
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isCurrent ? Color.accentColor : .white.opacity(0.25),
                                      lineWidth: isCurrent ? 3 : 1)
                }

            Text("\(number)")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(isCurrent ? Color.accentColor : .white.opacity(0.7))
        }
        .contentShape(Rectangle())
        .accessibilityIdentifier("praesentation.kachel.\(number)")
        .accessibilityLabel(Text(localized("Seite \(number)")))
        .task { await viewModel.loadThumbnailIfNeeded(for: page) }
    }

    @ViewBuilder
    private var preview: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if page.isWhiteboard {
            // Whiteboard: weisse Kachel ohne Dekodierung.
            Color.white
        } else {
            Color.white.overlay { ProgressView().controlSize(.small) }
        }
    }

    @ViewBuilder
    private var penBadge: some View {
        if viewModel.hasAnnotations(page) {
            Image(systemName: "pencil.tip")
                .font(.caption2)
                .foregroundStyle(.white)
                .padding(3)
                .background(.black.opacity(0.65), in: Circle())
                .padding(3)
                .accessibilityHidden(true)
        }
    }
}
