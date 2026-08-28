//
//  ElementValue.swift
//  PresentationCoreKit
//
//  JSON-Wertmodell der interaktiven Elemente. Codiert untagged
//  (`singleValueContainer`) — dadurch byte-kompatibel zu bestehenden Blobs,
//  die mit gleichartig codierten Typen (etwa `MoJSONWert` aus TypstKit)
//  geschrieben wurden. Die Decode-Reihenfolge (Bool vor Int vor Double vor
//  String) ist Teil dieses Kontrakts und darf nicht umgestellt werden.
//

import CoreGraphics
import Foundation

/// Ein JSON-faehiger Payload-Wert eines interaktiven Elements.
public nonisolated enum ElementValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([ElementValue])
    case object([String: ElementValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([ElementValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: ElementValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Kein JSON-fähiger Wert"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }

    // Bequeme Zugriffe fuer typische Payload-Felder.

    /// String-Wert, falls `.string`.
    public var stringValue: String? {
        if case .string(let s) = self { return s } else { return nil }
    }

    /// Int-Wert; `.double` wird verlustfrei konvertiert, falls moeglich.
    public var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d) where d == d.rounded(): return Int(d)
        default: return nil
        }
    }

    /// Double-Wert, falls `.double` oder `.int`.
    public var doubleValue: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }

    /// Bool-Wert, falls `.bool`.
    public var boolValue: Bool? {
        if case .bool(let b) = self { return b } else { return nil }
    }

    /// Listen-Wert, falls `.array`.
    public var arrayValue: [ElementValue]? {
        if case .array(let a) = self { return a } else { return nil }
    }

    /// Objekt-Wert, falls `.object`.
    public var objectValue: [String: ElementValue]? {
        if case .object(let o) = self { return o } else { return nil }
    }
}

// MARK: - Positions-Marker

/// Neutraler Positions-Marker einer Seite — die Eingangsform der interaktiven
/// Elemente. Die konsumierende App destilliert ihn aus ihrer Dokumentquelle
/// (z. B. dem Rueckkanal eines Typst-Kompilierlaufs).
public nonisolated struct PageElementMarker: Sendable, Equatable {
    /// 0-basierter Seitenindex im Dokument.
    public let page: Int
    /// Elementtyp (z. B. "timer", "quiz"); unbekannte Typen werden ignoriert,
    /// sofern keine eigene Darstellung registriert ist.
    public let kind: String
    /// Ankerpunkt in pt, Ursprung oben links der Seite.
    public let anchor: CGPoint
    /// JSON-Payload des Markers.
    public let data: [String: ElementValue]

    public init(page: Int, kind: String, anchor: CGPoint, data: [String: ElementValue]) {
        self.page = page
        self.kind = kind
        self.anchor = anchor
        self.data = data
    }
}
