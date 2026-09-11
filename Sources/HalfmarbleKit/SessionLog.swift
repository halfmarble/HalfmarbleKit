// A timestamped event log that survives the app being killed.
//
// Moved here 2026-08-14 from an app whose whole evaluation depended on these
// files, and which lost a day of them twice, in two different ways.
//
// ────────────────────────────────────────────────────────────────────────────
// TWO PROMISES THAT SOUND LIKE ONE, AND ARE NOT
//
// 1. SURVIVES A CRASH. Events used to live in a `@Published` array and reach
//    disk only when somebody tapped Export. That is fine for a session that
//    ends politely and worthless for one that does not: the app was jetsammed
//    and the entire session went with it, which is how a day of testing
//    produced no file at all.
//
//    So: every event appends to a file immediately, and `synchronizeFile()`
//    runs on each write, because SIGKILL does not flush anything for you. The
//    tail of the session is otherwise in a buffer the kernel discards.
//
// 2. SURVIVES A RELAUNCH — which the first fix did NOT deliver, and nobody
//    noticed for a day. Rotation moved `live` to `previous` and overwrote what
//    was there, so exactly two sessions ever existed. The write-through worked
//    perfectly; the ROTATION threw the results away. After a day of launches
//    the only surviving logs were a short evening session and a four-line stub.
//
//    So: rotation ARCHIVES to a timestamped name and keeps `keepSessions` of
//    them. A test day is a dozen launches, not two.
//
// The generalisable lesson, which is why this is in the kit rather than fixed
// twice: "it is written to disk" is not the same claim as "it is still there
// tomorrow", and a log that quietly holds only the last two runs looks
// identical to one that holds everything until the day you need the third.
//
// Documents rather than tmp because tmp is evictable, and because Finder file
// sharing and the share sheet can both reach Documents.
// ────────────────────────────────────────────────────────────────────────────
import Foundation
import SwiftUI

public struct LogEvent: Identifiable, Equatable {
    public let id = UUID()
    public let t: Date
    /// Free-form and app-defined — `start`, `user`, `flag:*`, `stop`. Kinds are
    /// the analysis axis afterwards, so treat them as a stable vocabulary:
    /// renaming one orphans every log already collected.
    public let kind: String
    public let detail: String

    public init(t: Date, kind: String, detail: String) {
        self.t = t; self.kind = kind; self.detail = detail
    }

    public static func == (a: LogEvent, b: LogEvent) -> Bool {
        a.id == b.id
    }
}

@MainActor
public final class SessionLog: ObservableObject {
    @Published public private(set) var events: [LogEvent] = []
    private var t0: Date?

    /// Filename stem for this app's logs — `<stem>-live.csv`,
    /// `<stem>-previous.csv`, `<stem>-<yyyy-MM-dd-HHmmss>.csv`. Set once at
    /// startup.
    /// Defaulted so a misconfigured app still logs somewhere findable rather
    /// than silently not at all.
    public let stem: String

    /// NOTHING IS DELETED (founder 2026-08-24: "stop rotating and loosing old
    /// logs, keep them all").
    ///
    /// This was 12, and 12 was already the SECOND answer to this problem — the
    /// first kept two. Both are the same mistake at different sizes: a drive
    /// log is the U1 measurement instrument, and the one that gets deleted is
    /// always the one somebody turns out to need. It cost real evidence the day
    /// the cap was removed: a spoken pre-flight rotated away the reply the
    /// founder was asking about, mid-diagnosis.
    ///
    /// The files are a few kilobytes of text. A year of daily driving is
    /// megabytes, against an app that ships 4.6 GB of model weights. There was
    /// never a storage argument.
    ///
    /// Kept as a symbol because `pruneArchives` and its tests still reference
    /// the idea, and because a future cap should have to reintroduce the
    /// mechanism deliberately rather than by changing a number.
    public static let keepSessions = Int.max

    /// A stamp that reads as a date and still sorts as a clock (founder
    /// 2026-08-24: "use dates and time in their names, so you can corelate them
    /// to when the log was written").
    ///
    /// `dashspike-1787514355.csv` is unreadable — nobody can tell which drive
    /// that was without converting it, and the whole reason to open an archive
    /// is that you remember roughly WHEN something happened.
    /// `dashspike-2026-08-24-110230.csv` says so, and zero-padded
    /// year-month-day-hhmmss still sorts oldest-first as plain text, which
    /// `archiveNames` depends on.
    ///
    /// LOCAL TIME, deliberately. The correlation being made is against a human
    /// memory of a drive, and that memory is in the driver's own timezone.
    public nonisolated static func stamp(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: date)
    }

    public init(stem: String = "session") {
        self.stem = stem
    }

    public var elapsed: TimeInterval { t0.map { Date().timeIntervalSince($0) } ?? 0 }

    /// Counts per `flag:*` kind — the one-tap failure markers.
    public var flagCounts: [String: Int] {
        events.filter { $0.kind.hasPrefix("flag:") }
            .reduce(into: [:]) { $0[$1.kind, default: 0] += 1 }
    }

    /// Begin a session. `header` is written as the `start` row's detail — put
    /// the run's configuration there, because a log you cannot attribute to a
    /// build is a log you cannot compare.
    public func start(_ header: String) {
        events.removeAll()
        t0 = Date()
        openLiveFile()
        add("start", header)
    }

    /// Record one event. **Safe to call from any thread.**
    ///
    /// This used to be main-actor isolated like the rest of the class, and a
    /// host app handed it to a synthesis engine's completion callback — a plain
    /// `(String) -> Void` slot, which Swift 5 lets a main-actor closure fill
    /// with nothing at runtime enforcing the promise. The engine invoked it on
    /// its own serial queue. Appending to a `@Published` array off the main
    /// thread takes Combine's publisher lock and then asks SwiftUI for its view
    /// graph lock; the main thread, mid-update from a timer-driven view, held
    /// the graph lock and was asking for the publisher lock to record an event
    /// of its own. Each waited for the other, forever. The app sat with its
    /// mouth open for twelve minutes, alive and silent, with no crash report —
    /// the one failure a logger that exists to survive crashes cannot log.
    ///
    /// So: the event is stamped HERE, at the moment of the call, and recorded
    /// on the main actor — synchronously when the caller is already there, so
    /// nothing about ordering or immediacy changes for the common case, and
    /// through the main queue otherwise, which keeps events in arrival order
    /// and keeps the file handle on one thread. An off-main caller pays a hop
    /// of a few milliseconds and its row still carries the time it happened.
    public nonisolated func add(_ kind: String, _ detail: String) {
        let e = LogEvent(t: Date(), kind: kind, detail: detail)
        if Thread.isMainThread {
            MainActor.assumeIsolated { record(e) }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { self.record(e) } }
        }
    }

    private func record(_ e: LogEvent) {
        events.append(e)
        write(row(e))
    }

    /// A one-tap failure marker.
    public nonisolated func flag(_ name: String) { add("flag:\(name)", "") }

    // MARK: - The copy that survives a kill

    public static var documents: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    /// The session currently being written.
    public var liveURL: URL? { Self.documents?.appendingPathComponent("\(stem)-live.csv") }

    /// The one before it, under a stable name that pull scripts can know.
    public var previousURL: URL? {
        Self.documents?.appendingPathComponent("\(stem)-previous.csv")
    }

    private var live: FileHandle?

    private func openLiveFile() {
        live?.closeFile()
        live = nil
        guard let url = liveURL, let dir = Self.documents else { return }
        // Roll the previous session into a DATED ARCHIVE rather than a single
        // slot the next launch overwrites — promise 2 above.
        if FileManager.default.fileExists(atPath: url.path) {
            let archived = dir.appendingPathComponent("\(stem)-\(Self.stamp()).csv")
            try? FileManager.default.moveItem(at: url, to: archived)
            // …and keep the previous-slot alias, which scripts already know.
            if let keep = previousURL {
                try? FileManager.default.removeItem(at: keep)
                try? FileManager.default.copyItem(at: archived, to: keep)
            }
            pruneArchives(in: dir)
        }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        live = try? FileHandle(forWritingTo: url)
        write(Self.csvHeader)
    }

    /// Keep the most recent `keepSessions` archives.
    func pruneArchives(in dir: URL) {
        let fm = FileManager.default
        guard let all = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        let archives = Self.archiveNames(in: all, stem: stem)
        guard archives.count > Self.keepSessions else { return }
        for name in archives.prefix(archives.count - Self.keepSessions) {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    /// Which files are rotatable archives — oldest first.
    ///
    /// Pulled out as a pure function so it can be TESTED. It is the piece that
    /// deletes things, it is the piece that got the promise wrong once, and it
    /// is the piece that must never match `-live` or `-previous`: matching
    /// either would delete the session currently being written.
    public nonisolated static func archiveNames(in files: [String], stem: String) -> [String] {
        files
            .filter { $0.hasPrefix("\(stem)-") && $0.hasSuffix(".csv") }
            .filter { $0 != "\(stem)-live.csv" && $0 != "\(stem)-previous.csv" }
            .sorted()                        // timestamped name sorts by age
    }

    // MARK: - What a row costs

    /// Time spent inside `write` below: the `write(2)` and the `fsync(2)` it
    /// makes, added up since process start.
    ///
    /// This class is `@MainActor` and `add` hops here, so EVERY row is written
    /// on the thread that draws. That is a deliberate trade for promise 1 at
    /// the top of this file, and it is worth knowing the size of rather than
    /// arguing about: on a quiet APFS volume an fsync answers in tens of
    /// microseconds, and behind a concurrent writer it can reach tens of
    /// milliseconds. An app that logs at a few hertz wants that number from
    /// its own hardware BEFORE anyone moves this onto a queue and pays for it
    /// in ordering guarantees.
    ///
    /// No lock, deliberately: the class is main-isolated, so the counter
    /// inherits that isolation and cannot race. No off-main counter either —
    /// `write` cannot run off the main actor, so such a field could only ever
    /// read zero, and a value that cannot vary is not evidence.
    public struct WriteCost: Sendable, Equatable {
        public var rows = 0
        public var seconds: Double = 0
        /// The worst single row. The mean hides exactly the stall being hunted:
        /// an fsync that is usually free and occasionally 40 ms averages to
        /// "fine" and feels like a stutter.
        public var worst: Double = 0
        public var meanMs: Double { rows == 0 ? 0 : seconds / Double(rows) * 1000 }
    }

    public private(set) static var writeCost = WriteCost()

    /// One field to append to a caller's existing telemetry row.
    ///
    /// `rows=` is the denominator and is not optional: without it a small
    /// total is ambiguous between a cheap fsync and a quiet app, and those two
    /// want opposite fixes.
    public static var writeCostFragment: String {
        let c = writeCost
        return String(format: "logio=%.3fs rows=%d mean=%.2fms worst=%.1fms",
                      c.seconds, c.rows, c.meanMs, c.worst * 1000)
    }

    private func write(_ line: String) {
        guard let h = live, let data = (line + "\n").data(using: .utf8) else { return }
        let tWrite = CFAbsoluteTimeGetCurrent()
        h.write(data)
        // Without this the tail of the session is in a buffer the kernel
        // discards when jetsam sends SIGKILL — which is the case this whole
        // file exists to survive.
        h.synchronizeFile()
        let dt = CFAbsoluteTimeGetCurrent() - tWrite
        Self.writeCost.rows += 1
        Self.writeCost.seconds += dt
        if dt > Self.writeCost.worst { Self.writeCost.worst = dt }
    }

    // MARK: - CSV

    public static let csvHeader = "time,elapsed_s,kind,detail"

    /// One CSV row. Shared by the live file and the export, so the two can
    /// never disagree about format — they were separate once.
    func row(_ e: LogEvent) -> String {
        Self.row(e, since: t0)
    }

    /// Pure, so the escaping is testable: a detail containing a quote or a
    /// newline must not break the row into two, because every consumer of this
    /// file is a line-oriented parser.
    ///
    /// `nonisolated` because formatting a string has nothing to do with the
    /// main actor — and because a contract test should not have to hop actors
    /// to check a comma.
    public nonisolated static func row(_ e: LogEvent, since t0: Date?) -> String {
        let f = ISO8601DateFormatter()
        let el = t0.map { Int(e.t.timeIntervalSince($0)) } ?? 0
        let d = e.detail.replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "\n", with: " ⏎ ")
        return "\(f.string(from: e.t)),\(el),\(e.kind),\"\(d)\""
    }

    public func csv() -> String {
        ([Self.csvHeader] + events.map(row)).joined(separator: "\n")
    }

    /// A snapshot for the share sheet — see `Share`.
    public func exportURL() -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(stem)-\(Self.stamp()).csv")
        try? csv().write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
