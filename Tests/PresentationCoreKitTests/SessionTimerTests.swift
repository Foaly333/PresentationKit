//
//  SessionTimerTests.swift
//  PresentationCoreKitTests
//
//  Countdown fuer Arbeitsphasen – Zustandsuebergaenge mit injizierter Uhr
//  (kein `Date.now` in der Logik, sonst waeren die Tests flaky).
//

import Testing
import Foundation
@testable import PresentationCoreKit

@Suite("SessionTimer Tests")
struct SessionTimerTests {

    /// Stellbare Uhr: liefert immer den zuletzt gesetzten Zeitpunkt.
    final class Clock {
        var now: Date
        init(_ start: Date = Date(timeIntervalSince1970: 1_000_000)) { self.now = start }
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    private func makeSut() -> (SessionTimer, Clock) {
        let clock = Clock()
        let sut = SessionTimer(now: { clock.now })
        return (sut, clock)
    }

    @Test("Ohne Start ist kein Timer aktiv")
    func withoutStart_noTimer() {
        let (sut, _) = makeSut()

        #expect(sut.remaining == nil)
        #expect(!sut.isActive)
        #expect(!sut.isPaused)
        #expect(!sut.isExpired)
        #expect(sut.remainingText == nil)
    }

    @Test("Start setzt die Restzeit; sie laeuft mit der Uhr herunter")
    func start_remainingCountsDown() {
        let (sut, clock) = makeSut()

        sut.start(duration: 600)
        #expect(sut.remaining == 600)
        #expect(sut.isActive)
        #expect(sut.remainingText == "10:00")

        clock.advance(90)
        #expect(sut.remaining == 510)
        #expect(sut.remainingText == "8:30")
    }

    @Test("Restzeit klemmt bei null und meldet Ablauf")
    func remaining_clampsAtZero() {
        let (sut, clock) = makeSut()

        sut.start(duration: 60)
        clock.advance(200)

        #expect(sut.remaining == 0)
        #expect(sut.isExpired)
        #expect(sut.remainingText == "0:00")
    }

    @Test("Pause friert die Restzeit ein, Fortsetzen laeuft von dort weiter")
    func pause_andResume() {
        let (sut, clock) = makeSut()

        sut.start(duration: 300)
        clock.advance(120)
        sut.pause()

        #expect(sut.isPaused)
        #expect(sut.remaining == 180)

        // Waehrend der Pause vergeht keine Zeit.
        clock.advance(500)
        #expect(sut.remaining == 180)

        sut.resume()
        #expect(!sut.isPaused)
        #expect(sut.remaining == 180)
        clock.advance(60)
        #expect(sut.remaining == 120)
    }

    @Test("Verlaengern addiert im laufenden und im pausierten Zustand")
    func extend_runningAndPaused() {
        let (sut, clock) = makeSut()

        sut.start(duration: 300)
        sut.extend(by: 60)
        #expect(sut.remaining == 360)

        clock.advance(60)
        sut.pause()
        sut.extend(by: 60)
        #expect(sut.remaining == 360)
    }

    @Test("Verlaengern nach Ablauf zaehlt ab jetzt")
    func extend_afterExpiry_countsFromNow() {
        let (sut, clock) = makeSut()

        sut.start(duration: 60)
        clock.advance(300)
        #expect(sut.remaining == 0)

        sut.extend(by: 60)
        #expect(sut.remaining == 60)
    }

    @Test("Verlaengern ohne laufenden Timer bleibt wirkungslos")
    func extend_withoutTimer_noEffect() {
        let (sut, _) = makeSut()

        sut.extend(by: 60)

        #expect(sut.remaining == nil)
        #expect(!sut.isActive)
    }

    @Test("Beenden raeumt beide Zustaende ab")
    func end_clearsBothStates() {
        let (sut, clock) = makeSut()

        sut.start(duration: 300)
        clock.advance(30)
        sut.pause()
        sut.end()

        #expect(sut.remaining == nil)
        #expect(!sut.isActive)
        #expect(!sut.isPaused)
        #expect(sut.endDate == nil)
        #expect(sut.pausedRemaining == nil)
    }

    @Test("Neustart ersetzt einen pausierten Countdown")
    func restart_replacesPause() {
        let (sut, _) = makeSut()

        sut.start(duration: 300)
        sut.pause()
        sut.start(duration: 900)

        #expect(!sut.isPaused)
        #expect(sut.remaining == 900)
    }
}
