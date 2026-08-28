//
//  AgendaPopoverView.swift
//  PresentationUIKit
//
//  Operator-Popover des Soll-Chips. Zeigt die Agenda der Sitzung mit den auf
//  die Zeitfenster gerechneten Uhrzeit-Fenstern; der laut Zeitplan aktuelle
//  Punkt ist hervorgehoben.
//

import PresentationCoreKit
import SwiftUI

struct AgendaPopoverView: View {

    let viewModel: PresentationViewModel

    var body: some View {
        // 30-Sekunden-Takt genuegt: das Popover zeigt Minutenangaben.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let status = viewModel.agendaStatus(now: context.date) {
                content(status: status)
            } else {
                Text(localized("Keine Agenda verfügbar."))
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .frame(width: 400)
        // Das Popover erbt sonst weisses foregroundStyle und iconOnly-labelStyle
        // der Steuerleiste — auf dem hellen Popover-Hintergrund waere der Text
        // kaum lesbar bzw. verschwunden.
        .foregroundStyle(Color.primary)
        .labelStyle(.titleAndIcon)
        .accessibilityIdentifier("praesentation.verlaufsplanpopover")
    }

    private func content(status: AgendaStatus) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header(status: status)
                ForEach(Array(status.windows.enumerated()), id: \.element.id) { index, window in
                    AgendaRow(
                        window: window,
                        isCurrent: currentIndex(status: status) == index
                    )
                }
            }
            .padding(16)
        }
        .frame(maxHeight: 520)
    }

    private func header(status: AgendaStatus) -> some View {
        HStack {
            Label(
                "\(Self.wallClock(status.sessionStart))–\(Self.wallClock(status.sessionEnd))",
                systemImage: "clock"
            )
            .font(.subheadline.weight(.semibold))
            Spacer()
            stateBadge(status: status)
        }
    }

    @ViewBuilder
    private func stateBadge(status: AgendaStatus) -> some View {
        switch status.state {
        case .beforeSession(let minutes):
            badge(localized("Beginn in \(minutes) min"), color: .secondary)
        case .item:
            EmptyView()
        case .pause:
            badge(localized("Pause"), color: .orange)
        case .overrun(let minutes):
            badge(localized("Plan +\(minutes) min"), color: .orange)
        case .afterSession:
            badge(localized("Sitzung beendet"), color: .secondary)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
    }

    /// Index des hervorzuhebenden Punkts: der laufende, in der Pause der naechste.
    private func currentIndex(status: AgendaStatus) -> Int? {
        switch status.state {
        case .item(let index, _): return index
        case .pause(let next): return next
        default: return nil
        }
    }

    static func wallClock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

/// Ein Agenda-Punkt des Popovers: Uhrzeit-Fenster, Titel, Form, Beschreibung, Material.
private struct AgendaRow: View {

    let window: AgendaWindow
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(AgendaPopoverView.wallClock(window.start))–\(AgendaPopoverView.wallClock(window.end))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(window.item.title.strippingHTMLTags)
                    .font(.subheadline.weight(isCurrent ? .bold : .regular))
                Text(localized("(\(window.item.durationMinutes) min)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let form = window.item.form, !form.isEmpty {
                    Text(form)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.15), in: Capsule())
                }
            }

            if let detail = window.item.detail?.strippingHTMLTags,
               !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Index als ID — Materialtitel duerfen doppelt vorkommen.
            ForEach(Array(window.item.materialTitles.enumerated()), id: \.offset) { _, title in
                Label(title.strippingHTMLTags, systemImage: "doc.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isCurrent ? Color.accentColor.opacity(0.15) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(alignment: .leading) {
            if isCurrent {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 3)
            }
        }
    }
}
