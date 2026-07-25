#if DEBUG
import AVFoundation
import Foundation

/// Dev-only startup profiler: timestamps named phases from process start and
/// records render-loop frames that overrun, to hunt work that can starve the
/// audio render thread during launch → BEGIN → first wave. `buildHUD` schedules a
/// REPEATING report dump (3 s cadence, so a run cut short still leaves one) to
/// stdout + the sandbox tmp/, where `simctl launch --console-pty` / the Xcode
/// console / `simctl get_app_container … data` capture it. Active profiling
/// (sampler + dumps) stops after `windowSecs`; compiled out of release entirely.
public enum StartupProf {
    public static let t0: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    /// OPT-IN, dormant by default. Arm it with the `STARTUP_PROFILE` environment
    /// variable (Simulator: `SIMCTL_CHILD_STARTUP_PROFILE=1`; device/Xcode: a scheme
    /// env var) — or FORCE-arm from the app (StringFusor arms in DEBUG at startup:
    /// icon-tap launches can't carry env vars, and the on-device crackle hunt needed
    /// exactly that flow). Unarmed, every call here no-ops. Compiled out of release.
    nonisolated(unsafe) public static var forceEnabled = false
    private static let envArmed = ProcessInfo.processInfo.environment["STARTUP_PROFILE"] != nil
    public static var enabled: Bool { forceEnabled || envArmed }
    /// The active-profiling window from process start: the CPU/route sampler and the
    /// repeating report dumps both stop here (events plateau once the sampler stops,
    /// so re-printing past it is pure console noise). Marks still record after it.
    public static let windowSecs: Double = 90
    private static let lock = NSLock()
    private static var events: [(t: Double, name: String)] = []

    /// Timestamp a point event (thread-safe; callable from any thread).
    public static func mark(_ name: String) {
        guard enabled else { return }
        let t = CFAbsoluteTimeGetCurrent() - t0
        lock.lock(); events.append((t, name)); lock.unlock()
    }

    /// Bracket a block, recording its start time and duration.
    @discardableResult
    public static func span<T>(_ name: String, _ body: () -> T) -> T {
        guard enabled else { return body() }
        let s = CFAbsoluteTimeGetCurrent()
        let r = body()
        let ms = (CFAbsoluteTimeGetCurrent() - s) * 1000
        lock.lock(); events.append((s - t0, String(format: "%@  [%.1fms]", name, ms))); lock.unlock()
        return r
    }

    /// Increment and return a named counter (e.g. to instrument only the first N spawns).
    public static func count(_ key: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        counters[key, default: 0] += 1
        return counters[key]!
    }
    private static var counters: [String: Int] = [:]

    /// Render-loop watchdog: record any live-render gap > 25ms in the first 25s of the
    /// session — a stall long enough to threaten the audio thread's deadlines. Owns its
    /// own previous-frame timestamp, so the render loop just forwards (time, started).
    /// Render-thread only; a no-op unless armed.
    private static var lastFrameT: TimeInterval = 0
    public static func frameTick(_ time: TimeInterval, started: Bool) {
        guard enabled else { return }
        let now = CFAbsoluteTimeGetCurrent() - t0
        if lastFrameT > 0, time - lastFrameT > 0.025, now < 25 {
            mark(String(format: "frame: GAP %.1fms (%@)",
                        (time - lastFrameT) * 1000, started ? "run" : "menu"))
        }
        lastFrameT = time
    }

    /// Arm a profiling session (call once from buildHUD, main thread): prove file I/O
    /// works, start the repeating report dump (3s cadence, so a run cut short still
    /// leaves one; stops after the window, since events plateau once the sampler ends),
    /// and start the system CPU/route sampler. A no-op unless armed.
    public static func beginSession() {
        guard enabled else { return }
        write("armed at buildHUD", "startup_profile_armed.txt")   // proves profiling + file I/O
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { t in
            dump()
            if CFAbsoluteTimeGetCurrent() - t0 > windowSecs { t.invalidate() }
        }
        startCPUSampler()   // stamp system-wide CPU/route for the window (post-install storm)
    }

    public static func report() -> String {
        lock.lock(); defer { lock.unlock() }
        let lines = events.sorted { $0.t < $1.t }
            .map { String(format: "%9.1fms  %@", $0.t * 1000, $0.name) }
        return "===== STARTUP PROFILE =====\n" + lines.joined(separator: "\n")
             + "\n===== END STARTUP PROFILE ====="
    }

    /// Per-session report name: a relaunch must NEVER overwrite the previous run's
    /// evidence (it happened once — a "messed-up run" report was lost to a quick
    /// second launch). The plain name stays as a "latest session" alias.
    private static let sessionFile = String(format: "startup_profile_%d.txt",
                                            ProcessInfo.processInfo.processIdentifier)

    /// Print the report AND write it into the app sandbox (tmp/ + Documents/), where
    /// the host can read it via (`simctl get_app_container … data`) — stdout is
    /// unreliable under `simctl launch`.
    public static func dump() {
        let text = report()
        print(text)
        write(text, sessionFile)
        write(text, "startup_profile.txt")   // "latest" alias
    }

    // MARK: - System CPU sampler (makes the "post-install storm" visible)

    private static var prevTicks: (busy: Double, total: Double)?
    /// System-wide CPU busy fraction (all cores, ALL processes) since the last call —
    /// the app can't see installd/Spotlight/MTLCompilerService directly, but their
    /// load shows up here and can be correlated with what the ear hears.
    private static func cpuBusySinceLastSample() -> Double? {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size
                                          / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let busy = Double(info.cpu_ticks.0) + Double(info.cpu_ticks.1) + Double(info.cpu_ticks.3)
        let total = busy + Double(info.cpu_ticks.2)
        defer { prevTicks = (busy, total) }
        guard let p = prevTicks, total > p.total else { return nil }
        return (busy - p.busy) / (total - p.total)
    }

    /// Mark system CPU load + the audio environment (route, hw rate, IO buffer) every
    /// 2s for the first `seconds` of the session (main thread). The route/format part
    /// exists to catch SILENT mid-run shifts — a Bluetooth codec/link renegotiation or
    /// a format change that never posts a notification would show up here and nowhere
    /// else.
    /// AVAudioSession is iOS-only.
    public static func startCPUSampler(seconds: Double = StartupProf.windowSecs) {
        #if os(iOS)
        guard enabled else { return }
        _ = cpuBusySinceLastSample()                       // prime the tick baseline
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { t in
            if CFAbsoluteTimeGetCurrent() - t0 > seconds { t.invalidate(); return }
            let sess = AVAudioSession.sharedInstance()
            let route = sess.currentRoute.outputs
                .map { "\($0.portName)(\($0.portType.rawValue))" }.joined(separator: "+")
            let cpu = cpuBusySinceLastSample().map { String(format: "%.0f%%", $0 * 100) } ?? "?"
            mark(String(format: "env: cpu %@ | %@ | hw %.0fHz io %.1fms lat %.1fms",
                        cpu, route, sess.sampleRate,
                        sess.ioBufferDuration * 1000, sess.outputLatency * 1000))
        }
        #endif
    }

    /// Write a marker/report file into the sandbox tmp/ (read from the host via
    /// `simctl get_app_container … data`). Deliberately NOT Documents/: tmp is
    /// system-purged and never enters device backups, while Documents would persist
    /// the report (whose audio-route lines can carry a personal Bluetooth device
    /// name, e.g. "<name>'s AirPods") into backups for no diagnostic gain.
    public static func write(_ text: String, _ name: String) {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
        try? text.write(to: tmp, atomically: true, encoding: .utf8)
    }
}
#endif
