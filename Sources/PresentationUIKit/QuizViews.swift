//
//  QuizViews.swift
//  PresentationUIKit
//
//  Quiz-Element im Praesentationsmodus. Das Geraet steuert (Antwort waehlen,
//  „Aufloesen", Schliessen), der Beamer liest — beide Scenes sehen denselben
//  Zustand im PresentationViewModel. Bewusst schlicht: Anzeige und Aufloesung,
//  keine Datenerfassung (Handzeichen statt Geraete-Voting).
//

import PresentationCoreKit
import SwiftUI

/// Inhalt eines Quiz-Elements, aus der Payload destilliert.
nonisolated struct QuizContent {
    let question: String
    let answers: [String]
    /// 0-basierter Index der richtigen Antwort.
    let correct: Int?

    init?(element: InteractiveElement) {
        guard element.kind == InteractiveElement.Kind.quiz,
              let question = element.data["frage"]?.stringValue
        else { return nil }
        let answers = (element.data["antworten"]?.arrayValue ?? [])
            .compactMap(\.stringValue)
        guard !answers.isEmpty else { return nil }
        self.question = question
        self.answers = answers
        // Payload ist 1-basiert (Marker-Kontrakt).
        if let oneBased = element.data["richtig"]?.intValue,
           (1...answers.count).contains(oneBased) {
            self.correct = oneBased - 1
        } else {
            self.correct = nil
        }
    }
}

/// Steuerndes Quiz-Overlay auf dem Geraet.
struct QuizOverlayView: View {
    let viewModel: PresentationViewModel

    var body: some View {
        if let element = viewModel.activeQuiz, let content = QuizContent(element: element) {
            VStack(spacing: 24) {
                Text(content.question)
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    ForEach(Array(content.answers.enumerated()), id: \.offset) { index, answer in
                        Button {
                            viewModel.selectQuizAnswer(index)
                        } label: {
                            HStack {
                                Text(verbatim: String(Character(UnicodeScalar(65 + index) ?? "A")))
                                    .font(.title3.weight(.bold))
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(.quaternary))
                                Text(answer)
                                    .font(.title3)
                                Spacer()
                                if let symbol = statusSymbol(index: index, content: content) {
                                    Image(systemName: symbol.name)
                                        .foregroundStyle(symbol.color)
                                        .font(.title3.weight(.semibold))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(background(index: index, content: content))
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("praesentation.quiz.antwort.\(index)")
                    }
                }

                HStack(spacing: 16) {
                    Button(localized("Schließen")) { viewModel.closeQuiz() }
                        .buttonStyle(.bordered)
                    if !viewModel.isQuizResolved {
                        Button(localized("Auflösen")) { viewModel.resolveQuiz() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("praesentation.quiz.aufloesen")
                    }
                }
                .controlSize(.large)
            }
            .padding(32)
            .frame(maxWidth: 640)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(radius: 24)
            )
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
    }

    private func background(index: Int, content: QuizContent) -> Color {
        if viewModel.isQuizResolved, index == content.correct { return .green.opacity(0.2) }
        if viewModel.quizSelection == index { return .blue.opacity(0.16) }
        return Color(uiColor: .secondarySystemBackground)
    }

    private func statusSymbol(index: Int, content: QuizContent) -> (name: String, color: Color)? {
        if viewModel.isQuizResolved {
            if index == content.correct { return ("checkmark.circle.fill", .green) }
            if viewModel.quizSelection == index { return ("xmark.circle.fill", .red) }
            return nil
        }
        if viewModel.quizSelection == index { return ("circle.inset.filled", .blue) }
        return nil
    }
}

/// Lesender Quiz-Zweig fuer den Beamer: gleiche Darstellung, keine Buttons.
struct QuizMirrorView: View {
    let viewModel: PresentationViewModel

    var body: some View {
        if let element = viewModel.activeQuiz, let content = QuizContent(element: element) {
            VStack(spacing: 28) {
                Text(content.question)
                    .font(.system(size: 44, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(content.answers.enumerated()), id: \.offset) { index, answer in
                        HStack(spacing: 14) {
                            Text(verbatim: String(Character(UnicodeScalar(65 + index) ?? "A")))
                                .font(.title.weight(.bold))
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(.white.opacity(0.2)))
                            Text(answer)
                                .font(.title)
                            if viewModel.isQuizResolved, index == content.correct {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                        }
                        .foregroundStyle(
                            viewModel.isQuizResolved && index != content.correct
                                ? .white.opacity(0.45)
                                : .white
                        )
                    }
                }
            }
            .padding(48)
            .frame(maxWidth: 900)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.black.opacity(0.82))
            )
        }
    }
}
