//
//  PresentationViewModel.swift
//  PresentationUIKit
//
//  Gemeinsamer Praesentations-Zustand fuer Geraete-Canvas und externes Display:
//  Seitenliste, aktuelle Seite, Live-Zeichnung, Laserpointer, Beamer-Zustaende,
//  interaktive Elemente, Bild-Elemente und Quiz. Annotationen werden debounced
//  in die Seite geschrieben; Persistenz ist Sache des injizierten
//  `PresentationPageStore`. Agenda-Eingabe und Anhang-Aufloesung kommen von
//  der konsumierenden App.
//

import Foundation
import ImageIO
import Observation
import PencilKit
import PresentationCoreKit
import UIKit

@Observable
final class PresentationViewModel {

    // MARK: - State

    /// Seiten der Praesentation, sortiert nach `order`.
    private(set) var pages: [any PresentationPage]
    private(set) var currentIndex: Int = 0
    /// Live-Zeichnung der aktuellen Seite – wird vom Canvas geschrieben und
    /// vom externen Display (Beamer) live mitgelesen.
    private(set) var currentDrawing = PKDrawing()
    /// Zaehler fuer programmatische Zeichnungswechsel (Seitenwechsel, Zuruecksetzen).
    /// Der Canvas uebernimmt die Zeichnung nur, wenn sich diese Version aendert –
    /// Nutzereingaben werden nie zurueckgesetzt (PKDrawing ist nicht Equatable).
    private(set) var drawingVersion = 0
    /// Dekodiertes Basisbild der aktuellen Seite (Cache – das PNG wird nur beim
    /// Seitenwechsel dekodiert, nicht bei jedem Layout-Durchlauf); nil bei Whiteboard.
    private(set) var currentBaseImage: UIImage?
    /// Kanonische Canvas-Breite in Punkten. Annotationen werden IMMER in diesem
    /// Koordinatenraum gezeichnet und gespeichert – unabhaengig von Geraetegroesse
    /// und Rotation (die Darstellung skaliert per `scaleEffect`). Dadurch bleiben
    /// Striche pro Seite lagestabil.
    static let canonicalWidth: CGFloat = 1024
    /// Zielbreite der Seitenvorschau in Punkten (Seitenleiste und Grid).
    static let thumbnailWidth: CGFloat = 200

    // MARK: - UI-State (Navigation)

    /// Aufklappbare Seitenleiste mit Seitenvorschau; startet zugeklappt.
    var isSidebarVisible = false
    /// Vollbild-Raster aller Seiten (Schnellsprung ueber die Seitenanzeige).
    var showsPageGrid = false
    /// Zur Laufzeit erzeugte Seitenvorschauen, Schluessel ist `PresentationPage.id`.
    private(set) var thumbnails: [UUID: UIImage] = [:]

    // MARK: - UI-State (Laserpointer)

    /// Im Laserpointer-Modus nimmt der Canvas keine Zeicheneingaben entgegen.
    /// Umschalten ueber `setLaserPointer(active:)` – Zustandswechsel raeumen
    /// die Position mit ab (kein `didSet`, das mit `@Observable` unzuverlaessig ist).
    private(set) var isLaserPointerActive = false
    /// Aktuelle Zeigerposition im kanonischen Koordinatenraum; nil = ausgeblendet.
    private(set) var laserPointerPosition: CGPoint?

    // MARK: - UI-State (Beamer)

    /// Meldet der `ExternalDisplayController` beim An-/Abstecken
    /// (`reportExternalDisplay(connected:)`). Steuert, ob die Beamer-
    /// Bedienelemente ueberhaupt erscheinen.
    private(set) var isExternalDisplayConnected = false
    /// Friert das Beamer-Bild ein; auf dem Geraet wird weiter navigiert.
    private(set) var isFrozen = false
    /// Schaltet den Beamer schwarz; hat Vorrang vor `isFrozen`.
    private(set) var isBlackout = false
    /// Standbild, das der Beamer waehrend des Einfrierens zeigt.
    private(set) var freezeSnapshot: UIImage?

    /// Countdown fuer Arbeitsphasen (siehe `SessionTimer`).
    let sessionTimer: SessionTimer

    // MARK: - UI-State (Seitenkontext)

    /// Blendet die Kontext-Karte zum aktuellen Material ein.
    var showsPageContext = false

    /// Kanonische Canvas-Groesse der aktuellen Seite (Hoehe folgt dem Seitenverhaeltnis).
    var canonicalSize: CGSize {
        CGSize(width: Self.canonicalWidth, height: Self.canonicalWidth / aspectRatio)
    }

    /// true, wenn Aenderungen dauerhaft gespeichert werden (Store-Eigenschaft).
    var isPersistent: Bool { store.isPersistent }

    // MARK: - Dependencies

    /// Persistenzgrenze: erzeugt/loescht Seiten und Bild-Elemente.
    private let store: PresentationPageStore
    private let progressService: AgendaProgressServiceProtocol
    /// Agenda-Eingabe der Soll-Anzeige, vom Aufrufer einmalig beim Start
    /// extrahiert — Plan und Zeitfenster aendern sich waehrend der Sitzung nicht.
    private let agendaInput: (items: [AgendaItem], slotIntervals: [DateInterval])?
    /// Loest den Anhang-Dateinamen eines Medien-Elements auf (App-Wissen).
    private let attachmentResolver: ((String) -> MediaTarget?)?
    /// Debounce-Intervall fuer das Speichern nach Strichende (in Tests auf 0 setzbar).
    private let saveDelay: Duration
    private var saveTask: Task<Void, Never>?

    // MARK: - Init

    init(
        pages: [any PresentationPage],
        store: PresentationPageStore,
        agendaInput: (items: [AgendaItem], slotIntervals: [DateInterval])? = nil,
        attachmentResolver: ((String) -> MediaTarget?)? = nil,
        saveDelay: Duration = .milliseconds(500),
        sessionTimer: SessionTimer = SessionTimer(),
        progressService: AgendaProgressServiceProtocol = AgendaProgressService()
    ) {
        self.pages = pages.sorted { $0.order < $1.order }
        self.store = store
        self.agendaInput = agendaInput
        self.attachmentResolver = attachmentResolver
        self.progressService = progressService
        self.saveDelay = saveDelay
        self.sessionTimer = sessionTimer
        loadCurrentPage()
    }

    // MARK: - Computed

    var currentPage: (any PresentationPage)? {
        pages.indices.contains(currentIndex) ? pages[currentIndex] : nil
    }

    /// Seiten mit Index fuer SwiftUI-`ForEach` (KeyPaths auf `any`-Typen sind
    /// nicht bildbar — die Huelle liefert die Identitaet).
    var indexedPages: [IndexedPresentationPage] {
        pages.enumerated().map { IndexedPresentationPage(index: $0.offset, page: $0.element) }
    }

    var canGoBack: Bool { currentIndex > 0 }
    var canGoForward: Bool { currentIndex < pages.count - 1 }

    /// Seitenverhaeltnis der aktuellen Seite (Whiteboard: 4:3 analog Render-Zielgroesse).
    var aspectRatio: CGFloat {
        guard let image = currentBaseImage, image.size.height > 0 else { return 4.0 / 3.0 }
        return image.size.width / image.size.height
    }

    var pageLabel: String {
        pages.isEmpty ? "–" : "\(currentIndex + 1)/\(pages.count)"
    }

    // MARK: - Agenda & Seitenkontext

    /// true, wenn eine Agenda-Eingabe injiziert wurde — steuert, ob
    /// Soll-Chip und Agenda-Popover erscheinen.
    var hasAgenda: Bool { agendaInput != nil }

    /// Soll-Zustand fuer den uebergebenen Zeitpunkt; `now` kommt aus der
    /// `TimelineView` der aufrufenden View (kein Date.now hier).
    func agendaStatus(now: Date) -> AgendaStatus? {
        guard let input = agendaInput else { return nil }
        return progressService.status(
            items: input.items, slotIntervals: input.slotIntervals, now: now
        )
    }

    /// Kontext des aktuell praesentierten Materials — von der aktuellen Seite
    /// rueckwaerts bis zur ersten Seite mit Kontext (Whiteboards tragen keinen,
    /// gehoeren aber zum davor gezeigten Abschnitt). nil auf Seiten vor dem
    /// ersten Kontext und bei Praesentationen ohne Kontextdaten.
    var currentPageContext: PageContext? {
        guard pages.indices.contains(currentIndex) else { return nil }
        for index in stride(from: currentIndex, through: 0, by: -1) {
            if let context = PageContext(contextData: pages[index].contextData) {
                return context
            }
        }
        return nil
    }

    // MARK: - Seitennavigation

    func showNextPage() {
        guard canGoForward else { return }
        move(to: currentIndex + 1)
    }

    func showPreviousPage() {
        guard canGoBack else { return }
        move(to: currentIndex - 1)
    }

    /// Direktsprung aus Seitenleiste und Grid-Overlay. Ungueltige Indizes und der
    /// Sprung auf die bereits sichtbare Seite sind wirkungslos.
    func jump(to index: Int) {
        guard pages.indices.contains(index), index != currentIndex else { return }
        move(to: index)
    }

    /// Speichert die Zeichnung der bisherigen Seite und laedt die der neuen.
    private func move(to index: Int) {
        saveCurrentDrawing()
        currentIndex = index
        loadCurrentPage()
    }

    // MARK: - Seitenvorschau (Thumbnails)

    /// Erzeugt die Vorschau einer Seite einmalig und legt sie im Cache ab.
    /// Whiteboard-Seiten brauchen keine Dekodierung (weisse Kachel in der View).
    func loadThumbnailIfNeeded(for page: any PresentationPage) async {
        guard thumbnails[page.id] == nil,
              !page.isWhiteboard,
              !page.baseImageData.isEmpty else { return }
        let image = await Self.makeThumbnail(from: page.baseImageData, targetWidth: Self.thumbnailWidth)
        guard let image else { return }
        thumbnails[page.id] = image
    }

    /// Verwirft die Vorschau einer Seite (z. B. wenn ihr Basisbild ersetzt wurde).
    func invalidateThumbnail(for page: any PresentationPage) {
        thumbnails.removeValue(forKey: page.id)
    }

    /// Downsampling direkt aus den PNG-Daten via ImageIO – das Vollbild wird nie
    /// komplett dekodiert. Laeuft explizit im Hintergrund.
    @concurrent
    nonisolated static func makeThumbnail(from data: Data, targetWidth: CGFloat) async -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: targetWidth * 2,  // @2x fuer Retina
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// true, wenn die Seite Annotationen traegt (fuer das Stift-Badge in der Vorschau).
    /// Fuer die aktuelle Seite zaehlt der noch nicht gespeicherte Live-Zustand.
    func hasAnnotations(_ page: any PresentationPage) -> Bool {
        if page === currentPage { return !currentDrawing.strokes.isEmpty }
        return !page.drawingData.isEmpty
    }

    // MARK: - Laserpointer

    /// Schaltet den Laserpointer-Modus; beim Ausschalten verschwindet der Punkt.
    func setLaserPointer(active: Bool) {
        isLaserPointerActive = active
        if !active { laserPointerPosition = nil }
    }

    /// Meldet die aktuelle Zeigerposition im kanonischen Koordinatenraum;
    /// `nil` blendet den Punkt aus (Loslassen). Wird nicht persistiert.
    func updateLaserPointer(_ position: CGPoint?) {
        guard isLaserPointerActive else { return }
        laserPointerPosition = position
    }

    // MARK: - Beamer: Freeze und Blackout

    /// Meldung des `ExternalDisplayController`. Beim Trennen werden Freeze und
    /// Blackout zurueckgesetzt – ohne Beamer sind sie gegenstandslos.
    func reportExternalDisplay(connected: Bool) {
        isExternalDisplayConnected = connected
        guard !connected else { return }
        setBlackout(false)
        setFrozen(false)
    }

    /// Friert das Beamer-Bild ein bzw. gibt es wieder frei. Beim Einfrieren wird
    /// der aktuelle Stand (Basisbild + Zeichnung) als Standbild festgehalten.
    func setFrozen(_ active: Bool) {
        guard active != isFrozen else { return }
        isFrozen = active
        freezeSnapshot = active ? makeFreezeSnapshot() : nil
    }

    /// Schaltet den Beamer schwarz bzw. wieder hell.
    func setBlackout(_ active: Bool) {
        isBlackout = active
    }

    /// Erzeugt das Standbild fuer den Freeze: Basisbild plus eingefuegte Bilder
    /// plus aktuelle Zeichnung im kanonischen Seitenraum – deckungsgleich mit
    /// dem Live-Rendering.
    private func makeFreezeSnapshot() -> UIImage {
        let size = canonicalSize
        let bounds = CGRect(origin: .zero, size: size)
        return UIGraphicsImageRenderer(size: size).image { context in
            if let image = currentBaseImage {
                image.draw(in: bounds)
            } else {
                UIColor.white.setFill()
                context.fill(bounds)
            }
            for element in currentImageElements {
                elementImages[element.id]?.draw(in: element.frame)
            }
            guard !currentDrawing.strokes.isEmpty else { return }
            currentDrawing.image(from: bounds, scale: 2).draw(in: bounds)
        }
    }

    // MARK: - Whiteboard

    /// Fuegt direkt hinter der aktuellen Seite eine leere Whiteboard-Seite ein
    /// und springt auf sie. Das Aufruecken nachfolgender Seiten uebernimmt das
    /// ViewModel selbst — der Store erzeugt nur das Objekt (persistiert
    /// oder in-memory, je nach Implementierung).
    func insertWhiteboardPage() {
        saveCurrentDrawing()
        let newOrder = (currentPage?.order ?? -1) + 1

        // Nachfolgende Seiten ruecken eine Position weiter, damit die
        // Reihenfolge luecken- und ueberschneidungsfrei bleibt.
        for page in pages where page.order >= newOrder {
            page.order += 1
        }
        let newPage = store.makeWhiteboardPage(order: newOrder)

        let insertionIndex = pages.isEmpty ? 0 : currentIndex + 1
        pages.insert(newPage, at: insertionIndex)
        currentIndex = insertionIndex
        // Neue Seite, neue Kachel: einen etwaigen Alteintrag zur ID verwerfen.
        invalidateThumbnail(for: newPage)
        loadCurrentPage()
    }

    // MARK: - Zeichnung

    /// Vom Canvas bei jedem Strichende gemeldet; Speichern erfolgt debounced,
    /// damit nicht jeder Strich einzeln in den Store schreibt.
    func updateDrawing(_ drawing: PKDrawing) {
        currentDrawing = drawing
        saveTask?.cancel()
        let delay = saveDelay
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.saveCurrentDrawing()
        }
    }

    /// Schreibt die Live-Zeichnung in die aktuelle Seite (Persistenz uebernimmt
    /// der Store der App; im Vorschau-Modus bleibt sie im Speicher, damit sie
    /// beim Vor-/Zurueckblaettern erhalten bleibt).
    func saveCurrentDrawing() {
        saveTask?.cancel()
        guard let page = currentPage else { return }
        page.drawingData = currentDrawing.dataRepresentation()
    }

    /// Setzt die Annotationen der aktuellen Seite zurueck (Live-Zustand und
    /// Persistenz); andere Seiten bleiben unberuehrt.
    func clearCurrentDrawing() {
        saveTask?.cancel()
        currentDrawing = PKDrawing()
        drawingVersion += 1
        guard let page = currentPage else { return }
        page.drawingData = Data()
    }

    /// Beim Beenden der Praesentation aufrufen: sichert den letzten Stand und
    /// raeumt die fluechtigen Praesentationszustaende ab.
    func end() {
        saveCurrentDrawing()
        setLaserPointer(active: false)
        setBlackout(false)
        setFrozen(false)
        sessionTimer.end()
    }

    // MARK: - Interaktive Elemente

    /// Elemente der aktuellen Seite (kanonischer 1024-pt-Raum).
    var currentElements: [InteractiveElement] {
        [InteractiveElement](elementsData: currentPage?.interactiveElementsData)
    }

    /// Startet den Arbeitsphasen-Countdown aus einem Timer-Element.
    func startTimer(minutes: Int) {
        sessionTimer.start(duration: TimeInterval(minutes) * 60)
    }

    /// Aufgedeckte Aufdeck-Elemente — Session-fluechtig:
    /// ueberlebt Seitenwechsel, aber keinen Neustart der Praesentation.
    private(set) var revealedElements: Set<UUID> = []

    func isRevealed(_ element: InteractiveElement) -> Bool {
        revealedElements.contains(element.id)
    }

    func reveal(_ element: InteractiveElement) {
        revealedElements.insert(element.id)
    }

    /// Loest die Medien-Referenz eines Medien-Elements zur Laufzeit auf:
    /// erst URL, dann Anhang-Dateiname ueber den injizierten Resolver.
    /// Nicht aufloesbar → nil (die View zeigt einen Hinweis, kein Crash).
    func mediaTarget(for element: InteractiveElement) -> MediaTarget? {
        if let text = element.data["url"]?.stringValue,
           let url = URL(string: text), url.scheme?.hasPrefix("http") == true {
            return .url(url)
        }
        if let filename = element.data["anhang"]?.stringValue, !filename.isEmpty {
            return attachmentResolver?(filename)
        }
        return nil
    }

    // MARK: - Bild-Elemente

    /// Bilder der aktuellen Seite, sortiert nach `order` (zugleich Z-Ordnung).
    private(set) var currentImageElements: [any PresentationPageImage] = []
    /// Dekodierte Bilder je Element-ID — beim Seitenwechsel bzw. Einfuegen befuellt.
    private(set) var elementImages: [UUID: UIImage] = [:]
    /// Ausgewaehltes Bild (Verschieben/Skalieren/Loeschen ueber das Overlay).
    private(set) var selectedImageElementID: UUID?
    /// Waehrend einer Geste gilt dieser Rahmen fuer das ausgewaehlte Element —
    /// das Modell wird erst beim Gestenende beschrieben (ein Schreibzugriff
    /// statt einem je Drag-Tick).
    private(set) var liveImageFrame: CGRect?

    /// Mindestens sichtbare Kante beim Verschieben und die kleinste Bildbreite.
    private static let imageMinimumEdge: CGFloat = 80

    var selectedImageElement: (any PresentationPageImage)? {
        currentImageElements.first { $0.id == selectedImageElementID }
    }

    /// Bild-Elemente mit Identitaets-Huelle fuer SwiftUI-`ForEach`.
    var identifiedImageElements: [IdentifiedPageImage] {
        currentImageElements.map { IdentifiedPageImage(element: $0) }
    }

    /// Oberstes Bild unter dem Punkt (kanonischer Raum); nil, wenn keines dort liegt.
    func imageElement(at point: CGPoint) -> (any PresentationPageImage)? {
        currentImageElements.last { $0.frame.contains(point) }
    }

    func selectImageElement(_ id: UUID?) {
        selectedImageElementID = id
        liveImageFrame = nil
    }

    /// Anzeigerahmen eines Elements: waehrend einer Geste der Live-Rahmen,
    /// sonst der gespeicherte.
    func frame(for element: any PresentationPageImage) -> CGRect {
        if element.id == selectedImageElementID, let live = liveImageFrame {
            return live
        }
        return element.frame
    }

    /// Von der Geste des Bearbeitungs-Overlays fortlaufend gemeldet.
    func setLiveImageFrame(_ frame: CGRect) {
        guard selectedImageElement != nil else { return }
        liveImageFrame = boundedImageFrame(frame)
    }

    /// Schreibt den Live-Rahmen ins Modell (Gestenende); Persistenz uebernimmt
    /// der Store der App.
    func commitLiveImageFrame() {
        defer { liveImageFrame = nil }
        guard let element = selectedImageElement, let live = liveImageFrame else { return }
        element.frame = live
    }

    /// Fuegt ein Bild um den Punkt (kanonischer Raum) auf der aktuellen Seite ein.
    /// Die Daten werden im Hintergrund auf Anzeigegroesse verkleinert; das neue
    /// Element ist anschliessend ausgewaehlt. false, wenn die Daten kein Bild
    /// sind oder die Seite waehrenddessen gewechselt wurde.
    func insertImageElement(data: Data, at point: CGPoint) async -> Bool {
        guard let page = currentPage else { return false }
        guard let normalized = await Self.normalizeImageData(data) else { return false }
        // Seitenwechsel waehrend der Verkleinerung: der Punkt gehoert zur alten Seite.
        guard page === currentPage else { return false }

        let frame = insertionFrame(for: normalized.pixelSize, around: point)
        let order = (currentImageElements.map { $0.order }.max() ?? -1) + 1

        let element = store.makeImageElement(
            on: page, imageData: normalized.data, frame: frame, order: order
        )

        currentImageElements.append(element)
        elementImages[element.id] = UIImage(data: normalized.data)
        selectImageElement(element.id)
        return true
    }

    func deleteImageElement(_ id: UUID) {
        guard let element = currentImageElements.first(where: { $0.id == id }),
              let page = currentPage else { return }
        store.deleteImageElement(element, on: page)
        currentImageElements.removeAll { $0.id == id }
        elementImages.removeValue(forKey: id)
        if selectedImageElementID == id { selectImageElement(nil) }
    }

    func deleteSelectedImageElement() {
        guard let id = selectedImageElementID else { return }
        deleteImageElement(id)
    }

    /// Standard-Einfuegegroesse: 320 pt Breite (gut scannbare QR-Groesse), auf
    /// das Seitenverhaeltnis des Bildes und die Seitengrenzen begrenzt; der
    /// Punkt wird zur Mitte des Rahmens.
    private func insertionFrame(for pixelSize: CGSize, around point: CGPoint) -> CGRect {
        let pageSize = canonicalSize
        var width = min(320, pageSize.width * 0.4)
        var height = width * 3 / 4
        if pixelSize.width > 0, pixelSize.height > 0 {
            height = width * pixelSize.height / pixelSize.width
            if height > pageSize.height * 0.6 {
                height = pageSize.height * 0.6
                width = height * pixelSize.width / pixelSize.height
            }
        }
        let x = min(max(point.x - width / 2, 0), pageSize.width - width)
        let y = min(max(point.y - height / 2, 0), pageSize.height - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Begrenzt einen Gestenrahmen: Breite zwischen Mindestkante und Seitenbreite
    /// (Seitenverhaeltnis bleibt erhalten), Lage so, dass mindestens die
    /// Mindestkante sichtbar bleibt.
    private func boundedImageFrame(_ frame: CGRect) -> CGRect {
        let pageSize = canonicalSize
        let aspect = frame.width > 0 ? frame.height / frame.width : 1
        var width = min(max(frame.width, Self.imageMinimumEdge), pageSize.width)
        var height = width * aspect
        if height > pageSize.height {
            height = pageSize.height
            width = aspect > 0 ? height / aspect : width
        }
        let edge = Self.imageMinimumEdge
        let x = min(max(frame.minX, edge - width), pageSize.width - edge)
        let y = min(max(frame.minY, edge - height), pageSize.height - edge)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Verkleinert Bilddaten auf die Anzeige-Zielgroesse (laengste Kante 2048 px,
    /// nie hochskaliert) und kodiert neu: PNG bei Transparenz (typisch QR-Code),
    /// sonst JPEG. Laeuft explizit im Hintergrund.
    @concurrent
    nonisolated static func normalizeImageData(
        _ data: Data, maxEdge: CGFloat = 2048
    ) async -> (data: Data, pixelSize: CGSize)? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        let hasAlpha: Bool
        switch cgImage.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: hasAlpha = false
        default: hasAlpha = true
        }
        let image = UIImage(cgImage: cgImage)
        guard let encoded = hasAlpha ? image.pngData() : image.jpegData(compressionQuality: 0.85)
        else { return nil }
        return (encoded, CGSize(width: cgImage.width, height: cgImage.height))
    }

    // MARK: - Quiz

    /// Gerade geoeffnetes Quiz; Zustand liegt im ViewModel, damit Geraet
    /// (steuernd) und Beamer (lesend) denselben Stand sehen.
    private(set) var activeQuiz: InteractiveElement?
    /// Gewaehlte Antwort (0-basiert); nil = noch keine Wahl.
    private(set) var quizSelection: Int?
    /// Aufgeloest: die richtige Antwort wird markiert.
    private(set) var isQuizResolved = false

    func openQuiz(_ element: InteractiveElement) {
        activeQuiz = element
        quizSelection = nil
        isQuizResolved = false
    }

    func selectQuizAnswer(_ index: Int) {
        guard !isQuizResolved else { return }
        quizSelection = index
    }

    func resolveQuiz() {
        isQuizResolved = true
    }

    func closeQuiz() {
        activeQuiz = nil
        quizSelection = nil
        isQuizResolved = false
    }

    /// Laedt Zeichnung, Basisbild und Bild-Elemente der aktuellen Seite in den
    /// Live-Zustand.
    private func loadCurrentPage() {
        if let page = currentPage, !page.drawingData.isEmpty,
           let drawing = try? PKDrawing(data: page.drawingData) {
            currentDrawing = drawing
        } else {
            currentDrawing = PKDrawing()
        }
        drawingVersion += 1

        if let page = currentPage, !page.isWhiteboard, !page.baseImageData.isEmpty {
            currentBaseImage = UIImage(data: page.baseImageData)
        } else {
            currentBaseImage = nil
        }

        selectImageElement(nil)
        if let page = currentPage {
            currentImageElements = store.imageElements(on: page)
                .sorted { $0.order < $1.order }
        } else {
            currentImageElements = []
        }
        elementImages = currentImageElements.reduce(into: [:]) { images, element in
            images[element.id] = UIImage(data: element.imageData)
        }
    }
}
