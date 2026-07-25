import SwiftUI

//  The black outline for SWIFTUI labels (2026-07-25) — the SwiftUI face of the
//  house treatment Outline.swift gives UIKit text and icons: the playfields
//  are busy (a lit cosmic sky, a drifting microscope field), and flat glyphs
//  disappear into the bright patches. Same technique as UIImage.outlined —
//  a silhouette stamped at 8 offsets around a ring, then the real content on
//  top. 8 points is the fewest that reads as a continuous edge rather than a
//  plus/cross shape.
//
//  Deliberately NOT .shadow: that gives a soft halo rather than a crisp edge.
//
//  The silhouettes are the content itself through .colorMultiply(.black), so
//  the outline's OPACITY follows the label's own — a dim 40% label gets a dim
//  outline, never a heavy black ring around faint text.

private struct HMOutlineModifier: ViewModifier {
    let width: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    ForEach(0..<8, id: \.self) { i in
                        let a = CGFloat(i) * .pi / 4
                        content
                            .colorMultiply(.black)
                            .offset(x: cos(a) * width, y: sin(a) * width)
                    }
                }
            }
    }
}

public extension View {
    /// The house black outline — apply to any label that floats over live
    /// art (HUD lines, overlays, landing text). Skip labels on opaque sheets;
    /// chrome earns its legibility where the background fights it.
    func hmOutlined(_ width: CGFloat = 1.2) -> some View {
        modifier(HMOutlineModifier(width: width))
    }
}
