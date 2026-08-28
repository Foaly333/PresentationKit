//
//  PresentationMirrorView.swift
//  PresentationUIKit
//
//  Nicht-interaktive Spiegelansicht fuer das externe Display (Beamer):
//  zeigt die aktuelle Seite plus Live-Zeichnung aus dem gemeinsamen
//  `PresentationViewModel`, dazu Laserpointer und Arbeitsphasen-Countdown.
//  Blackout und Freeze wirken ausschliesslich hier – auf dem Geraet bleibt
//  das Live-Bild sichtbar.
//

import SwiftUI
import PencilKit

struct PresentationMirrorView: View {

    let viewModel: PresentationViewModel

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if viewModel.isBlackout {
                    // Blackout hat Vorrang vor Freeze.
                    Color.black.ignoresSafeArea()
                } else if viewModel.isFrozen, let snapshot = viewModel.freezeSnapshot {
                    Image(uiImage: snapshot)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    content(in: geometry.size)
                }

                if !viewModel.isBlackout {
                    SessionTimerOverlay(timer: viewModel.sessionTimer)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 32)
                }

                // Quiz-Spiegel — lesend, Zustand kommt vom Geraet.
                if !viewModel.isBlackout, viewModel.activeQuiz != nil {
                    QuizMirrorView(viewModel: viewModel)
                        .transition(.opacity)
                }
            }
        }
    }

    @ViewBuilder
    private func content(in available: CGSize) -> some View {
        ZStack {
            pageBackground
            // Eingefuegte Bilder — dieselbe Ebene wie auf dem Geraet, hier auf
            // die Beamer-Flaeche skaliert.
            PageImagesLayer(viewModel: viewModel)
            if let drawingImage = renderedDrawing() {
                Image(uiImage: drawingImage)
                    .resizable()
            }
        }
        // Identische Abdeckflaechen wie auf dem Geraet — der Beamer deckt auf,
        // sobald auf dem Geraet aufgetippt wird.
        .overlay { RevealMirrorOverlay(viewModel: viewModel) }
        // Als Overlay auf der Seitenflaeche – so beeinflusst der Punkt das Layout
        // nicht und liegt im selben Rechteck wie das Seitenbild.
        .overlay { laserPointer }
        .aspectRatio(viewModel.aspectRatio, contentMode: .fit)
        .frame(width: available.width, height: available.height)
    }

    /// Der Punkt liegt im kanonischen Raum und wird auf die tatsaechliche
    /// Beamer-Flaeche umgerechnet – dadurch zeigt er dorthin, wo getippt wird.
    @ViewBuilder
    private var laserPointer: some View {
        if let point = viewModel.laserPointerPosition {
            GeometryReader { bounds in
                LaserPointerDotView(
                    position: CGPoint(
                        x: point.x / viewModel.canonicalSize.width * bounds.size.width,
                        y: point.y / viewModel.canonicalSize.height * bounds.size.height
                    )
                )
            }
        }
    }

    @ViewBuilder
    private var pageBackground: some View {
        if let image = viewModel.currentBaseImage {
            Image(uiImage: image)
                .resizable()
        } else {
            Color.white
        }
    }

    /// Rendert die Live-Zeichnung im kanonischen Seitenraum – dadurch liegen
    /// die Striche auf dem Beamer exakt an derselben Stelle wie auf dem Geraet.
    private func renderedDrawing() -> UIImage? {
        guard !viewModel.currentDrawing.strokes.isEmpty else { return nil }
        return viewModel.currentDrawing.image(
            from: CGRect(origin: .zero, size: viewModel.canonicalSize),
            scale: 2
        )
    }
}
