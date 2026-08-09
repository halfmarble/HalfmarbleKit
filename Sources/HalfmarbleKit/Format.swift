import Foundation

//  Number formatting for display, one implementation (2026-08-09) — extracted
//  from StringFusor's Copy.swift, whose formatter was already named
//  `hmGroupedFormatter` in anticipation of exactly this move, and from the two
//  NumberFormatters ViroFlick built inline in its share path.
//
//  THE LOCALE PIN IS WHY THIS IS SHARED RATHER THAN COPIED. Both games speak
//  single-voice English in every other string they show, so a device locale
//  that groups with "." renders "12.480" inside an otherwise-English sentence.
//  Worse, the two copies disagreed: StringFusor pinned en_US, ViroFlick left
//  the formatter on the device locale, so the same score read differently in
//  the two games on the same phone. Pinning here makes the house rule — scores
//  read XXX,XXX (gerard, 2026-07-26) — true in both, on every device.
//
//  If a halfmarble app is ever localized, this is the deliberate seam to
//  revisit: the pin is a copy decision, not a formatting accident, so it should
//  be lifted together with the strings rather than quietly per call site.
//
//  The formatter is a cached `static let` because NumberFormatter is expensive
//  to construct and safe to reuse for formatting; ViroFlick was building two of
//  them on every share tap.

extension Int {
    /// This number grouped for display — `12480` reads `12,480`.
    ///
    /// Always comma-grouped, regardless of device locale (see the file note).
    public var grouped: String {
        Int.hmGroupedFormatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }

    private static let hmGroupedFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        return f
    }()
}
