//
//  PageContext.swift
//  PresentationCoreKit
//
//  Seitenkontext: die inhaltliche Einheit, unter der das Material einer
//  Praesentationsseite liegt (im Unterricht die Verlaufsplan-Phase, im
//  Workshop der Agenda-Punkt). Wird von der App beim Aufbau der Sitzung
//  bestimmt und als JSON in `PresentationPage.contextData` persistiert;
//  kontextlose Seiten (Whiteboards) erben in der Anzeige den Kontext der
//  vorigen Seite.
//
//  Wire-Format: die JSON-Schluessel (`phaseId`, `titel`, `beschreibung`,
//  `form`) stammen aus der App-Historie und bleiben stabil, damit bestehende
//  Blobs lesbar bleiben.
//

import Foundation

/// Der inhaltliche Abschnitt, unter dem das Material einer Seite liegt.
public nonisolated struct PageContext: Codable, Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let detail: String?
    /// Sozial-/Arbeitsform o. ä. — kurzes Etikett neben dem Titel.
    public let form: String?

    enum CodingKeys: String, CodingKey {
        case id = "phaseId"
        case title = "titel"
        case detail = "beschreibung"
        case form
    }

    public init(id: UUID, title: String, detail: String?, form: String?) {
        self.id = id
        self.title = title
        self.detail = detail
        self.form = form
    }
}

// MARK: - JSON-Codierung fuer PresentationPage

public extension PageContext {

    /// Codiert fuer `PresentationPage.contextData`.
    nonisolated func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// Dekodiert aus `PresentationPage.contextData`; nil bei fehlendem oder
    /// nicht lesbarem Blob (Seiten ohne Kontext, Altbestand).
    nonisolated init?(contextData: Data?) {
        guard let data = contextData,
              let decoded = try? JSONDecoder().decode(PageContext.self, from: data)
        else { return nil }
        self = decoded
    }
}
