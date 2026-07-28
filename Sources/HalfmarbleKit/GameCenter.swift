import Foundation
import UIKit
import GameKit

//  Game Center, once, for every halfmarble app — extracted from ViroFlick's
//  proven GameCenter.swift (2026-07-26), the same way the audio host moved.
//
//  The kit owns the PLATFORM layer: the GameKit manager (auth, submit, the
//  native rankings UI) and the persisted pending-submission queue. Each app
//  keeps its own PURE board-ID mapping (ViroFlick's `Leaderboards` enum,
//  StringFusor's single energy board) — board IDs are App Store Connect
//  contracts and belong to the app that registered them.
//
//  Storage contract: the pending queue persists under `gc.pendingScores.v1`
//  (ViroFlick's original literal, kept as the kit default so its on-device
//  queues survive the extraction; UserDefaults are per-app sandboxes, so
//  sharing the literal across apps collides with nothing).

// MARK: - Pending submissions (persisted, testable)

public struct HMPendingScore: Codable, Equatable {
    public let id: String
    public let score: Int
    public let date: Date
    /// Day-scoped scores (a RECURRING daily board) are only meaningful on the
    /// UTC day they were earned — Game Center's recurrence buckets by
    /// SUBMISSION time, so flushing Monday's queued score on Tuesday would
    /// rank a run the player never played that day (the 2026-07-28 finding).
    /// This is that day (yyyymmdd); nil = never expires. Optional so
    /// pre-existing persisted queues still decode (missing keys → nil).
    public let utcDayOnly: Int?
    /// AUTHENTICATED submits that failed for this item so far (nil = 0). A
    /// board that doesn't exist in ASC fails every flush forever, and at the
    /// cap those poisoned entries evicted REAL scores — recordFailedAttempt
    /// abandons an item once it exhausts maxAttempts.
    public var attempts: Int?
    public init(id: String, score: Int, date: Date,
                utcDayOnly: Int? = nil, attempts: Int? = nil) {
        self.id = id; self.score = score; self.date = date
        self.utcDayOnly = utcDayOnly; self.attempts = attempts
    }
}

/// A capped FIFO of score submissions made while unauthenticated or after a
/// failed submit (e.g. the ASC boards aren't defined yet). Persisted as JSON;
/// at the cap the oldest are dropped. Injectable `UserDefaults` for tests.
public struct HMPendingScoreQueue: Equatable {
    /// The persistence key — a STORAGE CONTRACT (ViroFlick's legacy literal).
    /// A future app may point it elsewhere at startup, before any load.
    public static var storageKey = "gc.pendingScores.v1"
    public static let cap = 50

    public private(set) var items: [HMPendingScore] = []

    public init() {}

    public static func load(from defaults: UserDefaults = .standard) -> HMPendingScoreQueue {
        var q = HMPendingScoreQueue()
        if let data = defaults.data(forKey: storageKey),
           let items = try? JSONDecoder().decode([HMPendingScore].self, from: data) {
            q.items = items
        }
        return q
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    public mutating func enqueue(_ s: HMPendingScore) {
        items.append(s)
        if items.count > Self.cap { items.removeFirst(items.count - Self.cap) }   // drop oldest
    }

    /// The SUBMISSION identity: everything but the bookkeeping (`attempts`) —
    /// a caller holding an item from an earlier load must still match it after
    /// a failure bumped its counter in the persisted queue.
    private func index(matching s: HMPendingScore) -> Int? {
        items.firstIndex { $0.id == s.id && $0.score == s.score
            && $0.date == s.date && $0.utcDayOnly == s.utcDayOnly }
    }

    /// Remove ONE occurrence of `s` (the flush removes an item only after its
    /// submit succeeded — see HMGameCenter.flushQueue).
    public mutating func remove(_ s: HMPendingScore) {
        if let i = index(matching: s) { items.remove(at: i) }
    }

    public mutating func clear() { items.removeAll() }

    /// Authenticated-submit failures an item survives before it is abandoned.
    /// Eight flushes is at least eight app foregroundings/auth events — a
    /// transient outage clears long before that; only a dead board (an ID not
    /// created in ASC) keeps failing, and it must not retry forever.
    public static let maxAttempts = 8

    /// Drop day-scoped items whose UTC day has passed — submitted late, a
    /// recurring board would rank them on the WRONG day. Returns the dropped
    /// items so the host can log them.
    @discardableResult
    public mutating func pruneExpired(todayUTCDay: Int) -> [HMPendingScore] {
        let expired = items.filter { ($0.utcDayOnly ?? todayUTCDay) != todayUTCDay }
        items.removeAll { ($0.utcDayOnly ?? todayUTCDay) != todayUTCDay }
        return expired
    }

    /// Record one failed AUTHENTICATED submit for `s`; abandons the item once
    /// it exhausts maxAttempts (returns true then), so a poisoned entry can't
    /// retry forever and crowd real scores out of the capped queue.
    @discardableResult
    public mutating func recordFailedAttempt(of s: HMPendingScore) -> Bool {
        guard let i = index(matching: s) else { return false }
        let n = (items[i].attempts ?? 0) + 1
        if n >= Self.maxAttempts { items.remove(at: i); return true }
        items[i].attempts = n
        return false
    }
}

// MARK: - Game Center manager (GameKit, main thread)

/// The GameKit manager (singleton, main-thread contract) — the platform
/// adapter every halfmarble app shares. Scores submit through the pending
/// queue above; the app supplies board IDs from its own pure mapping.
public final class HMGameCenter: NSObject, GKGameCenterControllerDelegate {
    public static let shared = HMGameCenter()

    public private(set) var isAuthenticated = false
    /// UI refresh hook — fired on the main thread when auth state changes.
    /// Apps also use this to sync a pre-Game-Center stored best on first auth.
    public var onAuthChange: (() -> Void)?

    private var authHandlerSet = false
    private let defaults = UserDefaults.standard

    private override init() { super.init() }

    /// Set `GKLocalPlayer.local.authenticateHandler` exactly once. The handler
    /// re-fires on foregrounding, so on those repeats we only flush the queue —
    /// never re-present.
    public func authenticateIfNeeded(presentingFrom view: UIView) {
        startAuth { [weak view] vc in view?.hmTopPresenter?.present(vc, animated: true) }
    }

    /// SwiftUI-host variant: presents the sign-in over the key window's
    /// top-most presenter (a SwiftUI shell has no UIView to hand us).
    public func authenticateIfNeeded() {
        startAuth { vc in Self.keyWindowTopPresenter?.present(vc, animated: true) }
    }

    private func startAuth(present: @escaping (UIViewController) -> Void) {
        guard !authHandlerSet else { return }
        authHandlerSet = true
        GKLocalPlayer.local.authenticateHandler = { [weak self] vc, _ in
            guard let self = self else { return }
            if let vc = vc {
                present(vc)                                     // sign-in UI required
            } else {
                let was = self.isAuthenticated
                self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                #if DEBUG
                StartupProf.mark("gc: auth resolved (authenticated=\(self.isAuthenticated))")
                #endif
                if self.isAuthenticated { self.flushQueue() }
                if self.isAuthenticated != was { self.onAuthChange?() }
            }
        }
    }

    /// Submit a score. Queued if unauthenticated; queued again if the async
    /// submit throws (e.g. the board isn't defined in ASC yet). On success,
    /// drains the pending queue.
    ///
    /// `utcDayOnly`: pass true for a RECURRING daily board — a queued score is
    /// then only ever flushed on the UTC day it was earned (Game Center's
    /// recurrence buckets by SUBMISSION time, so a late flush would rank the
    /// score on the wrong day's board); after that day it is silently dropped.
    public func submit(score: Int, leaderboardID: String, utcDayOnly: Bool = false) {
        guard isAuthenticated else { enqueue(score, leaderboardID, utcDayOnly); return }
        Task {
            do {
                try await GKLeaderboard.submitScore(score, context: 0,
                                                    player: GKLocalPlayer.local,
                                                    leaderboardIDs: [leaderboardID])
                await MainActor.run { self.flushQueue() }
            } catch {
                await MainActor.run { self.enqueue(score, leaderboardID, utcDayOnly) }
            }
        }
    }

    /// The UTC calendar day of `date` as yyyymmdd — the recurrence bucket a
    /// daily board's day-scoped scores expire with (UTC, matching the one
    /// global moment the daily seed rolls at).
    public static func utcDay(of date: Date = Date()) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return c.year! * 10_000 + c.month! * 100 + c.day!
    }

    /// Present the native leaderboards UI — a specific board, or the board
    /// list if nil.
    public func presentRankings(leaderboardID: String?, from view: UIView) {
        guard let top = view.hmTopPresenter else { return }
        presentRankings(leaderboardID: leaderboardID, over: top)
    }

    /// SwiftUI-host variant: presents over the key window's top presenter.
    public func presentRankings(leaderboardID: String?) {
        guard let top = Self.keyWindowTopPresenter else { return }
        presentRankings(leaderboardID: leaderboardID, over: top)
    }

    private func presentRankings(leaderboardID: String?, over top: UIViewController) {
        let vc: GKGameCenterViewController
        if let id = leaderboardID {
            vc = GKGameCenterViewController(leaderboardID: id, playerScope: .global, timeScope: .allTime)
        } else {
            vc = GKGameCenterViewController(state: .leaderboards)
        }
        vc.gameCenterDelegate = self                                // required for dismissal
        top.present(vc, animated: true)
    }

    public func gameCenterViewControllerDidFinish(_ vc: GKGameCenterViewController) {
        vc.dismiss(animated: true)
    }

    // MARK: - Pending queue

    private func enqueue(_ score: Int, _ id: String, _ utcDayOnly: Bool) {
        var q = HMPendingScoreQueue.load(from: defaults)
        q.enqueue(HMPendingScore(id: id, score: score, date: Date(),
                                 utcDayOnly: utcDayOnly ? Self.utcDay() : nil))
        q.save(to: defaults)
    }

    private func flushQueue() {
        var pre = HMPendingScoreQueue.load(from: defaults)
        // Day-scoped scores from a PAST UTC day are dropped, never submitted:
        // the recurring board would rank them on the wrong day.
        let expired = pre.pruneExpired(todayUTCDay: Self.utcDay())
        if !expired.isEmpty {
            pre.save(to: defaults)
            #if DEBUG
            StartupProf.mark("gc: dropped \(expired.count) day-scoped score(s) from a past UTC day")
            #endif
        }
        let q = pre
        guard isAuthenticated, !q.items.isEmpty else { return }
        // Items stay PERSISTED until their submit succeeds — clearing the queue
        // up-front meant an app kill mid-flush silently dropped every score still
        // in flight. One sequential Task with a single load-remove-save at the end
        // (instead of a Task + defaults round-trip per item): a crash mid-flush
        // re-submits the already-sent items next launch (harmless; Game Center
        // keeps the max), never the reverse. Sequential also means overlapping
        // flush calls can't stampede 50 concurrent submits.
        Task {
            var sent: [HMPendingScore] = []
            var failed: [HMPendingScore] = []
            for it in q.items {
                do {
                    try await GKLeaderboard.submitScore(it.score, context: 0,
                                                        player: GKLocalPlayer.local,
                                                        leaderboardIDs: [it.id])
                    sent.append(it)
                } catch {
                    failed.append(it)   // persisted; counted below
                }
            }
            guard !sent.isEmpty || !failed.isEmpty else { return }
            let submitted = sent   // immutable captures — a captured VAR in a Sendable closure is a Swift 6 error
            let misses = failed
            await MainActor.run {
                var q2 = HMPendingScoreQueue.load(from: self.defaults)
                for it in submitted { q2.remove(it) }
                // A submit that fails while AUTHENTICATED is most likely a dead
                // board (an ID not created in ASC): count the failure and abandon
                // the item after maxAttempts, so poisoned entries can't retry
                // forever and crowd real scores out of the capped queue.
                for it in misses where q2.recordFailedAttempt(of: it) {
                    #if DEBUG
                    StartupProf.mark("gc: abandoned \(it.id) score \(it.score) after \(HMPendingScoreQueue.maxAttempts) failed submits")
                    #endif
                }
                q2.save(to: self.defaults)
            }
        }
    }

    /// The key window's top-most presented view controller — where a modal
    /// (sign-in / rankings) lands when the host has no UIView to offer.
    private static var keyWindowTopPresenter: UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        guard var top = window?.rootViewController else { return nil }
        while let p = top.presentedViewController { top = p }
        return top
    }
}

private extension UIView {
    /// The top-most presented view controller above this view's window — where
    /// a modal (sign-in / rankings) must be presented from.
    var hmTopPresenter: UIViewController? {
        guard var top = window?.rootViewController else { return nil }
        while let p = top.presentedViewController { top = p }
        return top
    }
}
