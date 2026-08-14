// Phase-tagged memory logging — what the process weighed, at the moment that
// matters, in a form you can read back after it died.
//
// Moved here 2026-08-14 from an app that was being jetsammed in the field and
// could not say why.
//
// WHY A LOG AND NOT A GAUGE. `PerfProbe.footprintMB()` already feeds the
// on-screen HUD, and a live gauge answers "how much NOW" — which is the wrong
// question when the device is in a pocket or a cradle and the app is killed
// while nobody is looking. What you need afterwards is which PHASE produced the
// peak: model loaded, assets decoded, first frame, first turn. That is a log,
// and it has to be written before the kill, not read off a screen after it.
//
// `phys_footprint` is the statistic to watch, and `PerfProbe` already takes it
// from the same `TASK_VM_INFO` call — this deliberately does NOT re-implement
// that. It is what jetsam actually meters, and it counts compressed pages and
// IOKit/Metal allocations that `resident_size` misses, which is usually exactly
// the gap being hunted.
//
// It prints through `print`, so `ConsoleLog` tees it into the in-app console
// and the whole trace can be read on the device with no Mac attached.
import Foundation

public enum Footprint {

    /// The process's `phys_footprint` in MB — the same statistic jetsam meters,
    /// so it is directly comparable with the `rpages` figure in a JetsamEvent
    /// report. `nil` only if the kernel call fails.
    ///
    /// Delegates to `PerfProbe`. A second copy of this mach call is precisely
    /// the drift this package exists to prevent, and it would be a copy that
    /// disagrees under memory pressure, when it matters.
    public static func mb() -> Int? {
        let v = PerfProbe.footprintMB()
        return v > 0 ? v : nil          // 0 is PerfProbe's failure sentinel
    }

    /// An extra allocator worth naming separately, if the app has one.
    ///
    /// THE KIT MUST NOT KNOW ABOUT GPU FRAMEWORKS. An app doing on-device ML
    /// (MLX, Core ML, a Metal pool) has a second accounting system, and the
    /// interesting quantity is the DIFFERENCE: an ML runtime reporting 2.2 GB
    /// inside a 5.6 GB process means the problem is NOT the ML runtime, and
    /// that subtraction is the whole diagnostic. So the app supplies a closure
    /// and the kit does the arithmetic and the formatting.
    ///
    /// Set it once at startup:
    /// ```swift
    /// Footprint.extra = { ("mlx", activeMB, peakMB) }
    /// ```
    public nonisolated(unsafe) static var extra: (() -> (name: String, active: Int, peak: Int)?)?

    /// One line, tagged so it is greppable in a console dump:
    /// `[mem] packs ready       footprint=2250 MB mlx active=2159 MB …`
    ///
    /// The phase is padded to a fixed width because these lines are READ IN
    /// COLUMNS — a dozen of them scrolling past, and the eye is looking for the
    /// number that jumped, not the label.
    public static func log(_ phase: String) {
        let foot = mb().map { "\($0) MB" } ?? "unknown"
        let padded = phase.padding(toLength: max(18, phase.count), withPad: " ",
                                   startingAt: 0)
        guard let e = extra?() else {
            print("[mem] \(padded) footprint=\(foot)")
            return
        }
        print("[mem] \(padded) footprint=\(foot) \(e.name) active=\(e.active) MB "
              + "peak=\(e.peak) MB (non-\(e.name) \((mb() ?? 0) - e.active) MB)")
    }
}
