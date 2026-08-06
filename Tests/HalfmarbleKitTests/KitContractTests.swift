import XCTest
import AVFAudio
import StoreKit
@testable import HalfmarbleKit

/// The kit's own contracts — born 2026-07-28 from two shipped bugs that only a
/// kit-side pin could have caught:
///  · the audio host's startup-ramp accumulator was capped at 1 s while the
///    solar-wind channel ramps over 10 s, pinning the bed at smoothstep(0.1)
///    = 0.028 (~−31 dB) FOREVER — inaudible, while the app-side isPlaying
///    test stayed green;
///  · the Game Center pending queue flushed day-scoped daily scores onto the
///    WRONG day's recurring board, and entries for a board that doesn't exist
///    in ASC retried forever, evicting real scores at the cap.
final class KitContractTests: XCTestCase {

    // MARK: - The startup ramp

    private func channel(ramp: Double) -> HMMusicChannel {
        HMMusicChannel(bundledLoopName: "t", baseVolume: 1, activeInMode: nil,
                       auxGainDriven: ramp > 0, startupRampSecs: ramp) {
            fatalError("never rendered in tests")
        }
    }

    func testStartupRampGainIsSmoothstepOverTheChannelRamp() {
        XCTAssertEqual(HMAudioHost.startupRampGain(audibleSecs: 0, rampSecs: 10), 0)
        // The OLD accumulator cap (1 s) landed here — and could never leave:
        // ~2.8% of base volume, the inaudible-solar-wind bug.
        XCTAssertEqual(HMAudioHost.startupRampGain(audibleSecs: 1, rampSecs: 10),
                       0.028, accuracy: 0.001)
        XCTAssertEqual(HMAudioHost.startupRampGain(audibleSecs: 5, rampSecs: 10), 0.5)
        XCTAssertEqual(HMAudioHost.startupRampGain(audibleSecs: 10, rampSecs: 10), 1)
        XCTAssertEqual(HMAudioHost.startupRampGain(audibleSecs: 99, rampSecs: 10), 1,
                       "past the ramp it stays at full")
        XCTAssertEqual(HMAudioHost.startupRampGain(audibleSecs: 0, rampSecs: 0), 1,
                       "no ramp = no attenuation")
    }

    func testRampAccumulatorCapReachesEveryChannelsFullRamp() {
        // THE regression pin: the accumulator's ceiling must let every
        // channel's smoothstep reach 1 — a fixed cap of 1 s could not.
        let chans = [channel(ramp: 0), channel(ramp: 10), channel(ramp: 3)]
        let cap = HMAudioHost.longestRamp(of: chans)
        XCTAssertEqual(cap, 10)
        for ch in chans {
            XCTAssertEqual(HMAudioHost.startupRampGain(audibleSecs: cap,
                                                       rampSecs: ch.startupRampSecs), 1,
                           "a ramp of \(ch.startupRampSecs)s completes under the shared cap")
        }
        XCTAssertEqual(HMAudioHost.longestRamp(of: []), 1,
                       "a no-ramp host keeps the old accumulator shape")
    }

    // MARK: - The pending-score queue

    private func freshDefaults(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testOldPersistedQueuesStillDecode() {
        let d = freshDefaults("hm.kit.tests.decode")
        // The pre-2026-07-28 on-disk shape: no utcDayOnly, no attempts.
        let old: [[String: Any]] = [["id": "lb.a", "score": 123, "date": 0.0]]
        d.set(try! JSONSerialization.data(withJSONObject: old), forKey: HMPendingScoreQueue.storageKey)
        let q = HMPendingScoreQueue.load(from: d)
        XCTAssertEqual(q.items.count, 1)
        XCTAssertEqual(q.items[0].id, "lb.a")
        XCTAssertEqual(q.items[0].score, 123)
        XCTAssertNil(q.items[0].utcDayOnly)
        XCTAssertNil(q.items[0].attempts)
    }

    func testPruneExpiredDropsOnlyPastDayScopedScores() {
        var q = HMPendingScoreQueue()
        let today = 2026_07_28
        q.enqueue(HMPendingScore(id: "lb.daily", score: 10, date: Date(), utcDayOnly: 2026_07_27))
        q.enqueue(HMPendingScore(id: "lb.daily", score: 20, date: Date(), utcDayOnly: today))
        q.enqueue(HMPendingScore(id: "lb.exam", score: 30, date: Date()))   // never expires
        let dropped = q.pruneExpired(todayUTCDay: today)
        XCTAssertEqual(dropped.map(\.score), [10], "yesterday's daily score is dropped, not submitted")
        XCTAssertEqual(q.items.map(\.score), [20, 30], "today's + unscoped survive")
    }

    func testFailedAttemptsAbandonAPoisonedEntry() {
        var q = HMPendingScoreQueue()
        let dead = HMPendingScore(id: "lb.not.in.asc", score: 999, date: Date())
        q.enqueue(dead)
        q.enqueue(HMPendingScore(id: "lb.real", score: 1, date: Date()))
        for n in 1..<HMPendingScoreQueue.maxAttempts {
            XCTAssertFalse(q.recordFailedAttempt(of: dead), "attempt \(n) keeps retrying")
            XCTAssertEqual(q.items.first?.attempts, n)
        }
        XCTAssertTrue(q.recordFailedAttempt(of: dead),
                      "attempt \(HMPendingScoreQueue.maxAttempts) abandons the entry")
        XCTAssertEqual(q.items.map(\.id), ["lb.real"],
                       "…and the real score is still queued, not evicted")
    }

    /// A leaderboard keeps the player's HIGH score, so a second entry for the same board is
    /// only ever the better of the two. Keeping both and evicting by age lost the good one:
    /// a player who never signs in and whose standout run is early gets it pushed out by 50
    /// later, worse runs, and nothing in the app will ever submit that score again.
    func testEnqueueKeepsOnlyTheBestScorePerBoard() {
        var q = HMPendingScoreQueue()
        let day = 2026_08_04
        q.enqueue(HMPendingScore(id: "lb.triage", score: 50_000, date: Date(), utcDayOnly: day))
        for s in stride(from: 100, to: 6_000, by: 100) {          // 59 worse runs after it
            q.enqueue(HMPendingScore(id: "lb.triage", score: s, date: Date(), utcDayOnly: day))
        }
        XCTAssertEqual(q.items.count, 1, "same board + same day collapses to one entry")
        XCTAssertEqual(q.items.first?.score, 50_000,
                       "the standout run must survive an avalanche of worse ones")
    }

    /// Different boards (and different day buckets on a recurring board) stay separate —
    /// the collapse must not merge scores that belong on different leaderboards.
    func testEnqueueKeepsBoardsAndDayBucketsSeparate() {
        var q = HMPendingScoreQueue()
        q.enqueue(HMPendingScore(id: "lb.a", score: 10, date: Date(), utcDayOnly: 2026_08_04))
        q.enqueue(HMPendingScore(id: "lb.b", score: 10, date: Date(), utcDayOnly: 2026_08_04))
        q.enqueue(HMPendingScore(id: "lb.a", score: 10, date: Date(), utcDayOnly: 2026_08_05))
        q.enqueue(HMPendingScore(id: "lb.a", score: 10, date: Date(), utcDayOnly: nil))
        XCTAssertEqual(q.items.count, 4, "board id and day bucket both discriminate")
    }

    /// If the cap is somehow still reached, it must cost the LOWEST scores, not the oldest.
    func testCapEvictsTheLowestScoresNotTheOldest() {
        var q = HMPendingScoreQueue()
        q.enqueue(HMPendingScore(id: "lb.oldest.and.best", score: 1_000_000, date: Date()))
        for i in 0...HMPendingScoreQueue.cap {                    // cap+1 distinct boards
            q.enqueue(HMPendingScore(id: "lb.\(i)", score: i + 1, date: Date()))
        }
        XCTAssertEqual(q.items.count, HMPendingScoreQueue.cap)
        XCTAssertTrue(q.items.contains { $0.id == "lb.oldest.and.best" },
                      "the oldest entry was also the best — age must not decide")
        XCTAssertFalse(q.items.contains { $0.score == 1 }, "the weakest entry is the one dropped")
    }

    /// A superseded entry must not hand its replacement a fresh retry budget — otherwise a
    /// board missing from ASC could retry forever by being re-enqueued each run.
    func testSupersedingCarriesTheRetryBudgetOver() {
        var q = HMPendingScoreQueue()
        let poisoned = HMPendingScore(id: "lb.not.in.asc", score: 10, date: Date())
        q.enqueue(poisoned)
        _ = q.recordFailedAttempt(of: poisoned)
        XCTAssertEqual(q.items.first?.attempts, 1)
        q.enqueue(HMPendingScore(id: "lb.not.in.asc", score: 99, date: Date()))
        XCTAssertEqual(q.items.first?.score, 99, "the better score wins the slot")
        XCTAssertEqual(q.items.first?.attempts, 1, "…but inherits the failures already spent")
    }

    func testUTCDayMatchesTheDailySeedBucket() {
        XCTAssertEqual(HMGameCenter.utcDay(of: Date(timeIntervalSince1970: 0)), 1970_01_01)
        // 2026-07-28 12:00:00 UTC.
        XCTAssertEqual(HMGameCenter.utcDay(of: Date(timeIntervalSince1970: 1_785_240_000)), 2026_07_28)
    }

    // MARK: - The store unlock (2026-07-29 extraction)

    /// Only the SYNCHRONOUS seed is deterministically testable without a
    /// StoreKit test configuration: assertions run on the main actor straight
    /// after init, before the async reconciliation tasks can have executed —
    /// the entitlement paths themselves are exercised by the apps' sandbox
    /// builds, not unit tests.
    @MainActor
    func testStoreUnlockSeedsFromTheDefaultsCache() {
        let d = freshDefaults("hm.kit.tests.store")
        let key = "test.unlocked"
        XCTAssertFalse(HMStoreUnlock(productID: "t.p", defaultsKey: key,
                                     defaults: d).unlocked,
                       "no cache, no unlock — the warm start is honest")
        d.set(true, forKey: key)
        XCTAssertTrue(HMStoreUnlock(productID: "t.p", defaultsKey: key,
                                    defaults: d).unlocked,
                      "a cached entitlement unlocks the first frame")
        #if DEBUG
        d.set(false, forKey: key)
        XCTAssertTrue(HMStoreUnlock(productID: "t.p", defaultsKey: key,
                                    defaults: d, devPin: { true }).unlocked,
                      "the dev pin forces the unlock with no receipt at all")
        #endif
    }

    /// The unverified-redelivery split (2026-08-04 audit): the clock failure
    /// must KEEP the launch-time retry (never finish), the fraud-class
    /// failures must be finished so a dead transaction stops redelivering
    /// forever, and anything StoreKit invents later defaults to the retry —
    /// a charged purchase is never consumed on a guess.
    @MainActor
    func testUnverifiedFinishSplitsByRecoverability() {
        XCTAssertFalse(HMStoreUnlock.verificationFailureIsPermanent(.invalidDeviceVerification),
                       "the device-clock failure heals on a future launch — keep the retry")
        for dead in [VerificationResult<StoreKit.Transaction>.VerificationError.revokedCertificate,
                     .invalidCertificateChain, .invalidSignature,
                     .invalidEncoding, .missingRequiredProperties] {
            XCTAssertTrue(HMStoreUnlock.verificationFailureIsPermanent(dead),
                          "\(dead) can never verify — finish it or it redelivers forever")
        }
    }
}
