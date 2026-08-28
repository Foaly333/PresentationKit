//
//  LaserPointerViews.swift
//  PresentationUIKit
//
//  Transparente Erfassungsflaeche fuer den Laserpointer. Sie liegt im
//  kanonischen 1024er-Layout ueber dem Canvas – die Touch-Koordinaten sind damit
//  ohne Umrechnung kanonisch und direkt beamer-tauglich. Nimmt Stift UND Finger
//  an (`UITouch.type` wird bewusst nicht gefiltert).
//

import SwiftUI
import UIKit

struct LaserPointerCapture: UIViewRepresentable {

    /// Meldet die Zeigerposition; `nil` beim Loslassen (Punkt ausblenden).
    let onPositionChanged: (CGPoint?) -> Void

    func makeUIView(context: Context) -> LaserPointerCaptureView {
        let view = LaserPointerCaptureView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false
        view.accessibilityIdentifier = "praesentation.laserpointer.erfassung"
        view.onPositionChanged = onPositionChanged
        return view
    }

    func updateUIView(_ view: LaserPointerCaptureView, context: Context) {
        view.onPositionChanged = onPositionChanged
    }
}

/// Der rote Punkt – auf Geraet und Beamer identisch gerendert.
struct LaserPointerDotView: View {

    /// Position im kanonischen Koordinatenraum.
    let position: CGPoint

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 26, height: 26)
            .shadow(color: .red.opacity(0.8), radius: 10)
            .position(position)
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}

final class LaserPointerCaptureView: UIView {

    var onPositionChanged: ((CGPoint?) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { report(touches) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { report(touches) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { onPositionChanged?(nil) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { onPositionChanged?(nil) }

    private func report(_ touches: Set<UITouch>) {
        guard let location = touches.first?.location(in: self) else { return }
        onPositionChanged?(location)
    }
}
