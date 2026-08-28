//
//  PencilCanvasView.swift
//  PresentationUIKit
//
//  `PKCanvasView`-Wrapper mit `PKToolPicker` und Swipe-Gesten fuer die
//  Seitennavigation. Die Eingabepolitik folgt der Systemeinstellung „Nur mit
//  Apple Pencil zeichnen" (`drawingPolicy = .default`): zeichnen Finger nicht,
//  blaettern sie stattdessen per Ein-Finger-Swipe. Der Zwei-Finger-Swipe bleibt
//  in beiden Faellen als verlaesslicher Weg erhalten.
//

import SwiftUI
import PencilKit
import UniformTypeIdentifiers

/// `PKCanvasView`, das PencilKits eigenes Edit-Menue („Alles auswaehlen“ /
/// „Leerzeile einfuegen“) dauerhaft unterbindet — der Rechtsklick gehoert dem
/// Bild-Einfuege-Menue; damit entfaellt bewusst auch das Kontextmenue der
/// Lasso-Auswahl. PencilKit haengt die Menue-Interaktion NICHT (nur) an das
/// Canvas selbst, sondern an interne Subviews und legt sie auch nachtraeglich
/// wieder an — einmaliges Entfernen am Canvas genuegte deshalb nicht. Der
/// `addInteraction`-Override sperrt das Canvas selbst, `layoutSubviews`
/// raeumt den gesamten Subview-Baum bei jedem Layout-Durchlauf.
final class MenuSuppressingCanvasView: PKCanvasView {
    override func addInteraction(_ interaction: UIInteraction) {
        guard !(interaction is UIEditMenuInteraction) else { return }
        super.addInteraction(interaction)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        Self.removeSystemMenus(in: self)
    }

    /// Entfernt Edit- und Kontextmenue-Interaktionen aus allen Subviews
    /// (nicht vom Canvas selbst — dort liegt auf dem Mac unsere eigene
    /// `UIContextMenuInteraction` fuer das Einfuege-Menue).
    private static func removeSystemMenus(in view: UIView) {
        for subview in view.subviews {
            for interaction in subview.interactions
            where interaction is UIEditMenuInteraction || interaction is UIContextMenuInteraction {
                subview.removeInteraction(interaction)
            }
            removeSystemMenus(in: subview)
        }
    }
}

struct PencilCanvasView: UIViewRepresentable {

    /// Anzuzeigende Zeichnung (Quelle: `PresentationViewModel.currentDrawing`).
    let drawing: PKDrawing
    /// Version der programmatischen Zeichnung (Seitenwechsel, Zuruecksetzen) –
    /// nur bei Aenderung wird die Zeichnung neu gesetzt (PKDrawing ist nicht Equatable).
    let drawingVersion: Int
    /// Wird bei jeder Aenderung durch den Nutzer gemeldet (Strichende).
    let onDrawingChanged: (PKDrawing) -> Void
    /// Swipe nach links (vorwaerts blaettern).
    let onSwipeLeft: () -> Void
    /// Swipe nach rechts (rueckwaerts blaettern).
    let onSwipeRight: () -> Void
    /// Finger-Langdruck auf der Zeichenflaeche; Punkt im kanonischen Raum
    /// (oeffnet das Bild-Einfuege-Menue).
    let onLongPress: (CGPoint) -> Void
    /// Bild per Drag & Drop auf der Zeichenflaeche abgelegt (Bilddaten im
    /// Originalformat, Ablagepunkt im kanonischen Raum).
    let onImageDropped: (Data, CGPoint) -> Void
    /// Im Laserpointer-Modus nimmt der Canvas keine Zeicheneingaben entgegen.
    let isLaserPointerActive: Bool
    /// Schaltet Langdruck-/Rechtsklick-Menue und Drop-Ziel (Konfiguration).
    let allowsImageInsertion: Bool

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = MenuSuppressingCanvasView()
        canvas.delegate = context.coordinator
        // Systemeinstellung „Nur mit Apple Pencil zeichnen" entscheidet, ob Finger zeichnen.
        canvas.drawingPolicy = .default
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // Kein Scrollen/Zoomen: das Canvas liegt deckungsgleich ueber dem Seitenbild.
        canvas.isScrollEnabled = false
        canvas.accessibilityIdentifier = "praesentation.canvas"

        // Zwei-Finger-Swipes fuer die Seitennavigation.
        let left = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.swipeLeft))
        left.direction = .left
        left.numberOfTouchesRequired = 2
        canvas.addGestureRecognizer(left)

        let right = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.swipeRight))
        right.direction = .right
        right.numberOfTouchesRequired = 2
        canvas.addGestureRecognizer(right)

        // Ein-Finger-Swipes nur, wenn Finger nicht zeichnen (Pencil-only aktiv).
        // `prefersPencilOnlyDrawing` kann sich zur Laufzeit aendern – die Recognizer
        // werden darum immer angelegt und in `updateUIView` per `isEnabled` geschaltet.
        let oneFingerLeft = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.swipeLeft))
        oneFingerLeft.direction = .left
        oneFingerLeft.numberOfTouchesRequired = 1
        oneFingerLeft.allowedTouchTypes = [UITouch.TouchType.direct.rawValue as NSNumber]
        canvas.addGestureRecognizer(oneFingerLeft)
        context.coordinator.oneFingerRecognizers.append(oneFingerLeft)

        let oneFingerRight = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.swipeRight))
        oneFingerRight.direction = .right
        oneFingerRight.numberOfTouchesRequired = 1
        oneFingerRight.allowedTouchTypes = [UITouch.TouchType.direct.rawValue as NSNumber]
        canvas.addGestureRecognizer(oneFingerRight)
        context.coordinator.oneFingerRecognizers.append(oneFingerRight)

        if allowsImageInsertion {
            // Finger-Langdruck oeffnet das Bild-Einfuege-Menue. Nur direkte Touches:
            // ein ruhender Pencil soll weiter zeichnen. Die Erkennung bricht den
            // laufenden Zeichen-Touch ab (cancelsTouchesInView), ein etwaiger
            // Punktansatz verschwindet damit wieder.
            //
            // WICHTIG: Der Delegate erlaubt die gleichzeitige Erkennung mit dem
            // Zeichen-Recognizer von PencilKit. Der beginnt seinen Strich sofort
            // bei Touch-Down — sobald ein Recognizer `began` meldet, setzt UIKit
            // alle anderen desselben Touches ohne diese Erlaubnis auf `failed`;
            // der Langdruck wuerde also nie erkannt.
            let longPress = UILongPressGestureRecognizer(
                target: context.coordinator, action: #selector(Coordinator.longPress(_:))
            )
            longPress.allowedTouchTypes = [UITouch.TouchType.direct.rawValue as NSNumber]
            longPress.delegate = context.coordinator
            canvas.addGestureRecognizer(longPress)

            // Mac (Designed for iPad) sowie iPad mit Maus/Trackpad: Rechtsklick
            // bzw. Sekundaerklick oeffnet dasselbe Menue — Zeigereingaben sind
            // `indirectPointer`-Touches, die der Langdruck oben gar nicht sieht.
            let rightClick = UITapGestureRecognizer(
                target: context.coordinator, action: #selector(Coordinator.rightClick(_:))
            )
            rightClick.allowedTouchTypes = [UITouch.TouchType.indirectPointer.rawValue as NSNumber]
            rightClick.buttonMaskRequired = .secondary
            rightClick.delegate = context.coordinator
            canvas.addGestureRecognizer(rightClick)

            // iPad-App auf dem Mac: Der Rechtsklick laeuft dort ueber die
            // Kontextmenue-Maschinerie und erreicht den Tap-Recognizer oben nicht
            // verlaesslich. Eine eigene UIContextMenuInteraction faengt ihn ab;
            // der Delegate oeffnet das Einfuege-Menue und praesentiert selbst kein
            // UIKit-Menue (nil). Nur auf dem Mac — auf dem iPad wuerde die
            // Interaktion auch auf Finger-Langdruck reagieren und sich mit dem
            // Langdruck-Recognizer doppeln.
            if ProcessInfo.processInfo.isiOSAppOnMac {
                canvas.addInteraction(UIContextMenuInteraction(delegate: context.coordinator))
            }

            // Zeichenflaeche als Drop-Ziel: Bilder aus Fotos, Dateien, Safari oder
            // dem Finder (Mac) landen direkt am Ablagepunkt.
            canvas.addInteraction(UIDropInteraction(delegate: context.coordinator))
        }

        // Werkzeugleiste (Stift/Marker/Radierer/Farben) anzeigen — Sichtbarkeit
        // ueber denselben nachgelagerten Weg wie in updateUIView.
        context.coordinator.toolPicker.addObserver(canvas)
        context.coordinator.updateResponder(canvas: canvas, laserPointerActive: isLaserPointerActive)
        context.coordinator.displayedVersion = drawingVersion
        context.coordinator.isProgrammaticUpdate = true
        canvas.drawing = drawing
        context.coordinator.isProgrammaticUpdate = false
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.onDrawingChanged = onDrawingChanged
        context.coordinator.onSwipeLeftAction = onSwipeLeft
        context.coordinator.onSwipeRightAction = onSwipeRight
        context.coordinator.onLongPressAction = onLongPress
        context.coordinator.onImageDroppedAction = onImageDropped

        // Ein-Finger-Blaettern genau dann, wenn Finger nicht zeichnen duerfen.
        let pencilOnly = UIPencilInteraction.prefersPencilOnlyDrawing
        for recognizer in context.coordinator.oneFingerRecognizers {
            recognizer.isEnabled = pencilOnly
        }

        // Laserpointer-Umschaltung (Interaktion, ToolPicker, First Responder)
        // KOMPLETT nach dem laufenden Durchlauf: auch
        // `UIScrollView.setUserInteractionEnabled` gibt den Responder-Status
        // synchron ab und meldet die Hierarchie-Aenderung mitten in den
        // SwiftUI-Update-Durchlauf zurueck — AttributeGraph erkennt einen Ring
        // (gleiches Muster wie PDFView.setDocument, TypstKit 0.2.3).
        context.coordinator.updateResponder(canvas: canvas, laserPointerActive: isLaserPointerActive)

        // Zeichnung nur bei neuer Version (Seitenwechsel, Zuruecksetzen) programmatisch
        // setzen – Nutzereingaben nicht anfassen (Endlosschleife Delegate → State → Update).
        guard context.coordinator.displayedVersion != drawingVersion else { return }
        context.coordinator.displayedVersion = drawingVersion
        context.coordinator.isProgrammaticUpdate = true
        canvas.drawing = drawing
        context.coordinator.isProgrammaticUpdate = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onDrawingChanged: onDrawingChanged,
            onSwipeLeft: onSwipeLeft,
            onSwipeRight: onSwipeRight,
            onLongPress: onLongPress,
            onImageDropped: onImageDropped
        )
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate,
                             UIContextMenuInteractionDelegate, UIDropInteractionDelegate {
        // Der ToolPicker muss stark referenziert bleiben, solange das Canvas lebt.
        let toolPicker = PKToolPicker()
        var onDrawingChanged: (PKDrawing) -> Void
        var onSwipeLeftAction: () -> Void
        var onSwipeRightAction: () -> Void
        var onLongPressAction: (CGPoint) -> Void
        var onImageDroppedAction: (Data, CGPoint) -> Void
        var isProgrammaticUpdate = false
        var displayedVersion: Int?
        /// Ein-Finger-Swipes; werden je nach Eingabepolitik ein-/ausgeschaltet.
        var oneFingerRecognizers: [UISwipeGestureRecognizer] = []
        /// Laufender Responder-Wechsel; bei schneller Update-Folge zaehlt nur der juengste.
        private var responderChange: Task<Void, Never>?

        /// Setzt ToolPicker-Sichtbarkeit und First-Responder-Status **nach** dem
        /// laufenden SwiftUI-Durchlauf — beide Aufrufe aendern die
        /// View-Hierarchie synchron und duerfen nicht aus `updateUIView` heraus
        /// direkt erfolgen.
        func updateResponder(canvas: PKCanvasView, laserPointerActive: Bool) {
            responderChange?.cancel()
            responderChange = Task { @MainActor in
                guard !Task.isCancelled else { return }
                // Jede Mutation nur bei tatsaechlicher Aenderung — die Task-Folge
                // konvergiert damit, statt weitere Update-Durchlaeufe anzustossen.
                // Im Laserpointer-Modus liegt die Erfassungsflaeche ueber dem
                // Canvas; das Canvas nimmt dann keine Eingaben mehr an.
                if canvas.isUserInteractionEnabled != !laserPointerActive {
                    canvas.isUserInteractionEnabled = !laserPointerActive
                }
                toolPicker.setVisible(!laserPointerActive, forFirstResponder: canvas)
                // Erst nach Einbau in die View-Hierarchie moeglich (in makeUIView zu frueh).
                if !laserPointerActive, canvas.window != nil, !canvas.isFirstResponder {
                    canvas.becomeFirstResponder()
                }
            }
        }

        init(
            onDrawingChanged: @escaping (PKDrawing) -> Void,
            onSwipeLeft: @escaping () -> Void,
            onSwipeRight: @escaping () -> Void,
            onLongPress: @escaping (CGPoint) -> Void,
            onImageDropped: @escaping (Data, CGPoint) -> Void
        ) {
            self.onDrawingChanged = onDrawingChanged
            self.onSwipeLeftAction = onSwipeLeft
            self.onSwipeRightAction = onSwipeRight
            self.onLongPressAction = onLongPress
            self.onImageDroppedAction = onImageDropped
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isProgrammaticUpdate else { return }
            onDrawingChanged(canvasView.drawing)
        }

        @objc func swipeLeft() { onSwipeLeftAction() }
        @objc func swipeRight() { onSwipeRightAction() }

        /// Das Canvas liegt in kanonischer Groesse – die Touch-Position ist
        /// damit bereits eine kanonische Koordinate.
        @objc func longPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let canvas = recognizer.view as? PKCanvasView else { return }
            // Den waehrend des Haltens angesetzten Strich abbrechen:
            // `cancelsTouchesInView` erreicht nur die View, nicht den
            // Zeichen-Recognizer — kurzes Deaktivieren setzt ihn zurueck.
            canvas.drawingGestureRecognizer.isEnabled = false
            canvas.drawingGestureRecognizer.isEnabled = true
            onLongPressAction(recognizer.location(in: canvas))
        }

        /// Sekundaerklick (Maus/Trackpad) — gleiche Aktion wie der Langdruck.
        @objc func rightClick(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let canvas = recognizer.view else { return }
            onLongPressAction(recognizer.location(in: canvas))
        }

        /// Mac-Rechtsklick (UIContextMenuInteraction): oeffnet das
        /// Einfuege-Menue; `nil` unterdrueckt das UIKit-eigene Kontextmenue.
        /// Die Position ist in Canvas-Koordinaten — also bereits kanonisch.
        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            configurationForMenuAtLocation location: CGPoint
        ) -> UIContextMenuConfiguration? {
            onLongPressAction(location)
            return nil
        }

        // MARK: - Drag & Drop

        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
            session.hasItemsConforming(toTypeIdentifiers: [UTType.image.identifier])
        }

        func dropInteraction(
            _ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession
        ) -> UIDropProposal {
            UIDropProposal(operation: .copy)
        }

        /// Das Canvas liegt in kanonischer Groesse — der Ablagepunkt ist damit
        /// bereits kanonisch. Die Daten werden im Originalformat geladen (das
        /// ViewModel normalisiert selbst); bei mehreren Items zaehlt das erste
        /// Bild.
        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
            guard let canvas = interaction.view else { return }
            let point = session.location(in: canvas)
            let provider = session.items
                .map(\.itemProvider)
                .first { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
            guard let provider else { return }
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                // Die Completion kommt auf einer Hintergrund-Queue an.
                Task { @MainActor in self.onImageDroppedAction(data, point) }
            }
        }

        /// Nur fuer Langdruck- und Rechtsklick-Recognizer gesetzt: beide
        /// muessen neben PencilKits sofort beginnendem Zeichen-Recognizer
        /// bestehen duerfen, sonst werden sie nie erkannt.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
