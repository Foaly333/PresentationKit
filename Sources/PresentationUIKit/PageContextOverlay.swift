//
//  PageContextOverlay.swift
//  PresentationUIKit
//
//  Einblendbare Karte mit der Beschreibung des aktuellen Seitenkontexts
//  (Agenda-Abschnitt des praesentierten Materials) — reine Operator-Ansicht
//  auf dem Geraet, der Beamer (PresentationMirrorView) bleibt unberuehrt.
//  Der Inhalt folgt Seitenwechseln automatisch (`currentPageContext` im
//  ViewModel).
//

import PresentationCoreKit
import SwiftUI

struct PageContextOverlay: View {

    let context: PageContext
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(context.title.strippingHTMLTags)
                    .font(.headline)
                if let form = context.form, !form.isEmpty {
                    Text(form)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.2), in: Capsule())
                }
                Spacer()
                Button {
                    close()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.7))
                }
                .accessibilityIdentifier("praesentation.phasenbeschreibung.schliessen")
                .accessibilityLabel(Text(localized("Beschreibung schließen")))
            }

            if let detail = context.detail?.strippingHTMLTags,
               !detail.isEmpty {
                Text(detail)
                    .font(.subheadline)
            } else {
                Text(localized("Keine Beschreibung hinterlegt."))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: 380, alignment: .leading)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("praesentation.phasenbeschreibung.karte")
    }
}
