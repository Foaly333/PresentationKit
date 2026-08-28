// swift-tools-version: 6.2
//
//  PresentationKit — Vollbild-Praesentationsmodus fuer iOS-Apps.
//
//  Produkte:
//  - PresentationCoreKit: Seiten-/Store-Protokolle, Wertmodell der interaktiven
//    Elemente, Agenda-Fortschritt, Sitzungs-Timer, In-Memory-Store
//  - PresentationUIKit:   Praesentationsansicht (PencilKit-Canvas, Beamer-
//    Spiegelung, Laserpointer, Timer, Quiz/Aufdecken/Medien-Overlays,
//    Seitenraster), Konfiguration und Element-Registry
//
//  Eingang sind gerenderte Seiten (PDF-Seiten als Bilder) plus optionale
//  Positions-Marker — das Paket ist bewusst frei von Typst, SwiftData und
//  jeder App-Semantik. Entstanden aus dem MaterialOrganizer-Vorhaben
//  „PresentationKit" (2026-08); iOS-only wegen PencilKit/UIKit/UIScreen.
//

import PackageDescription

/// Gleiche Concurrency-Einstellungen wie in den konsumierenden App-Projekten:
/// Default Actor Isolation = MainActor + Approachable Concurrency.
let appIsolationSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "PresentationKit",
    defaultLocalization: "de",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(name: "PresentationCoreKit", targets: ["PresentationCoreKit"]),
        .library(name: "PresentationUIKit", targets: ["PresentationUIKit"]),
    ],
    targets: [
        .target(
            name: "PresentationCoreKit",
            path: "Sources/PresentationCoreKit",
            swiftSettings: appIsolationSettings
        ),
        .target(
            name: "PresentationUIKit",
            dependencies: ["PresentationCoreKit"],
            path: "Sources/PresentationUIKit",
            resources: [
                .process("Resources")
            ],
            swiftSettings: appIsolationSettings
        ),
        .testTarget(
            name: "PresentationCoreKitTests",
            dependencies: ["PresentationCoreKit"],
            path: "Tests/PresentationCoreKitTests",
            swiftSettings: appIsolationSettings
        ),
        // ViewModel- und Inhalts-Tests (Quiz, Timer, Medien) — das ViewModel
        // lebt im UI-Target, weil es PencilKit/UIKit braucht.
        .testTarget(
            name: "PresentationUIKitTests",
            dependencies: ["PresentationUIKit"],
            path: "Tests/PresentationUIKitTests",
            swiftSettings: appIsolationSettings
        ),
    ]
)
