//
//  ExternalDisplayController.swift
//  PresentationUIKit
//
//  Anbindung des externen Displays (Beamer). Externe Bildschirme verbinden
//  sich seit iOS 13 als eigene `UIWindowScene` mit der Rolle
//  `.windowExternalDisplayNonInteractive`; das System erzeugt die Scene
//  automatisch. Dieser Controller haengt ein `UIWindow` mit der Spiegelansicht
//  (`PresentationMirrorView`) hinein – auch wenn der Beamer erst waehrend der
//  laufenden Praesentation angeschlossen wird. Ohne externes Display passiert
//  nichts (Fallback: Vollbild auf dem Geraet, siehe `PresentationView`).
//

import UIKit
import SwiftUI

final class ExternalDisplayController {

    private var window: UIWindow?
    private var viewModel: PresentationViewModel?
    private var observers: [NSObjectProtocol] = []

    /// Startet die Spiegelung: verbindet ein bereits vorhandenes externes Display
    /// sofort und beobachtet spaeteres An-/Abstecken.
    func start(viewModel: PresentationViewModel) {
        self.viewModel = viewModel
        connectExternalSceneIfPresent()

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIScene.didActivateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Notification-Callbacks sind nonisolated – zurueck auf den MainActor.
            Task { @MainActor in self?.connectExternalSceneIfPresent() }
        })
        observers.append(center.addObserver(
            forName: UIScene.didDisconnectNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let scene = notification.object as? UIWindowScene
            Task { @MainActor in self?.disconnectIfDetached(scene: scene) }
        })
    }

    /// Beendet die Spiegelung und gibt das Fenster frei.
    func end() {
        for entry in observers {
            NotificationCenter.default.removeObserver(entry)
        }
        observers.removeAll()
        window?.isHidden = true
        window = nil
        viewModel?.reportExternalDisplay(connected: false)
        viewModel = nil
    }

    // MARK: - Intern

    private func connectExternalSceneIfPresent() {
        guard window == nil, let viewModel else { return }
        guard let scene = Self.externalScene() else { return }

        let newWindow = UIWindow(windowScene: scene)
        newWindow.rootViewController = UIHostingController(
            rootView: PresentationMirrorView(viewModel: viewModel)
        )
        newWindow.isHidden = false
        window = newWindow
        // Erst jetzt sind Freeze und Blackout sinnvoll – die Steuerleiste
        // blendet ihre Bedienelemente an diesem Flag ein.
        viewModel.reportExternalDisplay(connected: true)
    }

    private func disconnectIfDetached(scene: UIWindowScene?) {
        guard let scene, window?.windowScene === scene else { return }
        window?.isHidden = true
        window = nil
        // Setzt im ViewModel auch Freeze und Blackout zurueck.
        viewModel?.reportExternalDisplay(connected: false)
    }

    /// Sucht eine verbundene externe (nicht-interaktive) Window-Scene.
    private static func externalScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.session.role == .windowExternalDisplayNonInteractive }
    }
}
