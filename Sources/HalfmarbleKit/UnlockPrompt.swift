import UIKit

//  The one-time-unlock purchase card (2026-08-09).
//
//  The kit has owned the STORE PLUMBING since 2026-07-29 (HMStoreUnlock: product
//  load, the lifelong transaction listener, entitlement reconciliation, purchase,
//  three-state restore) but not one pixel of the UI in front of it — so the modal
//  that every paid-unlock app needs was on course to be rebuilt per app, and with
//  it the two things ViroFlick only got right the second time:
//
//    * THE STATUS LINE. A purchase can fail BEFORE StoreKit has any UI of its own
//      to show (product never loaded, no network, an op already in flight). With
//      no status line, that path produced exactly one UI tick and no visible
//      change — indistinguishable from a dead button. On a reviewer's sandbox
//      account that is the shape of a Guideline 2.1 "unable to complete the
//      in-app purchase" rejection. The card must be able to speak for itself.
//
//    * THE BODY LABEL'S SIZING. At a fixed height the last line truncated on a
//      375pt-wide screen — "…stay free forever: surges 1…" — cutting a free-tier
//      promise off mid-sentence on the one screen where that promise is the
//      disclosure. The body fills the space it actually has and shrinks to fit.
//
//  The app supplies copy, the accent, and what the two buttons DO. Everything
//  here is layout and the two lessons above.

/// What the card says. The caller composes `buyTitle` with its own price string
/// (`HMStoreUnlock.displayPrice`) — the kit never formats a price, because the
/// only correct formatting is the one StoreKit hands back for the user's
/// storefront.
public struct HMUnlockPromptCopy {
    public var title: String
    public var body: String
    public var buyTitle: String
    public var dismissTitle: String

    public init(title: String, body: String, buyTitle: String, dismissTitle: String) {
        self.title = title
        self.body = body
        self.buyTitle = buyTitle
        self.dismissTitle = dismissTitle
    }
}

/// How the card looks. Defaults are the house card: near-black panel, amber-ish
/// accent supplied by the app, dimmed surroundings.
public struct HMUnlockPromptStyle {
    /// The buy button's fill, and the card's border tint at half strength.
    public var accent: UIColor
    /// The card panel — and the buy button's TITLE color, so the button reads as
    /// a hole punched in the card rather than a sticker on it.
    public var panel: UIColor
    /// How far the surroundings dim. 0.6 is enough to kill the game behind it
    /// without hiding that a game is still there.
    public var scrimAlpha: CGFloat
    /// Card width is `min(bounds.width - horizontalInset, maxWidth)`.
    public var maxWidth: CGFloat
    public var horizontalInset: CGFloat
    /// Card height. The internal offsets are measured from the BOTTOM, so a
    /// taller card grows its body copy and nothing else moves.
    public var height: CGFloat

    public init(accent: UIColor,
                panel: UIColor = UIColor(red: 0.06, green: 0.07, blue: 0.11, alpha: 1),
                scrimAlpha: CGFloat = 0.6,
                maxWidth: CGFloat = 340,
                horizontalInset: CGFloat = 56,
                height: CGFloat = 296) {
        self.accent = accent
        self.panel = panel
        self.scrimAlpha = scrimAlpha
        self.maxWidth = maxWidth
        self.horizontalInset = horizontalInset
        self.height = height
    }
}

/// The full-screen scrim with the unlock card centered in it. Add it as a
/// subview; remove it to dismiss. Lays out on every pass, so it survives
/// rotation and a resized host.
public final class HMUnlockPromptView: UIView {

    // Card-relative geometry, all measured from the card's bottom edge so the
    // button stack stays put whatever `style.height` is.
    private enum Metrics {
        static let titleTop: CGFloat = 20
        static let titleHeight: CGFloat = 28
        static let bodyTop: CGFloat = 54
        static let buyBottomOffset: CGFloat = 118   // buy.minY = height - this
        static let buyHeight: CGFloat = 46
        static let statusBottomOffset: CGFloat = 68
        static let statusHeight: CGFloat = 32
        static let dismissBottomOffset: CGFloat = 34
        static let dismissHeight: CGFloat = 26
        static let bodySideInset: CGFloat = 20
        static let buttonSideInset: CGFloat = 24
    }

    /// The card's OWN status line — empty (and so invisible) until something
    /// happens. Every purchase outcome should land here; see the file header for
    /// why a silent failure path is not an option.
    public let statusLabel = UILabel()

    private let card = UIView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let buyButton: UIButton
    private let dismissButton: UIButton
    private let style: HMUnlockPromptStyle

    public init(frame: CGRect,
                copy: HMUnlockPromptCopy,
                style: HMUnlockPromptStyle,
                onBuy: @escaping () -> Void,
                onDismiss: @escaping () -> Void) {
        self.style = style
        buyButton = UIButton(type: .system)
        dismissButton = UIButton(type: .system)
        super.init(frame: frame)

        backgroundColor = UIColor(white: 0, alpha: style.scrimAlpha)

        card.backgroundColor = style.panel
        card.layer.cornerRadius = 18
        card.layer.borderWidth = 1.5
        card.layer.borderColor = style.accent.withAlphaComponent(0.5).cgColor
        addSubview(card)

        titleLabel.textAlignment = .center
        titleLabel.textColor = .white
        titleLabel.font = Self.font("AvenirNext-Heavy", 20, .heavy)
        titleLabel.text = copy.title
        card.addSubview(titleLabel)

        bodyLabel.numberOfLines = 0
        bodyLabel.textAlignment = .center
        bodyLabel.adjustsFontSizeToFitWidth = true
        bodyLabel.minimumScaleFactor = 0.85
        bodyLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        bodyLabel.font = Self.font("AvenirNext-Medium", 13, .medium)
        bodyLabel.text = copy.body
        card.addSubview(bodyLabel)

        buyButton.setTitle(copy.buyTitle, for: .normal)
        buyButton.titleLabel?.font = Self.font("AvenirNext-Heavy", 18, .heavy)
        buyButton.setTitleColor(style.panel, for: .normal)
        buyButton.backgroundColor = style.accent
        buyButton.layer.cornerRadius = Metrics.buyHeight / 2
        HMMenu.addPressFeedback(to: buyButton)
        buyButton.addAction(UIAction { _ in onBuy() }, for: .primaryActionTriggered)
        card.addSubview(buyButton)

        statusLabel.numberOfLines = 2
        statusLabel.textAlignment = .center
        statusLabel.font = Self.font("AvenirNext-Medium", 12, .medium)
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        statusLabel.adjustsFontSizeToFitWidth = true
        statusLabel.minimumScaleFactor = 0.85
        statusLabel.text = ""
        card.addSubview(statusLabel)

        dismissButton.setTitle(copy.dismissTitle, for: .normal)
        dismissButton.titleLabel?.font = Self.font("AvenirNext-Bold", 13, .bold)
        dismissButton.setTitleColor(UIColor.white.withAlphaComponent(0.5), for: .normal)
        HMMenu.addPressFeedback(to: dismissButton)
        dismissButton.addAction(UIAction { _ in onDismiss() }, for: .primaryActionTriggered)
        card.addSubview(dismissButton)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The buy title changes when a price arrives late (the product load can
    /// outlive the tap that opened this card).
    public func setBuyTitle(_ title: String) {
        buyButton.setTitle(title, for: .normal)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let w = min(bounds.width - style.horizontalInset, style.maxWidth)
        let h = style.height
        guard w > 0, h > 0 else { return }              // pre-layout zero bounds
        card.frame = CGRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)

        titleLabel.frame = CGRect(x: 12, y: Metrics.titleTop,
                                  width: w - 24, height: Metrics.titleHeight)

        // Fill everything between the title and the buy button, rather than a
        // fixed height that truncates the last line on a narrow screen.
        let bodyHeight = (h - Metrics.buyBottomOffset) - Metrics.bodyTop - 8
        bodyLabel.frame = CGRect(x: Metrics.bodySideInset, y: Metrics.bodyTop,
                                 width: w - Metrics.bodySideInset * 2,
                                 height: max(0, bodyHeight))

        buyButton.frame = CGRect(x: Metrics.buttonSideInset, y: h - Metrics.buyBottomOffset,
                                 width: w - Metrics.buttonSideInset * 2, height: Metrics.buyHeight)
        statusLabel.frame = CGRect(x: 16, y: h - Metrics.statusBottomOffset,
                                   width: w - 32, height: Metrics.statusHeight)
        dismissButton.frame = CGRect(x: Metrics.buttonSideInset,
                                     y: h - Metrics.dismissBottomOffset,
                                     width: w - Metrics.buttonSideInset * 2,
                                     height: Metrics.dismissHeight)
    }

    private static func font(_ name: String, _ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    // MARK: Test seams

    public var t_cardFrame: CGRect { card.frame }
    public var t_bodyFrame: CGRect { bodyLabel.frame }
    public var t_buyButton: UIButton { buyButton }
    public var t_dismissButton: UIButton { dismissButton }
}
