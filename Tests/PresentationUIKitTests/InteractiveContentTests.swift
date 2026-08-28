//
//  InteractiveContentTests.swift
//  PresentationUIKitTests
//
//  Interaktive Elemente im ViewModel: Timer-Start, Aufdeck-Zustand,
//  Quiz-Zustand und -Inhalt sowie die Medien-Aufloesung ueber den
//  injizierten Resolver.
//

import Testing
import CoreGraphics
import Foundation
@testable import PresentationCoreKit
@testable import PresentationUIKit

@Suite("Interaktive Elemente")
@MainActor
struct InteractiveContentTests {

    private func element(_ kind: String, data: [String: ElementValue] = [:]) -> InteractiveElement {
        InteractiveElement(kind: kind, data: data, frame: .zero)
    }

    private func viewModel(
        attachmentResolver: ((String) -> MediaTarget?)? = nil
    ) -> PresentationViewModel {
        PresentationViewModel(
            pages: [],
            store: TransientPresentationStore(),
            attachmentResolver: attachmentResolver,
            saveDelay: .zero
        )
    }

    @Test("Timer-Element startet den Arbeitsphasen-Countdown")
    func timerStart() {
        let vm = viewModel()
        #expect(!vm.sessionTimer.isActive)
        vm.startTimer(minutes: 5)
        #expect(vm.sessionTimer.isActive)
    }

    @Test("Aufdeck-Zustand ist Session-fluechtig und je Element")
    func reveal() {
        let vm = viewModel()
        let a = element(InteractiveElement.Kind.reveal)
        let b = element(InteractiveElement.Kind.reveal)

        #expect(!vm.isRevealed(a))
        vm.reveal(a)
        #expect(vm.isRevealed(a))
        #expect(!vm.isRevealed(b))
    }

    @Test("Quiz-Zustand: oeffnen, waehlen, aufloesen, schliessen")
    func quizState() {
        let vm = viewModel()
        let quiz = element(InteractiveElement.Kind.quiz, data: [
            "frage": .string("Wie viele Bit hat ein Byte?"),
            "antworten": .array([.string("4"), .string("8")]),
            "richtig": .int(2),
        ])

        vm.openQuiz(quiz)
        #expect(vm.activeQuiz?.id == quiz.id)

        vm.selectQuizAnswer(1)
        #expect(vm.quizSelection == 1)

        vm.resolveQuiz()
        #expect(vm.isQuizResolved)
        // Nach dem Aufloesen ist die Wahl eingefroren.
        vm.selectQuizAnswer(0)
        #expect(vm.quizSelection == 1)

        vm.closeQuiz()
        #expect(vm.activeQuiz == nil)
        #expect(vm.quizSelection == nil)
        #expect(!vm.isQuizResolved)
    }

    @Test("QuizContent: 1-basierte richtig-Angabe wird 0-basiert, Unsinn wird nil")
    func quizContent() {
        let valid = QuizContent(element: element(InteractiveElement.Kind.quiz, data: [
            "frage": .string("F?"),
            "antworten": .array([.string("A"), .string("B"), .string("C")]),
            "richtig": .int(2),
        ]))
        #expect(valid?.correct == 1)
        #expect(valid?.answers.count == 3)

        // richtig ausserhalb des Bereichs → keine Markierung, Quiz bleibt nutzbar
        let outOfRange = QuizContent(element: element(InteractiveElement.Kind.quiz, data: [
            "frage": .string("F?"),
            "antworten": .array([.string("A")]),
            "richtig": .int(9),
        ]))
        #expect(outOfRange?.correct == nil)

        // Ohne Antworten → kein Quiz
        #expect(QuizContent(element: element(InteractiveElement.Kind.quiz,
                                             data: ["frage": .string("F?")])) == nil)
    }

    @Test("Medium: URL-Referenz wird aufgeloest, Anhang laeuft ueber den Resolver")
    func media() {
        var requestedFilename: String?
        let vm = viewModel(attachmentResolver: { filename in
            requestedFilename = filename
            guard filename == "skript.py" else { return nil }
            return .attachment(data: Data([1]), filename: filename)
        })

        let url = vm.mediaTarget(
            for: element(InteractiveElement.Kind.media, data: ["url": .string("https://example.org/x")])
        )
        switch url {
        case .some(.url(let target)):
            #expect(target.absoluteString == "https://example.org/x")
        default:
            Issue.record("URL-Referenz wurde nicht aufgelöst")
        }

        // Anhang: Treffer nach Dateiname ueber den Resolver.
        let found = vm.mediaTarget(
            for: element(InteractiveElement.Kind.media, data: ["anhang": .string("skript.py")])
        )
        switch found {
        case .some(.attachment(let data, let name)):
            #expect(data == Data([1]))
            #expect(name == "skript.py")
        default:
            Issue.record("Anhang-Referenz wurde nicht aufgelöst")
        }
        #expect(requestedFilename == "skript.py")

        // Ohne Referenz bzw. ohne Resolver-Treffer → nil.
        #expect(vm.mediaTarget(for: element(InteractiveElement.Kind.media)) == nil)
        #expect(vm.mediaTarget(
            for: element(InteractiveElement.Kind.media, data: ["anhang": .string("fehlt.pdf")])
        ) == nil)
    }
}
