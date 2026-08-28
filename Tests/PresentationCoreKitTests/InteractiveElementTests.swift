//
//  InteractiveElementTests.swift
//  PresentationCoreKitTests
//
//  Marker-Mapping in den kanonischen Raum, Wire-Format der Element-Blobs
//  (deutsche JSON-Schluessel bleiben stabil) und der Transient-Store.
//

import Testing
import CoreGraphics
import Foundation
@testable import PresentationCoreKit

@Suite("InteractiveElement")
struct InteractiveElementTests {

    private func marker(
        kind: String,
        page: Int = 0,
        x: Double = 0,
        y: Double = 0,
        data: [String: ElementValue] = [:]
    ) -> PageElementMarker {
        PageElementMarker(page: page, kind: kind, anchor: CGPoint(x: x, y: y), data: data)
    }

    @Test("pt → kanonisch: Breite wird auf 1024 normiert, Hoehe skaliert mit")
    func mapping_normalizesToCanonicalSpace() {
        // A4 hoch: 595 × 842 pt. Marker in der Seitenmitte.
        let elements = InteractiveElement.elements(
            from: [marker(kind: "timer", x: 297.5, y: 421)],
            page: 0,
            pageSizePt: CGSize(width: 595, height: 842)
        )

        #expect(elements.count == 1)
        let frame = elements[0].frame
        #expect(abs(frame.minX - 512) < 0.1)
        #expect(abs(frame.minY - 724.3) < 0.5)
    }

    @Test("Nur Elemente der angefragten Seite, nur zugelassene Typen")
    func mapping_filtersPageAndKind() {
        let markers = [
            marker(kind: "timer", page: 0),
            marker(kind: "timer", page: 1),
            marker(kind: "kann", page: 0),
            marker(kind: "kopien", page: 0),
            marker(kind: "quiz", page: 0),
        ]

        let elements = InteractiveElement.elements(
            from: markers, page: 0, pageSizePt: CGSize(width: 595, height: 842)
        )

        #expect(elements.map(\.kind) == [InteractiveElement.Kind.timer, InteractiveElement.Kind.quiz])
    }

    @Test("Registrierte eigene Typen passieren den Filter (Element-Registry)")
    func mapping_allowsRegisteredCustomKinds() {
        let markers = [marker(kind: "abstimmung", page: 0), marker(kind: "unbekannt", page: 0)]

        let elements = InteractiveElement.elements(
            from: markers, page: 0, pageSizePt: CGSize(width: 595, height: 842),
            kinds: InteractiveElement.Kind.builtIn.union(["abstimmung"])
        )

        #expect(elements.map(\.kind) == ["abstimmung"])
    }

    @Test("Gemeldete Ausdehnung wird zum Rahmen")
    func mapping_appliesReportedSize() {
        let elements = InteractiveElement.elements(
            from: [marker(
                kind: "aufdecken",
                x: 59.5,
                y: 0,
                data: ["breite_pt": .double(119), "hoehe_pt": .double(59.5)]
            )],
            page: 0,
            pageSizePt: CGSize(width: 595, height: 842)
        )

        // Skala 1024/595: 59.5 pt → 102.4, 119 pt → 204.8
        let frame = elements[0].frame
        #expect(abs(frame.minX - 102.4) < 0.1)
        #expect(abs(frame.width - 204.8) < 0.1)
        #expect(abs(frame.height - 102.4) < 0.1)
    }

    @Test("Leere Liste codiert zu nil, nil dekodiert zu leerer Liste")
    func coding_emptyListIsNil() {
        #expect([InteractiveElement]().encoded() == nil)
        #expect([InteractiveElement](elementsData: nil).isEmpty)
        #expect([InteractiveElement](elementsData: Data([0x7b])).isEmpty)
    }

    @Test("Wire-Format: JSON-Schluessel typ/daten/rahmen bleiben stabil")
    func coding_wireKeysStayStable() throws {
        let element = InteractiveElement(
            kind: InteractiveElement.Kind.timer,
            data: ["minuten": .int(5)],
            frame: CGRect(x: 10, y: 20, width: 0, height: 0)
        )

        let data = try #require([element].encoded())
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"typ\":\"timer\""))
        #expect(json.contains("\"daten\""))
        #expect(json.contains("\"rahmen\""))
        #expect(!json.contains("\"kind\""))
    }

    @Test("Vor der Umbenennung persistierte Blobs bleiben dekodierbar")
    func coding_legacyBlobsRemainReadable() {
        // JSON, wie es die fruehere App-Fassung geschrieben hat (deutsche
        // Schluessel, untagged Werte, CGRect als geschachtelte Arrays).
        let legacy = Data("""
        [{"id":"11111111-2222-3333-4444-555555555555","typ":"aufdecken",
          "daten":{"breite_pt":80,"hoehe_pt":40},"rahmen":[[10,20],[30,40]]}]
        """.utf8)

        let elements = [InteractiveElement](elementsData: legacy)

        #expect(elements.count == 1)
        #expect(elements.first?.kind == InteractiveElement.Kind.reveal)
        #expect(elements.first?.data["breite_pt"]?.doubleValue == 80)
        #expect(elements.first?.frame == CGRect(x: 10, y: 20, width: 30, height: 40))
    }

    @Test("Unbekannte Typen ueberleben das Dekodieren (kind ist String)")
    func coding_unknownKindsSurvive() throws {
        let blob = Data(#"[{"id":"11111111-2222-3333-4444-555555555555","typ":"abstimmung","daten":{},"rahmen":[[0,0],[0,0]]}]"#.utf8)

        let elements = [InteractiveElement](elementsData: blob)

        #expect(elements.first?.kind == "abstimmung")
    }
}

// MARK: - PageContext

@Suite("PageContext")
struct PageContextTests {

    @Test("Wire-Format: JSON-Schluessel phaseId/titel/beschreibung/form bleiben stabil")
    func coding_wireKeysStayStable() throws {
        let id = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let context = PageContext(id: id, title: "Einstieg", detail: "B", form: "Plenum")

        let data = try #require(context.encoded())
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"phaseId\""))
        #expect(json.contains("\"titel\":\"Einstieg\""))
        #expect(json.contains("\"beschreibung\":\"B\""))

        let decoded = PageContext(contextData: context.encoded())
        #expect(decoded == context)
    }

    @Test("Alt-Blob mit deutschen Schluesseln bleibt lesbar")
    func coding_legacyBlobRemainsReadable() {
        let legacy = Data(#"{"phaseId":"11111111-2222-3333-4444-555555555555","titel":"Sicherung","beschreibung":null,"form":"EA"}"#.utf8)

        let decoded = PageContext(contextData: legacy)

        #expect(decoded?.title == "Sicherung")
        #expect(decoded?.detail == nil)
        #expect(decoded?.form == "EA")
    }
}

// MARK: - TransientPresentationStore

@Suite("TransientPresentationStore")
struct TransientPresentationStoreTests {

    @Test("Haelt Bild-Elemente je Seite im Speicher, persistiert nichts")
    func keepsImageElementsPerPage() {
        let sut = TransientPresentationStore()

        let page = sut.makeWhiteboardPage(order: 0)
        let otherPage = sut.makeWhiteboardPage(order: 1)
        let image = sut.makeImageElement(
            on: page, imageData: Data([1]),
            frame: CGRect(x: 0, y: 0, width: 100, height: 100), order: 0
        )

        #expect(!sut.isPersistent)
        #expect(page.isWhiteboard)
        #expect(sut.imageElements(on: page).count == 1)
        #expect(sut.imageElements(on: otherPage).isEmpty)

        sut.deleteImageElement(image, on: page)
        #expect(sut.imageElements(on: page).isEmpty)
    }
}
