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
/// which land later through the updates listener.
public enum HMPurchaseOutcome {
    case success, cancelled, pending, failed, unavailable
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
        // Ask-to-Buy approvals, refunds, purchases from other devices.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let t) = update { await t.finish() }
                await self?.reconcile()
            }
        }
        Task { await refresh() }
    }

    /// Load the product (for the price) and re-derive the entitlement.
    public func refresh() async {
        if let p = try? await Product.products(for: [productID]).first {
            product = p
            if displayPrice != p.displayPrice {
                displayPrice = p.displayPrice
                onChange?()
            }
        }
        await reconcile()
    }

    /// Buy the unlock. On a verified success the entitlement is reflected
    /// before returning, so the caller can immediately re-present unlocked UI.
    public func purchase() async -> HMPurchaseOutcome {
        guard !busy else { return .failed }
        busy = true
        defer { busy = false }
        if product == nil { await refresh() }         // lazy retry if launch missed
        guard let product else { return .unavailable }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let t) = verification else { return .failed }
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
        guard !busy else { return unlocked }
        busy = true
        defer { busy = false }
        try? await AppStore.sync()
        await reconcile()
        return unlocked
    }

    /// Reflect the current entitlement set EXACTLY — including absence: a
    /// refund clears the entitlement (or stamps revocationDate), and the
    /// mirror must follow it back to false or a refunded install stays
    /// unlocked forever off the stale cache (StringFusor's pre-kit bug).
    private func reconcile() async {
        #if DEBUG
        if devPin() { setUnlocked(true); return }
        #endif
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result,
               t.productID == productID,
               t.revocationDate == nil {
                entitled = true
            }
        }
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
