//
//  PresentationPage.swift
//  PresentationCoreKit
//
//  Datenmodell-Grenze des Praesentationsmodus. Konsumierende Apps konformieren
//  ihre eigenen (z. B. SwiftData-)Klassen per Extension; fuer Sitzungen ohne
//  eigene Persistenz liefert `TransientPresentationStore` eine
//  In-Memory-Implementierung mit. Class-Constraint bewusst: Persistenz per
//  Property-Schreiben auf Referenztypen (etwa SwiftData-Autosave) und die
//  Identitaetsvergleiche (`===`) des ViewModels funktionieren dadurch ohne
//  Umwege.
//

import CoreGraphics
import Foundation

/// Eine Seite der Praesentation: gerendertes Grundbild plus die vom
/// Praesentationsmodus beschriebenen Blobs (Zeichnung, interaktive Elemente,
/// Seitenkontext). Wer persistiert, entscheidet der `PresentationPageStore`.
public nonisolated protocol PresentationPage: AnyObject {
    var id: UUID { get }
    /// Anzeige-Reihenfolge; das ViewModel rueckt sie beim Whiteboard-Einfuegen auf.
    var order: Int { get set }
    var isWhiteboard: Bool { get }
    /// Gerenderte Grundseite (PNG); leer bei Whiteboard.
    var baseImageData: Data { get }
    /// Serialisiertes `PKDrawing` der Stift-Annotationen.
    var drawingData: Data { get set }
    /// JSON-codierte `[InteractiveElement]`; nil ohne Marker.
    var interactiveElementsData: Data? { get set }
    /// JSON-codierter `PageContext` (App-Bedeutung, z. B. Agenda-Abschnitt).
    var contextData: Data? { get set }
}

/// Ein vom Nutzer ueber die Grundseite gelegtes Bild (z. B. QR-Code).
/// Lage im kanonischen 1024-pt-Raum der Seite (Ursprung oben links).
public nonisolated protocol PresentationPageImage: AnyObject {
    var id: UUID { get }
    /// Einfuege- und Z-Reihenfolge innerhalb der Seite.
    var order: Int { get }
    var frame: CGRect { get set }
    var imageData: Data { get }
}

// MARK: - Store

/// Persistenzgrenze des Praesentationsmodus. Erzeugt und loescht Seiten und
/// Bild-Elemente; ob dabei dauerhaft gespeichert wird, ist Sache der
/// Implementierung (Store der App, `TransientPresentationStore` fuer
/// Sitzungen ohne Speicherung). Implizit `@MainActor` (Default Actor
/// Isolation) — wird ausschliesslich vom ViewModel aufgerufen.
public protocol PresentationPageStore {
    /// true, wenn Aenderungen dauerhaft gespeichert werden — steuert den
    /// Hinweis „Ohne Speicherung" in der Steuerleiste.
    var isPersistent: Bool { get }

    /// Erzeugt eine leere Whiteboard-Seite mit der gegebenen Reihenfolge.
    /// Das Aufruecken nachfolgender Seiten uebernimmt das ViewModel.
    func makeWhiteboardPage(order: Int) -> any PresentationPage

    /// Erzeugt ein Bild-Element auf der Seite. `frame` liegt im kanonischen
    /// 1024-pt-Raum der Seite.
    @discardableResult
    func makeImageElement(
        on page: any PresentationPage, imageData: Data, frame: CGRect, order: Int
    ) -> any PresentationPageImage

    /// Entfernt ein Bild-Element von seiner Seite.
    func deleteImageElement(_ element: any PresentationPageImage, on page: any PresentationPage)

    /// Bild-Elemente einer Seite (unsortiert; das ViewModel sortiert nach `order`).
    func imageElements(on page: any PresentationPage) -> [any PresentationPageImage]
}

// MARK: - ForEach-Huellen

/// Identifizierbare Huelle um eine existentielle Seite — SwiftUI-`ForEach`
/// braucht `Identifiable` bzw. einen KeyPath, und KeyPaths auf `any`-Typen
/// sind nicht bildbar.
public nonisolated struct IndexedPresentationPage: Identifiable {
    public let index: Int
    public let page: any PresentationPage
    public var id: UUID { page.id }

    public init(index: Int, page: any PresentationPage) {
        self.index = index
        self.page = page
    }
}

/// Identifizierbare Huelle um ein existentielles Bild-Element (analog oben).
public nonisolated struct IdentifiedPageImage: Identifiable {
    public let element: any PresentationPageImage
    public var id: UUID { element.id }

    public init(element: any PresentationPageImage) {
        self.element = element
    }
}
