//
//  PresentationConfiguration.swift
//  PresentationUIKit
//
//  Werkzeug-Konfiguration des Praesentationsmodus: jede konsumierende App
//  schaltet die Bausteine einzeln (Meeting-App ohne Quiz, Taktikboard nur mit
//  Stift). Dazu die Element-Registry: eigene Marker-Typen bekommen hier ihre
//  Darstellung — unbekannte Typen ohne Registrierung werden ignoriert.
//

import PresentationCoreKit
import SwiftUI

/// Schaltet die Werkzeuge und Overlays der `PresentationView`.
public struct PresentationConfiguration {

    /// Laserpointer-Werkzeug in der Steuerleiste.
    public var showsLaserPointer = true
    /// Arbeitsphasen-Timer (Steuerleiste + Overlays).
    public var showsTimer = true
    /// Whiteboard-Seiten einfuegen.
    public var allowsWhiteboardPages = true
    /// Bilder einfuegen (Langdruck-Menue, Drag & Drop, Bearbeitungs-Overlay).
    public var allowsImageInsertion = true
    /// Beamer-Menue (Freeze/Blackout) bei verbundenem externem Display.
    public var showsExternalDisplayControls = true
    /// Seitenraster-Overlay (Tipp auf die Seitenanzeige).
    public var showsPageGrid = true
    /// Soll-Chip und Agenda-Popover (nur wirksam, wenn die Sitzung eine
    /// Agenda-Eingabe traegt).
    public var showsAgenda = true

    /// Element-Registry: Darstellung fuer eigene Marker-Typen, Schluessel ist
    /// `InteractiveElement.kind`. Die View wird an der Element-Position im
    /// kanonischen Raum platziert. `AnyView` ist an dieser Registry-Grenze
    /// bewusst in Kauf genommen — heterogene, zur Laufzeit registrierte
    /// Darstellungen lassen sich nicht generisch typisieren.
    public var customElementRenderers: [String: (InteractiveElement) -> AnyView] = [:]

    /// Alle zugelassenen Elementtypen: die eingebauten plus die registrierten.
    /// Beim Destillieren der Elemente (`InteractiveElement.elements(from:…)`)
    /// als `kinds` uebergeben, damit eigene Typen die Seiten erreichen.
    public var elementKinds: Set<String> {
        InteractiveElement.Kind.builtIn.union(customElementRenderers.keys)
    }

    public init() {}
}
