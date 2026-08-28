//
//  SessionTimer.swift
//  PresentationCoreKit
//
//  Countdown fuer Arbeitsphasen im Praesentationsmodus. Gespeichert wird nur
//  der Zielzeitpunkt – kein `Timer`-Objekt, kein Drift, kein State-Update im
//  Sekundentakt. Die Anzeige fragt die computed Restzeit per `TimelineView` ab.
//

import Foundation
import Observation

@Observable
public final class SessionTimer {

    // MARK: - State

    /// Zielzeitpunkt des laufenden Countdowns; nil, wenn pausiert oder beendet.
    public private(set) var endDate: Date?
    /// Verbleibende Zeit im pausierten Zustand; nil, wenn laufend oder beendet.
    public private(set) var pausedRemaining: TimeInterval?

    // MARK: - Dependencies

    /// Injizierbare Uhr – Tests laufen mit stehender bzw. gestellter Zeit.
    private let now: () -> Date

    // MARK: - Init

    public init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    // MARK: - Computed

    /// Verbleibende Sekunden; nil, wenn kein Timer gesetzt ist. Klemmt bei 0.
    public var remaining: TimeInterval? {
        if let pausedRemaining { return max(0, pausedRemaining) }
        guard let endDate else { return nil }
        return max(0, endDate.timeIntervalSince(now()))
    }

    public var isActive: Bool { endDate != nil || pausedRemaining != nil }
    public var isPaused: Bool { pausedRemaining != nil }
    /// true, sobald ein gesetzter Timer bei null angekommen ist.
    public var isExpired: Bool {
        guard let remaining else { return false }
        return remaining <= 0
    }

    /// Restzeit als `mm:ss` (bzw. `h:mm:ss` ab einer Stunde) fuer die Anzeige.
    public var remainingText: String? {
        guard let remaining else { return nil }
        let totalSeconds = Int(remaining.rounded(.up))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Steuerung

    /// Startet (oder ersetzt) den Countdown mit der angegebenen Dauer.
    public func start(duration: TimeInterval) {
        pausedRemaining = nil
        endDate = now().addingTimeInterval(max(0, duration))
    }

    /// Haelt den Countdown an; die Restzeit bleibt eingefroren erhalten.
    public func pause() {
        guard let rest = remaining else { return }
        pausedRemaining = rest
        endDate = nil
    }

    /// Setzt einen pausierten Countdown mit der eingefrorenen Restzeit fort.
    public func resume() {
        guard let rest = pausedRemaining else { return }
        start(duration: rest)
    }

    /// Verlaengert den Countdown (Button „+1 min") – auch im pausierten Zustand.
    public func extend(by extra: TimeInterval) {
        guard isActive else { return }
        if let pausedRemaining {
            self.pausedRemaining = max(0, pausedRemaining + extra)
        } else if let endDate {
            // Bei bereits abgelaufenem Timer zaehlt die Verlaengerung ab jetzt,
            // sonst waere sie durch die verstrichene Zeit sofort aufgezehrt.
            let base = max(endDate, now())
            self.endDate = base.addingTimeInterval(extra)
        }
    }

    /// Beendet den Countdown vollstaendig.
    public func end() {
        endDate = nil
        pausedRemaining = nil
    }
}
