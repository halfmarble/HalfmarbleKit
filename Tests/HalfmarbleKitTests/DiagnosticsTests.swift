// Contracts for the diagnostics trio moved in 2026-08-14: Footprint,
// ConsoleLog, SessionLog.
//
// Each assertion below corresponds to something that actually went wrong in
// the app these came from. They are in the KIT because the next app will make
// the same mistakes for the same reasons — and because two of them are the
// kind of bug that is invisible until the day you need the data and it is not
// there.
import XCTest
import SwiftUI
@testable import HalfmarbleKit

final class DiagnosticsTests: XCTestCase {

    // MARK: - SessionLog: the rotation that ate a day

    /// THE BUG THIS PINS. Rotation used to move `live` onto `previous` and
    /// overwrite it, so exactly two sessions ever existed no matter how many
    /// times the app ran. A day of launches left one usable log.
    ///
    /// `archiveNames` is the selector that decides what gets DELETED, so the
    /// first thing it must do is never name the two live slots.
    func testArchiveSelectionNeverIncludesTheLiveOrPreviousSlots() {
        let files = ["dash-live.csv", "dash-previous.csv",
                     "dash-1000.csv", "dash-1001.csv", "other-1002.csv",
                     "dash-notes.txt"]
        let picked = SessionLog.archiveNames(in: files, stem: "dash")
        XCTAssertEqual(picked, ["dash-1000.csv", "dash-1001.csv"])
        XCTAssertFalse(picked.contains("dash-live.csv"),
                       "the session being written was selected for deletion")
        XCTAssertFalse(picked.contains("dash-previous.csv"))
        XCTAssertFalse(picked.contains("other-1002.csv"),
                       "another app's logs are not ours to prune")
    }

    /// Archives sort oldest-first, because pruning takes from the FRONT. If
    /// this ever sorted the other way it would delete the newest sessions and
    /// keep the ancient ones — the same lost-data outcome, harder to spot.
    func testArchivesSortOldestFirst() {
        let names = SessionLog.archiveNames(
            in: ["s-1755200000.csv", "s-1755100000.csv", "s-1755300000.csv"], stem: "s")
        XCTAssertEqual(names.first, "s-1755100000.csv")
        XCTAssertEqual(names.last, "s-1755300000.csv")
    }

    /// NOTHING IS DELETED (founder 2026-08-24: "stop rotating and loosing old
    /// logs, keep them all"). Twelve was already the second answer to this —
    /// the first kept two — and both are the same mistake at different sizes.
    func testNoSessionIsEverPruned() {
        XCTAssertEqual(SessionLog.keepSessions, Int.max,
                       "a cap is back; a drive log is the measurement instrument")
        // The selector still works, it simply never has anything to hand over.
        let many = (1...500).map { "dash-2026-08-24-\(String(format: "%06d", $0)).csv" }
        XCTAssertGreaterThan(SessionLog.archiveNames(in: many, stem: "dash").count,
                             12, "the selector stopped seeing archives at all")
    }

    /// A NAME THAT READS AS A DATE AND SORTS AS A CLOCK (founder 2026-08-24:
    /// "use dates and time in their names, so you can corelate them to when the
    /// log was written"). Both halves matter: `archiveNames` sorts these as
    /// plain text, so a format that reads well but sorts wrong would order the
    /// archives by nothing in particular.
    func testTheStampIsReadableAndSortsOldestFirst() {
        let t0 = Date(timeIntervalSince1970: 1_787_000_000)
        let a = SessionLog.stamp(t0)
        let b = SessionLog.stamp(t0.addingTimeInterval(3600))
        let c = SessionLog.stamp(t0.addingTimeInterval(86_400 * 40))
        XCTAssertEqual(a.count, "yyyy-MM-dd-HHmmss".count, "unexpected shape: \(a)")
        XCTAssertTrue(a.hasPrefix("20"), "not a readable year: \(a)")
        XCTAssertLessThan(a, b, "an hour later must sort later: \(a) vs \(b)")
        XCTAssertLessThan(b, c, "a month later must sort later: \(b) vs \(c)")
        // ...and it survives the selector's sort, which is what depends on it.
        let names = SessionLog.archiveNames(
            in: ["s-\(c).csv", "s-\(a).csv", "s-\(b).csv"], stem: "s")
        XCTAssertEqual(names, ["s-\(a).csv", "s-\(b).csv", "s-\(c).csv"])
    }

    // MARK: - SessionLog: one row is one line

    /// Every consumer of this file is a line-oriented parser. A detail with a
    /// newline in it — a captured multi-line reply, a stack trace — must not
    /// break one event into two rows.
    func testARowSurvivesNewlinesAndQuotes() {
        let e = LogEvent(t: Date(), kind: "reply",
                         detail: "line one\nline two and a \"quote\"")
        let row = SessionLog.row(e, since: nil)
        XCTAssertEqual(row.components(separatedBy: "\n").count, 1,
                       "a multi-line detail split the CSV row")
        XCTAssertFalse(row.contains("\"quote\""),
                       "an unescaped quote closes the CSV field early")
        XCTAssertTrue(row.hasSuffix("\""), "the detail field is not closed")
    }

    func testElapsedSecondsAreRelativeToTheSessionStart() {
        let t0 = Date()
        let e = LogEvent(t: t0.addingTimeInterval(65), kind: "user", detail: "x")
        XCTAssertTrue(SessionLog.row(e, since: t0).contains(",65,"),
                      SessionLog.row(e, since: t0))
    }

    /// The header is shared by the live file and the export so the two cannot
    /// disagree about format — they were written separately once.
    @MainActor
    func testTheExportAndTheLiveFileShareOneHeader() {
        let log = SessionLog(stem: "test")
        XCTAssertTrue(log.csv().hasPrefix(SessionLog.csvHeader))
    }

    /// Filenames are per-app, or two apps on one device fight over the slot
    /// and prune each other's history.
    @MainActor
    func testTheStemNamesTheFiles() {
        let log = SessionLog(stem: "myapp")
        XCTAssertEqual(log.liveURL?.lastPathComponent, "myapp-live.csv")
        XCTAssertEqual(log.previousURL?.lastPathComponent, "myapp-previous.csv")
    }

    // MARK: - ConsoleLog: line assembly

    /// Chunks arrive on arbitrary descriptor boundaries. Holding the tail until
    /// its newline is the difference between a readable log and one where every
    /// other entry starts mid-word.
    @MainActor
    func testAChunkSplitMidLineIsReassembled() {
        let log = ConsoleLog.shared
        log.clear()
        log.ingest("[a] hello wo")
        XCTAssertTrue(log.lines.isEmpty, "half a line was published as a line")
        log.ingest("rld\n[b] next\n")
        XCTAssertEqual(log.lines, ["[a] hello world", "[b] next"])
        log.clear()
    }

    // MARK: - ConsoleLog: colour is the app's business

    /// It shipped with one app's tags hardcoded. For any other app that colours
    /// nothing while looking like it should — worse than plain text, because it
    /// reads as broken.
    func testTintsAreConfigurableAndAlarmWordsWinRegardless() {
        let saved = ConsoleLog.tints
        defer { ConsoleLog.tints = saved }

        ConsoleLog.tints = [("[tool]", .green), ("[brain]", .orange)]
        XCTAssertEqual(ConsoleLog.tint("[tool] opened maps"), .green)
        XCTAssertEqual(ConsoleLog.tint("[brain] loaded"), .orange)
        XCTAssertEqual(ConsoleLog.tint("[misc] something"), .secondary)
        // An error is red whatever tag carries it.
        XCTAssertEqual(ConsoleLog.tint("[tool] ERROR could not open"), .red)
    }

    func testAnAppThatSetsNoTintsStillGetsReadableOutput() {
        let saved = ConsoleLog.tints
        defer { ConsoleLog.tints = saved }
        ConsoleLog.tints = []
        XCTAssertEqual(ConsoleLog.tint("[anything] x"), .secondary)
        XCTAssertEqual(ConsoleLog.tint("WARNING: hot"), .red)
    }

    // MARK: - Footprint

    /// It must not re-implement `PerfProbe`'s mach call. Two copies of the same
    /// measurement is what this package exists to prevent, and they would
    /// disagree under memory pressure — exactly when the number matters.
    func testFootprintAgreesWithPerfProbe() {
        guard let mb = Footprint.mb() else {
            return XCTFail("no footprint reading in a live process")
        }
        XCTAssertEqual(mb, PerfProbe.footprintMB())
        XCTAssertGreaterThan(mb, 0)
    }

    /// The kit must not know about MLX, Core ML or Metal. The app supplies the
    /// second allocator's numbers; the kit does the subtraction that makes them
    /// diagnostic.
    func testTheExtraAllocatorHookIsOptionalAndUsed() {
        let saved = Footprint.extra
        defer { Footprint.extra = saved }

        Footprint.extra = nil
        Footprint.log("no extra")          // must not trap

        Footprint.extra = { ("mlx", 2159, 2735) }
        Footprint.log("with extra")        // must not trap
        XCTAssertEqual(Footprint.extra?()?.name, "mlx")
    }
}
