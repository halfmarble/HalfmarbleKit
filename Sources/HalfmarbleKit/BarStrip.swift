import SwiftUI

// A row of bars drawn in ONE pass — the shared shape behind every scrolling
// meter in a halfmarble app.
//
// WHY IT EXISTS (DashTales, 2026-08-19). Two rows in the same screen had
// independently grown the same wrong shape: an `HStack` of N `Capsule` views
// fed by a timer. Every tick shifted the array, so all N diffed, laid out and
// re-rendered — 14 times a second, for as long as the app was on. Bar count
// was therefore a PER-FRAME COST, and "can we show twice as many?" was a
// question about frame budget instead of a question about pixels. One of those
// rows had already starved SwiftUI badly enough to black the screen.
//
// A `Canvas` draws all of them in one pass. The count stops mattering: 60 costs
// what 240 costs, and the only real limit becomes how thin a bar may get before
// it stops being visible. That is a question with an arithmetic answer — see
// `barWidth` — rather than a profiling session.
//
// DELIBERATELY DUMB. It knows nothing about audio, memory or heat: the caller
// supplies a height in 0…1 and a colour per element, and this draws them. That
// is what lets one view serve a microphone trace and a thermal-tinted memory
// trace without either one leaking into the other. It is also why the package's
// iOS 16 floor is not a problem — `Color.mix` is iOS 18, and it happens in the
// CALLER, where the deployment target is the app's.
public struct HMBarStrip<Element>: View {

    private let items: [Element]
    private let level: (Element) -> Double
    private let fill: (Element) -> Color
    private let minHeight: CGFloat
    private let gapRatio: CGFloat

    /// - Parameters:
    ///   - items: one element per bar, oldest → newest.
    ///   - minHeight: what a zero-level bar still occupies, in points. A meter
    ///     that vanishes at zero reads as "broken", not as "quiet", so silence
    ///     keeps a visible floor.
    ///   - gapRatio: the gap between bars as a fraction of a bar's own width.
    ///     A RATIO, not a constant, because a fixed 1 pt gap is invisible at 60
    ///     bars and wider than the bar itself at 240 — the fixed gap is exactly
    ///     what made doubling the count look broken.
    ///   - level: 0…1, the bar's share of the full height. Values outside are
    ///     clamped; feed 0 for a hole and give it a clear `fill`.
    ///   - fill: the bar's colour. Return `.clear` for "no sample here" — a gap
    ///     in the data must never be drawn as a low reading.
    public init(_ items: [Element],
                minHeight: CGFloat = 2,
                gapRatio: CGFloat = 0.5,
                level: @escaping (Element) -> Double,
                fill: @escaping (Element) -> Color) {
        self.items = items
        self.minHeight = minHeight
        self.gapRatio = gapRatio
        self.level = level
        self.fill = fill
    }

    /// How wide each bar gets. `width = n·w + (n−1)·w·gapRatio`, solved for w.
    ///
    /// This is the number that decides whether a bar count is sensible: at
    /// 370 pt and a 0.5 ratio, 120 bars are ~2.06 pt and 240 are ~1.03 pt —
    /// still three device pixels on a 3× screen. Pinned by a test so the answer
    /// to "can we double it again?" stays arithmetic.
    public static func barWidth(width: CGFloat, count: Int, gapRatio: CGFloat) -> CGFloat {
        guard count > 0, width > 0 else { return 0 }
        return width / (CGFloat(count) + CGFloat(count - 1) * gapRatio)
    }

    /// A bar's drawn height. Bars grow from the row's CENTRE line in both
    /// directions, which is what makes a level meter read as a waveform rather
    /// than a bar chart.
    public static func barHeight(level: Double, rowHeight: CGFloat,
                                 minHeight: CGFloat) -> CGFloat {
        let v = min(1, max(0, level))
        let span = max(0, rowHeight - minHeight)
        return minHeight + CGFloat(v) * span
    }

    public var body: some View {
        // rendersAsynchronously: false — this is fed by a timer that already
        // paces it, and async rendering would let frames land out of order.
        Canvas(rendersAsynchronously: false) { ctx, size in
            let n = items.count
            guard n > 0, size.width > 0, size.height > 0 else { return }
            let w = Self.barWidth(width: size.width, count: n, gapRatio: gapRatio)
            let step = w + w * gapRatio
            for i in 0..<n {
                let color = fill(items[i])
                let h = Self.barHeight(level: level(items[i]),
                                       rowHeight: size.height, minHeight: minHeight)
                let rect = CGRect(x: CGFloat(i) * step, y: (size.height - h) / 2,
                                  width: w, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: min(w, h) / 2),
                         with: .color(color))
            }
        }
    }
}
