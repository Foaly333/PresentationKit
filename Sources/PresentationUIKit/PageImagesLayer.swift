//
//  PageImagesLayer.swift
//  PresentationUIKit
//
//  Rein darstellende Ebene fuer die vom Nutzer eingefuegten Bilder (z. B.
//  QR-Codes) einer Seite. Liegt UNTER dem PencilKit-Canvas — Striche werden
//  also ueber die Bilder gezeichnet. Wird auf dem Geraet (kanonischer Raum,
//  Skala 1) und auf dem Beamer (skaliert) identisch verwendet; waehrend einer
//  Geste gilt der Live-Rahmen des ViewModels, damit Verschieben und Skalieren
//  fluessig sichtbar sind.
//

import SwiftUI

struct PageImagesLayer: View {
    let viewModel: PresentationViewModel

    var body: some View {
        GeometryReader { bounds in
            let scale = bounds.size.width / viewModel.canonicalSize.width
            ForEach(viewModel.identifiedImageElements) { entry in
                if let image = viewModel.elementImages[entry.id] {
                    let frame = viewModel.frame(for: entry.element)
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: frame.width * scale, height: frame.height * scale)
                        .offset(x: frame.minX * scale, y: frame.minY * scale)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityIdentifier("praesentation.bilder.ebene")
    }
}
