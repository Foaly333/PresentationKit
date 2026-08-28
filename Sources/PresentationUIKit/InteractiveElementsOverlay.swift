//
//  InteractiveElementsOverlay.swift
//  PresentationUIKit
//
//  Tap-Flaechen fuer die interaktiven Elemente ueber dem Seitenbild — im
//  kanonischen 1024-pt-Raum layoutet, deckungsgleich mit den gedruckten Badges.
//
//  Bewusste Abweichung: Die Flaechen liegen UEBER dem PencilKit-Canvas, nicht
//  darunter — PKCanvasView reicht Touches nicht an dahinterliegende Views
//  durch (UIKit-Hit-Testing). Die Flaechen sind klein (Badge-Groesse), ein
//  Strich, der genau dort ansetzt, geht als Tap statt als Zeichnung — im
//  Alltag vernachlaessigbar.
//
//  Eigene Marker-Typen aus der Element-Registry der Konfiguration werden an
//  ihrer Element-Position gerendert; unbekannte Typen ohne Registrierung
//  erscheinen nicht.
//

import PresentationCoreKit
import SwiftUI

/// Overlay ueber der Seitenflaeche (Geraet, steuernd): eine Tap-Flaeche je Element.
struct InteractiveElementsOverlay: View {
    let viewModel: PresentationViewModel
    let configuration: PresentationConfiguration
    /// Medium-Tap: die View drumherum praesentiert QuickLook/Safari.
    let onMedia: (InteractiveElement) -> Void

    /// Kurzes Pulse-Feedback nach einem Timer-Start.
    @State private var pulsingElement: UUID?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(viewModel.currentElements) { element in
                surface(for: element)
            }
        }
        .frame(width: viewModel.canonicalSize.width,
               height: viewModel.canonicalSize.height,
               alignment: .topLeading)
        .allowsHitTesting(!viewModel.isLaserPointerActive)
    }

    // MARK: - Flaechen je Typ

    @ViewBuilder
    private func surface(for element: InteractiveElement) -> some View {
        switch element.kind {
        case InteractiveElement.Kind.timer where configuration.showsTimer:
            tapSurface(for: element, systemImage: "timer") {
                let minutes = element.data["minuten"]?.intValue ?? 5
                viewModel.startTimer(minutes: minutes)
                pulse(element)
            }
        case InteractiveElement.Kind.media:
            tapSurface(for: element, systemImage: "play.rectangle") {
                onMedia(element)
                pulse(element)
            }
        case InteractiveElement.Kind.quiz:
            tapSurface(for: element, systemImage: "questionmark.circle") {
                viewModel.openQuiz(element)
            }
        case InteractiveElement.Kind.reveal:
            if !viewModel.isRevealed(element) {
                cover(for: element)
            }
        default:
            // Registrierte eigene Typen an der Element-Position; der Rahmen
            // bekommt dieselbe Mindest-Tap-Flaeche wie die eingebauten Typen.
            if let renderer = configuration.customElementRenderers[element.kind] {
                let frame = tapFrame(element.frame)
                renderer(element)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
    }

    /// Transparente Tap-Flaeche am Badge-Anker. Nullgroessen-Rahmen (Timer,
    /// Medium, Quiz melden keine Ausdehnung) werden auf eine Mindest-Tap-
    /// Flaeche aufgeblasen (44 pt kanonisch, um den Anker zentriert).
    private func tapSurface(
        for element: InteractiveElement,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        let frame = tapFrame(element.frame)
        return Button(action: action) {
            Color.clear
                .contentShape(Rectangle())
                .overlay(alignment: .topTrailing) {
                    // Dezenter Interaktions-Hinweis am Badge; pulst nach dem Tap.
                    Image(systemName: systemImage)
                        .font(.system(size: 22))
                        .foregroundStyle(.blue.opacity(0.75))
                        .scaleEffect(pulsingElement == element.id ? 1.6 : 1)
                        .animation(.spring(duration: 0.35), value: pulsingElement)
                }
        }
        .buttonStyle(.plain)
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        .accessibilityIdentifier("praesentation.element.\(element.kind)")
    }

    /// Deckende Flaeche eines nicht aufgedeckten Aufdeck-Elements.
    /// Neutralgrau, identisch auf Geraet und Beamer; Tap deckt auf. Der Rahmen
    /// traegt das Aufmass aus `coverFrame` — der gemeldete Rahmen allein
    /// laesst vor allem unten Text stehen.
    private func cover(for element: InteractiveElement) -> some View {
        let frame = element.coverFrame
        return Button {
            withAnimation(.easeOut(duration: 0.25)) {
                viewModel.reveal(element)
            }
        } label: {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .systemGray4))
                .overlay {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                }
        }
        .buttonStyle(.plain)
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        .accessibilityIdentifier("praesentation.element.aufdecken")
    }

    // MARK: - Helfer

    /// Mindest-Tap-Flaeche um den Ankerpunkt (Badge-Anker ist die linke obere
    /// Ecke des gemeldeten Elements).
    private func tapFrame(_ frame: CGRect) -> CGRect {
        let width = max(frame.width, 88)
        let height = max(frame.height, 44)
        // Ohne Ausdehnung: Flaeche um den Anker zentrieren, leicht nach rechts
        // versetzt (das Badge beginnt am Anker und laeuft nach rechts).
        let x = frame.width > 0 ? frame.minX : frame.minX - 12
        let y = frame.height > 0 ? frame.minY : frame.minY - height / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func pulse(_ element: InteractiveElement) {
        pulsingElement = element.id
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            if pulsingElement == element.id { pulsingElement = nil }
        }
    }
}

// MARK: - Abdeckungen fuer den Beamer

/// Lesende Abdeckungs-Schicht fuer die Beamer-Spiegelansicht: zeigt dieselben
/// Abdeckflaechen wie das Geraet, ohne Interaktion. Wird im Rechteck der
/// Seitenflaeche mit deren tatsaechlicher Groesse layoutet.
struct RevealMirrorOverlay: View {
    let viewModel: PresentationViewModel

    var body: some View {
        GeometryReader { bounds in
            let scale = bounds.size.width / viewModel.canonicalSize.width
            ForEach(viewModel.currentElements.filter { $0.kind == InteractiveElement.Kind.reveal }) { element in
                if !viewModel.isRevealed(element) {
                    let cover = element.coverFrame
                    RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                        .fill(Color(uiColor: .systemGray4))
                        .frame(width: cover.width * scale, height: cover.height * scale)
                        .offset(x: cover.minX * scale, y: cover.minY * scale)
                }
            }
        }
    }
}
