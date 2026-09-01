import XCTest
import StoreKit
import StoreKitTest
@testable import HalfmarbleKit

/// The PURCHASE FLOW — the one code path that turns a download into money, and
/// the only part of `HMStoreUnlock` that had never been executed by a test.
///
/// Before this file the kit pinned exactly two things about the store: that
/// `unlocked` warm-starts from the defaults mirror, and that
/// `verificationFailureIsPermanent` splits the clock case from the fraud cases.
/// Both are pure functions. Everything that actually moves money — product
/// load, `purchase()`, `AppStore.sync()`, the `Transaction.updates` listener,
/// and `reconcile()`'s exact reflection of `currentEntitlements` — ran only in
/// production, on a customer's phone, after the App Store had taken the money.
///
/// That is the wrong place to find out. A broken unlock does not crash and does
/// not fail a unit suite: the app launches, plays, looks perfect, and silently
/// earns nothing. `StoreKitTest.SKTestSession` runs the real StoreKit 2 stack
/// against a local `.storekit` file, in the simulator, with no App Store
/// Connect round trip — so every case below is the genuine article, not a mock.
///
/// The two cases that map to shipped bugs named in `StoreUnlock.swift`'s own
/// header are `testRefundRelocksTheInstall` (StringFusor's pre-kit manager
/// applied only transactions it FOUND, so a refund never wrote `false` and the
/// mirror stayed unlocked forever) and `testFailedSyncIsNotNothingToRestore`
/// (a swallowed `AppStore.sync()` error told paying customers, in the
/// App Store-mandated restore UI, that they owned nothing).
/// WHAT IS *NOT* HERE, AND WHY — measured 2026-09-01, not assumed.
///
/// A SwiftPM test target has NO HOST APPLICATION, and StoreKit 2 needs one to
/// complete a transaction. Running the full suite here produced, in the log:
///
///   "Could not get confirmation scene ID for <product> purchase."
///   Error Domain=AMSErrorDomain Code=301 ... AMSStatusCode=400
///     AMSURL=http://localhost:.../inApps/v1/history
///
/// So `Product.purchase()` has no scene to confirm in and `AppStore.sync()`
/// gets a 400 from the local test server. Seven tests failed for that reason
/// alone — purchase completion, refund/revocation, restore, Ask-to-Buy
/// APPROVAL, and even `SKTestSession.buyProduct` itself (which throws
/// "unknown"). They are not flaky and they are not wrong; they cannot run in a
/// package. They live in an APP test target, which has a host app.
///
/// What survives here is everything that needs only product metadata and the
/// pre-confirmation half of a purchase — which is still worth pinning, because
/// it covers the product load, the localized price, the `busy` guard and the
/// Ask-to-Buy DECLINE path.
///
/// Gated at iOS 17 because the non-deprecated `SKTestSession.buyProduct(identifier:options:)`
/// starts there. The pre-17 knobs (`failTransactionsEnabled`, `failureError`) are marked
/// API_DEPRECATED "No longer supported" — they still COMPILE, which is the trap: a failure
/// injector that silently stops injecting turns every refusal test below into a test that
/// cannot fail. The Ask-to-Buy decline path is used instead; it is documented, current, and
/// observably does something.
@available(iOS 17.0, tvOS 17.0, *)
@MainActor
final class StoreUnlockTransactionTests: XCTestCase {

    private static let productID = "com.halfmarble.kit.tests.unlock"
    private static let otherID   = "com.halfmarble.kit.tests.other"

    private var session: SKTestSession!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()

        // `configurationFileNamed:` searches the test BUNDLE, which a SwiftPM
        // resource is not in — the package puts it in `Bundle.module`. Resolve
        // the URL explicitly and use `contentsOf:` instead; the named form
        // fails here with a file-not-found that reads like a broken checkout.
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "KitStore", withExtension: "storekit"),
            "KitStore.storekit is missing from the test bundle — check that Package.swift "
            + "declares it as a resource of HalfmarbleKitTests")
        session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true          // no purchase sheet to tap in CI
        session.clearTransactions()            // each test starts owning nothing

        // A per-test defaults suite. `.standard` would leak the entitlement
        // mirror between tests and, worse, between this suite and whatever
        // else runs in the same process — the mirror is the thing under test.
        suiteName = "kit.store.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        session?.clearTransactions()
        session = nil
        if let suiteName { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        defaults = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// `HMStoreUnlock` does its real work in detached tasks it does not expose
    /// (the `Transaction.updates` listener and the `refresh()` kicked off from
    /// `init`), so there is nothing to await. Poll instead of sleeping a fixed
    /// interval: a fixed sleep is either flaky or slow, and usually both.
    private func waitUntil(_ what: String,
                           timeout: TimeInterval = 15,
                           file: StaticString = #filePath, line: UInt = #line,
                           _ condition: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 40_000_000)   // 40 ms
        }
        XCTFail("timed out after \(timeout)s waiting for: \(what)", file: file, line: line)
    }

    private func makeUnlock(defaults d: UserDefaults? = nil) -> HMStoreUnlock {
        HMStoreUnlock(productID: Self.productID,
                      defaultsKey: "kit.tests.unlocked",
                      defaults: d ?? defaults)
    }


    // MARK: - The happy path


    func testDisplayPriceComesFromTheStoreNotAHardcodedString() async {
        let store = makeUnlock()
        await waitUntil("the localized price") { store.displayPrice != nil }
        // The figure lives in KitStore.storekit; the point is that it arrived
        // from StoreKit at all. Apps render this string, never a literal, so
        // that the selling price can move in App Store Connect alone.
        XCTAssertEqual(store.displayPrice, "$4.99")
    }

    // MARK: - The refusals

    func testDeclinedAskToBuyLeavesTheInstallLocked() async throws {
        session.askToBuyEnabled = true
        defer { session.askToBuyEnabled = false }

        let store = makeUnlock()
        await waitUntil("the product to load") { store.displayPrice != nil }

        let pendingOutcome = await store.purchase()
        XCTAssertEqual(pendingOutcome, .pending)
        let pending = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == Self.productID })
        try session.declineAskToBuyTransaction(identifier: pending.identifier)

        // Give the listener the same chance to react that the approval test gives it,
        // so a pass here means "it stayed locked", not "we asserted too early".
        try? await Task.sleep(nanoseconds: 750_000_000)
        await store.refresh()

        XCTAssertFalse(store.unlocked, "a declined purchase must NOT unlock")
        XCTAssertFalse(defaults.bool(forKey: "kit.tests.unlocked"),
                       "nor write the mirror — a free unlock is a revenue bug, not a nice bug")
    }

    func testASecondPurchaseWhileOneIsInFlightIsBusyNotFailed() async {
        let store = makeUnlock()
        await waitUntil("the product to load") { store.displayPrice != nil }

        async let first = store.purchase()
        // Give the first call time to take the `busy` flag before racing it.
        try? await Task.sleep(nanoseconds: 5_000_000)
        let second = await store.purchase()
        _ = await first

        // `busy` means the tap never reached StoreKit. Hosts must render it as
        // nothing, never as an error — telling a player their purchase failed
        // when it did not is how you get a one-star review and a refund.
        XCTAssertEqual(second, .busy,
                       "a double-tap is a no-op, not a failure")
    }

    // MARK: - Restore




    // MARK: - Revocation


    // MARK: - The listener


}
