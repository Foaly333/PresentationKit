//
//  PresentationView.swift
//  PresentationUIKit
//
//  Vollbild-Praesentationsansicht: Seitenbild + PencilKit-Canvas, Seitenleiste
//  und Grid-Overlay fuer den Direktsprung, Laserpointer, Arbeitsphasen-Timer,
//  Steuerleiste und Anbindung des externen Displays. Ohne Beamer laeuft die
//  Praesentation im Vollbild auf dem Geraet.
//
//  Oeffentliches API des Pakets: Seiten + Store + optionale Agenda-Eingabe,
//  Anhang-Aufloesung, Konfiguration und Steuerleisten-Slot. Alles Weitere
//  (ViewModel, Overlays) bleibt paketintern.
//

import PhotosUI
import PresentationCoreKit
import SwiftUI
import PencilKit
import UniformTypeIdentifiers

public struct PresentationView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: PresentationViewModel
    @State private var externalDisplay = ExternalDisplayController()
    private let configuration: PresentationConfiguration
    private let toolbarAccessory: AnyView?

    // Aufgeloestes Medium bzw. Hinweis bei nicht aufloesbarer Referenz.
    @State private var presentedMedium: PresentedMedium?
    @State private var mediaHint = false

    // Bild-Einfuegen: Langdruck-Menue und Bildquellen.
    /// Position des offenen Einfuege-Menues (kanonischer Raum); nil = zu.
    @State private var imageMenuPoint: CGPoint?
    /// Einfuegeposition — bleibt ueber die Picker-Praesentation hinweg erhalten.
    @State private var imageInsertionPoint: CGPoint = .zero
    /// Bild-Element unter dem Langdruck (fuer Bearbeiten/Loeschen im Menue).
    @State private var hitImageID: UUID?
    @State private var showsPhotoPicker = false
    @State private var photoSelection: PhotosPickerItem?
    @State private var showsFilePicker = false
    @State private var imageError: String?

    /// Baut die Praesentation aus Seiten und Store. `agendaInput` speist den
    /// Soll-Chip, `attachmentResolver` loest Anhang-Referenzen der
    /// Medien-Elemente auf, `toolbarAccessory` haengt App-Chrome in die
    /// Steuerleiste (rechte Zone).
    public init(
        pages: [any PresentationPage],
        store: PresentationPageStore,
        agendaInput: (items: [AgendaItem], slotIntervals: [DateInterval])? = nil,
        attachmentResolver: ((String) -> MediaTarget?)? = nil,
        configuration: PresentationConfiguration = PresentationConfiguration(),
        toolbarAccessory: AnyView? = nil
    ) {
        _viewModel = State(initialValue: PresentationViewModel(
            pages: pages,
            store: store,
            agendaInput: agendaInput,
            attachmentResolver: attachmentResolver
        ))
        self.configuration = configuration
        self.toolbarAccessory = toolbarAccessory
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                pageSurface(in: geometry.size)

                imageMenuAnchor(in: geometry.size)

                // Ohne Beamer laeuft der Countdown im Geraete-Vollbild mit.
                if configuration.showsTimer, !viewModel.isExternalDisplayConnected {
                    VStack {
                        SessionTimerOverlay(timer: viewModel.sessionTimer)
                            .padding(.top, 24)
                        Spacer()
                    }
                }

                VStack {
                    HStack {
                        Spacer()
                        displayBadge
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                    Spacer()

                    PresentationToolbar(
                        viewModel: viewModel,
                        configuration: configuration,
                        end: {
                            viewModel.end()
                            dismiss()
                        },
                        insertWhiteboard: {
                            viewModel.insertWhiteboardPage()
                        },
                        accessory: toolbarAccessory
                    )
                }

                // Kontext-Karte des aktuellen Materials, oben rechts unter dem
                // Beamer-Badge — reine Regieinfo auf dem Geraet.
                if viewModel.showsPageContext,
                   let context = viewModel.currentPageContext {
                    VStack {
                        HStack {
                            Spacer()
                            PageContextOverlay(context: context) {
                                viewModel.showsPageContext = false
                            }
                        }
                        .padding(.trailing, 24)
                        .padding(.top, 64)
                        Spacer()
                    }
                    .transition(.opacity)
                }

                sidebar

                if viewModel.showsPageGrid {
                    PageGridView(viewModel: viewModel) {
                        viewModel.showsPageGrid = false
                    }
                    .transition(.opacity)
                }

                // Quiz-Overlay (steuernd); der Beamer spiegelt den Zustand.
                if viewModel.activeQuiz != nil {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture { viewModel.closeQuiz() }
                    QuizOverlayView(viewModel: viewModel)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.isSidebarVisible)
            .animation(.easeInOut(duration: 0.2), value: viewModel.showsPageContext)
            .animation(.easeInOut(duration: 0.2), value: viewModel.showsPageGrid)
            .animation(.easeInOut(duration: 0.2), value: viewModel.activeQuiz != nil)
        }
        .statusBarHidden()
        .sheet(item: $presentedMedium) { medium in
            switch medium.kind {
            case .attachment:
                QuickLookSheet(url: medium.url, title: medium.url.lastPathComponent)
            case .web:
                SafariSheet(url: medium.url)
            }
        }
        .alert(localized("Medium nicht auffindbar"), isPresented: $mediaHint) {
            Button("OK") {}
        } message: {
            Text(localized("Die referenzierte URL oder der Anhang konnte nicht aufgelöst werden."))
        }
        .photosPicker(isPresented: $showsPhotoPicker, selection: $photoSelection, matching: .images)
        .onChange(of: photoSelection) { _, selection in
            guard let selection else { return }
            Task {
                let data = try? await selection.loadTransferable(type: Data.self)
                photoSelection = nil
                await insertImage(data: data)
            }
        }
        .fileImporter(isPresented: $showsFilePicker, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let data = readFile(url)
            Task { await insertImage(data: data) }
        }
        .alert(localized("Bild einfügen"), isPresented: .constant(imageError != nil)) {
            Button("OK") { imageError = nil }
        } message: {
            Text(imageError ?? "")
        }
        .onAppear { externalDisplay.start(viewModel: viewModel) }
        .onDisappear {
            viewModel.end()
            externalDisplay.end()
        }
    }

    // MARK: - Medium

    /// Loest die Medien-Referenz auf und praesentiert QuickLook (Anhang) bzw.
    /// eine Safari-View (URL); nicht aufloesbar → Hinweis statt Crash.
    private func openMedia(_ element: InteractiveElement) {
        switch viewModel.mediaTarget(for: element) {
        case .url(let url):
            presentedMedium = PresentedMedium(url: url, kind: .web)
        case .attachment(let data, let filename):
            let target = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            do {
                try data.write(to: target)
                presentedMedium = PresentedMedium(url: target, kind: .attachment)
            } catch {
                mediaHint = true
            }
        case nil:
            mediaHint = true
        }
    }

    // MARK: - Bild einfuegen

    /// Unsichtbarer 1-pt-Anker an der Langdruck-Position, umgerechnet vom
    /// kanonischen Raum in die aeusseren Koordinaten (die Seitenflaeche liegt
    /// zentriert und per `scaleEffect` skaliert — Popover-Anker muessen
    /// ausserhalb der Skalierung liegen). Das Einfuege-Menue erscheint als
    /// Popover genau am gedrueckten Punkt.
    private func imageMenuAnchor(in available: CGSize) -> some View {
        let canonical = viewModel.canonicalSize
        let scale = scaleFactor(for: canonical, in: available)
        let point = imageMenuPoint ?? .zero
        return Color.clear
            .frame(width: 1, height: 1)
            .position(x: available.width / 2 + (point.x - canonical.width / 2) * scale,
                      y: available.height / 2 + (point.y - canonical.height / 2) * scale)
            .confirmationDialog(
                hitImageID == nil ? localized("Bild einfügen") : localized("Bild"),
                isPresented: Binding(
                    get: { imageMenuPoint != nil },
                    set: { if !$0 { imageMenuPoint = nil } }
                ),
                titleVisibility: .visible
            ) {
                imageMenuActions
            }
    }

    @ViewBuilder
    private var imageMenuActions: some View {
        if let hitID = hitImageID {
            Button(localized("Bild verschieben/skalieren")) {
                viewModel.selectImageElement(hitID)
            }
            Button(localized("Bild löschen"), role: .destructive) {
                viewModel.deleteImageElement(hitID)
            }
        }
        Button(localized("Aus Zwischenablage einfügen")) { insertFromPasteboard() }
        Button(localized("Aus Fotos einfügen")) { showsPhotoPicker = true }
        Button(localized("Aus Dateien einfügen")) { showsFilePicker = true }
    }

    private func insertFromPasteboard() {
        guard let image = UIPasteboard.general.image, let data = image.pngData() else {
            imageError = localized("Die Zwischenablage enthält kein Bild.")
            return
        }
        Task { await insertImage(data: data) }
    }

    private func insertImage(data: Data?) async {
        guard let data,
              await viewModel.insertImageElement(data: data, at: imageInsertionPoint)
        else {
            imageError = localized("Die Auswahl konnte nicht als Bild eingefügt werden.")
            return
        }
    }

    /// Liest eine per Dateien-App gewaehlte Datei (Security-Scoped-Zugriff).
    private func readFile(_ url: URL) -> Data? {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }

    // MARK: - Seite und Canvas

    /// Seite und Canvas werden IMMER in der kanonischen Groesse layoutet und nur
    /// zur Darstellung skaliert (aspect fit). Die Strichkoordinaten sind dadurch
    /// geraete- und rotationsunabhaengig – Annotationen bleiben pro Seite
    /// lagestabil. Auch der Laserpointer wird so kanonisch erfasst.
    private func pageSurface(in available: CGSize) -> some View {
        let canonical = viewModel.canonicalSize
        let scale = scaleFactor(for: canonical, in: available)
        return ZStack {
            pageBackground
            // Eingefuegte Bilder unter dem Canvas: Striche liegen ueber ihnen.
            PageImagesLayer(viewModel: viewModel)
            PencilCanvasView(
                drawing: viewModel.currentDrawing,
                drawingVersion: viewModel.drawingVersion,
                onDrawingChanged: { viewModel.updateDrawing($0) },
                onSwipeLeft: { viewModel.showNextPage() },
                onSwipeRight: { viewModel.showPreviousPage() },
                onLongPress: { point in
                    imageInsertionPoint = point
                    hitImageID = viewModel.imageElement(at: point)?.id
                    imageMenuPoint = point
                },
                onImageDropped: { data, point in
                    imageInsertionPoint = point
                    Task { await insertImage(data: data) }
                },
                isLaserPointerActive: viewModel.isLaserPointerActive,
                allowsImageInsertion: configuration.allowsImageInsertion
            )
            if viewModel.isLaserPointerActive {
                LaserPointerCapture { viewModel.updateLaserPointer($0) }
            }
            // Tap-Flaechen der interaktiven Elemente — im kanonischen Raum,
            // skaliert mit der Seite.
            InteractiveElementsOverlay(viewModel: viewModel, configuration: configuration) { element in
                openMedia(element)
            }
            // Bearbeitungsschicht des ausgewaehlten Bildes (nur bei Auswahl aktiv).
            if configuration.allowsImageInsertion {
                PageImageEditOverlay(viewModel: viewModel) {
                    viewModel.deleteSelectedImageElement()
                }
            }
            if let point = viewModel.laserPointerPosition {
                LaserPointerDotView(position: point)
            }
        }
        .frame(width: canonical.width, height: canonical.height)
        .animation(.easeOut(duration: 0.15), value: viewModel.laserPointerPosition == nil)
        .scaleEffect(scale)
        .frame(width: canonical.width * scale, height: canonical.height * scale)
    }

    @ViewBuilder
    private var pageBackground: some View {
        if let image = viewModel.currentBaseImage {
            Image(uiImage: image)
                .resizable()
        } else {
            // Whiteboard oder fehlendes Bild: weisse Flaeche.
            Color.white
        }
    }

    /// Aspect-fit-Faktor, mit dem der kanonische Seitenraum in den verfuegbaren
    /// Platz skaliert wird.
    private func scaleFactor(for canonical: CGSize, in available: CGSize) -> CGFloat {
        guard available.width > 0, available.height > 0,
              canonical.width > 0, canonical.height > 0 else { return 1 }
        return min(available.width / canonical.width, available.height / canonical.height)
    }

    // MARK: - Seitenleiste und Badge

    @ViewBuilder
    private var sidebar: some View {
        if viewModel.isSidebarVisible {
            HStack(spacing: 0) {
                PageSidebarView(viewModel: viewModel)
                Spacer(minLength: 0)
            }
            .transition(.move(edge: .leading))
        }
    }

    /// Auf dem Geraet bleibt immer das Live-Bild sichtbar – ein aktiver
    /// Beamer-Zustand wird darum nur als Badge angezeigt.
    @ViewBuilder
    private var displayBadge: some View {
        if viewModel.isBlackout || viewModel.isFrozen {
            Label(viewModel.isBlackout ? localized("Beamer schwarz") : localized("Beamer eingefroren"),
                  systemImage: viewModel.isBlackout ? "rectangle.slash" : "pause.rectangle")
                .font(.footnote.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.orange, in: Capsule())
                .accessibilityIdentifier("praesentation.beamer.badge")
        }
    }
}
