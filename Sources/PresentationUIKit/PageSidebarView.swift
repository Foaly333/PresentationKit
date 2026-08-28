//
//  PageSidebarView.swift
//  PresentationUIKit
//
//  Aufklappbare Seitenleiste mit vertikaler Seitenvorschau. Tipp auf eine
//  Kachel springt direkt zur Seite; beim Oeffnen scrollt die Leiste zur
//  aktuellen Seite.
//

import SwiftUI

struct PageSidebarView: View {

    let viewModel: PresentationViewModel

    private static let thumbnailWidth: CGFloat = 120

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.indexedPages) { entry in
                        Button {
                            viewModel.jump(to: entry.index)
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
                .padding(.vertical, 16)
                .padding(.horizontal, 12)
            }
            .onAppear { scrollToCurrentPage(proxy) }
            .onChange(of: viewModel.currentIndex) { scrollToCurrentPage(proxy) }
        }
        .frame(width: Self.thumbnailWidth + 24)
        .background(.black.opacity(0.85))
        .accessibilityIdentifier("praesentation.seitenleiste")
    }

    private func scrollToCurrentPage(_ proxy: ScrollViewProxy) {
        guard let page = viewModel.currentPage else { return }
        proxy.scrollTo(page.id, anchor: .center)
    }
}
