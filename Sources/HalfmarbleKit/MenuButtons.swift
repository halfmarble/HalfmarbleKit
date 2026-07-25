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

    /// One 5 Hz resting-tremor period — the same constant both apps ship.
    public static let menuTapCooldown: TimeInterval = 0.25
    nonisolated(unsafe) private static var lastMenuTapDown: TimeInterval = -1

    /// Leading-edge throttle: true — and arms the cooldown — if a menu tap at
    /// `now` should be honored; false if it lands within the cooldown of the
    /// last accepted tap.
    public static func acceptMenuTap(now: TimeInterval = CACurrentMediaTime()) -> Bool {
        if now - lastMenuTapDown < menuTapCooldown { return false }
        lastMenuTapDown = now
        return true
    }

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

    /// The "new here?  start with  [symbol] LABEL" coaching hint — ViroFlick's
    /// makeTextbookHint, generalized: dim Medium-12 text with the SF Symbol
    /// outlined, tinted the same dim colour, and centered on the cap height.
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
        b.addAction(UIAction { [weak b] _ in
            guard let b else { return }
            if !acceptMenuTap() { b.cancelTracking(with: nil) }
        }, for: .touchDown)

        var restingFg: UIColor?          // per-button, shared by the down/up closures
        b.addAction(UIAction { [weak b] _ in
            guard let b else { return }
            restingFg = buttonForeground(b)
            setButtonForeground(b, restingFg?.hmDarkened(by: 0.45))
            UIView.animate(withDuration: 0.09, delay: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState]) {
                b.transform = CGAffineTransform(scaleX: 0.93, y: 0.93)
            }
        }, for: [.touchDown, .touchDragEnter])
        b.addAction(UIAction { [weak b] _ in
            guard let b else { return }
            if let r = restingFg { setButtonForeground(b, r) }
            UIView.animate(withDuration: 0.16, delay: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState]) {
                b.transform = .identity
            }
        }, for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    /// The button's current title/foreground colour, whichever styling API it
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

private extension UIColor {
    /// Scale RGB toward black (alpha preserved) — the darken-on-press feedback.
    func hmDarkened(by f: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return self }
        return UIColor(red: r * f, green: g * f, blue: b * f, alpha: a)
    }
}
