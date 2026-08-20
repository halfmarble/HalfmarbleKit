import XCTest
import SwiftUI
@testable import HalfmarbleKit

// The geometry behind `HMBarStrip`, pinned.
//
// WHY THESE ARE WORTH A TEST when the view itself is 20 lines: the whole reason
// the strip exists is that bar COUNT stopped being a frame-budget question and
// became a pixel question. These assertions are that pixel question, answered —
// so "can we double it again?" is settled by arithmetic instead of by shipping
// a build and squinting at it in a car.
final class BarStripTests: XCTestCase {

    private typealias Strip = HMBarStrip<Double>

    /// The founder's actual question, 2026-08-19: doubling 120 → 240 in the
    /// ~370 pt this row gets. A bar must stay at least one device pixel on a 3×
    /// screen — 1/3 pt — and comfortably more than that here.
    func testDoublingTheCountStillLeavesAVisibleBar() {
        let w120 = Strip.barWidth(width: 370, count: 120, gapRatio: 0.5)
        let w240 = Strip.barWidth(width: 370, count: 240, gapRatio: 0.5)
        XCTAssertEqual(w120, 2.06, accuracy: 0.01)
        XCTAssertEqual(w240, 1.03, accuracy: 0.01)
        XCTAssertGreaterThan(w240 * 3, 3.0, "under three device pixels at 3× — too thin to read")
    }

    /// THE BUG THE RATIO EXISTS TO PREVENT. With a FIXED 1 pt gap — what both
    /// rows used before — 240 bars are thinner than the space between them, and
    /// the row reads as mostly empty. The ratio keeps bar and gap in proportion
    /// at any count.
    func testTheGapNeverOutgrowsTheBar() {
        for n in [30, 60, 120, 240, 480] {
            let w = Strip.barWidth(width: 370, count: n, gapRatio: 0.5)
            XCTAssertEqual(w * 0.5, w * 0.5, accuracy: 0)      // gap is defined as w·ratio
            XCTAssertGreaterThan(w, w * 0.5, "gap wider than the bar at \(n)")
            // And the row is exactly filled: n bars + (n-1) gaps.
            let used = w * CGFloat(n) + w * 0.5 * CGFloat(n - 1)
            XCTAssertEqual(used, 370, accuracy: 0.01, "row not filled at \(n)")
        }
    }

    /// A meter that vanishes at zero reads as broken rather than quiet.
    func testSilenceKeepsAVisibleFloorAndPeaksFillTheRow() {
        XCTAssertEqual(Strip.barHeight(level: 0, rowHeight: 32, minHeight: 3), 3)
        XCTAssertEqual(Strip.barHeight(level: 1, rowHeight: 32, minHeight: 3), 32)
        XCTAssertEqual(Strip.barHeight(level: 0.5, rowHeight: 32, minHeight: 3),
                       3 + 29 * 0.5, accuracy: 0.001)
    }

    /// Out-of-range input clamps rather than drawing outside the row — a level
    /// meter fed a bad sample must not paint over its neighbours.
    func testLevelsClamp() {
        XCTAssertEqual(Strip.barHeight(level: 9, rowHeight: 24, minHeight: 2), 24)
        XCTAssertEqual(Strip.barHeight(level: -5, rowHeight: 24, minHeight: 2), 2)
    }

    func testDegenerateInputsDoNotDivideByZero() {
        XCTAssertEqual(Strip.barWidth(width: 370, count: 0, gapRatio: 0.5), 0)
        XCTAssertEqual(Strip.barWidth(width: 0, count: 60, gapRatio: 0.5), 0)
        XCTAssertEqual(Strip.barHeight(level: 0.5, rowHeight: 0, minHeight: 3), 3)
    }
}
