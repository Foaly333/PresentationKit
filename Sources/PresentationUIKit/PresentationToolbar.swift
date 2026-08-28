//
//  PresentationToolbar.swift
//  PresentationUIKit
//
//  Steuerleiste des Praesentationsmodus in drei Zonen: links Sitzung, Mitte
//  Navigation, rechts Werkzeuge und Ausgabe. Das Beamer-Menue (Freeze/Blackout)
//  erscheint nur bei verbundenem externem Display; die uebrigen Werkzeuge
//  schaltet die `PresentationConfiguration`. Der `accessory`-Slot nimmt
//  App-Chrome auf, ohne dass in die Leiste hineingepatcht werden muss.
//

import PresentationCoreKit
import SwiftUI

struct PresentationToolbar: View {

    let viewModel: PresentationViewModel
    let configuration: PresentationConfiguration
    let end: () -> Void
    let insertWhiteboard: () -> Void
    /// App-Chrome-Slot (rechte Zone); nil = kein Zusatz.
    let accessory: AnyView?

    @State private var showsClearDialog = false
    @State private var showsTimerPopover = false
    @State private var showsAgendaPopover = false

    var body: some View {
        HStack(spacing: 0) {
            sessionZone
            divider
            navigationZone
            divider
            toolsZone
        }
        .font(.title2)
        .labelStyle(.iconOnly)
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.black.opacity(0.6), in: Capsule())
        .padding(.bottom, 8)
    }

    private var divider: some View {
        Divider()
            .frame(height: 24)
            .overlay(.white.opacity(0.3))
            .padding(.horizontal, 14)
    }

    // MARK: - Links · Sitzung

    private var sessionZone: some View {
        HStack(spacing: 18) {
            Button {
                end()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .accessibilityIdentifier("praesentation.beenden")

            Button {
                viewModel.isSidebarVisible.toggle()
            } label: {
                Image(systemName: "sidebar.left")
                    .foregroundStyle(viewModel.isSidebarVisible ? Color.accentColor : .white)
            }
            .accessibilityIdentifier("praesentation.seitenleiste.toggle")
            .accessibilityLabel(Text(localized("Seitenleiste")))

            if configuration.showsAgenda, viewModel.hasAgenda {
                agendaChip
            }

            if !viewModel.isPersistent {
                Label(localized("Ohne Speicherung"), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .labelStyle(.titleAndIcon)
            }
        }
    }

    // MARK: - Mitte · Navigation

    private var navigationZone: some View {
        HStack(spacing: 18) {
            Button {
                viewModel.showPreviousPage()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!viewModel.canGoBack)
            .accessibilityIdentifier("praesentation.zurueck")

            // Tipp auf die Seitenanzeige oeffnet das Grid-Overlay.
            Button {
                viewModel.showsPageGrid = true
            } label: {
                Text(viewModel.pageLabel)
                    .monospacedDigit()
            }
            .disabled(!configuration.showsPageGrid)
            .accessibilityIdentifier("praesentation.seitenanzeige")
            .accessibilityLabel(Text(localized("Seite \(viewModel.pageLabel), Seitenübersicht öffnen")))

            Button {
                viewModel.showNextPage()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!viewModel.canGoForward)
            .accessibilityIdentifier("praesentation.weiter")
        }
    }

    // MARK: - Rechts · Werkzeuge und Ausgabe

    private var toolsZone: some View {
        HStack(spacing: 18) {
            if configuration.showsLaserPointer {
                Button {
                    viewModel.setLaserPointer(active: !viewModel.isLaserPointerActive)
                } label: {
                    Image(systemName: "dot.circle.and.hand.point.up.left.fill")
                        .foregroundStyle(viewModel.isLaserPointerActive ? Color.red : .white)
                }
                .accessibilityIdentifier("praesentation.laserpointer")
                .accessibilityLabel(Text(localized("Laserpointer")))
            }

            if configuration.allowsWhiteboardPages {
                Button {
                    insertWhiteboard()
                } label: {
                    Label(localized("Whiteboard"), systemImage: "plus.rectangle.on.rectangle")
                }
                .accessibilityIdentifier("praesentation.whiteboard")
            }

            clearButton

            if viewModel.currentPageContext != nil {
                pageContextButton
            }

            if configuration.showsTimer {
                timerButton
            }

            if configuration.showsExternalDisplayControls, viewModel.isExternalDisplayConnected {
                displayMenu
            }

            if let accessory {
                accessory
            }
        }
    }

    // MARK: - Agenda-Chip

    /// Dauerhaft mitlaufender Soll-Chip; Tipp oeffnet das Agenda-Popover.
    /// Der 10-Sekunden-Takt haelt die Minutenangabe aktuell, ohne die Leiste
    /// im Sekundentakt neu zu bauen.
    private var agendaChip: some View {
        TimelineView(.periodic(from: .now, by: 10)) { context in
            Button {
                showsAgendaPopover = true
            } label: {
                Label(chipText(now: context.date), systemImage: "clock")
                    .font(.caption)
                    .labelStyle(.titleAndIcon)
            }
        }
        .accessibilityIdentifier("praesentation.phasenchip")
        .accessibilityLabel(Text(localized("Soll-Abschnitt laut Agenda")))
        .popover(isPresented: $showsAgendaPopover) {
            AgendaPopoverView(viewModel: viewModel)
                .presentationCompactAdaptation(.popover)
        }
    }

    private func chipText(now: Date) -> String {
        guard let status = viewModel.agendaStatus(now: now) else { return localized("Agenda") }
        switch status.state {
        case .beforeSession(let minutes):
            return localized("Beginn in \(minutes) min")
        case .item(let index, let remaining):
            let title = status.windows.indices.contains(index)
                ? status.windows[index].item.title : localized("Abschnitt \(index + 1)")
            return localized("\(title) · noch \(remaining) min")
        case .pause(let next):
            if let next, status.windows.indices.contains(next) {
                return localized("Pause · dann \(status.windows[next].item.title)")
            }
            return localized("Pause")
        case .overrun(let minutes):
            return localized("Plan +\(minutes) min")
        case .afterSession:
            return localized("Sitzung beendet")
        }
    }

    /// Blendet die Kontext-Karte zum aktuellen Material ein/aus.
    private var pageContextButton: some View {
        Button {
            viewModel.showsPageContext.toggle()
        } label: {
            Image(systemName: "note.text")
                .foregroundStyle(viewModel.showsPageContext ? Color.accentColor : .white)
        }
        .accessibilityIdentifier("praesentation.phasenbeschreibung")
        .accessibilityLabel(Text(localized("Abschnittsbeschreibung")))
    }

    private var clearButton: some View {
        Button {
            showsClearDialog = true
        } label: {
            Label(localized("Annotationen löschen"), systemImage: "eraser.line.dashed")
        }
        .disabled(viewModel.currentDrawing.strokes.isEmpty)
        .accessibilityIdentifier("praesentation.zuruecksetzen")
        .confirmationDialog(
            localized("Annotationen dieser Seite löschen?"),
            isPresented: $showsClearDialog,
            titleVisibility: .visible
        ) {
            Button(localized("Löschen"), role: .destructive) {
                viewModel.clearCurrentDrawing()
            }
            Button(localized("Abbrechen"), role: .cancel) { }
        }
    }

    private var timerButton: some View {
        Button {
            showsTimerPopover = true
        } label: {
            if viewModel.sessionTimer.isActive {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Label(viewModel.sessionTimer.remainingText ?? "",
                          systemImage: "timer")
                        .labelStyle(.titleAndIcon)
                        .font(.title3.monospacedDigit())
                }
            } else {
                Image(systemName: "timer")
            }
        }
        .accessibilityIdentifier("praesentation.timer")
        .accessibilityLabel(Text(localized("Arbeitsphasen-Timer")))
        .popover(isPresented: $showsTimerPopover) {
            TimerPopoverView(timer: viewModel.sessionTimer) {
                showsTimerPopover = false
            }
            .presentationCompactAdaptation(.popover)
        }
    }

    /// Buendelt Freeze und Blackout; ohne Beamer entfaellt das Menue vollstaendig.
    private var displayMenu: some View {
        Menu {
            Button {
                viewModel.setFrozen(!viewModel.isFrozen)
            } label: {
                Label(viewModel.isFrozen ? localized("Freigeben") : localized("Einfrieren"),
                      systemImage: "pause.rectangle")
            }
            Button {
                viewModel.setBlackout(!viewModel.isBlackout)
            } label: {
                Label(viewModel.isBlackout ? localized("Blackout aus") : localized("Blackout"),
                      systemImage: "rectangle.slash")
            }
        } label: {
            Image(systemName: "tv")
                .foregroundStyle(viewModel.isFrozen || viewModel.isBlackout
                                 ? Color.orange : .white)
        }
        .accessibilityIdentifier("praesentation.beamermenue")
        .accessibilityLabel(Text(localized("Beamer")))
    }
}
