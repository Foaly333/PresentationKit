//
//  CollapsedToolbarButton.swift
//  PresentationUIKit
//
//  Eingeklappte Steuerleiste: ein kleines, ueber der Seite schwebendes Symbol
//  analog zur minimierten PencilKit-Palette. Tipp klappt die Leiste wieder
//  auf; per Ziehen rastet das Symbol in einer der vier Ecken ein, damit es
//  keine Inhalte verdeckt.
//

import SwiftUI

/// Ecke, in der das eingeklappte Steuerleisten-Symbol einrastet.
enum ToolbarCorner: CaseIterable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    /// Mittelpunkt des Symbols in dieser Ecke; `inset` ist der Abstand des
    /// Mittelpunkts vom Rand.
    func center(in size: CGSize, inset: CGFloat) -> CGPoint {
        let isLeading = self == .topLeading || self == .bottomLeading
        let isTop = self == .topLeading || self == .topTrailing
        return CGPoint(x: isLeading ? inset : size.width - inset,
                       y: isTop ? inset : size.height - inset)
    }

    /// Ecke, deren Mittelpunkt dem Punkt am naechsten liegt.
    static func nearest(to point: CGPoint, in size: CGSize, inset: CGFloat) -> ToolbarCorner {
        func distance(_ corner: ToolbarCorner) -> CGFloat {
            let center = corner.center(in: size, inset: inset)
            return hypot(center.x - point.x, center.y - point.y)
        }
        return allCases.min { distance($0) < distance($1) } ?? .bottomTrailing
    }
}

struct CollapsedToolbarButton: View {

    let viewModel: PresentationViewModel
    @Binding var corner: ToolbarCorner
    let containerSize: CGSize
    let expand: () -> Void

    @State private var dragOffset: CGSize = .zero

    private static let diameter: CGFloat = 56
    private static let inset: CGFloat = 44

    var body: some View {
        let center = corner.center(in: containerSize, inset: Self.inset)
        // Gesten vor `.position` anhaengen — danach fuellt die View den
        // ganzen Container und wuerde alle Eingaben auf der Seite schlucken.
        Image(systemName: viewModel.isLaserPointerActive
              ? "dot.circle.and.hand.point.up.left.fill" : "ellipsis")
            .font(.title2)
            .foregroundStyle(viewModel.isLaserPointerActive ? Color.red : .white)
            .frame(width: Self.diameter, height: Self.diameter)
            .background(.black.opacity(0.6), in: Circle())
            .contentShape(Circle())
            .onTapGesture(perform: expand)
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { dragOffset = $0.translation }
                    .onEnded { value in
                        let end = CGPoint(x: center.x + value.translation.width,
                                          y: center.y + value.translation.height)
                        withAnimation(.spring(duration: 0.3)) {
                            corner = .nearest(to: end, in: containerSize, inset: Self.inset)
                            dragOffset = .zero
                        }
                    }
            )
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(localized("Steuerleiste aufklappen")))
            .accessibilityAction { expand() }
            .accessibilityIdentifier("praesentation.steuerleiste.aufklappen")
            .position(x: center.x + dragOffset.width, y: center.y + dragOffset.height)
    }
}
