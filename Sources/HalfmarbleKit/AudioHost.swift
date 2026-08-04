import AVFoundation
import AudioToolbox
// UnsafeMutableAudioBufferListPointer (the source node's render callback) is a
// CoreAudio overlay type: iOS re-exports it through AVFoundation, Mac Catalyst
// does not.
import CoreAudio
import os
#if canImport(UIKit)
import UIKit
#endif

//  The AVAudioEngine HOST every halfmarble app shares (2026-07-25) — extracted
//  from the two GameAudio twins (ViroFlick's, then StringFusor's fork of it),
//  which carried ~500 near-identical lines of the hardest-won audio plumbing:
//
//    · the engine graph: SFX source node + N music players → mixer → brickwall
//      peak limiter → output at the hardware format;
//    · the audio session (.playback, mixWithOthers, ~20ms IO buffer);
//    · interruption / route-change / media-services-reset recovery, plus the
//      20Hz fader that doubles as an engine WATCHDOG (a death none of the
//      discrete signals observes used to mean MINUTES of silence — the
//      watchdog restarts a down engine within ~2s);
//    · the music machinery: per-channel bundled-wav loading with live-synthesis
//      fallback, smooth 20Hz volume fades, pause-at-silence (a playing node at
//      volume 0 resamples forever), hold/duck/mode/enable state.
//
//  What stays in each app is the CONTENT: the SFX palette and its synthesis or
//  C core, the coalescing policy, the music loop renders, and the app's public
//  audio face. The host renders SFX through ONE callback and never looks
//  inside.
//
//  THREADING (inherited discipline, verbatim): `stateLock` serializes the
//  cross-thread state — the music flags written by main + render threads and
//  read by the fader, and the engine-side REFERENCES reassigned wholesale on a
//  media-services reset (an unlocked read during that swap is a torn-pointer
//  race, TSan-caught in the ancestors). Never hold the lock across an AVFAudio
//  call: nodes take AVFAudio's own locks and can block on the audio IO cycle.

/// One background-music channel: a bundled pre-rendered loop (with a
/// live-synthesis fallback), its resting volume, and when it is audible.
public struct HMMusicChannel {
    /// The bundled wav's resource name (loadBundledLoop's lookup key).
    public let bundledLoopName: String
    /// The channel's resting volume when active (before duck/aux scaling).
    public let baseVolume: Float
    /// The music-mode index this channel plays in — nil = always active
    /// (an ambience bed riding on top of whichever mode is playing).
    public let activeInMode: Int?
    /// True for a bed whose level is DRIVEN live (setAuxGain — e.g. a rumble
    /// tracking a visual): target = base × aux × ramp × duck.
    public let auxGainDriven: Bool
    /// One-time startup swell (seconds from first audible to full) — 0 = none.
    /// Smoothstepped; climbs once at launch and stays (an interruption
    /// mid-session returns instantly).
    public let startupRampSecs: Double
    /// Live synthesis when the bundled wav is missing/malformed. Runs on a
    /// background utility queue at launch.
    public let fallback: () -> AVAudioPCMBuffer

    public init(bundledLoopName: String, baseVolume: Float, activeInMode: Int?,
                auxGainDriven: Bool = false, startupRampSecs: Double = 0,
                fallback: @escaping () -> AVAudioPCMBuffer) {
        self.bundledLoopName = bundledLoopName
        self.baseVolume = baseVolume
        self.activeInMode = activeInMode
        self.auxGainDriven = auxGainDriven
        self.startupRampSecs = startupRampSecs
        self.fallback = fallback
    }
}

public final class HMAudioHost {

    // MARK: - Engine-side objects (all `var`: a media-services reset invalidates
    // every one; Apple's contract is to discard and rebuild — see
    // handleMediaServicesReset / buildEngineGraph).

    private var engine = AVAudioEngine()
    private var limiter = HMAudioHost.makeLimiter()
    private static func makeLimiter() -> AVAudioUnitEffect {
        let desc = AudioComponentDescription(componentType: kAudioUnitType_Effect,
                                             componentSubType: kAudioUnitSubType_PeakLimiter,
                                             componentManufacturer: kAudioUnitManufacturer_Apple,
                                             componentFlags: 0, componentFlagsMask: 0)
        return AVAudioUnitEffect(audioComponentDescription: desc)
    }
    private var sfxNode: AVAudioSourceNode?
    private var musicNodes: [AVAudioPlayerNode]
    private var loopBuffers: [AVAudioPCMBuffer?]

    /// The post-mixer limiter — exposed for dev taps (e.g. StringFusor's
    /// AUDIO_CAP records the engine's own mastered output from here).
    public var limiterNode: AVAudioUnitEffect { limiter }

    // MARK: - Configuration (immutable)

    private let sampleRate: Double
    private let musicFormat: AVAudioFormat
    private let channels: [HMMusicChannel]
    private let sfxRender: (UnsafeMutablePointer<Float>, UnsafeMutablePointer<Float>, Int) -> Void
    /// Flush the app's voice mixer after a media-services reset (its voices
    /// and policy history describe dead audio).
    private let onEngineReset: () -> Void
    /// Optional startup-profiler hook (the apps wire StartupProf.mark).
    private let debugMark: ((String) -> Void)?

    // MARK: - Cross-thread state (under stateLock)

    private let stateLock = OSAllocatedUnfairLock()
    private var musicMode = 0
    private var musicDucked = false
    private var musicHold = false
    private var auxGain: Float = 0
    private var _musicEnabled: Bool
    private var _sfxEnabled: Bool
    /// Fader-thread-only (no lock — only the fader touches it): seconds of
    /// AUDIBLE time accumulated for the startup ramps, capped at `rampCap`.
    private var rampProgress: Double = 0
    /// The accumulator's ceiling: the LONGEST channel ramp, so every channel's
    /// smoothstep can reach 1. The old cap of 1 s could never complete a 10 s
    /// ramp — x = min(1, 1/10) pinned the gain at smoothstep(0.1) = 0.028,
    /// ~−31 dB, forever (the 2026-07-28 finding: StringFusor's solar-wind bed
    /// was inaudible for the whole session while its isPlaying-based test
    /// stayed green). Pinned by HalfmarbleKitTests.
    private let rampCap: Double

    public var musicEnabled: Bool { stateLock.withLock { _musicEnabled } }
    public var sfxEnabled: Bool { stateLock.withLock { _sfxEnabled } }

    private var observers: [NSObjectProtocol] = []
    private var engineObserver: NSObjectProtocol?
    private var musicFader: DispatchSourceTimer?
    private var watchdogTick = 0
    /// Main-thread only: the mixer→limiter→output chain is wired for a route/format that may
    /// no longer be current (a reconnect was skipped, or a start failed against it). Makes
    /// `restartEngineIfNeeded` rewire before retrying instead of failing forever in silence.
    private var outputChainStale = false
    /// ANOTHER APP OWNS THE AUDIO. iOS raises `secondaryAudioShouldBeSilencedHint` while a
    /// foreground-eligible app (Music, Spotify, Podcasts) is playing primary audio, and the
    /// platform contract for a `.mixWithOthers` game is to drop its own MUSIC while that is
    /// true — not to lay a 24 s minor-key drone over the player's podcast. Guarded by
    /// `stateLock`: written on main from the hint notification and each configureSession(),
    /// read by the 20 Hz fader. SFX are deliberately unaffected — the game still speaks.
    private var otherAudioActive = false

    // MARK: - Init

    public init(sampleRate: Double,
                channels: [HMMusicChannel],
                sfxRender: @escaping (UnsafeMutablePointer<Float>, UnsafeMutablePointer<Float>, Int) -> Void,
                onEngineReset: @escaping () -> Void,
                debugMark: ((String) -> Void)? = nil) {
        self.sampleRate = sampleRate
        self.musicFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        self.channels = channels
        self.rampCap = Self.longestRamp(of: channels)
        self.sfxRender = sfxRender
        self.onEngineReset = onEngineReset
        self.debugMark = debugMark
        let d = UserDefaults.standard
        _musicEnabled = d.object(forKey: HMDefaultsKeys.musicEnabled) == nil
            || d.bool(forKey: HMDefaultsKeys.musicEnabled)
        _sfxEnabled = d.object(forKey: HMDefaultsKeys.sfxEnabled) == nil
            || d.bool(forKey: HMDefaultsKeys.sfxEnabled)
        musicNodes = channels.map { _ in AVAudioPlayerNode() }
        loopBuffers = channels.map { _ in nil }

        configureSession()
        debugMark?("audio: init begin (session configured)")
        buildEngineGraph()
        startMusicFader()
        observeAudioLifecycle()
        #if os(iOS)
        if let mark = debugMark {
            let sess = AVAudioSession.sharedInstance()
            mark(String(format: "audio: engine running (hw %.0fHz, io buffer %.1fms)",
                        sess.sampleRate, sess.ioBufferDuration * 1000))
        }
        #endif
        // The music loops LOAD from bundled pre-rendered WAVs. Synthesizing them
        // live costs seconds of on-device CPU that overlapped launch and starved
        // the audio IO thread → sustained crackle on first run (both ancestors'
        // crackle investigations). Loading takes ~tens of ms; a missing/corrupt
        // resource falls back to live synthesis. Off the main thread either way;
        // the schedule+play hops to main so the kept buffers and node schedules
        // have one home thread (shared with interruption recovery).
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let loops = self.channels.map { ch in
                self.loadBundledLoop(ch.bundledLoopName) ?? ch.fallback()
            }
            DispatchQueue.main.async {
                self.debugMark?("audio: music loops scheduled")
                self.loopBuffers = loops
                for (node, loop) in zip(self.musicNodes, loops) {
                    node.scheduleBuffer(loop, at: nil, options: .loops, completionHandler: nil)
                }
                guard self.engine.isRunning else { return }   // interrupted mid-launch: recovery replays
                self.musicNodes.forEach { $0.play() }
            }
        }
    }

    deinit {
        musicFader?.cancel()   // else the 20 Hz timer keeps firing (no-op via weak self) forever
        observers.forEach(NotificationCenter.default.removeObserver)
        if let o = engineObserver { NotificationCenter.default.removeObserver(o) }
    }

    // MARK: - State control

    /// Held during a launch warm-up burst (shader compiles saturate CPU and
    /// audio played through it can crackle) — the music fade-in waits.
    public func setMusicHold(_ hold: Bool) { stateLock.withLock { musicHold = hold } }
    /// Mode/duck/enable are written from the main and render threads and read
    /// by the fader tick — worst case is one 50ms tick of staleness.
    public func setMusicMode(_ mode: Int) { stateLock.withLock { musicMode = mode } }
    public func duckMusic(_ ducked: Bool) { stateLock.withLock { musicDucked = ducked } }
    public func setMusicEnabled(_ on: Bool) {
        stateLock.withLock { _musicEnabled = on }
        UserDefaults.standard.set(on, forKey: HMDefaultsKeys.musicEnabled)
    }
    public func setSFXEnabled(_ on: Bool) {
        stateLock.withLock { _sfxEnabled = on }
        UserDefaults.standard.set(on, forKey: HMDefaultsKeys.sfxEnabled)
    }
    /// Drive an aux-gain channel's swell (0 = silent … 1 = full), e.g. a
    /// rumble bed tracking a visual each frame. Cheap: one locked Float write.
    public func setAuxGain(_ g: Float) {
        stateLock.withLock { auxGain = g < 0 ? 0 : (g > 1 ? 1 : g) }
    }

    // MARK: - The 20Hz fader + engine watchdog

    private func startMusicFader() {
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "halfmarble.music.fade"))
        t.schedule(deadline: .now() + 0.05, repeating: 0.05)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.watchdogTick += 1
            // One locked snapshot — flags AND the engine-side references (see
            // the threading essay in the header).
            let (duck, audible, mode, aux, engine, nodes):
                (Float, Bool, Int, Float, AVAudioEngine, [AVAudioPlayerNode]) = self.stateLock.withLock {
                (self.musicDucked ? 0.35 : 1.0,
                 // `otherAudioActive` gates the MUSIC only — it rides here rather than on
                 // each channel's target so the existing fade-to-silence-then-pause path
                 // does the work, and the loops resume mid-bar when the podcast stops.
                 self._musicEnabled && !self.musicHold && !self.otherAudioActive,
                 self.musicMode,
                 self.auxGain,
                 self.engine, self.musicNodes)
            }
            if self.watchdogTick % 40 == 0, !engine.isRunning {   // every 2s
                self.debugMark?("audio: WATCHDOG — engine down, restarting")
                DispatchQueue.main.async { self.restartEngineIfNeeded() }
            }
            // Seconds of audible time, capped at the LONGEST channel ramp (a
            // cap of 1 s could never complete a 10 s ramp — see rampCap).
            if audible { self.rampProgress = min(self.rampCap, self.rampProgress + 0.05) }
            for (i, ch) in self.channels.enumerated() {
                guard i < nodes.count else { break }
                let active = audible && (ch.activeInMode == nil || ch.activeInMode == mode)
                var target: Float = active ? ch.baseVolume * duck : 0
                if ch.auxGainDriven { target *= aux }
                if ch.startupRampSecs > 0 {
                    target *= Self.startupRampGain(audibleSecs: self.rampProgress,
                                                   rampSecs: ch.startupRampSecs)
                }
                self.fade(nodes[i], toward: target, engine: engine)
            }
        }
        t.resume()
        musicFader = t
    }

    /// The startup-ramp gain: smoothstep of audible-time over the channel's
    /// ramp length. Pure and public so the kit's tests pin the curve — and its
    /// interplay with `longestRamp` (the accumulator's cap must reach every
    /// channel's full ramp; the 1 s cap that couldn't was the 2026-07-28
    /// inaudible-solar-wind finding) — without running the 20 Hz fader.
    public static func startupRampGain(audibleSecs: Double, rampSecs: Double) -> Float {
        guard rampSecs > 0 else { return 1 }
        let x = Float(min(1, audibleSecs / rampSecs))
        return x * x * (3 - 2 * x)                                // smoothstep
    }

    /// What `rampProgress` must be allowed to reach: the longest channel ramp
    /// (never below 1 s, the old cap, so a no-ramp host keeps its old shape).
    public static func longestRamp(of channels: [HMMusicChannel]) -> Double {
        max(1, channels.map(\.startupRampSecs).max() ?? 0)
    }

    /// Ease one music player toward its target volume — and PAUSE the node once
    /// it has faded to silence: a playing node keeps the audio render thread
    /// pulling and resampling its loop forever, even at volume 0. Resumes
    /// mid-loop on the next fade-in — it's ambient, the seam is inaudible.
    ///
    /// ACCEPTED TOCTOU (2026-07-26 audit; inherited from both ancestors): the
    /// engine can stop between the `engine.isRunning` check and `play()` — an
    /// interruption landing inside a 20 Hz tick's microsecond window — and
    /// `play()` on a stopped engine raises. Kept as-is deliberately: the
    /// window is vanishingly small, both ancestors shipped it for weeks, and
    /// exception-guarding or hopping play() to main costs more than the risk.
    /// Do not "simplify" the isRunning guard away — it is what makes the
    /// window microseconds instead of the whole interruption.
    /// Pinned app-side (fade→pause→resume + recovery): ViroFlick's
    /// GameEnergyTests and StringFusor's GameAudioHostTests — the twin suites.
    private func fade(_ node: AVAudioPlayerNode, toward target: Float, engine: AVAudioEngine) {
        if target > 0, !node.isPlaying, engine.isRunning { node.play() }
        node.volume += (target - node.volume) * 0.12
        if target == 0, node.volume < 0.004 {
            node.volume = 0
            if node.isPlaying { node.pause() }
        }
    }

    // MARK: - Graph build / recovery (the hardest-won code in either ancestor —
    // preserved verbatim in structure; see their headers for the war stories)

    private func buildEngineGraph() {
        let mixer = engine.mainMixerNode
        mixer.outputVolume = 0.7
        // Brickwall peak limiter AFTER the mixer — it runs at the hardware rate
        // (past the resample), so it catches BOTH coincident-SFX sums AND the
        // resample's true-peak overshoot before they reach the DAC.
        engine.attach(limiter)
        configureLimiter()
        connectOutputChain()
        // The SFX source node: the engine pulls the app's render every quantum
        // at the palette's native rate and converts to hardware rate itself. It
        // renders CONTINUOUSLY while the engine runs (an empty mix is two
        // memsets — noise), which doubles as converter/page-fault warm-up.
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let render = sfxRender
        let node = AVAudioSourceNode(format: fmt) { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard abl.count >= 2,
                  let l = abl[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = abl[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            render(l, r, Int(frameCount))
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: mixer, format: fmt)
        sfxNode = node
        for n in musicNodes {
            engine.attach(n)
            engine.connect(n, to: mixer, format: musicFormat)
            n.volume = 0                                  // the fader raises them
        }
        engine.prepare()
        try? engine.start()
        observeEngine()                // (re)bind the config observer to THIS engine
    }

    /// The config-change observer is bound to a SPECIFIC engine object —
    /// re-registered on every (re)build, else a reset would leave it watching a
    /// dead engine.
    private func observeEngine() {
        if let o = engineObserver { NotificationCenter.default.removeObserver(o) }
        engineObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.debugMark?("audio: engine configuration change")
            self?.handleConfigurationChange()
        }
    }

    /// Full rebuild after a media-services reset (mediaserverd crash/restart):
    /// every engine-side object we hold is invalid; discard and rebuild. The
    /// music re-schedules from the kept loops and the fader brings the active
    /// mode back in. Main thread only.
    private func handleMediaServicesReset() {
        debugMark?("audio: MEDIA SERVICES RESET — rebuilding the engine")
        engine.stop()
        // Build the replacements first, then swap under stateLock: the fader
        // snapshots these references (torn-pointer race otherwise). No AVFAudio
        // call runs while the lock is held.
        let newEngine = AVAudioEngine()
        let newNodes = channels.map { _ in AVAudioPlayerNode() }
        // Hand the OLD engine/nodes out of the critical section before releasing them. The
        // swap alone would drop their last reference INSIDE the lock, and a dead engine's
        // dealloc tears down an AUGraph whose server is gone — an AVFAudio call that can
        // block on XPC, which is exactly what the header rule ("never hold the lock across
        // an AVFAudio call") and this block's own "no AVFAudio call runs while the lock is
        // held" comment forbid. The fader's next tick would stall on stateLock for that
        // whole duration, including the watchdog that is the last line of defence here.
        let (oldEngine, oldNodes): (AVAudioEngine, [AVAudioPlayerNode]) = stateLock.withLock {
            let e = engine, n = musicNodes
            engine = newEngine
            musicNodes = newNodes
            return (e, n)
        }
        withExtendedLifetime((oldEngine, oldNodes)) {}   // release out here, lock not held
        limiter = Self.makeLimiter()
        sfxNode = nil
        onEngineReset()                // app flushes its voices + policy history
        configureSession()             // the reset tears the session down too
        buildEngineGraph()
        for (node, loop) in zip(musicNodes, loopBuffers) {
            guard let loop else { continue }
            node.scheduleBuffer(loop, at: nil, options: .loops, completionHandler: nil)
        }
    }

    /// Everything that can silence the engine, and the signal that revives it —
    /// see the ancestors' essays: interruption `.ended`, `didBecomeActive` (the
    /// answered-call path), and the engine-bound configuration change (route
    /// changes fire with NO interruption and NO foreground event).
    private func observeAudioLifecycle() {
        #if os(iOS)
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification,
                                        object: AVAudioSession.sharedInstance(),
                                        queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            self?.debugMark?("audio: interruption \(type == .began ? "BEGAN" : type == .ended ? "ended" : "?")")
            guard type == .ended else { return }
            self?.restartEngineIfNeeded()
        })
        observers.append(nc.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            self?.restartEngineIfNeeded()
        })
        observers.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                                        object: AVAudioSession.sharedInstance(),
                                        queue: .main) { [weak self] _ in
            self?.handleMediaServicesReset()
        })
        // Another app started or stopped playing primary audio (Music, Spotify, Podcasts).
        // Registered UNCONDITIONALLY — it drives real behaviour now, not just a debug line.
        observers.append(nc.addObserver(forName: AVAudioSession.silenceSecondaryAudioHintNotification,
                                        object: AVAudioSession.sharedInstance(),
                                        queue: .main) { [weak self] note in
            guard let self else { return }
            let type = (note.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt)
                .flatMap(AVAudioSession.SilenceSecondaryAudioHintType.init(rawValue:))
            let silence = (type == .begin)
            self.debugMark?("audio: secondary-audio hint \(silence ? "BEGIN (other app playing)" : "end")")
            self.stateLock.withLock { self.otherAudioActive = silence }
        })
        // Route changes: the observer is registered unconditionally too (the log stays
        // behind debugMark). Yanking headphones does not stop the engine, so there is
        // nothing to repair here — this is the diagnostic trail for the route-dependent
        // format bugs that connectOutputChain now guards against.
        observers.append(nc.addObserver(forName: AVAudioSession.routeChangeNotification,
                                        object: AVAudioSession.sharedInstance(),
                                        queue: .main) { [weak self] note in
            guard let mark = self?.debugMark else { return }
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            let outs = AVAudioSession.sharedInstance().currentRoute.outputs
                .map { $0.portType.rawValue }.joined(separator: "+")
            mark("audio: route change reason=\(reason.map { String(describing: $0) } ?? "?") → \(outs)")
        })
        #endif
    }

    /// (Re)connect mixer → limiter → output at the CURRENT hardware format —
    /// a new route can carry a different sample rate that invalidates the old
    /// format-pinned connections.
    /// Returns false when the hardware format was unusable and nothing was reconnected —
    /// the caller must then leave `outputChainStale` set so a later signal retries.
    ///
    /// THE FORMAT MUST BE VALIDATED. `engine.connect(_:to:format:)` raises an uncatchable
    /// Core Audio exception on a 0 Hz / 0-channel format ("required condition is false:
    /// IsFormatSampleRateAndChannelCountValid"), and `outputNode.inputFormat` returns exactly
    /// that when the session is inactive or the engine's I/O is torn down — which is the
    /// state a configuration change can arrive in (a route change landing during an
    /// interruption, or a config change racing a media-services reset, where the two
    /// notifications have no defined order). A skipped reconnect is recoverable; a SIGABRT
    /// takes the run and its unbanked score with it.
    @discardableResult
    private func connectOutputChain() -> Bool {
        let hwFormat = engine.outputNode.inputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            debugMark?("audio: skipped reconnect — invalid hw format \(hwFormat)")
            outputChainStale = true
            return false
        }
        engine.connect(engine.mainMixerNode, to: limiter, format: hwFormat)
        engine.connect(limiter, to: engine.outputNode, format: hwFormat)
        outputChainStale = false
        return true
    }

    private func handleConfigurationChange() {
        engine.stop()                 // normalize so the reconnect is safe
        // Reactivate BEFORE sampling the format: every other recovery path already runs
        // configureSession() first (init, and handleMediaServicesReset), and reading the
        // format off an inactive session is what yields the invalid/stale value above.
        configureSession()
        connectOutputChain()
        restartEngineIfNeeded()
    }

    /// Reactivate the session, restart the engine, and put every node back to
    /// work. Idempotent — a no-op while the engine is running. Main thread only.
    /// (The ancestors' restart skipped their aux bed's reschedule — an
    /// oversight; ALL channels reschedule here.)
    private func restartEngineIfNeeded() {
        guard !engine.isRunning else { return }
        configureSession()
        // SELF-HEALING. If a reconnect was ever skipped (invalid format) or a start failed
        // against a stale format-pinned chain, the graph is wired for a route that no longer
        // exists and `engine.start()` will keep failing — silently, because the `try?` below
        // swallows it. Without this retry the 2 s watchdog would re-enter here forever and
        // the game stays silent for the rest of the session with no crash and no log.
        if outputChainStale { connectOutputChain() }
        engine.prepare()
        guard (try? engine.start()) != nil else {            // still interrupted — the next signal retries
            outputChainStale = true                          // …and it will rewire before trying again
            return
        }
        for (node, loop) in zip(musicNodes, loopBuffers) {
            guard let loop else { continue }                 // load still running — it schedules itself
            node.stop()
            node.scheduleBuffer(loop, at: nil, options: .loops, completionHandler: nil)
        }
    }

    private func configureSession() {
        #if os(iOS)
        // .playback so SFX are audible regardless of the ring/silent switch;
        // mixWithOthers stays polite to any background audio. ~20ms IO buffer
        // doubles the underrun headroom against CPU storms for an
        // imperceptible latency cost.
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, options: [.mixWithOthers])
        try? s.setPreferredIOBufferDuration(0.02)
        try? s.setActive(true)
        // Sample the hint here too, not only from its notification: the app can launch with
        // another app's audio ALREADY playing, in which case no notification ever arrives.
        let hint = s.secondaryAudioShouldBeSilencedHint
        stateLock.withLock { otherAudioActive = hint }
        #endif
    }

    /// Read a bundled pre-rendered music loop into the stereo music format.
    /// Strict about format: a wrong-rate/channel export returns nil (→ live
    /// synthesis) rather than sneaking a per-frame resample into the render path.
    public func loadBundledLoop(_ name: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let file = try? AVAudioFile(forReading: url),
              file.processingFormat.sampleRate == musicFormat.sampleRate,
              file.processingFormat.channelCount == musicFormat.channelCount,
              file.length > 0,
              let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                         frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buf)) != nil,
              buf.frameLength == AVAudioFrameCount(file.length)
        else { return nil }
        return buf
    }

    /// Fast limiter attack (~2ms): the default ~12ms lets a coincident-SFX
    /// sum's leading transient through as a clip-crackle on the speaker's DAC.
    private func configureLimiter() {
        let au = limiter.audioUnit
        AudioUnitSetParameter(au, kLimiterParam_AttackTime, kAudioUnitScope_Global, 0, 0.002, 0)
        AudioUnitSetParameter(au, kLimiterParam_DecayTime,  kAudioUnitScope_Global, 0, 0.050, 0)
    }

    // MARK: - The policy clock

    /// Monotonic host seconds — the clock SFX triggers are stamped with (the
    /// portable mixers take plain seconds so any port passes its own clock).
    public static func monotonicNow() -> Double {
        AVAudioTime.seconds(forHostTime: mach_absolute_time())
    }

    #if DEBUG
    /// Test seam: coalescing-policy tests drive the throttle/cap windows
    /// deterministically.
    public var t_nowOverride: (() -> Double)?
    #endif
    public func policyNow() -> Double {
        #if DEBUG
        if let now = t_nowOverride { return now() }
        #endif
        return Self.monotonicNow()
    }

    // MARK: - Test seams (the energy/interruption tests both apps carry)

    #if DEBUG
    public func t_channelPlaying(_ i: Int) -> Bool { musicNodes[i].isPlaying }
    /// The channel's CURRENT fader volume. Prefer this over t_channelPlaying when
    /// the question is "was this audible?": scheduleAndPlay play()s every node at
    /// volume 0 and lets the fader pause the inactive ones a tick later, so
    /// `isPlaying` is transiently true for EVERY channel at launch regardless of
    /// mode or hold — a test built on it is inherently racy. Volume has no such
    /// transient: a held or out-of-mode channel never leaves 0.
    public func t_channelVolume(_ i: Int) -> Float { musicNodes[i].volume }
    public var t_engineRunning: Bool { engine.isRunning }
    public func t_stopEngine() { engine.stop() }   // what the system does when a call arrives
    /// Post the real configuration-change notification against the real engine,
    /// exercising the full observer→reconnect→restart path.
    public func t_postConfigurationChange() {
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: engine)
    }
    #endif
}
