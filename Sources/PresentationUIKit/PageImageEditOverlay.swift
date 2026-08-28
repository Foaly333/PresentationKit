//
//  PageImageEditOverlay.swift
//  PresentationUIKit
//
//  Bearbeitungsschicht fuer das ausgewaehlte Bild-Element — Verschieben per
//  Drag, Skalieren ueber den Eckgriff, Loeschen und Fertig ueber die kleine
//  Aktionsleiste. Liegt UEBER dem PencilKit-Canvas und faengt waehrend der
//  Auswahl alle Eingaben ab (wie der Laserpointer-Modus); ohne Auswahl rendert
//  die Schicht nichts und laesst alle Eingaben durch. Gesten melden fortlaufend
//  einen Live-Rahmen an das ViewModel, das Modell wird erst am Gestenende
//  beschrieben.
//

import PresentationCoreKit
import SwiftUI

struct PageImageEditOverlay: View {
    let viewModel: PresentationViewModel
    /// Loeschen laeuft ueber die umgebende View (dort haengt die Aktionsleiste).
    let onDelete: () -> Void

    var body: some View {
        if let element = viewModel.selectedImageElement {
            ZStack(alignment: .topLeading) {
                // Tap neben dem Bild beendet die Auswahl.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.selectImageElement(nil) }
                selectionFrame(for: element)
            }
            .frame(width: viewModel.canonicalSize.width,
                   height: viewModel.canonicalSize.height,
                   alignment: .topLeading)
        }
    }

    // MARK: - Auswahlrahmen

    private func selectionFrame(for element: any PresentationPageImage) -> some View {
        let frame = viewModel.frame(for: element)
        return Color.clear
            .contentShape(Rectangle())
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.blue, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
            }
            .overlay(alignment: .bottomTrailing) { scaleHandle(for: element) }
            .overlay(alignment: .top) { actionBar.offset(y: -64) }
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .gesture(moveGesture(for: element))
            .accessibilityIdentifier("praesentation.bild.auswahl")
    }

    /// Eckgriff unten rechts: Ziehen skaliert proportional.
    private func scaleHandle(for element: any PresentationPageImage) -> some View {
        Circle()
            .fill(.blue)
            .frame(width: 28, height: 28)
            .overlay {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .offset(x: 14, y: 14)
            .gesture(scaleGesture(for: element))
            .accessibilityIdentifier("praesentation.bild.skalieren")
    }

    private var actionBar: some View {
        HStack(spacing: 20) {
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.red)
            }
            .accessibilityIdentifier("praesentation.bild.loeschen")

            Button {
                viewModel.selectImageElement(nil)
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .semibold))
            }
            .accessibilityIdentifier("praesentation.bild.fertig")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
    }

    // MARK: - Gesten

    /// Basis ist stets der gespeicherte Rahmen — das Modell aendert sich erst
    /// am Gestenende, die Translation ist also gegen eine feste Lage kumuliert.
    private func moveGesture(for element: any PresentationPageImage) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let base = element.frame
                viewModel.setLiveImageFrame(CGRect(
                    x: base.minX + value.translation.width,
                    y: base.minY + value.translation.height,
                    width: base.width, height: base.height
                ))
            }
            .onEnded { _ in viewModel.commitLiveImageFrame() }
    }

    private func scaleGesture(for element: any PresentationPageImage) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let base = element.frame
                let width = base.width + value.translation.width
                let height = base.width > 0 ? width * base.height / base.width : base.height
                viewModel.setLiveImageFrame(CGRect(
                    x: base.minX, y: base.minY, width: width, height: height
                ))
            }
            .onEnded { _ in viewModel.commitLiveImageFrame() }
    }
}
