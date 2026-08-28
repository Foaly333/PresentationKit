//
//  PageGridView.swift
//  PresentationUIKit
//
//  Schnellsprung als Vollbild-Raster aller Seiten (Lichttisch).
//  Tipp auf eine Kachel springt und schliesst, Tipp daneben schliesst nur.
//

import SwiftUI

struct PageGridView: View {

    let viewModel: PresentationViewModel
    let close: () -> Void

    private static let thumbnailWidth: CGFloat = 180

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: Self.thumbnailWidth, maximum: Self.thumbnailWidth * 1.4), spacing: 20)]
    }

    var body: some View {
        ZStack {
            // Tipp daneben schliesst das Overlay.
            Color.black.opacity(0.92)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { close() }

            VStack(spacing: 0) {
                header
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(viewModel.indexedPages) { entry in
                                Button {
                                    viewModel.jump(to: entry.index)
                                    close()
                                } label: {
                                    PageThumbnailView(
                                        page: entry.page,
                                        number: entry.index + 1,
                                        isCurrent: entry.index == viewModel.currentIndex,
                                        width: Self.thumbnailWidth,
                                        viewModel: viewModel
                                    )
                                }
                                .buttonStyle(.plain)
                                .id(entry.id)
                            }
                        }
                        .padding(24)
                    }
                    .onAppear {
                        guard let page = viewModel.currentPage else { return }
                        proxy.scrollTo(page.id, anchor: .center)
                    }
                }
            }
        }
        .accessibilityIdentifier("praesentation.seitengrid")
    }

    private var header: some View {
        HStack {
            Text(localized("Seiten"))
                .font(.title3.weight(.semibold))
            Spacer()
            Button {
                close()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
            }
            .accessibilityIdentifier("praesentation.seitengrid.schliessen")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }
}
