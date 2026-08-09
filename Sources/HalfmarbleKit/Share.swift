import UIKit

//  The system share sheet, presented correctly (2026-08-09) — extracted from
//  ViroFlick's game-over SHARE pill, which is the only shipped caller today but
//  hand-rolled both of the things every future caller will also have to get
//  right: finding a presenter, and anchoring the popover.
//
//  Sharing itself needs no permission — UIActivityViewController hands the items
//  to the system, which owns every downstream action (Messages, Photos, AirDrop)
//  and the privacy prompt for each. What the app owns is the two mistakes below.
//
//  iOS and Mac Catalyst only: UIActivityViewController does not exist on tvOS,
//  and there is nothing sensible to degrade to (no share sheet, no Files) — so
//  this whole file compiles out rather than offering a no-op that would look
//  like a dead button.

#if os(iOS)
public enum HMShare {

    /// The view controller actually on screen — the deepest link in the
    /// `presentedViewController` chain from the window's root.
    ///
    /// Presenting from the ROOT controller while anything is already presented
    /// (a settings sheet, a Game Center panel) throws away the presentation:
    /// UIKit logs a warning about presenting on a controller whose view is not
    /// in the window hierarchy, and the share sheet never appears. Games that
    /// live in one long-lived view controller hit this exactly as often as
    /// navigation-based apps, because the sheet is usually raised from an
    /// overlay that is itself presented.
    public static func topMostViewController(from root: UIViewController?) -> UIViewController? {
        var top = root
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    /// Present the share sheet for `items`, anchored to `source`.
    ///
    /// The anchor is not cosmetic. On iPad (and in any size class where UIKit
    /// chooses a popover) a `UIActivityViewController` presented with no
    /// `sourceView`/`sourceRect` and no `barButtonItem` **crashes** —
    /// "UIPopoverPresentationController should have a non-nil sourceView or
    /// barButtonItem set before the presentation occurs". It is a hard trap
    /// because the iPhone path, where the sheet comes up as a card, never shows
    /// it. Anchoring at the source view's centre is the safe default for a
    /// full-screen game surface with no bar button to point at.
    ///
    /// Returns false when there was no controller to present from — the caller
    /// can decide whether that is worth reporting; it is not worth crashing over.
    @discardableResult
    public static func present(items: [Any], from source: UIView,
                               applicationActivities: [UIActivity]? = nil) -> Bool {
        guard let top = topMostViewController(from: source.window?.rootViewController) else {
            return false
        }
        let vc = UIActivityViewController(activityItems: items,
                                          applicationActivities: applicationActivities)
        vc.popoverPresentationController?.sourceView = source
        vc.popoverPresentationController?.sourceRect =
            CGRect(x: source.bounds.midX, y: source.bounds.midY, width: 1, height: 1)
        top.present(vc, animated: true)
        return true
    }
}
#endif
