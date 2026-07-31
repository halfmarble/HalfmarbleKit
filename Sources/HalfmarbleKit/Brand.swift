import UIKit
import SwiftUI

//  The halfmarble BRAND, in one place (2026-07-25): the wordmark, the ring
//  mark (the PNG rides the kit's resource bundle — the two apps carried
//  byte-identical copies), the charitable pledge, the lockup metrics both
//  splash choreographies share, and the landing-screen geometry bands.

public enum HMBrand {
    /// The studio wordmark — always lowercase (the one cased use is "Halfmarble LLC").
    public static let name = "halfmarble"

    /// The charitable-giving pledge, one line each (mirrors halfmarble.com).
    /// Factual statement only — no logos, no endorsement, no tap target.
    /// WORDING IS CONTRACTUAL: the signed Team Fox agreement is the source of
    /// truth; never edit these lines from anywhere else.
    public static let pledgeLines = [
        "5% of software net profits pledged:",
        "2.5% to Michael J. Fox Foundation (MJFF)",
        "2.5% to Public Health Collaboration (PHC)",   // "(PHC)", not "(PHC UK)" — gerard, 2026-07-31
        // The Team Fox terms require the third-party relationship to be
        // explicit on all promotional surfaces (agreement wording pass,
        // 2026-07-29); gerard asked for it in-app the same day.
        "halfmarble is an independent Team Fox third-party fundraiser.",
    ]

    /// The ring mark, template-rendered — tint it (white on the dark grounds).
    public static var logo: UIImage? {
        UIImage(named: "halfmarble_logo", in: .module, with: nil)?
            .withRenderingMode(.alwaysTemplate)
    }
    /// The same mark for SwiftUI hosts. UIImage-backed on purpose:
    /// UIImage(named:in:) reliably finds LOOSE bundle files, where SwiftUI's
    /// Image(_:bundle:) proved unwilling (blank 22pt frame, 2026-07-25).
    public static var logoImage: Image {
        if let ui = logo { return Image(uiImage: ui).renderingMode(.template) }
        return Image(systemName: "circle.dashed")   // visible fallback, never a silent blank
    }

    // MARK: Lockup metrics — the splash's BIG centred lockup and the header's
    // small one, shared by both apps' morph choreographies.
    public static let logoBig: CGFloat = 96
    public static let logoSmall: CGFloat = 22
    public static let nameBigFont: CGFloat = 24
    public static let nameSmallFont: CGFloat = 16
    public static let nameAlpha: CGFloat = 0.7
    public static let lockupGap: CGFloat = 8
    /// The cold-start cover behind the big lockup.
    public static let coverColor = UIColor(red: 0.03, green: 0.04, blue: 0.07, alpha: 1)
    /// Hold the lockup as the loading screen, then morph into the header.
    public static let splashHold: TimeInterval = 1.4
    public static let splashMorph: TimeInterval = 0.62
}

/// The landing / menu screen's shared geometry bands — ViroFlick's
/// presentStartScreen formulas, named (StringFusor's LandingView evaluates
/// the same numbers; matching literals in two apps is how screens drift).
public enum HMLanding {
    /// The title row's top, as a fraction of full-screen height.
    public static let titleBand: CGFloat = 0.22
    /// The hub band (hint + action pills), as a fraction of height.
    public static let hubBand: CGFloat = 0.80
    public static let lockupRise: CGFloat = 34     // lockup top = titleY − this
    public static let titleHeight: CGFloat = 54
    public static let taglineDrop: CGFloat = 58    // tagline top = titleY + this
    public static let taglineHeight: CGFloat = 22
    public static let dashTopDrop: CGFloat = 118   // island band top = titleY + this
    public static let dashBottomRise: CGFloat = 104 // island band bottom = hubY − this
    public static let hintRise: CGFloat = 94       // hint top = hubY − this
    public static let pillRise: CGFloat = 54       // first pill top = hubY − this
}
