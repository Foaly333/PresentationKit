//
//  AgendaProgress.swift
//  PresentationCoreKit
//
//  Reine Zeitmathematik „Wo muesste ich laut Plan gerade sein?". Eingaben sind
//  die Agenda-Punkte der Sitzung und die belegten Zeitfenster als
//  Datumsintervalle; Pausen zwischen den Intervallen (z. B. Doppelstunde)
//  zaehlen nicht als Sitzungszeit. Kein Date.now im Service — `now` kommt vom
//  Aufrufer, damit Anzeige (TimelineView) und Tests die Zeit stellen koennen.
//

import Foundation

/// Ein Punkt der Agenda, aufbereitet fuer die Soll-Anzeige.
public nonisolated struct AgendaItem: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let detail: String?
    /// Sozial-/Arbeitsform o. ä. — kurzes Etikett neben dem Titel.
    public let form: String?
    /// Geplante Dauer in Minuten; 0 bei fehlender Angabe.
    public let durationMinutes: Int
    /// Materialspalte des Punkts (verknuepfte Materialien, Anhaenge, …).
    public let materialTitles: [String]

    public init(
        id: UUID, title: String, detail: String?, form: String?,
        durationMinutes: Int, materialTitles: [String]
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.form = form
        self.durationMinutes = durationMinutes
        self.materialTitles = materialTitles
    }
}

/// Uhrzeit-Fenster eines Agenda-Punkts, ueber Pausen hinweg gerechnet.
public nonisolated struct AgendaWindow: Equatable, Identifiable, Sendable {
    public let item: AgendaItem
    public let start: Date
    public let end: Date
    public var id: UUID { item.id }

    public init(item: AgendaItem, start: Date, end: Date) {
        self.item = item
        self.start = start
        self.end = end
    }
}

/// Wo die Sitzung laut Zeitplan gerade steht.
public nonisolated enum AgendaState: Equatable, Sendable {
    case beforeSession(minutesUntilStart: Int)
    case item(index: Int, remainingMinutes: Int)
    /// Luecke zwischen belegten Zeitfenstern (Pause); `nextIndex` ist der
    /// danach anstehende Punkt, nil wenn der Plan bereits verbraucht ist.
    case pause(nextIndex: Int?)
    /// Sitzung laeuft noch, aber die Plansumme ist bereits ueberschritten.
    case overrun(minutes: Int)
    case afterSession
}

/// Vollstaendiges Ergebnis der Soll-Berechnung fuer einen Zeitpunkt.
public nonisolated struct AgendaStatus: Equatable, Sendable {
    public let windows: [AgendaWindow]
    public let state: AgendaState
    public let sessionStart: Date
    public let sessionEnd: Date

    public init(windows: [AgendaWindow], state: AgendaState, sessionStart: Date, sessionEnd: Date) {
        self.windows = windows
        self.state = state
        self.sessionStart = sessionStart
        self.sessionEnd = sessionEnd
    }
}

public protocol AgendaProgressServiceProtocol {
    /// Berechnet Fenster und Zustand fuer `now`.
    /// - Parameter slotIntervals: belegte Zeitfenster als Intervalle am
    ///   Sitzungstag, aufsteigend und ueberlappungsfrei; leer → nil.
    /// - Returns: nil bei leerer Agenda, Plansumme 0 oder fehlenden Intervallen.
    func status(items: [AgendaItem], slotIntervals: [DateInterval], now: Date) -> AgendaStatus?
}

public final class AgendaProgressService: AgendaProgressServiceProtocol {

    public init() {}

    public func status(items: [AgendaItem], slotIntervals: [DateInterval], now: Date) -> AgendaStatus? {
        let totalMinutes = items.reduce(0) { $0 + max($1.durationMinutes, 0) }
        guard !items.isEmpty, totalMinutes > 0,
              let firstSlot = slotIntervals.first, let lastSlot = slotIntervals.last
        else { return nil }

        // Uhrzeit-Fenster: kumulative Minuten-Offsets ueber die Intervalle gelegt.
        var windows: [AgendaWindow] = []
        var offset = 0.0
        for item in items {
            let start = wallClock(afterMinutes: offset, in: slotIntervals, asEnd: false)
            offset += Double(max(item.durationMinutes, 0))
            let end = wallClock(afterMinutes: offset, in: slotIntervals, asEnd: true)
            windows.append(AgendaWindow(item: item, start: start, end: end))
        }

        return AgendaStatus(
            windows: windows,
            state: state(items: items, slotIntervals: slotIntervals,
                         totalMinutes: totalMinutes,
                         start: firstSlot.start, end: lastSlot.end, now: now),
            sessionStart: firstSlot.start,
            sessionEnd: lastSlot.end
        )
    }

    // MARK: - Intern

    private func state(
        items: [AgendaItem],
        slotIntervals: [DateInterval],
        totalMinutes: Int,
        start: Date,
        end: Date,
        now: Date
    ) -> AgendaState {
        guard now >= start else {
            let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
            return .beforeSession(minutesUntilStart: max(minutes, 0))
        }
        guard now < end else {
            return .afterSession
        }

        let elapsed = elapsedMinutes(until: now, in: slotIntervals)
        let inPause = !slotIntervals.contains { $0.start <= now && now < $0.end }
        let currentIndex = itemIndex(at: elapsed, items: items)

        if inPause {
            return .pause(nextIndex: currentIndex)
        }
        if let index = currentIndex {
            let untilEnd = cumulativeEnd(of: index, items: items) - elapsed
            return .item(index: index, remainingMinutes: max(Int(untilEnd.rounded(.up)), 0))
        }
        return .overrun(minutes: max(Int((elapsed - Double(totalMinutes)).rounded(.down)), 0))
    }

    /// Verstrichene Sitzungsminuten: Ueberlappung der Intervalle mit `(-∞, now]`.
    private func elapsedMinutes(until now: Date, in slots: [DateInterval]) -> Double {
        slots.reduce(0.0) { sum, slot in
            let until = min(now, slot.end)
            guard until > slot.start else { return sum }
            return sum + until.timeIntervalSince(slot.start) / 60
        }
    }

    /// Wanduhr-Zeitpunkt nach `offset` Sitzungsminuten. Ein Offset genau auf
    /// einer Intervall-Grenze liegt als Punkt-Ende am Intervall-Ende, als
    /// Punkt-Start am Beginn des Folgeintervalls (nach der Pause). Ueberhang
    /// ueber die Kapazitaet klemmt auf das Sitzungsende.
    private func wallClock(afterMinutes offset: Double, in slots: [DateInterval], asEnd: Bool) -> Date {
        var remaining = offset
        for (index, slot) in slots.enumerated() {
            let capacity = slot.duration / 60
            let isLast = index == slots.count - 1
            if remaining < capacity || (asEnd && remaining == capacity) || isLast {
                return min(slot.start.addingTimeInterval(remaining * 60), slot.end)
            }
            remaining -= capacity
        }
        return slots.last?.end ?? Date.distantPast
    }

    /// Index des Punkts, in dem der kumulierte Minutenstand liegt; Punkte ohne
    /// Dauer werden uebersprungen. nil, wenn der Plan verbraucht ist.
    private func itemIndex(at elapsed: Double, items: [AgendaItem]) -> Int? {
        var cumulative = 0.0
        for (index, item) in items.enumerated() {
            cumulative += Double(max(item.durationMinutes, 0))
            if item.durationMinutes > 0, cumulative > elapsed {
                return index
            }
        }
        return nil
    }

    private func cumulativeEnd(of index: Int, items: [AgendaItem]) -> Double {
        items.prefix(index + 1).reduce(0.0) { $0 + Double(max($1.durationMinutes, 0)) }
    }
}
