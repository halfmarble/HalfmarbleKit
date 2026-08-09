import UIKit

//  The halfmarble menu-button family — ported from ViroFlick's GameView+MenuKit
//  so every app draws the SAME buttons (gerard, 2026-07-25). Two shapes:
//
//    PILL  — a white SF Symbol + white outlined text on a near-opaque dark
//            capsule (Apple's own GameKit-banner answer to "chrome over an app
//            you have never seen": commit to a dark pill, don't negotiate).
//    CTA   — the big translucent capsule (ENTER CLINIC / ENTER REACTOR /
//            BEGIN): AvenirNext-Heavy, black-outlined white title, thin white
//            border, and the breathing pulse.
//
//  Both get the shared press feedback: a quick scale-in + darkened title while
//  held, and the tremor tap-debounce (accessibility — the first tap of a
//  tremor burst registers, the after-shocks are dropped).

public enum HMMenu {

    // MARK: Shared geometry (the cross-app constants — matching literals in two
    // apps is how buttons drift; they live here so they can't).

    /// The primary CTA: one size everywhere.
    public static let ctaButtonSize = CGSize(width: 240, height: 54)
    /// Gap from the screen bottom to the CTA's bottom edge (tall phones).
    public static let ctaBottomGap: CGFloat = 66
    /// How far below the CTA the "v… (b…)" version stamp sits (tall phones).
    public static let versionStampGap: CGFloat = 14
    /// The action-pill height (tall phones; compact uses 34).
    public static let pillHeight: CGFloat = 38

    // MARK: Tremor debounce (shared by every kit button)

    /// One full period of a 5 Hz Parkinsonian rest tremor (1 / 5 Hz = 0.20 s;
    /// 5 Hz is the middle of the ~4–6 Hz band) — wide enough to swallow the
    /// fastest same-run tremor bounce, short enough that a deliberate re-press
    /// still registers. The SAME tuned constant StringFusor's in-game commit
    /// controls use (its tremor-debounce commit grounds the rationale); the
    /// old 0.25 here was the untuned legacy value with a mislabelled comment.
    ///
    /// KEEP THIS A CONSTANT — do not expose it as a user setting. The value is
    /// *derived* (one period of the tremor it filters), not a preference, and a
    /// slider invites numbers with no physiology behind them: too short filters
    /// nothing, too long eats deliberate re-presses. The derivation is the
    /// feature. See PRIOR_ART_TREMOR_DEBOUNCE.md for the arithmetic.
    public static let menuTapCooldown: TimeInterval = 0.20
    nonisolated(unsafe) private static var lastMenuTapDown: TimeInterval = -1

    /// Leading-edge throttle: true — and arms the cooldown — if a menu tap at
    /// `now` should be honored; false if it lands within the cooldown of the
    /// last accepted tap.
    public static func acceptMenuTap(now: TimeInterval = CACurrentMediaTime()) -> Bool {
        if now - lastMenuTapDown < menuTapCooldown { return false }
        lastMenuTapDown = now
        return true
    }

    /// Test seam: the debounce state is process-global (one thumb, one
    /// cooldown), which would leak between unit tests — reset it explicitly.
    public static func resetMenuTapDebounce() { lastMenuTapDown = -1 }

    /// The click every kit button plays on an ACCEPTED tap — install once per
    /// app (StringFusor: `{ audio.play(.uiTap) }`). Nil = silent buttons.
    /// ViroFlick deliberately does NOT install it: its button handlers already
    /// play their own uiTap, and the hook would double-fire.
    nonisolated(unsafe) public static var onTap: (() -> Void)?

    // MARK: Builders

    /// The pill's SF Symbol, tinted white and given a black outline.
    public static func pillSymbol(_ symbol: String) -> UIImage? {
        guard !symbol.isEmpty else { return nil }
        let cfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        return UIImage(systemName: symbol, withConfiguration: cfg)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
            .outlined(width: 1.5)
    }

    /// A flat, uniform action pill — white SF Symbol + white outlined text on a
    /// near-opaque dark capsule.
    public static func makePill(symbol: String, title: String,
                                height: CGFloat = HMMenu.pillHeight) -> UIButton {
        let b = UIButton(type: .system)
        var cfg = UIButton.Configuration.plain()
        cfg.image = pillSymbol(symbol)
        cfg.title = title
        cfg.imagePadding = 6
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        cfg.baseForegroundColor = .white
        // The transformer survives later `configuration.title` mutations, so the
        // stroke lives here rather than in an attributedTitle.
        cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { c in
            var m = c
            m.font = UIFont(name: "AvenirNext-Bold", size: 14) ?? .boldSystemFont(ofSize: 14)
            m.strokeColor = Outline.color
            m.strokeWidth = -3.0            // negative → fill + outline
            return m
        }
        var bg = UIBackgroundConfiguration.clear()
        // 0.75 follows Apple's GameKit banners: near-opaque dark, not a polite tint.
        bg.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        bg.cornerRadius = height / 2
        bg.strokeColor = UIColor.white.withAlphaComponent(0.3)
        bg.strokeWidth = 1.5
        cfg.background = bg
        b.configuration = cfg
        // ONE motion per press, not three (gerard: the pill "fluttered"): a
        // configuration button re-applies its whole configuration on every
        // state change — UIKit's own highlight dim stacking on top of the
        // press feedback's darken + scale. Freeze the automatic updates; the
        // kit's press feedback is the single source of touch response.
        // (Manual `configuration?.x = y` mutations — the toggles — still
        // apply immediately; only STATE-driven re-renders are silenced.)
        b.automaticallyUpdatesConfiguration = false
        addPressFeedback(to: b)
        return b
    }

    /// A text CTA button (BEGIN / ENTER CLINIC / ENTER REACTOR / DONE / buy…):
    /// the translucent capsule. Caller sets the frame + target.
    public static func makeActionButton(_ title: String, fontSize: CGFloat = 25,
                                        height: CGFloat = HMMenu.ctaButtonSize.height,
                                        bgAlpha: CGFloat = 0.13,
                                        borderAlpha: CGFloat = 0.55) -> UIButton {
        let b = UIButton(type: .system)
        let font = UIFont(name: "AvenirNext-Heavy", size: fontSize)
            ?? .systemFont(ofSize: fontSize, weight: .heavy)
        b.titleLabel?.font = font
        b.titleLabel?.adjustsFontSizeToFitWidth = true
        b.titleLabel?.minimumScaleFactor = 0.7
        // Both: setTitleColor keeps buttonForeground() able to read the resting color,
        // and the attributed title carries the black outline.
        b.setTitleColor(.white, for: .normal)
        b.setAttributedTitle(Outline.string(title, font: font, color: .white, alignment: .center),
                             for: .normal)
        b.backgroundColor = UIColor.white.withAlphaComponent(bgAlpha)
        b.layer.cornerRadius = height / 2
        b.layer.borderWidth = 1.5
        b.layer.borderColor = UIColor.white.withAlphaComponent(borderAlpha).cgColor
        addPressFeedback(to: b)
        return b
    }

    // MARK: Toggle pills

    /// A settings toggle's title alpha, ON and OFF (2026-08-09). The pair is the
    /// house answer to "how does a pill show its own state": the label stays put
    /// and the whole pill dims, so the row never reflows and the OFF state reads
    /// at a glance without a second glyph or a switch control. ViroFlick had this
    /// literal pair written out five times in one file.
    ///
    /// 0.4, not lower: the OFF title must still be legible — a toggle you cannot
    /// read is a toggle you cannot find your way back to.
    public static let toggleOnAlpha: CGFloat = 0.9
    public static let toggleOffAlpha: CGFloat = 0.4

    /// Point a toggle pill at its current state: swap the title and dim it.
    ///
    /// Mutating `configuration` directly is deliberate — `makePill` freezes
    /// automatic configuration updates (see the comment there), so a manual
    /// assignment is what actually re-renders. A plain `.system` button without a
    /// configuration falls back to `setButtonForeground`, so callers do not have
    /// to know which shape they were handed.
    public static func styleToggle(_ b: UIButton, on: Bool,
                                   onTitle: String, offTitle: String) {
        let color = UIColor.white.withAlphaComponent(on ? toggleOnAlpha : toggleOffAlpha)
        guard b.configuration != nil else {
            b.setTitle(on ? onTitle : offTitle, for: .normal)
            setButtonForeground(b, color)
            return
        }
        b.configuration?.title = on ? onTitle : offTitle
        b.configuration?.baseForegroundColor = color
    }

    /// The "new here?  start with  [symbol] LABEL" coaching hint — ViroFlick's
    /// makeTextbookHint, generalized: dim Medium-12 text with the SF Symbol
    /// outlined, tinted the same dim color, and centered on the cap height.
    public static func hintString(_ prefix: String, symbol: String, suffix: String,
                                  fontSize: CGFloat = 12,
                                  color: UIColor = UIColor.white.withAlphaComponent(0.4))
        -> NSAttributedString {
        let font = UIFont(name: "AvenirNext-Medium", size: fontSize) ?? .systemFont(ofSize: fontSize)
        let s = NSMutableAttributedString(string: prefix,
                                          attributes: [.foregroundColor: color, .font: font])
        let cfg = UIImage.SymbolConfiguration(pointSize: font.pointSize, weight: .semibold)
        if let img = UIImage(systemName: symbol, withConfiguration: cfg)?
            .withTintColor(color, renderingMode: .alwaysOriginal)
            .outlined(width: 1.5) {
            let att = NSTextAttachment(image: img)
            att.bounds = CGRect(x: 0, y: (font.capHeight - img.size.height) / 2,
                                width: img.size.width, height: img.size.height)
            s.append(NSAttributedString(attachment: att))
        }
        s.append(NSAttributedString(string: suffix,
                                    attributes: [.foregroundColor: color, .font: font]))
        return s
    }

    /// The hint as a ready, centered UILabel (UIKit hosts).
    public static func makeHint(_ prefix: String, symbol: String, suffix: String) -> UILabel {
        let l = UILabel()
        l.textAlignment = .center
        l.attributedText = hintString(prefix, symbol: symbol, suffix: suffix)
        return l
    }

    // MARK: Press feedback

    /// Uniform tap response for EVERY kit button: tremor debounce on touch-down,
    /// then a quick scale-in AND a darkened title while held, restored on
    /// release/cancel. Scale is transform-only so it never fights the pulse,
    /// which breathes on opacity alone.
    public static func addPressFeedback(to b: UIButton) {
        // THE HOUSE PRESS = the console DROP pill's (gerard, 2026-07-25, after
        // three glyph-treatment iterations all read as noise): the capsule
        // LIGHTS UP while held — fill brightens, stroke brightens — and eases
        // off on release. Nothing scales, no glyph ever changes, and it's an
        // OVERLAY view, so no configuration re-render can twitch it. The
        // overlay slides under the title/image so the glyphs stay crisp on
        // top of the lit fill, exactly like the SwiftUI console pills.
        let glow = UIView()
        glow.isUserInteractionEnabled = false
        glow.alpha = 0
        glow.backgroundColor = UIColor.white.withAlphaComponent(0.28)
        glow.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        glow.layer.borderWidth = 1.5
        b.addSubview(glow)

        let light: (UIButton, UIView) -> Void = { b, glow in
            glow.frame = b.bounds
            glow.layer.cornerRadius = b.bounds.height / 2
            if let iv = b.imageView { b.insertSubview(glow, belowSubview: iv) }
            if let tl = b.titleLabel { b.insertSubview(glow, belowSubview: tl) }
            UIView.animate(withDuration: 0.08, delay: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState]) {
                glow.alpha = 1
            }
        }

        // THE DEBOUNCE DECIDES BEFORE ANYTHING LIGHTS UP. These used to be two separate
        // .touchDown actions — debounce first, glow second — and both ran. So a tremor
        // after-shock was correctly suppressed (cancelTracking) while the glow still lit,
        // and because no touch-up ever follows a cancelled track, the capsule stayed lit
        // FOREVER: white fill, white hairline, nothing happening. To the exact user this
        // accessibility feature exists for, the button reads as pressed-and-active while
        // the app did nothing — so the natural response is to press it again. One action,
        // decision first, is correct regardless of how UIKit orders same-event handlers.
        b.addAction(UIAction { [weak b, weak glow] _ in
            guard let b, let glow else { return }
            guard acceptMenuTap() else {
                b.cancelTracking(with: nil)
                glow.alpha = 0                     // never leave a suppressed tap looking held
                return
            }
            light(b, glow)
        }, for: .touchDown)
        // Dragging BACK onto an already-tracking button re-lights it; the debounce has
        // already been paid for this press, so it must not be consulted again.
        b.addAction(UIAction { [weak b, weak glow] _ in
            guard let b, let glow else { return }
            light(b, glow)
        }, for: .touchDragEnter)
        b.addAction(UIAction { [weak glow] _ in
            guard let glow else { return }
            UIView.animate(withDuration: 0.12, delay: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState]) {
                glow.alpha = 0
            }
        }, for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        // The house click, on the accepted tap only (a debounced tap was
        // cancelTracking'd on touch-down, so no primary action is triggered).
        //
        // .primaryActionTriggered, NOT .touchUpInside: a tvOS remote SELECT
        // fires the former and never the latter, so on Apple TV every kit
        // button was focusable and DEAD — you could highlight ENTER REACTOR
        // and press it forever. On iOS the two fire at the same moment, and
        // the tremor debounce still gates both (cancelTracking suppresses the
        // primary action as well), so touch behaviour is unchanged.
        b.addAction(UIAction { _ in onTap?() }, for: .primaryActionTriggered)
    }

    /// The button's current title/foreground color, whichever styling API it
    /// uses (`Configuration` pills vs. plain `.system` CTAs).
    public static func buttonForeground(_ b: UIButton) -> UIColor? {
        b.configuration?.baseForegroundColor ?? b.titleColor(for: .normal)
    }
    public static func setButtonForeground(_ b: UIButton, _ c: UIColor?) {
        if b.configuration != nil { b.configuration?.baseForegroundColor = c; return }
        b.setTitleColor(c, for: .normal)

        // setTitleColor is a no-op on an ATTRIBUTED title, so the outlined CTAs
        // would never darken on press. Recolor the attributed title in place — in
        // place, so the font and the black stroke survive. Skipped for titles
        // carrying an image attachment (per-range colors would flatten).
        guard let attributed = b.attributedTitle(for: .normal), attributed.length > 0,
              let c = c else { return }
        let whole = NSRange(location: 0, length: attributed.length)
        var hasAttachment = false
        attributed.enumerateAttribute(.attachment, in: whole) { v, _, stop in
            if v != nil { hasAttachment = true; stop.pointee = true }
        }
        if hasAttachment { return }
        let m = NSMutableAttributedString(attributedString: attributed)
        m.addAttribute(.foregroundColor, value: c, range: whole)
        b.setAttributedTitle(m, for: .normal)
    }

    // MARK: The breathing pulse

    public static let ctaPulseKey = "hmCTAPulse"

    /// The standard primary-CTA "breathing" pulse — opacity-only via a
    /// CABasicAnimation, NOT UIView.animate: a CA animation animates only the
    /// PRESENTATION layer, so when iOS strips it on backgrounding the button
    /// returns to FULL opacity (never stuck dim). Hosts should re-call this on
    /// didBecomeActive for any button still on screen (iOS never re-adds
    /// stripped animations).
    public static func ctaPulse(_ views: [UIView]) {
        for v in views {
            v.layer.removeAnimation(forKey: ctaPulseKey)
            v.alpha = 1; v.transform = .identity
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 0.4
            pulse.duration = 0.8
            pulse.beginTime = CACurrentMediaTime() + 0.3
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            v.layer.add(pulse, forKey: ctaPulseKey)
        }
    }

    /// Stop the breathing pulse and reset to the resting state.
    public static func stopCTAPulse(_ view: UIView) {
        view.layer.removeAnimation(forKey: ctaPulseKey)
        view.alpha = 1; view.transform = .identity
    }
}
