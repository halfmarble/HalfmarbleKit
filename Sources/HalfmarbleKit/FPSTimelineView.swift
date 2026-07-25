import UIKit

//  An FPS timeline in the strip above the Dynamic Island: the last 60 seconds of frame
//  rate, one bucket per second. Yellow = measured FPS; green line = 60 (the gameplay
//  target); red = 30 (menus/pause idle here by design); grey = ~1 (frozen).
//
//  Ships on a three-tier ladder (FPSStrip.isEnabled):
//    dev builds   → on           (DEBUG default)
//    TestFlight   → on           (testers are collaborators; hitch screenshots are
//                                  free profiling data across devices)
//    App Store    → OFF, with a Settings toggle — customers would misread the red
//                                  line ("game only runs at 30fps!"), but Glass Box
//                                  means anyone may look under the hood, and support
//                                  can ask for a screenshot with it enabled.
//  An explicit user choice (the Settings pill) overrides the channel default on
//  every tier and persists.
//
//  A UIKIT view, deliberately NOT a node in the SpriteKit HUD overlay: the menus draw
//  UIKit chrome over the whole SCNView (the home screen's scrim gradient is fully
//  opaque across the top third), so anything inside the scene's render stack vanishes
//  the moment a menu is up. A diagnostic must outlive the thing it diagnoses — this
//  view sits above ALL of it, and re-fronts itself as new screens are presented.
//
//  Threading: tick() runs on the RENDER thread (the callback that measures frames) and
//  touches only the ring buffer. Layer/path mutation happens on MAIN, handed a snapshot
//  of the ring — the same render→main hop syncPauseUI already uses. At one redraw per
//  second the hop is noise. The GameView-side handoff (Settings toggle creating or
//  destroying the strip vs the render thread ticking it) is serialized by fpsStripLock —
//  see ensureFPSTimeline/tickFPSTimeline at the bottom of this file.
//
//  Honesty notes, because an FPS meter that lies is worse than none:
//    * Each bucket is frames ÷ wall-time over ~1s of REAL frame deltas (the render
//      loop's raw delta, not the sim's clamped dt — the clamp would hide any stall
//      longer than 50ms, which is exactly what this exists to show).
//    * The game LOCKS to 60fps (GameScene.applyPreferredFrameRate; 120 wasn't reliably
//      holdable) and drops to 30 on pause / game over / Low Power Mode. So the scale
//      top is 66: 60 rides just under the ceiling, and the 30fps states read as an
//      honest mid-strip plateau, not a fault.
//    * When rendering STOPS (opaque menus freeze the render loop on purpose), there
//      are no frames to measure. That time is drawn as a HOLE in the trace, never
//      interpolated: a gap means "nothing rendered", not "rendered slowly".
public final class FPSTimelineView: UIView {

    public static let capacity = 60                 // one bucket per second, last 60s
    public static let islandWidth: CGFloat = 126    // the Dynamic Island's width (no public API)
    /// Fixed scale, by gerard's call (auto-ranging moved the reference grid under the
    /// trace and he vetoed it): 0..66 puts green-60 near the ceiling and red-30 at
    /// mid-strip, and those lines NEVER move. Anything faster than 66 draws pinned at
    /// the top — with the 60 line fixed, "above green" is all it needs to say.
    public static let scaleTop: Float = 66

    // Per-second aggregation — render thread only.
    private var lastTick: TimeInterval = -1
    private var frames = 0
    private var span: Double = 0

    /// Ring of per-second average FPS; -1 marks a hole (rendering was stopped).
    /// `head` is the next write slot, so (head + i) % capacity reads oldest → newest.
    /// Written on the render thread; redraws receive an immutable snapshot.
    private var ring = [Float](repeating: -1, count: FPSTimelineView.capacity)
    private var head = 0

    private let backing = CAShapeLayer()
    private let area = CAShapeLayer()        // translucent yellow: the region under the trace
    private let areaMask = CAShapeLayer()    // clips that region to the pill's rounded ends
    private let line1 = CAShapeLayer()       // grey: ~1fps, the "effectively frozen" floor
    private let line30 = CAShapeLayer()      // red: the "this is a problem" floor
    private let line60 = CAShapeLayer()      // green: the target the game locks to
    private let trace = CAShapeLayer()       // yellow: measured FPS

    /// MAIN-thread copy of the last published snapshot. layoutSubviews re-maps the trace
    /// to new geometry from THIS, never from the live ring — reading the ring from main
    /// while the render thread is mid-push would be a data race.
    private var lastPublished = [Float](repeating: -1, count: FPSTimelineView.capacity)

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false     // never eat a game touch

        backing.fillColor = UIColor.black.withAlphaComponent(0.4).cgColor
        layer.addSublayer(backing)

        area.fillColor = UIColor.yellow.withAlphaComponent(0.45).cgColor
        area.strokeColor = nil
        area.mask = areaMask
        layer.addSublayer(area)

        line1.strokeColor = UIColor.gray.withAlphaComponent(0.85).cgColor
        line1.fillColor = nil
        line1.lineWidth = 1
        layer.addSublayer(line1)

        trace.strokeColor = UIColor.yellow.cgColor
        trace.fillColor = nil
        trace.lineWidth = 1.5
        trace.lineJoin = .round
        layer.addSublayer(trace)

        // The red-30 and green-60 reference lines sit ON TOP of the yellow trace + fill:
        // they are the thresholds the data is judged against, so the data must never
        // cover them — a trace hugging 60 still shows the green line through it.
        line30.strokeColor = UIColor.red.withAlphaComponent(0.85).cgColor
        line30.fillColor = nil
        line30.lineWidth = 1
        layer.addSublayer(line30)

        line60.strokeColor = UIColor.green.withAlphaComponent(0.85).cgColor
        line60.fillColor = nil
        line60.lineWidth = 1
        layer.addSublayer(line60)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    public override func layoutSubviews() {
        super.layoutSubviews()
        // Sublayers have no delegate to veto implicit actions, so path changes ANIMATE
        // by default — a 0.25s sliding gridline under a deliberately fixed scale reads
        // as data movement. Same discipline as redraw(): snap, never animate.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let pill = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).cgPath
        backing.path = pill
        areaMask.frame = bounds                  // the fill runs to the floor; the pill clips it
        areaMask.path = pill
        for (layer, fps) in [(line1, Float(1)), (line30, Float(30)), (line60, Float(60))] {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 4, y: yFor(fps)))
            p.addLine(to: CGPoint(x: bounds.width - 4, y: yFor(fps)))
            layer.path = p
        }
        CATransaction.commit()
        redraw(lastPublished)                // re-map the trace to the new geometry
    }

    /// Feed one rendered frame. RENDER thread; the only member it may touch besides
    /// the ring is the 1Hz hop to main.
    public func tick(now: TimeInterval) {
        if lastTick < 0 { lastTick = now; return }
        let dt = now - lastTick
        lastTick = now

        // Non-monotonic hiccup or duplicate timestamp: drop the sample (re-primed above).
        // Counting it would push `span` toward ≤ 0 — the accumulator then either starves
        // (no bucket for seconds of healthy rendering) or completes one at an absurd rate.
        if dt <= 0 { return }

        if dt > 0.5 {
            // Rendering was stopped (opaque menu, backgrounded) — record the hole.
            // One giant slow bucket would draw a dramatic fake dip instead.
            let holes = max(1, min(Self.capacity, Int(dt)))
            for _ in 0..<holes { push(-1) }
            frames = 0
            span = 0
            publish()
            return
        }

        frames += 1
        span += dt
        if span >= 1.0 {
            push(Float(Double(frames) / span))
            frames = 0
            span = 0
            publish()
        }
    }

    private func push(_ v: Float) {
        ring[head] = v
        head = (head + 1) % Self.capacity
    }

    /// Hand main a snapshot; never let it read the live ring. Synchronous when already
    /// on main (unit tests drive tick() from the main thread).
    private func publish() {
        let snap = (0..<Self.capacity).map { ring[(head + $0) % Self.capacity] }
        if Thread.isMainThread {
            redraw(snap)
        } else {
            DispatchQueue.main.async { [weak self] in self?.redraw(snap) }
        }
    }

    private func yFor(_ fps: Float) -> CGFloat {
        let f = max(0, min(fps, Self.scaleTop))
        // UIKit y grows DOWN: high fps = near the top edge.
        return bounds.height * CGFloat(1 - f / Self.scaleTop)
    }

    /// Rebuild the yellow polyline. Runs once per SECOND, on main.
    ///
    /// A sample with holes on BOTH sides gets a short horizontal dash instead of a lone
    /// moveTo: a bare moveTo draws no ink, so a single measured second between two
    /// render stops would otherwise be invisible.
    private func redraw(_ snap: [Float]) {
        lastPublished = snap
        let w = bounds.width - 8
        guard w > 0 else { return }
        // Split the ring into contiguous runs of MEASURED samples. The gaps between runs are
        // the holes, and both the line and the region under it have to break across them —
        // a fill that spanned a hole would claim frames that were never rendered.
        var runs: [[CGPoint]] = []
        var run: [CGPoint] = []
        for i in 0..<Self.capacity {
            let v = snap[i]
            if v < 0 {
                if !run.isEmpty { runs.append(run); run = [] }
                continue
            }
            let x = 4 + w * CGFloat(i) / CGFloat(Self.capacity - 1)
            run.append(CGPoint(x: x, y: yFor(v)))
        }
        if !run.isEmpty { runs.append(run) }

        let floor = yFor(0)                              // where the fill closes
        let path = CGMutablePath()
        let under = CGMutablePath()
        for r in runs {
            if r.count == 1 {                            // isolated sample → dash, and a sliver under it
                let p = r[0]
                path.move(to: CGPoint(x: p.x - 1.5, y: p.y))
                path.addLine(to: CGPoint(x: p.x + 1.5, y: p.y))
                under.addRect(CGRect(x: p.x - 1.5, y: p.y, width: 3, height: floor - p.y))
            } else {
                path.addLines(between: r)
                under.move(to: CGPoint(x: r[0].x, y: floor))
                for p in r { under.addLine(to: p) }
                under.addLine(to: CGPoint(x: r[r.count - 1].x, y: floor))
                under.closeSubpath()
            }
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)            // no implicit path animation
        trace.path = path
        area.path = under
        CATransaction.commit()

        // Menus/pause/game-over add whole screens of UIKit above the game view — stay
        // on top of whatever was presented since the last second.
        if let sv = superview, sv.subviews.last !== self { sv.bringSubviewToFront(self) }
    }

    // MARK: test seams
    public var t_snapshot: [Float] { (0..<Self.capacity).map { ring[(head + $0) % Self.capacity] } }
    public var t_tracePointCount: Int {
        guard let p = trace.path else { return 0 }
        var n = 0
        p.applyWithBlock { _ in n += 1 }
        return n
    }
    public var t_line1Color: CGColor? { line1.strokeColor }
    public var t_line30Color: CGColor? { line30.strokeColor }
    public var t_line60Color: CGColor? { line60.strokeColor }
    public var t_traceColor: CGColor? { trace.strokeColor }
    public var t_areaColor: CGColor? { area.fillColor }
    /// The 30/60 reference lines must render ABOVE the yellow trace and fill (they are
    /// the thresholds the data is judged against). True when the sublayer order says so.
    public var t_gridAboveTrace: Bool {
        guard let subs = layer.sublayers,
              let t = subs.firstIndex(of: trace), let a = subs.firstIndex(of: area),
              let r = subs.firstIndex(of: line30), let g = subs.firstIndex(of: line60)
        else { return false }
        return r > t && g > t && r > a && g > a
    }
    /// One closed region per run of measured samples — so this counts the runs, and a
    /// region spanning a hole would show up here as one too few.
    public var t_areaSubpathCount: Int {
        guard let p = area.path else { return 0 }
        var n = 0
        p.applyWithBlock { if $0.pointee.type == .moveToPoint { n += 1 } }
        return n
    }
    /// The lowest point the fill reaches — it must sit ON the strip's floor (0 fps),
    /// not float at the lowest sample.
    public var t_areaFloorY: CGFloat {
        guard let p = area.path else { return 0 }
        return p.boundingBoxOfPath.maxY
    }
    /// Implicit animations attached to ANY of the strip's layers (must stay empty —
    /// the grid and trace snap to new geometry, never slide).
    public var t_layerAnimationKeys: [String] {
        [backing, area, line1, line30, line60, trace].flatMap { $0.animationKeys() ?? [] }
    }
}
