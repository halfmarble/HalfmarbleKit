import XCTest

//  Shared test harnesses (2026-07-25). A separate PRODUCT on purpose: this
//  target imports XCTest, so only TEST targets may depend on it — never apps.

public enum HMLeakCheck {
    /// Assert that `make()`'s instance deallocates once released — the pattern
    /// that caught GameAudio's fader/closure retain cycles in both games.
    /// Generous timeout on purpose: legitimate background work (e.g. a music
    /// loop mid-synthesis) holds self while it runs, and under full-suite CPU
    /// contention that can be slow — a REAL cycle never dies, so it still
    /// fails. Exits the instant the instance deallocates.
    public static func assertDeallocates<T: AnyObject>(
        timeout: TimeInterval = 45,
        _ message: @autoclosure () -> String = "instance leaked",
        file: StaticString = #filePath, line: UInt = #line,
        make: () -> T
    ) {
        weak var leaked: T?
        autoreleasepool {
            let obj = make()
            leaked = obj
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))   // let timers/async work start
        }
        let deadline = Date(timeIntervalSinceNow: timeout)
        while leaked != nil && Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        }
        XCTAssertNil(leaked, message(), file: file, line: line)
    }
}
