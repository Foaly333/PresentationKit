//
//  AgendaProgressServiceTests.swift
//  PresentationCoreKitTests
//
//  Reine Wertetests der Zeitmathematik — feste Zeitpunkte, kein Date.now.
//

import Testing
import Foundation
@testable import PresentationCoreKit

@Suite("AgendaProgressService Tests")
struct AgendaProgressServiceTests {

    private let sut = AgendaProgressService()

    // MARK: - Fixtures

    /// Fester Sitzungstag, Uhrzeiten daran verankert.
    private static let day: Date = {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 8; comps.day = 20
        return Calendar.current.date(from: comps) ?? .distantPast
    }()

    private static func clock(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? .distantPast
    }

    private static func item(_ title: String, minutes: Int) -> AgendaItem {
        AgendaItem(id: UUID(), title: title, detail: nil, form: nil,
                   durationMinutes: minutes, materialTitles: [])
    }

    /// Einzelsitzung 09:45–10:30 (45 min).
    private static let singleSession = [DateInterval(start: clock(9, 45), end: clock(10, 30))]

    /// Doppelsitzung mit Pause: 09:45–10:30 und 10:50–11:35.
    private static let doubleSession = [
        DateInterval(start: clock(9, 45), end: clock(10, 30)),
        DateInterval(start: clock(10, 50), end: clock(11, 35)),
    ]

    /// Standardplan 10 + 20 + 15 = 45 min.
    private static let plan45 = [
        item("Einstieg", minutes: 10), item("Erarbeitung", minutes: 20), item("Sicherung", minutes: 15),
    ]

    // MARK: - Einzelsitzung

    @Test("Laufender Punkt mit Restminuten")
    func runningItem() throws {
        let status = try #require(sut.status(
            items: Self.plan45, slotIntervals: Self.singleSession, now: Self.clock(9, 58)
        ))
        // 13 min verstrichen → Erarbeitung (10–30), Ende bei Minute 30 → noch 17.
        #expect(status.state == .item(index: 1, remainingMinutes: 17))
    }

    @Test("Grenzminute: exakt am Wechsel beginnt der naechste Punkt")
    func boundaryMinute() throws {
        let status = try #require(sut.status(
            items: Self.plan45, slotIntervals: Self.singleSession, now: Self.clock(9, 55)
        ))
        #expect(status.state == .item(index: 1, remainingMinutes: 20))
    }

    @Test("Uhrzeit-Fenster folgen den kumulierten Dauern")
    func windowsSingleSession() throws {
        let status = try #require(sut.status(
            items: Self.plan45, slotIntervals: Self.singleSession, now: Self.clock(9, 50)
        ))
        #expect(status.windows.count == 3)
        #expect(status.windows[0].start == Self.clock(9, 45))
        #expect(status.windows[0].end == Self.clock(9, 55))
        #expect(status.windows[1].end == Self.clock(10, 15))
        #expect(status.windows[2].end == Self.clock(10, 30))
        #expect(status.sessionStart == Self.clock(9, 45))
        #expect(status.sessionEnd == Self.clock(10, 30))
    }

    @Test("Vor der Sitzung: Minuten bis Beginn (aufgerundet)")
    func beforeSession() throws {
        let status = try #require(sut.status(
            items: Self.plan45, slotIntervals: Self.singleSession, now: Self.clock(9, 40)
        ))
        #expect(status.state == .beforeSession(minutesUntilStart: 5))
    }

    @Test("Nach der Sitzung")
    func afterSession() throws {
        let status = try #require(sut.status(
            items: Self.plan45, slotIntervals: Self.singleSession, now: Self.clock(10, 30)
        ))
        #expect(status.state == .afterSession)
    }

    @Test("Plan kuerzer als Sitzung: nach dem letzten Punkt ueberzogen")
    func overrun() throws {
        let shortPlan = [Self.item("Einstieg", minutes: 10), Self.item("Erarbeitung", minutes: 10)]
        let status = try #require(sut.status(
            items: shortPlan, slotIntervals: Self.singleSession, now: Self.clock(10, 8)
        ))
        // 23 min verstrichen, Plansumme 20 → 3 min ueberzogen.
        #expect(status.state == .overrun(minutes: 3))
    }

    @Test("Plan laenger als Sitzung: Fenster klemmen auf das Sitzungsende")
    func planLongerThanSession() throws {
        let longPlan = [Self.item("Einstieg", minutes: 30), Self.item("Erarbeitung", minutes: 40)]
        let status = try #require(sut.status(
            items: longPlan, slotIntervals: Self.singleSession, now: Self.clock(10, 0)
        ))
        #expect(status.windows[1].start == Self.clock(10, 15))
        #expect(status.windows[1].end == Self.clock(10, 30))
    }

    // MARK: - Doppelsitzung mit Pause

    @Test("Verstrichene Sitzungszeit ueberspringt die Pause")
    func doubleSessionAfterBreak() throws {
        let plan90 = [Self.item("Einstieg", minutes: 30), Self.item("Erarbeitung", minutes: 40),
                      Self.item("Sicherung", minutes: 20)]
        let status = try #require(sut.status(
            items: plan90, slotIntervals: Self.doubleSession, now: Self.clock(11, 0)
        ))
        // 45 min (1. Slot) + 10 min (2. Slot) = 55 → Erarbeitung (30–70), noch 15.
        #expect(status.state == .item(index: 1, remainingMinutes: 15))
    }

    @Test("In der Pause: Zustand pause mit naechstem Punkt")
    func duringBreak() throws {
        let plan90 = [Self.item("Einstieg", minutes: 45), Self.item("Erarbeitung", minutes: 45)]
        let status = try #require(sut.status(
            items: plan90, slotIntervals: Self.doubleSession, now: Self.clock(10, 40)
        ))
        #expect(status.state == .pause(nextIndex: 1))
    }

    @Test("Fenster ueber die Pause hinweg bekommen die spaetere Uhrzeit")
    func windowsAcrossBreak() throws {
        let plan90 = [Self.item("Einstieg", minutes: 45), Self.item("Erarbeitung", minutes: 45)]
        let status = try #require(sut.status(
            items: plan90, slotIntervals: Self.doubleSession, now: Self.clock(9, 50)
        ))
        // Einstieg endet am Slot-Ende, Erarbeitung beginnt nach der Pause.
        #expect(status.windows[0].end == Self.clock(10, 30))
        #expect(status.windows[1].start == Self.clock(10, 50))
        #expect(status.windows[1].end == Self.clock(11, 35))
    }

    // MARK: - Randfaelle

    @Test("Punkte ohne Dauer werden im Zustand uebersprungen")
    func itemsWithoutDuration() throws {
        let plan = [Self.item("Organisatorisches", minutes: 0), Self.item("Erarbeitung", minutes: 45)]
        let status = try #require(sut.status(
            items: plan, slotIntervals: Self.singleSession, now: Self.clock(9, 45)
        ))
        #expect(status.state == .item(index: 1, remainingMinutes: 45))
    }

    @Test("Leerer Plan oder Plansumme 0 liefert nil")
    func emptyPlan() {
        #expect(sut.status(items: [], slotIntervals: Self.singleSession, now: Self.clock(10, 0)) == nil)
        #expect(sut.status(items: [Self.item("Leer", minutes: 0)],
                           slotIntervals: Self.singleSession, now: Self.clock(10, 0)) == nil)
    }

    @Test("Ohne Slot-Intervalle liefert nil")
    func withoutSlots() {
        #expect(sut.status(items: Self.plan45, slotIntervals: [], now: Self.clock(10, 0)) == nil)
    }
}
