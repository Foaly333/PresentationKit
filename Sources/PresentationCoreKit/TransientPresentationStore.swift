//
//  TransientPresentationStore.swift
//  PresentationCoreKit
//
//  In-Memory-Implementierung der Persistenzgrenze: Seiten und Bild-Elemente
//  leben nur im Speicher, ueberleben aber Seitenwechsel innerhalb der Sitzung.
//  Einsatz: Vorschau ohne Speicherung sowie Whiteboard-only-Sitzungen
//  (Taktikboard) in Apps ohne eigene Persistenzschicht.
//

import CoreGraphics
import Foundation

/// Fluechtige Seite fuer Sitzungen ohne Persistenz. Auch nuetzlich, um aus
/// beliebigen Quellen (PDF-Renderings, Bilddaten) eine Sitzung zu bauen.
public nonisolated final class TransientPresentationPage: PresentationPage {
    public let id = UUID()
    public var order: Int
    public let isWhiteboard: Bool
    public let baseImageData: Data
    public var drawingData = Data()
    public var interactiveElementsData: Data?
    public var contextData: Data?

    public init(order: Int, isWhiteboard: Bool = false, baseImageData: Data = Data()) {
        self.order = order
        self.isWhiteboard = isWhiteboard
        self.baseImageData = baseImageData
    }
}

/// Fluechtiges Bild-Element (Gegenstueck zu `TransientPresentationPage`).
public nonisolated final class TransientPageImage: PresentationPageImage {
    public let id = UUID()
    public let order: Int
    public var frame: CGRect
    public let imageData: Data

    public init(order: Int, frame: CGRect, imageData: Data) {
        self.order = order
        self.frame = frame
        self.imageData = imageData
    }
}

/// Store der Sitzung ohne Speicherung: erzeugt fluechtige Objekte und haelt
/// die Bild-Elemente je Seiten-ID.
public final class TransientPresentationStore: PresentationPageStore {

    private var imageElementsByPage: [UUID: [TransientPageImage]] = [:]

    public init() {}

    public var isPersistent: Bool { false }

    public func makeWhiteboardPage(order: Int) -> any PresentationPage {
        TransientPresentationPage(order: order, isWhiteboard: true)
    }

    @discardableResult
    public func makeImageElement(
        on page: any PresentationPage, imageData: Data, frame: CGRect, order: Int
    ) -> any PresentationPageImage {
        let element = TransientPageImage(order: order, frame: frame, imageData: imageData)
        imageElementsByPage[page.id, default: []].append(element)
        return element
    }

    public func deleteImageElement(_ element: any PresentationPageImage, on page: any PresentationPage) {
        imageElementsByPage[page.id]?.removeAll { $0.id == element.id }
    }

    public func imageElements(on page: any PresentationPage) -> [any PresentationPageImage] {
        imageElementsByPage[page.id] ?? []
    }
}
