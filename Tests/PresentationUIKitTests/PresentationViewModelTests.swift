//
//  PresentationViewModelTests.swift
//  PresentationUIKitTests
//
//  Gemeinsamer Praesentations-Zustand – Seitennavigation, Whiteboard-Einfuegen,
//  Persistenz der PencilKit-Zeichnungen, Bild-Elemente, Agenda und Kontext.
//  Alle Tests laufen gegen den Transient-Store; das Zusammenspiel mit einem
//  persistierenden Store deckt die konsumierende App ab.
//

import Testing
import CoreGraphics
import Foundation
import PencilKit
import UIKit
@testable import PresentationCoreKit
@testable import PresentationUIKit

/// Mock des Fortschritt-Service — liefert einen gestubbten Status und
/// protokolliert die uebergebenen Eingaben.
final class MockAgendaProgressService: AgendaProgressServiceProtocol {

    var stubbedStatus: AgendaStatus?
    private(set) var statusCalled = false
    private(set) var lastNow: Date?

    func status(items: [AgendaItem], slotIntervals: [DateInterval], now: Date) -> AgendaStatus? {
        statusCalled = true
        lastNow = now
        return stubbedStatus
    }
}

@Suite("PresentationViewModel Tests")
@MainActor
struct PresentationViewModelTests {

    // MARK: - Hilfsfunktionen

    /// Erzeugt fluechtige Seiten mit gegebener Reihenfolge.
    private static func pages(_ orders: [Int], whiteboard: Bool = false) -> [TransientPresentationPage] {
        orders.map { TransientPresentationPage(order: $0, isWhiteboard: whiteboard) }
    }

    /// Programmatische PKDrawing mit einem Strich (Pencil-Striche sind in
    /// UI-Tests nicht simulierbar – Zeichnungslogik gehoert in Unit-Tests).
    private static func sampleDrawing() -> PKDrawing {
        let points = [CGPoint(x: 10, y: 10), CGPoint(x: 60, y: 40), CGPoint(x: 120, y: 80)].map {
            PKStrokePoint(location: $0, timeOffset: 0, size: CGSize(width: 4, height: 4),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let path = PKStrokePath(controlPoints: points, creationDate: .now)
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .red), path: path)])
    }

    private func makeSut(
        pages: [TransientPresentationPage],
        store: PresentationPageStore = TransientPresentationStore(),
        attachmentResolver: ((String) -> MediaTarget?)? = nil
    ) -> PresentationViewModel {
        PresentationViewModel(
            pages: pages,
            store: store,
            attachmentResolver: attachmentResolver,
            saveDelay: .zero
        )
    }

    /// Kleines, echtes PNG – Grundlage fuer die Thumbnail-Erzeugung via ImageIO.
    private static func samplePNG(width: CGFloat = 800, height: CGFloat = 600) -> Data {
        let size = CGSize(width: width, height: height)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.pngData() ?? Data()
    }

    // MARK: - Agenda & Seitenkontext

    private static func contextData(title: String) -> Data? {
        PageContext(id: UUID(), title: title, detail: "B", form: "Plenum").encoded()
    }

    @Test("currentPageContext greift bei kontextlosen Seiten auf die vorige zurueck")
    func currentPageContext_carriesBackOverWhiteboards() {
        let pages = Self.pages([0, 1, 2, 3])
        pages[1].contextData = Self.contextData(title: "Einstieg")
        pages[3].contextData = Self.contextData(title: "Erarbeitung")
        let sut = makeSut(pages: pages)

        // Uebersichtsseite ohne Kontext.
        #expect(sut.currentPageContext == nil)
        sut.showNextPage()
        #expect(sut.currentPageContext?.title == "Einstieg")
        // Seite 2 (z. B. Whiteboard) ohne eigenen Kontext → Rueckgriff.
        sut.showNextPage()
        #expect(sut.currentPageContext?.title == "Einstieg")
        sut.showNextPage()
        #expect(sut.currentPageContext?.title == "Erarbeitung")
    }

    @Test("Ohne Agenda-Eingabe gibt es keinen Soll-Status")
    func hasAgenda_withoutInputFalse() {
        let sut = makeSut(pages: Self.pages([0]))

        #expect(!sut.hasAgenda)
        #expect(sut.agendaStatus(now: .now) == nil)
    }

    @Test("Mit Agenda-Eingabe delegiert der Soll-Status an den Service")
    func agendaStatus_delegatesToService() {
        let mock = MockAgendaProgressService()
        let item = AgendaItem(id: UUID(), title: "Einstieg", detail: nil, form: "Plenum",
                              durationMinutes: 45, materialTitles: [])
        let start = Date(timeIntervalSince1970: 1_755_000_000)
        let sut = PresentationViewModel(
            pages: Self.pages([0]),
            store: TransientPresentationStore(),
            agendaInput: (items: [item], slotIntervals: [DateInterval(start: start, duration: 2700)]),
            saveDelay: .zero,
            progressService: mock
        )
        let now = start.addingTimeInterval(60)

        #expect(sut.hasAgenda)
        _ = sut.agendaStatus(now: now)
        #expect(mock.statusCalled)
        #expect(mock.lastNow == now)
    }

    // MARK: - Navigation

    @Test("Init sortiert die Seiten nach Reihenfolge")
    func init_sortsPagesByOrder() {
        let unsorted = Self.pages([2, 0, 1])
        let sut = makeSut(pages: unsorted)

        #expect(sut.pages.map { $0.order } == [0, 1, 2])
        #expect(sut.currentIndex == 0)
        #expect(sut.pageLabel == "1/3")
    }

    @Test("Navigation respektiert die Seitengrenzen")
    func navigation_respectsBounds() {
        let sut = makeSut(pages: Self.pages([0, 1]))

        #expect(!sut.canGoBack)
        sut.showPreviousPage()
        #expect(sut.currentIndex == 0)

        sut.showNextPage()
        #expect(sut.currentIndex == 1)
        #expect(!sut.canGoForward)
        sut.showNextPage()
        #expect(sut.currentIndex == 1)
    }

    @Test("Seitenwechsel speichert die Zeichnung der vorherigen Seite")
    func pageChange_savesPreviousDrawing() {
        let pages = Self.pages([0, 1])
        let sut = makeSut(pages: pages)

        sut.updateDrawing(Self.sampleDrawing())
        sut.showNextPage()

        #expect(!pages[0].drawingData.isEmpty)
        let loaded = try? PKDrawing(data: pages[0].drawingData)
        #expect(loaded?.strokes.count == 1)
        // Auf der neuen Seite ist die Live-Zeichnung leer.
        #expect(sut.currentDrawing.strokes.isEmpty)
    }

    @Test("Seitenwechsel laedt die gespeicherte Zeichnung der neuen Seite")
    func pageChange_loadsNewPagesDrawing() {
        let pages = Self.pages([0, 1])
        pages[1].drawingData = Self.sampleDrawing().dataRepresentation()
        let sut = makeSut(pages: pages)

        sut.showNextPage()

        #expect(sut.currentDrawing.strokes.count == 1)
    }

    @Test("Annotationen bleiben je Seite getrennt und werden beim Zurueckblaettern wiederhergestellt")
    func backAndForth_keepsAnnotationsPerPage() {
        let pages = Self.pages([0, 1, 2])
        let sut = makeSut(pages: pages)

        // Seite 1: ein Strich, Seite 2: zwei Striche, Seite 3: bleibt leer.
        sut.updateDrawing(Self.sampleDrawing())
        sut.showNextPage()
        let twoStrokes = PKDrawing(strokes: Self.sampleDrawing().strokes + Self.sampleDrawing().strokes)
        sut.updateDrawing(twoStrokes)
        sut.showNextPage()
        #expect(sut.currentDrawing.strokes.isEmpty)

        // Zurueckblaettern stellt die jeweilige Seiten-Zeichnung wieder her.
        sut.showPreviousPage()
        #expect(sut.currentDrawing.strokes.count == 2)
        sut.showPreviousPage()
        #expect(sut.currentDrawing.strokes.count == 1)

        // Und die Persistenz je Seite ist getrennt.
        #expect((try? PKDrawing(data: pages[0].drawingData))?.strokes.count == 1)
        #expect((try? PKDrawing(data: pages[1].drawingData))?.strokes.count == 2)
        #expect(pages[2].drawingData.isEmpty || (try? PKDrawing(data: pages[2].drawingData))?.strokes.count == 0)
    }

    // MARK: - Direktsprung (Seitenleiste und Grid)

    @Test("jump wechselt auf einen gueltigen Index")
    func jump_validIndex_moves() {
        let sut = makeSut(pages: Self.pages([0, 1, 2, 3]))

        sut.jump(to: 3)

        #expect(sut.currentIndex == 3)
        #expect(sut.pageLabel == "4/4")
    }

    @Test("jump ignoriert ungueltige Indizes und die aktuelle Seite")
    func jump_invalidIndex_stays() {
        let sut = makeSut(pages: Self.pages([0, 1, 2]))
        sut.jump(to: 1)

        sut.jump(to: -1)
        #expect(sut.currentIndex == 1)

        sut.jump(to: 3)
        #expect(sut.currentIndex == 1)

        sut.jump(to: 1)
        #expect(sut.currentIndex == 1)
    }

    @Test("jump speichert die Zeichnung der verlassenen Seite")
    func jump_savesPreviousDrawing() {
        let pages = Self.pages([0, 1, 2])
        let sut = makeSut(pages: pages)

        sut.updateDrawing(Self.sampleDrawing())
        sut.jump(to: 2)

        #expect(!pages[0].drawingData.isEmpty)
        #expect((try? PKDrawing(data: pages[0].drawingData))?.strokes.count == 1)
        #expect(sut.currentDrawing.strokes.isEmpty)
    }

    // MARK: - Thumbnails

    @Test("Thumbnail wird einmalig erzeugt und gecacht")
    func thumbnail_isCreatedAndCached() async {
        let sut = makeSut(pages: [TransientPresentationPage(order: 0, baseImageData: Self.samplePNG())])

        let page = sut.pages[0]
        #expect(sut.thumbnails.isEmpty)
        await sut.loadThumbnailIfNeeded(for: page)

        let first = sut.thumbnails[page.id]
        #expect(first != nil)
        // Downgesampelt: deutlich kleiner als das Original (800 pt breit).
        #expect((first?.size.width ?? .infinity) <= PresentationViewModel.thumbnailWidth * 2)

        // Zweiter Aufruf liefert dieselbe Instanz aus dem Cache.
        await sut.loadThumbnailIfNeeded(for: page)
        #expect(sut.thumbnails[page.id] === first)
    }

    @Test("Whiteboard- und bildlose Seiten erzeugen kein Thumbnail")
    func thumbnail_whiteboardWithoutDecoding() async {
        let whiteboard = TransientPresentationPage(order: 0, isWhiteboard: true)
        let withoutImage = TransientPresentationPage(order: 1)
        let sut = makeSut(pages: [whiteboard, withoutImage])

        await sut.loadThumbnailIfNeeded(for: whiteboard)
        await sut.loadThumbnailIfNeeded(for: withoutImage)

        #expect(sut.thumbnails.isEmpty)
    }

    @Test("Whiteboard-Einfuegen invalidiert die Kachel der neuen Seite")
    func thumbnail_invalidationOnWhiteboardInsertion() async throws {
        let page = TransientPresentationPage(order: 0, baseImageData: Self.samplePNG())
        let sut = makeSut(pages: [page])
        await sut.loadThumbnailIfNeeded(for: page)
        #expect(sut.thumbnails.count == 1)

        sut.insertWhiteboardPage()

        // Die neue Seite hat keine Kachel im Cache, die alte bleibt erhalten.
        let newPage = try #require(sut.currentPage)
        #expect(newPage.isWhiteboard)
        #expect(sut.thumbnails[newPage.id] == nil)
        #expect(sut.thumbnails[page.id] != nil)
    }

    @Test("Stift-Badge folgt dem Live-Zustand der aktuellen Seite")
    func hasAnnotations_reflectsLiveState() {
        let pages = Self.pages([0, 1])
        pages[1].drawingData = Self.sampleDrawing().dataRepresentation()
        let sut = makeSut(pages: pages)

        #expect(!sut.hasAnnotations(pages[0]))
        #expect(sut.hasAnnotations(pages[1]))

        // Noch ungespeicherte Striche der aktuellen Seite zaehlen bereits.
        sut.updateDrawing(Self.sampleDrawing())
        #expect(sut.hasAnnotations(pages[0]))
    }

    // MARK: - Laserpointer

    @Test("Laserpointer meldet Positionen nur im aktiven Modus")
    func laserPointer_onlyWhileActive() {
        let sut = makeSut(pages: Self.pages([0]))

        sut.updateLaserPointer(CGPoint(x: 10, y: 20))
        #expect(sut.laserPointerPosition == nil)

        sut.setLaserPointer(active: true)
        sut.updateLaserPointer(CGPoint(x: 10, y: 20))
        #expect(sut.laserPointerPosition == CGPoint(x: 10, y: 20))

        // Loslassen blendet den Punkt aus.
        sut.updateLaserPointer(nil)
        #expect(sut.laserPointerPosition == nil)
    }

    @Test("Deaktivieren des Laserpointers loescht die Position")
    func laserPointer_deactivation_clearsPosition() {
        let sut = makeSut(pages: Self.pages([0]))
        sut.setLaserPointer(active: true)
        sut.updateLaserPointer(CGPoint(x: 5, y: 5))

        sut.setLaserPointer(active: false)

        #expect(sut.laserPointerPosition == nil)
        #expect(!sut.isLaserPointerActive)
    }

    // MARK: - Freeze und Blackout

    @Test("Einfrieren legt einen Snapshot an und gibt ihn beim Freigeben frei")
    func freeze_createsSnapshot() {
        let sut = makeSut(pages: [TransientPresentationPage(order: 0, baseImageData: Self.samplePNG())])
        #expect(sut.freezeSnapshot == nil)

        sut.setFrozen(true)
        #expect(sut.isFrozen)
        #expect(sut.freezeSnapshot != nil)

        sut.setFrozen(false)
        #expect(!sut.isFrozen)
        #expect(sut.freezeSnapshot == nil)
    }

    @Test("Blackout und Freeze koennen gleichzeitig aktiv sein; Vorrang klaert die Anzeige")
    func blackout_andFreeze_sideBySide() {
        let sut = makeSut(pages: Self.pages([0]))

        sut.setFrozen(true)
        sut.setBlackout(true)

        #expect(sut.isFrozen)
        #expect(sut.isBlackout)
        #expect(sut.freezeSnapshot != nil)
    }

    @Test("Trennen des externen Displays setzt Freeze und Blackout zurueck")
    func externalDisplay_disconnect_resetsStates() {
        let sut = makeSut(pages: Self.pages([0]))
        sut.reportExternalDisplay(connected: true)
        sut.setFrozen(true)
        sut.setBlackout(true)

        sut.reportExternalDisplay(connected: false)

        #expect(!sut.isExternalDisplayConnected)
        #expect(!sut.isFrozen)
        #expect(!sut.isBlackout)
        #expect(sut.freezeSnapshot == nil)
    }

    @Test("Beenden raeumt Laserpointer, Beamer-Zustaende und Timer ab")
    func end_clearsTransientStates() {
        let sut = makeSut(pages: Self.pages([0]))
        sut.reportExternalDisplay(connected: true)
        sut.setLaserPointer(active: true)
        sut.setFrozen(true)
        sut.setBlackout(true)
        sut.sessionTimer.start(duration: 300)

        sut.end()

        #expect(!sut.isLaserPointerActive)
        #expect(!sut.isFrozen)
        #expect(!sut.isBlackout)
        #expect(!sut.sessionTimer.isActive)
    }

    // MARK: - Zeichnung

    @Test("Beenden speichert die aktuelle Zeichnung")
    func end_savesCurrentDrawing() {
        let pages = Self.pages([0])
        let sut = makeSut(pages: pages)

        sut.updateDrawing(Self.sampleDrawing())
        sut.end()

        #expect(!pages[0].drawingData.isEmpty)
    }

    @Test("Zuruecksetzen loescht nur die Annotationen der aktuellen Seite")
    func clear_resetsOnlyCurrentPage() {
        let pages = Self.pages([0, 1])
        pages[1].drawingData = Self.sampleDrawing().dataRepresentation()
        let sut = makeSut(pages: pages)
        sut.updateDrawing(Self.sampleDrawing())
        let versionBefore = sut.drawingVersion

        sut.clearCurrentDrawing()

        // Live-Zustand und Persistenz der aktuellen Seite sind leer …
        #expect(sut.currentDrawing.strokes.isEmpty)
        #expect(pages[0].drawingData.isEmpty)
        // … der Canvas wird ueber die Version zum Uebernehmen gezwungen …
        #expect(sut.drawingVersion > versionBefore)
        // … und andere Seiten bleiben unberuehrt.
        #expect((try? PKDrawing(data: pages[1].drawingData))?.strokes.count == 1)

        // Auch nach Beenden (speichert leere Zeichnung) bleibt die Seite leer ladbar.
        sut.end()
        let loaded = try? PKDrawing(data: pages[0].drawingData)
        #expect(loaded == nil || loaded?.strokes.isEmpty == true)
    }

    // MARK: - Whiteboard

    @Test("Whiteboard-Seite wird hinter der aktuellen Seite eingefuegt, nachfolgende ruecken auf")
    func whiteboard_insertsAfterCurrentPage() {
        let sut = makeSut(pages: Self.pages([0, 1]))

        sut.insertWhiteboardPage()

        #expect(sut.pages.count == 3)
        #expect(sut.currentIndex == 1)
        #expect(sut.currentPage?.isWhiteboard == true)
        // Reihenfolge bleibt lueckenlos: alte Seite 1 ist aufgerueckt.
        #expect(sut.pages.map { $0.order } == [0, 1, 2])
    }

    // MARK: - Bild-Elemente

    @Test("Bild einfuegen zentriert um den Punkt und waehlt das Element aus")
    func imageInsertion_centersAndSelects() async {
        let sut = makeSut(pages: Self.pages([0], whiteboard: true))

        let success = await sut.insertImageElement(
            data: Self.samplePNG(width: 800, height: 600),
            at: CGPoint(x: 500, y: 400)
        )

        #expect(success)
        #expect(sut.currentImageElements.count == 1)
        guard let element = sut.currentImageElements.first else { return }
        // 320 pt Standardbreite, Seitenverhaeltnis 4:3 des Quellbilds.
        #expect(element.frame == CGRect(x: 340, y: 280, width: 320, height: 240))
        #expect(sut.selectedImageElementID == element.id)
        #expect(sut.elementImages[element.id] != nil)
    }

    @Test("Bild einfuegen am Rand bleibt innerhalb der Seite")
    func imageInsertion_atEdgeStaysInside() async {
        let sut = makeSut(pages: Self.pages([0], whiteboard: true))

        _ = await sut.insertImageElement(data: Self.samplePNG(), at: .zero)

        let frame = sut.currentImageElements.first?.frame ?? .null
        #expect(frame.minX == 0)
        #expect(frame.minY == 0)
    }

    @Test("Ungueltige Daten werden abgewiesen")
    func imageInsertion_invalidData_false() async {
        let sut = makeSut(pages: Self.pages([0]))

        let success = await sut.insertImageElement(data: Data("kein bild".utf8), at: .zero)

        #expect(!success)
        #expect(sut.currentImageElements.isEmpty)
    }

    @Test("Transiente Bilder ueberleben den Seitenwechsel")
    func imageInsertion_survivesPageChange() async {
        let sut = makeSut(pages: Self.pages([0, 1]))

        _ = await sut.insertImageElement(data: Self.samplePNG(), at: CGPoint(x: 500, y: 400))
        sut.showNextPage()
        #expect(sut.currentImageElements.isEmpty)
        sut.showPreviousPage()

        #expect(sut.currentImageElements.count == 1)
        // Nach dem Seitenwechsel ist nichts mehr ausgewaehlt.
        #expect(sut.selectedImageElementID == nil)
    }

    @Test("Live-Rahmen gilt nur bis zur Uebernahme ins Modell")
    func liveFrame_commitsOnlyAtGestureEnd() async {
        let sut = makeSut(pages: Self.pages([0], whiteboard: true))
        _ = await sut.insertImageElement(data: Self.samplePNG(), at: CGPoint(x: 500, y: 400))
        guard let element = sut.currentImageElements.first else { return }
        let oldFrame = element.frame

        sut.setLiveImageFrame(oldFrame.offsetBy(dx: 100, dy: 50))

        // Anzeige folgt dem Live-Rahmen, das Modell noch nicht.
        #expect(sut.frame(for: element) == oldFrame.offsetBy(dx: 100, dy: 50))
        #expect(element.frame == oldFrame)

        sut.commitLiveImageFrame()

        #expect(element.frame == oldFrame.offsetBy(dx: 100, dy: 50))
        #expect(sut.liveImageFrame == nil)
    }

    @Test("Live-Rahmen wird auf Mindestgroesse und sichtbare Lage begrenzt")
    func liveFrame_isBounded() async {
        let sut = makeSut(pages: Self.pages([0], whiteboard: true))
        _ = await sut.insertImageElement(data: Self.samplePNG(), at: CGPoint(x: 500, y: 400))

        // Kleiner als die Mindestkante und weit ausserhalb der Seite.
        sut.setLiveImageFrame(CGRect(x: -5000, y: -5000, width: 10, height: 10))
        sut.commitLiveImageFrame()

        guard let element = sut.currentImageElements.first else { return }
        #expect(element.frame.width == 80)
        // Mindestens 80 pt bleiben sichtbar.
        #expect(element.frame.minX >= 80 - element.frame.width)
        #expect(element.frame.minY >= 80 - element.frame.height)
    }

    @Test("Loeschen entfernt Element, Bildcache und Auswahl")
    func imageDeletion_removesElementAndSelection() async {
        let sut = makeSut(pages: Self.pages([0], whiteboard: true))
        _ = await sut.insertImageElement(data: Self.samplePNG(), at: CGPoint(x: 500, y: 400))
        guard let id = sut.selectedImageElementID else { return }

        sut.deleteSelectedImageElement()

        #expect(sut.currentImageElements.isEmpty)
        #expect(sut.elementImages[id] == nil)
        #expect(sut.selectedImageElementID == nil)
    }

    @Test("imageElement(at:) liefert das oberste Bild unter dem Punkt")
    func imageElementAtPoint_returnsTopmost() async {
        let sut = makeSut(pages: Self.pages([0], whiteboard: true))
        _ = await sut.insertImageElement(data: Self.samplePNG(), at: CGPoint(x: 500, y: 400))
        _ = await sut.insertImageElement(data: Self.samplePNG(), at: CGPoint(x: 500, y: 400))

        let hit = sut.imageElement(at: CGPoint(x: 500, y: 400))

        #expect(hit?.id == sut.currentImageElements.last?.id)
        #expect(sut.imageElement(at: CGPoint(x: 5, y: 700)) == nil)
    }

    @Test("Normalisierung verkleinert auf die Maximalkante")
    func normalization_shrinksToMaxEdge() async {
        let data = Self.samplePNG(width: 1200, height: 600)

        let result = await PresentationViewModel.normalizeImageData(data, maxEdge: 400)

        #expect(result != nil)
        #expect(result?.pixelSize.width ?? 0 <= 400)
        #expect(result?.pixelSize.height ?? 0 <= 400)
    }
}
