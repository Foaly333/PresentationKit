//
//  InteractiveElement.swift
//  PresentationCoreKit
//
//  Positionsbehaftetes interaktives Element einer Praesentationsseite: beim
//  Vorbereiten der Seiten aus den `PageElementMarker`n destilliert und als
//  JSON in `PresentationPage.interactiveElementsData` persistiert, damit
//  fortgesetzte Praesentationen interaktiv bleiben.
//
//  Wire-Format (historisch gewachsen, bleibt stabil): die JSON-Schluessel
//  lauten `typ`, `daten`, `rahmen` — die CodingKeys bilden die englischen
//  Property-Namen darauf ab, bestehende Blobs bleiben lesbar. `kind` ist
//  bewusst ein String statt eines Enums: unbekannte Typen ueberleben das
//  Dekodieren und koennen ueber die Element-Registry der Konfiguration eine
//  eigene Darstellung bekommen.
//

import CoreGraphics
import Foundation

/// Ein interaktives Element auf einer Praesentationsseite.
public nonisolated struct InteractiveElement: Codable, Sendable, Equatable, Identifiable {

    /// Namensraum der eingebauten Elementtypen. Rohwerte sind Teil des
    /// Wire-Formats (deutsch, aus dem mo-tools-Kontrakt) und bleiben stabil.
    public nonisolated enum Kind {
        public static let timer = "timer"
        public static let quiz = "quiz"
        public static let reveal = "aufdecken"
        public static let media = "medium"

        /// Die vier eingebauten, raeumlich gerenderten Typen.
        public static let builtIn: Set<String> = [timer, quiz, reveal, media]
    }

    /// Stabile Identitaet — Aufdeck-/Quiz-Zustand referenziert Elemente ueber sie.
    public let id: UUID
    public let kind: String
    /// Payload der Meldung (JSON-getreu aus dem Marker uebernommen).
    public let data: [String: ElementValue]
    /// Lage im kanonischen 1024-pt-Raum (Ursprung oben links, Breite 1024).
    /// Elemente ohne gemeldete Ausdehnung tragen einen Nullgroessen-Rahmen am
    /// Ankerpunkt — die Overlay-Schicht sorgt fuer die Mindest-Tap-Flaeche.
    public let frame: CGRect

    enum CodingKeys: String, CodingKey {
        case id
        case kind = "typ"
        case data = "daten"
        case frame = "rahmen"
    }

    public init(id: UUID = UUID(), kind: String, data: [String: ElementValue], frame: CGRect) {
        self.id = id
        self.kind = kind
        self.data = data
        self.frame = frame
    }
}

extension InteractiveElement {

    /// Destilliert die Elemente einer Dokumentseite aus den Positions-Markern.
    ///
    /// - Parameters:
    ///   - markers: alle Marker des Dokuments
    ///   - page: 0-basierter Seitenindex
    ///   - pageSizePt: MediaBox-Groesse der Seite in pt
    ///   - kinds: zugelassene Elementtypen — die eingebauten plus etwaige
    ///     ueber die Konfiguration registrierte eigene Typen
    /// - Returns: Elemente der Seite im kanonischen 1024-pt-Raum;
    ///   leer, wenn die Seite keine zugelassenen Marker traegt.
    public static func elements(
        from markers: [PageElementMarker],
        page: Int,
        pageSizePt: CGSize,
        kinds: Set<String> = Kind.builtIn
    ) -> [InteractiveElement] {
        guard pageSizePt.width > 0 else { return [] }
        // pt → kanonisch: die Breite wird auf 1024 normiert, die Hoehe skaliert
        // mit demselben Faktor (Seitenverhaeltnis bleibt erhalten). Die
        // Ankerpunkte kommen bereits mit Ursprung oben links.
        let scale = 1024.0 / pageSizePt.width

        return markers
            .filter { $0.page == page && kinds.contains($0.kind) }
            .map { marker in
                // Gemeldete Ausdehnung (Aufdecken misst sich selbst);
                // ohne Meldung bleibt der Rahmen am Ankerpunkt groessenlos.
                let widthPt = marker.data["breite_pt"]?.doubleValue ?? 0
                let heightPt = marker.data["hoehe_pt"]?.doubleValue ?? 0
                return InteractiveElement(
                    kind: marker.kind,
                    data: marker.data,
                    frame: CGRect(
                        x: marker.anchor.x * scale,
                        y: marker.anchor.y * scale,
                        width: widthPt * scale,
                        height: heightPt * scale
                    )
                )
            }
    }
}

// MARK: - Abdeckung

extension InteractiveElement {

    /// Aufmass der Abdeckflaeche im kanonischen 1024-pt-Raum.
    ///
    /// Der gemeldete Rahmen ist das reine Mass des Inhalts ab dem Ankerpunkt:
    /// Zeilenabstand unter der letzten Zeile, Unterlaengen und der Rand einer
    /// abgedeckten Box liegen ausserhalb. Die Abdeckung wird deshalb an allen
    /// Seiten aufgeweitet — unten am staerksten, weil dort die fehlende
    /// Zeilenluft am deutlichsten durchscheint.
    private nonisolated enum CoverInsets {
        static let horizontal: CGFloat = 14
        static let top: CGFloat = 12
        static let bottom: CGFloat = 26
        /// Mindestkantenlaenge, damit auch ein Element ohne gemeldete Ausdehnung
        /// eine sichtbare, tippbare Flaeche bekommt.
        static let minimumEdge: CGFloat = 44
    }

    /// Flaeche, die ein nicht aufgedecktes Aufdeck-Element verdeckt —
    /// identisch auf iPad und Beamer.
    public nonisolated var coverFrame: CGRect {
        CGRect(
            x: frame.minX - CoverInsets.horizontal,
            y: frame.minY - CoverInsets.top,
            width: max(frame.width, CoverInsets.minimumEdge) + 2 * CoverInsets.horizontal,
            height: max(frame.height, CoverInsets.minimumEdge) + CoverInsets.top + CoverInsets.bottom
        )
    }
}

// MARK: - Medien-Ziel

/// Aufgeloestes Ziel eines Medien-Elements.
public nonisolated enum MediaTarget {
    case url(URL)
    case attachment(data: Data, filename: String)
}

// MARK: - JSON-Codierung fuer PresentationPage

public extension Array where Element == InteractiveElement {
    /// Codiert fuer `PresentationPage.interactiveElementsData`; nil bei leerer
    /// Liste, damit Seiten ohne Marker kein Daten-Blob tragen.
    nonisolated func encoded() -> Data? {
        guard !isEmpty else { return nil }
        return try? JSONEncoder().encode(self)
    }

    /// Dekodiert aus `PresentationPage.interactiveElementsData`.
    nonisolated init(elementsData: Data?) {
        guard let data = elementsData,
              let decoded = try? JSONDecoder().decode([InteractiveElement].self, from: data)
        else {
            self = []
            return
        }
        self = decoded
    }
}
