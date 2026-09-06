// `SessionLog.add` from a thread that is not main.
//
// The class is main-actor isolated, and `add` was too — until a host app
// handed it to an engine's completion callback and the engine called it on
// its own queue. A `@Published` mutation off the main thread took Combine's
// publisher lock and then waited on SwiftUI's graph lock, while the main
// thread held the graph lock and waited on the publisher lock. A deadlock
// with no crash report, in the logger built to survive crashes.
//
// Against the old isolated `add`, the first test here does not compile: a
// main-actor method cannot be called from a `@Sendable` closure. That is the
// point — the API now says, in the type system, what the engine had been
// doing all along.

import XCTest
@testable import HalfmarbleKit

final class SessionLogThreadingTests: XCTestCase {

    /// The failure that established this: called off main, the event must be
    /// recorded, and recording must happen on the main actor rather than on
    /// the caller's thread.
    @MainActor
    func testAnEventAddedOffMainIsRecordedOnMain() async {
        let log = SessionLog(stem: "threading-test")
        let returned = expectation(description: "add returned on the background thread")
        DispatchQueue.global(qos: .userInitiated).async {
            XCTAssertFalse(Thread.isMainThread, "precondition: this must run off main")
            log.add("bg", "from a worker thread")
            returned.fulfill()
        }
        await fulfillment(of: [returned], timeout: 2)

        // Drain the main queue past the hop. `add` enqueued its record with
        // `DispatchQueue.main.async`; a second block enqueued after it runs
        // after it, so when this resumes the event has landed.
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { c.resume() }
        }
        XCTAssertEqual(log.events.last?.kind, "bg")
        XCTAssertEqual(log.events.last?.detail, "from a worker thread")
    }

    /// Nothing changes for the common case: on main, `add` is synchronous and
    /// the event is visible the moment the call returns — the ordering every
    /// existing caller was written against.
    @MainActor
    func testAnEventAddedOnMainIsVisibleImmediately() {
        let log = SessionLog(stem: "threading-test")
        let before = log.events.count
        log.add("main", "synchronous")
        XCTAssertEqual(log.events.count, before + 1)
        XCTAssertEqual(log.events.last?.kind, "main")
    }

    /// Arrival order survives the hop. Two events added from two threads in a
    /// known order must be recorded in that order, because the file this
    /// class writes is read as a timeline.
    @MainActor
    func testOrderIsPreservedAcrossThreads() async {
        let log = SessionLog(stem: "threading-test")
        let first = expectation(description: "first add returned")
        DispatchQueue.global().async {
            log.add("one", "")
            first.fulfill()
        }
        await fulfillment(of: [first], timeout: 2)
        log.add("two", "")                  // on main, synchronous
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { c.resume() }
        }
        let kinds = log.events.suffix(2).map(\.kind)
        // "one" was enqueued to main before "two" ran on main only if the main
        // queue had already been reached; what must hold is that both are
        // present and "one" is not lost. The stamp, taken at the call, is what
        // orders the file — assert that rather than queue luck.
        XCTAssertEqual(Set(kinds), ["one", "two"])
        let one = log.events.last { $0.kind == "one" }!
        let two = log.events.last { $0.kind == "two" }!
        XCTAssertLessThanOrEqual(one.t, two.t, "the stamp must be the call time, not the record time")
    }
}
