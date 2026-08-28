//
//  TimerViews.swift
//  PresentationUIKit
//
//  Gross sichtbarer Countdown der Arbeitsphase (Beamer bzw. Geraete-Vollbild)
//  und das Bedien-Popover der Steuerleiste. Farbwechsel in den letzten 30 s
//  (orange) und 10 s (rot), bei null kurzes Pulsieren, dann Ausblenden.
//  Kein Signalton.
//

import PresentationCoreKit
import SwiftUI

/// Wrapper, der die Restzeit sekuendlich abfragt, ohne selbst State zu mutieren
/// (`TimelineView` statt tickendem `Timer`).
struct SessionTimerOverlay: View {

    let timer: SessionTimer

    /// Wie lange der abgelaufene Timer noch pulsierend stehen bleibt.
    private static let lingerDuration: TimeInterval = 5

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let remaining = timer.remaining, isVisible(now: context.date) {
                TimerOverlayView(remaining: remaining, isPaused: timer.isPaused)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: timer.isActive)
    }

    /// Nach Ablauf bleibt der Countdown kurz pulsierend stehen und blendet dann aus.
    private func isVisible(now: Date) -> Bool {
        guard let end = timer.endDate else { return true }  // laufend oder pausiert
        return now.timeIntervalSince(end) < Self.lingerDuration
    }
}

struct TimerOverlayView: View {

    let remaining: TimeInterval
    let isPaused: Bool

    @State private var isPulsing = false

    private var seconds: Int { Int(remaining.rounded(.up)) }

    private var color: Color {
        if seconds <= 10 { return .red }
        if seconds <= 30 { return .orange }
        return .white
    }

    private var text: String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        HStack(spacing: 10) {
            if isPaused {
                Image(systemName: "pause.fill")
                    .font(.system(size: 28, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 36)
        .padding(.vertical, 18)
        .background(.black.opacity(0.72), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.6), lineWidth: 2))
        .scaleEffect(isPulsing ? 1.08 : 1)
        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isPulsing)
        .onChange(of: seconds == 0, initial: true) { _, expired in
            isPulsing = expired
        }
        .accessibilityIdentifier("praesentation.timer.overlay")
        .accessibilityLabel(Text(localized("Verbleibende Zeit \(text)")))
    }
}

/// Bedienung der Arbeitsphasen-Uhr aus der Steuerleiste. Ohne laufenden
/// Timer: Presets 5/10/15 min plus Stepper (Start in zwei Tipps). Mit laufendem
/// Timer: Pause/Fortsetzen, +1 min, Beenden.
struct TimerPopoverView: View {

    let timer: SessionTimer
    let close: () -> Void

    /// Frei gewaehlte Dauer in Minuten (Stepper).
    @State private var minutes: Int = 10

    private static let presets = [5, 10, 15]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localized("Arbeitsphase"))
                .font(.headline)

            if timer.isActive {
                runningControls
            } else {
                startControls
            }
        }
        .padding(20)
        .frame(minWidth: 260)
    }

    // MARK: - Start

    private var startControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ForEach(Self.presets, id: \.self) { value in
                    Button(localized("\(value) min")) {
                        start(minutes: value)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("praesentation.timer.preset.\(value)")
                }
            }

            Stepper(value: $minutes, in: 1...120) {
                Text(localized("\(minutes) min"))
                    .monospacedDigit()
            }
            .accessibilityIdentifier("praesentation.timer.stepper")

            Button {
                start(minutes: minutes)
            } label: {
                Label(localized("Starten"), systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("praesentation.timer.starten")
        }
    }

    // MARK: - Laufend

    private var runningControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(timer.remainingText ?? "–")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            HStack(spacing: 12) {
                Button {
                    if timer.isPaused { timer.resume() } else { timer.pause() }
                } label: {
                    Label(timer.isPaused ? localized("Fortsetzen") : localized("Pause"),
                          systemImage: timer.isPaused ? "play.fill" : "pause.fill")
                }
                .accessibilityIdentifier("praesentation.timer.pause")

                Button {
                    timer.extend(by: 60)
                } label: {
                    Label(localized("+1 min"), systemImage: "plus")
                }
                .accessibilityIdentifier("praesentation.timer.plusEins")
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                timer.end()
                close()
            } label: {
                Label(localized("Beenden"), systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("praesentation.timer.beenden")
        }
    }

    private func start(minutes value: Int) {
        timer.start(duration: TimeInterval(value * 60))
        close()
    }
}
