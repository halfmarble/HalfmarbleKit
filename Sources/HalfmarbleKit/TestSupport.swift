import Foundation

//  Test support shared by the app test suites (2026-07-26) — extracted from
//  the twins both apps hand-rolled: ViroFlick's DefaultsGuard (TestWorld) and
//  the run-loop poll() pump (GameEnergyTests / GameAudioHostTests).
//
//  Foundation-only ON PURPOSE: no XCTest import, so it lives in the library
//  target next to the kit's other dev machinery (StartupProf, the leak
//  harness) and app-hosted test bundles just call it. Nothing here runs
//  unless called — inert in a shipping binary.

/// Snapshot a fixed set of UserDefaults keys — plus optional PREFIX families
/// (e.g. a per-case `bestScore.` namespace) — and put every one of them back
/// on `restore()`. Keys a test CREATED inside a guarded prefix family are
/// removed, so a run leaves the host app container exactly as it found it.
///
/// The apps wrap this with their own key lists (ViroFlick's `DefaultsGuard`
/// stays the name its ~16 suites install); any new persisted key must be
/// added to the wrapping app's list or tests leak state into the dev install.
public final class HMDefaultsGuard {
    private let prefixes: [String]
    private var saved: [String: Any?] = [:]

    public init(keys: [String], prefixes: [String] = []) {
        self.prefixes = prefixes
        let d = UserDefaults.standard
        var all = keys
        if !prefixes.isEmpty {
            all += d.dictionaryRepresentation().keys.filter { k in
                prefixes.contains { k.hasPrefix($0) }
            }
        }
        for k in all { saved[k] = d.object(forKey: k) }
    }

    public func restore() {
        let d = UserDefaults.standard
        // Keys born inside a guarded prefix family since the snapshot → drop.
        for k in d.dictionaryRepresentation().keys
        where prefixes.contains(where: { k.hasPrefix($0) }) && saved.index(forKey: k) == nil {
            d.removeObject(forKey: k)
        }
        for (k, v) in saved {
            if let v { d.set(v, forKey: k) } else { d.removeObject(forKey: k) }
        }
    }
}

public enum HMTest {
    /// Spin the CURRENT run loop until `cond` holds or the deadline passes —
    /// the standard wait for machinery that delivers on main (the audio host's
    /// recovery observers, async schedule + fade-in) while a test occupies the
    /// main thread. Returns the final verdict so callers can assert on it.
    @discardableResult
    public static func poll(_ deadline: TimeInterval, until cond: () -> Bool) -> Bool {
        let end = Date(timeIntervalSinceNow: deadline)
        while Date() < end {
            if cond() { return true }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        return cond()
    }
}
