import UIKit
import SwiftUI

//  The halfmarble BRAND, in one place (2026-07-25): the wordmark, the ring
//  mark (the PNG rides the kit's resource bundle — the two apps carried
//  byte-identical copies), the charitable pledge, the lockup metrics both
//  splash choreographies share, and the landing-screen geometry bands.

public enum HMBrand {
    /// The studio wordmark — always lowercase (the one cased use is "Halfmarble LLC").
    public static let name = "halfmarble"

    /// MJFF NAMED? ON since 2026-08-04, the day MJFF confirmed in writing that
    /// the App Store listing language was approved on their side. That closes the
    /// 2026-08-01 ruling, which let a beta carry the name but not a public
    /// launch until that confirmation arrived.
    ///
    /// The fallback stays wired underneath: flipping this back to `false` removes
    /// the name everywhere in both games in one edit, which is why the unnamed
    /// wording is kept rather than deleted.
    public static let mjffNamed = true

    /// The charitable-giving pledge, one line each (mirrors halfmarble.com).
    /// Factual statement only — no logos, no endorsement, no tap target.
    /// WORDING IS CONTRACTUAL: the signed Team Fox agreement is the source of
    /// truth; never edit these lines from anywhere else.
    public static var pledgeLines: [String] { mjffNamed ? namedPledge : unnamedPledge }

    /// The contractual wording, kept VERBATIM so restoring it is a flag and not a
    /// retype. Do not edit these except against the signed agreement.
    static let namedPledge = [
        "5% of software net profits pledged:",
        // Lex Knipper (MJFF Community Fundraising) asked for exactly this framing
        // on 2026-08-19, after checking with their Communications Team; it replaces
        // "2.5% to Michael J. Fox Foundation (MJFF)". Split across two entries
        // because each entry renders on its own fixed 14pt row — as one string it
        // overflows the row at AvenirNext-Medium 10 on every phone width.
        "2.5% to Team Fox, the grassroots fundraising arm",
        "of The Michael J. Fox Foundation",
        "2.5% to Public Health Collaboration (PHC)",   // "(PHC)", not "(PHC UK)" — gerard, 2026-07-31
        // The Team Fox terms require the third-party relationship to be
        // explicit on all promotional surfaces (agreement wording pass,
        // 2026-07-29); gerard asked for it in-app the same day.
        "halfmarble is an independent Team Fox third-party fundraiser.",
    ]

    /// The unnamed form. The PLEDGE is unchanged — the same 5%, split the same
    /// way — only the recipient goes unnamed, because naming a charity implies a
    /// relationship they have not confirmed yet.
    ///
    /// The Team Fox line goes WITH the name, not after it: it exists solely to
    /// make the third-party relationship explicit, and "Team Fox" is an MJFF
    /// program, so keeping it while dropping "MJFF" would name them anyway and
    /// leave a sentence about a relationship the copy no longer mentions.
    static let unnamedPledge = [
        "5% of software net profits pledged:",
        "2.5% to Parkinson's aligned research",
        "2.5% to Public Health Collaboration (PHC)",
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
    /// The fade that brings the big lockup up on the cover.
    public static let splashFadeDelay: TimeInterval = 0.05
    public static let splashFadeIn: TimeInterval = 0.5
    /// THE STILL BEAT: once the lockup is fully up it sits there, motionless,
    /// for at least this long before the morph starts (gerard, 2026-08-01 — the
    /// beat was 0.85s here and 0.5s in ViroFlick). A shorter one makes the
    /// morph read as a jarring snap: the mark has to LAND before it moves, or
    /// the eye never resolves it as a brand at all. Both choreographies honour
    /// it — the SwiftUI splash via `splashHold`, ViroFlick's UIKit one as the
    /// `notBefore` on its warm-up gate.
    public static let splashMinHold: TimeInterval = 1.0
    /// Appearance → morph, for the SwiftUI splash. DERIVED, never a literal:
    /// hand-tuning this is exactly what silently ate the still beat above.
    public static let splashHold: TimeInterval = splashFadeDelay + splashFadeIn + splashMinHold
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
