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
    /// `<stem>-previous.csv`, `<stem>-<unixtime>.csv`. Set once at startup.
    /// Defaulted so a misconfigured app still logs somewhere findable rather
    /// than silently not at all.
    public let stem: String

    /// Sessions kept on disk. Bounded so a long-lived install does not
    /// accumulate forever; generous enough that a whole day of testing
    /// survives. Twelve, because two was the bug.
    public static let keepSessions = 12

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

    public func add(_ kind: String, _ detail: String) {
        let e = LogEvent(t: Date(), kind: kind, detail: detail)
        events.append(e)
        write(row(e))
    }

    /// A one-tap failure marker.
    public func flag(_ name: String) { add("flag:\(name)", "") }

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
            let stamp = Int(Date().timeIntervalSince1970)
            let archived = dir.appendingPathComponent("\(stem)-\(stamp).csv")
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

    private func write(_ line: String) {
        guard let h = live, let data = (line + "\n").data(using: .utf8) else { return }
        h.write(data)
        // Without this the tail of the session is in a buffer the kernel
        // discards when jetsam sends SIGKILL — which is the case this whole
        // file exists to survive.
        h.synchronizeFile()
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
            .appendingPathComponent("\(stem)-\(Int(Date().timeIntervalSince1970)).csv")
        try? csv().write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
