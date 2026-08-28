# PresentationKit

Vollbild-Präsentationsmodus für iOS-Apps (iPad im Fokus): gerenderte Seiten
zeigen, mit PencilKit annotieren, auf einen Beamer spiegeln — plus
Laserpointer, Arbeitsphasen-Timer, Seitenraster, eingefügte Bilder
(z. B. QR-Codes), interaktive Elemente (Quiz, Aufdecken, Timer, Medien)
und eine Soll-Anzeige gegen eine Agenda.

Das Paket ist bewusst frei von Typst, SwiftData und jeder App-Semantik:
**Eingang sind gerenderte Seitenbilder (z. B. PDF-Seiten als PNG) plus
optionale Positions-Marker.** Persistenz läuft über ein Store-Protokoll —
die App bringt ihre eigene Schicht mit oder nutzt den mitgelieferten
In-Memory-Store (Vorschau, Whiteboard-only-Sitzungen).

## Produkte

| Produkt | Inhalt |
|---|---|
| `PresentationCoreKit` | Seiten-/Store-Protokolle, `TransientPresentationStore`, `InteractiveElement` + `ElementValue`/`PageElementMarker`, `PageContext`, Agenda-Fortschritt, `SessionTimer` |
| `PresentationUIKit` | `PresentationView` (Canvas, Beamer-Spiegelung, Steuerleiste, Overlays), `PresentationConfiguration` mit Werkzeug-Schaltern und Element-Registry |

## Verwendung

```swift
import PresentationCoreKit
import PresentationUIKit

// Seiten aus beliebiger Quelle (hier: fluechtig, z. B. aus PDF-Renderings).
let pages = pageImages.enumerated().map { index, data in
    TransientPresentationPage(order: index, baseImageData: data)
}

PresentationView(
    pages: pages,
    store: TransientPresentationStore(),          // oder eigener Store (SwiftData, …)
    agendaInput: (items: agendaItems, slotIntervals: slots),  // optional: Soll-Chip
    attachmentResolver: { filename in … },        // optional: Medien-Anhaenge
    configuration: {
        var config = PresentationConfiguration()
        config.showsAgenda = false                // Werkzeuge einzeln schaltbar
        return config
    }()
)
```

Eigene Marker-Typen registrieren (Element-Registry):

```swift
config.customElementRenderers["abstimmung"] = { element in
    AnyView(MyPollBadge(element: element))
}
// Beim Destillieren der Elemente die zugelassenen Typen mitgeben:
InteractiveElement.elements(from: markers, page: i, pageSizePt: size,
                            kinds: config.elementKinds)
```

## Wire-Format

Die JSON-Blobs an den Seiten (`interactiveElementsData`, `contextData`)
verwenden historisch gewachsene deutsche Schlüssel (`typ`, `daten`, `rahmen`
bzw. `phaseId`, `titel`, `beschreibung`, `form`). Sie sind Teil des Kontrakts
und bleiben stabil — bestehende Bestände der MaterialOrganizer-App bleiben
lesbar. `ElementValue` codiert untagged; die Decode-Reihenfolge
(Bool → Int → Double → String) darf nicht umgestellt werden.

## Plattform und Tests

iOS 26+, Swift 6.2, Default Actor Isolation `MainActor` + Approachable
Concurrency. **iOS-only** (PencilKit, UIKit, externe Displays) — `swift test`
auf dem Mac baut daher nicht; Tests laufen über Xcode gegen einen
iOS-Simulator:

```bash
xcodebuild test -scheme PresentationKit-Package -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)'
```

## Herkunft

Extrahiert aus der MaterialOrganizer-App (Vorhaben „PresentationKit",
2026-08). Die Lokalisierung liegt in `Sources/PresentationUIKit/Resources/
Localizable.xcstrings` (Basis Deutsch, Englisch übersetzt).
