//
//  Support.swift
//  PresentationUIKit
//
//  Interne Helfer: Lokalisierung aus dem Paket-Bundle, HTML-Bereinigung fuer
//  Titel/Beschreibungen sowie QuickLook- und Safari-Huellen fuer die
//  Medien-Elemente.
//

import Foundation
import QuickLook
import SafariServices
import SwiftUI
import UIKit

/// Aufloesung eines UI-Strings aus dem Paket-Katalog (`Localizable.xcstrings`,
/// Basissprache Deutsch). SwiftUI-Literale wuerden sonst im Main-Bundle der
/// App suchen und nie uebersetzt.
nonisolated func localized(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}

// MARK: - HTML-Bereinigung

/// Einmalig uebersetztes Tag-Muster — `strippingHTMLTags` steckt in Titeln,
/// die pro Durchlauf mehrfach ausgewertet werden.
private nonisolated let htmlTagPattern = try? NSRegularExpression(pattern: "<[^>]+>")

nonisolated extension String {
    /// Entfernt HTML-Tags und liefert den reinen Textinhalt — Agenda-Titel
    /// und -Beschreibungen koennen rohes HTML enthalten.
    var strippingHTMLTags: String {
        // Schnellweg: Ohne '<' im Text ist nichts zu ersetzen.
        guard self.contains("<"), let pattern = htmlTagPattern else {
            return self.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let stripped = pattern.stringByReplacingMatches(
            in: self,
            range: NSRange(self.startIndex..., in: self),
            withTemplate: ""
        )
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Medien-Praesentation

/// Identifizierbares, aufgeloestes Medium fuer `.sheet(item:)`.
struct PresentedMedium: Identifiable {
    enum Kind { case web, attachment }
    let id = UUID()
    let url: URL
    let kind: Kind
}

/// Safari-View im Sheet — die Praesentation bleibt im Hintergrund bestehen
/// (kein App-Wechsel mitten in der Sitzung).
struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// `QLPreviewController`-Wrapper: zeigt eine einzelne Datei (temporaere
/// lokale URL) in der System-Vorschau.
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

/// Navigierbare Huelle, um `QuickLookPreview` per `.sheet(item:)` zu praesentieren.
struct QuickLookSheet: View {
    @Environment(\.dismiss) var dismiss
    let url: URL
    let title: String

    var body: some View {
        NavigationStack {
            QuickLookPreview(url: url)
                .edgesIgnoringSafeArea(.all)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(localized("Fertig")) { dismiss() }
                    }
                    ToolbarItem {
                        ShareLink(item: url)
                    }
                }
        }
    }
}
