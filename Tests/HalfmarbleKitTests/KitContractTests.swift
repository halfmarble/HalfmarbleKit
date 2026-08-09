import XCTest
import AVFAudio
import StoreKit
import UIKit
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

    // MARK: - HMTexture (2026-08-09 extraction)

    /// The whole point of the type. A regression to the renderer's DEFAULT scale
    /// is invisible — every image still renders, just at 4–9× the bytes — which is
    /// exactly how ViroFlick's backdrop became a 21 MB bitmap.
    func testSoftFormatIsAlwaysScaleOneWhateverTheScreenIs() {
        XCTAssertEqual(HMTexture.softFormat().scale, 1)
        XCTAssertEqual(HMTexture.softFormat(opaque: true).scale, 1)
    }

    /// Alpha by default: a glow or a soft blob rendered opaque comes out on a
    /// black square, so `opaque` must never creep into being the default.
    func testSoftFormatKeepsAlphaUnlessAskedOtherwise() {
        XCTAssertFalse(HMTexture.softFormat().opaque, "transparency is the default")
        XCTAssertTrue(HMTexture.softFormat(opaque: true).opaque)
    }

    // MARK: - HMHaptics enable flag (2026-08-09: the kit gained the setter)

    /// Absent = ON. Two apps used to restate this rule in their own code; it has
    /// exactly one definition now, and a flip to absent-=-off would silently mute
    /// haptics for every first-launch player.
    func testHapticsDefaultsOnWhenTheKeyIsAbsentAndRoundTrips() {
        let d = UserDefaults.standard
        let saved = d.object(forKey: HMDefaultsKeys.hapticsEnabled)
        defer {
            if let saved { d.set(saved, forKey: HMDefaultsKeys.hapticsEnabled) }
            else { d.removeObject(forKey: HMDefaultsKeys.hapticsEnabled) }
        }

        d.removeObject(forKey: HMDefaultsKeys.hapticsEnabled)
        XCTAssertTrue(HMHaptics.enabled, "first launch must feel the game")

        HMHaptics.setEnabled(false)
        XCTAssertFalse(HMHaptics.enabled)
        XCTAssertEqual(d.object(forKey: HMDefaultsKeys.hapticsEnabled) as? Bool, false,
                       "the setter must write the SHARED key, not a private one")
        HMHaptics.setEnabled(true)
        XCTAssertTrue(HMHaptics.enabled)
    }

    // MARK: - HMMenu.styleToggle (2026-08-09 extraction)

    @MainActor
    func testStyleToggleSwapsTitleAndDimsOnAConfigurationPill() {
        let pill = HMMenu.makePill(symbol: "music.note", title: "MUSIC ON")
        HMMenu.styleToggle(pill, on: true, onTitle: "MUSIC ON", offTitle: "MUSIC OFF")
        XCTAssertEqual(pill.configuration?.title, "MUSIC ON")
        XCTAssertEqual(pill.configuration?.baseForegroundColor?.cgColor.alpha ?? 0,
                       HMMenu.toggleOnAlpha, accuracy: 0.001)

        HMMenu.styleToggle(pill, on: false, onTitle: "MUSIC ON", offTitle: "MUSIC OFF")
        XCTAssertEqual(pill.configuration?.title, "MUSIC OFF")
        XCTAssertEqual(pill.configuration?.baseForegroundColor?.cgColor.alpha ?? 0,
                       HMMenu.toggleOffAlpha, accuracy: 0.001)
    }

    /// A plain `.system` button has no `configuration`, so the mutation path is a
    /// silent no-op on it — the fallback is what makes the helper safe to point at
    /// whatever button a caller happens to be holding.
    @MainActor
    func testStyleToggleFallsBackForAPlainButton() {
        let b = UIButton(type: .system)
        HMMenu.styleToggle(b, on: false, onTitle: "ON", offTitle: "OFF")
        XCTAssertEqual(b.title(for: .normal), "OFF")
        XCTAssertEqual(b.titleColor(for: .normal)?.cgColor.alpha ?? 0,
                       HMMenu.toggleOffAlpha, accuracy: 0.001)
    }

    /// The OFF state must stay readable — a toggle you cannot read is one you
    /// cannot find your way back to.
    func testToggleOffStaysLegible() {
        XCTAssertGreaterThanOrEqual(HMMenu.toggleOffAlpha, 0.35)
        XCTAssertGreaterThan(HMMenu.toggleOnAlpha, HMMenu.toggleOffAlpha)
    }

    // MARK: - HMShare (2026-08-09 extraction)

    @MainActor
    func testTopMostViewControllerWalksThePresentationChain() {
        XCTAssertNil(HMShare.topMostViewController(from: nil))

        let root = UIViewController()
        XCTAssertIdentical(HMShare.topMostViewController(from: root), root,
                           "nothing presented → the root IS the top")

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = root
        window.isHidden = false
        let sheet = UIViewController()
        root.present(sheet, animated: false)
        XCTAssertTrue(HMTest.poll(2) { root.presentedViewController != nil },
                      "presentation never completed — the rest of this test proves nothing")
        // Presenting from `root` while it is already presenting is exactly what
        // silently drops a share sheet; the walk has to reach `sheet`.
        XCTAssertIdentical(HMShare.topMostViewController(from: root), sheet)
        window.isHidden = true
    }

    // MARK: - HMUnlockPromptView (2026-08-09 extraction)

    @MainActor
    private func makePrompt(width: CGFloat,
                            onBuy: @escaping () -> Void = {},
                            onDismiss: @escaping () -> Void = {}) -> HMUnlockPromptView {
        let v = HMUnlockPromptView(
            frame: CGRect(x: 0, y: 0, width: width, height: 844),
            copy: HMUnlockPromptCopy(title: "UNLOCK ALL",
                                     body: String(repeating: "word ", count: 40),
                                     buyTitle: "UNLOCK · $2.99", dismissTitle: "NOT NOW"),
            style: HMUnlockPromptStyle(accent: .orange),
            onBuy: onBuy, onDismiss: onDismiss)
        v.layoutIfNeeded()
        return v
    }

    /// The status line is the card's only voice on the paths where StoreKit shows
    /// no UI of its own. It must exist, and it must start SILENT — a card that
    /// opens already saying something reads as an error before you touched it.
    @MainActor
    func testUnlockPromptStatusLineStartsEmptyAndIsWritable() {
        let v = makePrompt(width: 390)
        XCTAssertEqual(v.statusLabel.text, "")
        v.statusLabel.text = "Purchase failed."
        XCTAssertEqual(v.statusLabel.text, "Purchase failed.")
    }

    /// The body must have real room on a NARROW screen — this is the fixed-height
    /// bug that truncated a free-tier promise mid-sentence at 375pt.
    @MainActor
    func testUnlockPromptBodyGetsRoomOnEveryPhoneWidth() {
        for width in [320.0, 375.0, 390.0, 430.0] as [CGFloat] {
            let v = makePrompt(width: width)
            XCTAssertGreaterThan(v.t_bodyFrame.height, 40,
                                 "body squeezed to \(v.t_bodyFrame.height)pt at \(width)pt wide")
            XCTAssertLessThanOrEqual(v.t_cardFrame.width, 340, "card must not exceed maxWidth")
            XCTAssertLessThan(v.t_cardFrame.width, width, "card must not touch the screen edges")
            XCTAssertEqual(v.t_bodyFrame.maxY, v.t_buyButton.frame.minY - 8, accuracy: 0.5,
                           "the body must stop above the buy button, never under it")
        }
    }

    @MainActor
    func testUnlockPromptButtonsFireTheirActions() {
        var bought = 0, dismissed = 0
        let v = makePrompt(width: 390, onBuy: { bought += 1 }, onDismiss: { dismissed += 1 })
        v.t_buyButton.sendActions(for: .primaryActionTriggered)
        v.t_dismissButton.sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(bought, 1)
        XCTAssertEqual(dismissed, 1)
    }

    // MARK: - Grouped scores

    /// The house rule: scores read XXX,XXX (gerard, 2026-07-26).
    func testGroupedScoresReadWithCommas() {
        XCTAssertEqual(1234.grouped, "1,234")
        XCTAssertEqual(12480.grouped, "12,480")
        XCTAssertEqual(96400.grouped, "96,400")
        XCTAssertEqual(1234567.grouped, "1,234,567")
    }

    /// Below the grouping threshold nothing is inserted, and zero stays "0" —
    /// the readouts show small numbers constantly (a fresh board is 0 ENERGY).
    func testGroupedLeavesSmallNumbersAlone() {
        XCTAssertEqual(0.grouped, "0")
        XCTAssertEqual(7.grouped, "7")
        XCTAssertEqual(999.grouped, "999")
    }

    /// THE REASON THIS LIVES IN THE KIT. ViroFlick's two inline formatters were
    /// unpinned, so a device grouping with "." rendered "12.480" inside
    /// otherwise-English copy — and disagreed with StringFusor on the same
    /// phone. The separator must be en_US whatever the device is set to, so
    /// this asserts against a de_DE formatter rather than trusting the ambient
    /// test locale (which is en_US, and would pass either way).
    func testGroupingIgnoresTheDeviceLocale() {
        let german = NumberFormatter()
        german.numberStyle = .decimal
        german.locale = Locale(identifier: "de_DE")
        XCTAssertEqual(german.string(from: NSNumber(value: 12480)), "12.480",
                       "sanity: de_DE really does group with a period")
        XCTAssertEqual(12480.grouped, "12,480")
        XCTAssertNotEqual(12480.grouped, german.string(from: NSNumber(value: 12480)),
                          "grouped must not follow a period-grouping locale")
    }
}
