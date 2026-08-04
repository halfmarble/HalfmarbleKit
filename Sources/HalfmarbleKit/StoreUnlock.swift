import Foundation
import StoreKit

//  The one-time unlock, once, for every halfmarble app — extracted 2026-07-29
//  from the TWO independently written ~140-line StoreKit 2 managers
//  (ViroFlick's StoreManager, StringFusor's FusionCoreStore) the moment they
//  were seen to have already drifted: StringFusor's copy only applied
//  transactions it FOUND in currentEntitlements, so a refund that removed the
//  transaction never wrote `false` and the defaults cache stayed unlocked
//  forever; ViroFlick's reflected the set exactly but swallowed no outcomes.
//  This class keeps the better half of each — the same story, move for move,
//  as HMGameCenter's extraction.
//
//  The kit owns the PLATFORM layer: product load (localized price), the
//  lifelong Transaction.updates listener (started before the first await —
//  Apple's required shape), exact entitlement reconciliation (verified-only,
//  offline-capable, revocation- and absence-aware), the UserDefaults mirror
//  that keeps synchronous gating reads off the hot path, purchase with
//  verify-then-finish, and restore via AppStore.sync(). Each app keeps its
//  PURE side: the product ID (an App Store Connect contract), its defaults
//  key, its gating semantics (StringFusor's locked tracks and daily taste;
//  ViroFlick's case locks), and its purchase UI.

/// What a purchase attempt resolved to — pending is Ask-to-Buy and friends,
/// which land later through the updates listener; busy means another
/// purchase/restore already holds the store (the tap never reached StoreKit —
/// NOT a failure, and hosts should render it as nothing or "one moment",
/// never as an error).
public enum HMPurchaseOutcome {
    case success, cancelled, pending, failed, unavailable, busy
    /// StoreKit returned a transaction whose signature/date check did not pass. The player
    /// HAS been charged, so this must not be reported as a plain failure: the actionable
    /// advice is "check that Date & Time is set automatically", and the transaction is
    /// deliberately left unfinished so StoreKit can redeliver it once verification succeeds.
    case unverified
}

/// Restore is three-state, not a Bool: "sync failed" and "you own nothing" are opposite
/// messages, and collapsing them told paying customers they owned nothing.
public enum HMRestoreOutcome {
    case restored, nothingToRestore, failed, busy
}

/// One non-consumable product's entitlement, mirrored into UserDefaults.
/// Main-actor: it only touches defaults and drives UI callbacks; StoreKit's
/// async APIs are actor-agnostic. Framework-neutral like HMGameCenter — a
/// SwiftUI host wraps it in its own @Observable face, a UIKit host reads it
/// directly and hangs UI refresh on `onChange`.
@MainActor
public final class HMStoreUnlock {

    /// The App Store product this instance manages.
    public let productID: String
    /// Where the entitlement mirror persists (each app's own legacy literal —
    /// per-app sandboxes, so the strings never collide across apps).
    public let defaultsKey: String

    /// The entitlement, live. Seeded from the defaults cache for an instant
    /// first frame, then confirmed against StoreKit's cryptographically
    /// verified currentEntitlements (which work offline) — the cache is a
    /// warm-start, never the truth.
    public private(set) var unlocked: Bool
    /// The App Store's localized price ("$4.99", "4,99 €") — nil until the
    /// product loads; hosts show their own fallback until then, never a
    /// hard-coded figure.
    public private(set) var displayPrice: String?
    /// A purchase/restore is in flight — sheets disable their buttons on it.
    public private(set) var busy = false

    /// Fired on the main thread whenever `unlocked` or `displayPrice` moves —
    /// the UIKit hosts' refresh hook (SwiftUI hosts mirror state here too).
    public var onChange: (() -> Void)?

    private let defaults: UserDefaults
    /// DEBUG pin: a capture/sim install with no App Store (and, pre-ASC, no
    /// product) can force the unlock; while pinned, the empty local receipt
    /// must never re-lock the install. Consulted only in DEBUG builds.
    private let devPin: () -> Bool
    private var product: Product?
    /// Lifelong by design: both hosts keep their unlock manager for the app's
    /// lifetime (a cancelled listener is how a transaction slips past).
    private var updatesTask: Task<Void, Never>?

    public init(productID: String, defaultsKey: String,
                defaults: UserDefaults = .standard,
                devPin: @escaping () -> Bool = { false }) {
        self.productID = productID
        self.defaultsKey = defaultsKey
        self.defaults = defaults
        self.devPin = devPin
        unlocked = defaults.bool(forKey: defaultsKey)
        #if DEBUG
        if devPin() { unlocked = true }
        #endif
        // Listen BEFORE the first await so no transaction slips past unhandled:
        // Ask-to-Buy approvals, refunds, purchases from other devices. OUR
        // product only — finishing another product's transaction here would
        // silently consume it before its own handler ever saw it (harmless
        // with one product per app today, a booby trap the day there are two).
        let watched = productID
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard case .verified(let t) = update,
                      t.productID == watched else { continue }
                await t.finish()
                await self?.reconcile()
            }
        }
        Task { await refresh() }
    }

    /// Load the product (for the price) and re-derive the entitlement.
    ///
    /// THE TWO RUN CONCURRENTLY, deliberately. Awaiting the product FIRST put the
    /// entitlement behind a network request: `Transaction.currentEntitlements` is local and
    /// resolves offline in milliseconds, while `Product.products(for:)` can hang for the
    /// whole App Store timeout on a captive-portal or very slow network. On a paid
    /// REINSTALL the UserDefaults mirror is gone, so `unlocked` seeds false — and the ~2 s
    /// splash plus one tap is all that stands between launch and `startWave(1)`, which
    /// snapshots `freeCapActive` for the entire run. A player who owns the game could
    /// therefore be force-ended AS A WIN at surge 22 and have the score banked to the
    /// free-tier board. The price string can afford to arrive late; the entitlement cannot.
    public func refresh() async {
        async let productLoad = try? Product.products(for: [productID]).first
        await reconcile()                       // local, offline, fast — never gated on the network
        if let p = await productLoad {
            product = p
            if displayPrice != p.displayPrice {
                displayPrice = p.displayPrice
                onChange?()
            }
        }
    }

    /// Buy the unlock. On a verified success the entitlement is reflected
    /// before returning, so the caller can immediately re-present unlocked UI.
    public func purchase() async -> HMPurchaseOutcome {
        guard !busy else { return .busy }   // the tap never reached StoreKit
        busy = true
        defer { busy = false }
        if product == nil { await refresh() }         // lazy retry if launch missed
        guard let product else { return .unavailable }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                // UNVERIFIED is its own outcome, not a generic failure. Verification is a
                // local JWS signature + date check, so the realistic cause is a badly wrong
                // system clock — and the player HAS been charged. Deliberately do NOT
                // `finish()` it: leaving it unfinished is what lets StoreKit redeliver it
                // through `Transaction.updates` once verification succeeds, so the install
                // self-heals when the clock is corrected. Reporting it distinctly is the
                // only way the host can say "check Date & Time" instead of "try again",
                // which is advice that cannot work.
                guard case .verified(let t) = verification else { return .unverified }
                await t.finish()
                await reconcile()
                return .success
            case .userCancelled: return .cancelled
            case .pending:       return .pending      // resolves via the listener
            @unknown default:    return .failed
            }
        } catch { return .failed }
    }

    /// Restore — AppStore.sync() re-authenticates with the store, then the
    /// entitlements re-derive. (currentEntitlements alone usually suffices;
    /// the explicit button is the App Store review requirement.) Returns
    /// whether the unlock is owned afterward.
    @discardableResult
    public func restore() async -> Bool {
        await restoreOutcome() == .restored
    }

    /// The three-state restore the UI actually needs. `try? await AppStore.sync()` used to
    /// swallow its error, so a sync that failed (no network, a captive portal, a dismissed
    /// Apple ID prompt) on an install with nothing cached locally was reported to the player
    /// as "No purchases found to restore." — telling a paying customer, in the App Store-
    /// mandated restore UI, that they do not own what they bought. `.failed` lets the host
    /// say "couldn't reach the App Store" instead, which is both true and actionable.
    public func restoreOutcome() async -> HMRestoreOutcome {
        guard !busy else { return .busy }        // never render a no-op as "nothing to restore"
        busy = true
        defer { busy = false }
        var syncFailed = false
        do { try await AppStore.sync() } catch { syncFailed = true }
        await reconcile()                        // local entitlements may still resolve it
        if unlocked { return .restored }         // …and if they did, the sync error is moot
        return syncFailed ? .failed : .nothingToRestore
    }

    /// Reflect the current entitlement set EXACTLY — including absence: a
    /// refund clears the entitlement (or stamps revocationDate), and the
    /// mirror must follow it back to false or a refunded install stays
    /// unlocked forever off the stale cache (StringFusor's pre-kit bug).
    /// Monotonic pass counter: reconcile suspends inside the entitlement
    /// stream, so two passes can interleave (a sheet-refresh scan vs the
    /// purchase's own), and last-WRITER-wins used to let a STALE pre-purchase
    /// scan finish after the purchase and re-lock a just-paid user —
    /// persisting `false` into the mirror until the next refresh. Only the
    /// newest pass may write; an obsolete one discards its answer.
    private var reconcileGen = 0

    private func reconcile() async {
        #if DEBUG
        if devPin() { setUnlocked(true); return }
        #endif
        reconcileGen += 1
        let gen = reconcileGen
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result,
               t.productID == productID,
               t.revocationDate == nil {
                entitled = true
            }
        }
        guard gen == reconcileGen else { return }   // a newer pass owns the truth
        #if DEBUG
        StartupProf.mark("store: entitlements resolved (\(productID) entitled=\(entitled))")
        #endif
        setUnlocked(entitled)
    }

    private func setUnlocked(_ owned: Bool) {
        guard unlocked != owned else { return }
        unlocked = owned
        defaults.set(owned, forKey: defaultsKey)
        onChange?()
    }
}
