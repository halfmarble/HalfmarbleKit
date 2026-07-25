import UIKit

//  Black outlines for labels and icons — ported verbatim from ViroFlick's
//  Outline.swift (the SKLabelNode notes travel with it; they cost nothing here
//  and save the next SpriteKit host from re-learning the paragraph-style trap).
//
//  The playfield and the menu backdrop are both busy, and flat white glyphs
//  disappear into the bright patches. An outline fixes that without darkening
//  the art behind it.
//
//  Two techniques, because there are two kinds of glyph:
//
//    TEXT  — CoreText stroke attributes. A NEGATIVE .strokeWidth means "fill AND
//            stroke" (a positive one means stroke only, i.e. hollow text). Honored
//            by SKLabelNode.attributedText, UILabel.attributedText, and
//            UIButton.Configuration.attributedTitle alike, so one path covers all
//            three.
//
//    ICONS — SF Symbols are images, and a text stroke cannot touch them. Instead we
//            pre-render the outline ONCE into the UIImage: stamp a black silhouette
//            at 8 offsets around a ring, then draw the symbol on top. It costs a
//            little memory and nothing at all per frame.
//
//  Deliberately NOT a CALayer shadow: that gives a soft halo rather than a crisp
//  edge, and it re-renders on every layer change.

public enum Outline {

    /// Stroke width, as a fraction of font size. Negative = fill + stroke.
    public static let textStrokeRatio: CGFloat = -0.25

    public static let color: UIColor = .black

    /// Attributes for outlined text. `stroke` overrides the default ratio when a label
    /// needs a heavier or lighter edge than its size would imply.
    ///
    /// `alignment` is OPTIONAL, and nil means "attach no paragraph style at all" — which
    /// is what SKLabelNode wants (a fresh paragraph style's .byWordWrapping overrides the
    /// node's own layout and wraps growing strings off their anchor). UILabel/UIButton
    /// titles DO want one (they have a frame to align within).
    public static func attributes(font: UIFont,
                                  color textColor: UIColor,
                                  alignment: NSTextAlignment? = nil,
                                  stroke: CGFloat? = nil) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .strokeColor: Self.color,
            .strokeWidth: stroke ?? (font.pointSize * textStrokeRatio),
        ]
        if let alignment {
            let para = NSMutableParagraphStyle()
            para.alignment = alignment
            para.lineBreakMode = .byClipping     // never re-wrap a single-line label
            attrs[.paragraphStyle] = para
        }
        return attrs
    }

    /// An outlined attributed string — the one-liner every label wants.
    public static func string(_ s: String, font: UIFont, color: UIColor,
                              alignment: NSTextAlignment? = nil,
                              stroke: CGFloat? = nil) -> NSAttributedString {
        NSAttributedString(string: s, attributes: attributes(font: font, color: color,
                                                             alignment: alignment, stroke: stroke))
    }
}

public extension UIImage {
    /// A copy of this image with a solid outline baked in. Call on an image that is
    /// ALREADY tinted its final color (i.e. after `.withTintColor(_:renderingMode:)`),
    /// because the result is `.alwaysOriginal` and will not take a tint afterwards.
    ///
    /// The canvas grows by `width` on every side so the outline is not clipped.
    func outlined(_ outlineColor: UIColor = Outline.color, width: CGFloat = 2) -> UIImage {
        guard width > 0 else { return self }
        let canvas = CGSize(width: size.width + width * 2, height: size.height + width * 2)
        let inner = CGRect(x: width, y: width, width: size.width, height: size.height)

        return UIGraphicsImageRenderer(size: canvas).image { ctx in
            let cg = ctx.cgContext

            // A black silhouette of the glyph, stamped around a ring. 8 points is the
            // fewest that reads as a continuous edge rather than a plus/cross shape.
            let silhouette = UIGraphicsImageRenderer(size: size).image { s in
                draw(in: CGRect(origin: .zero, size: size))
                s.cgContext.setBlendMode(.sourceIn)
                outlineColor.setFill()
                s.cgContext.fill(CGRect(origin: .zero, size: size))
            }
            for i in 0..<8 {
                let a = CGFloat(i) * .pi / 4
                cg.saveGState()
                silhouette.draw(in: inner.offsetBy(dx: cos(a) * width, dy: sin(a) * width))
                cg.restoreGState()
            }
            draw(in: inner)
        }
        .withRenderingMode(.alwaysOriginal)
    }
}

public extension UIImage {
    /// Draw centered in a square of side `box`, scaled DOWN if needed so it fits.
    /// `outlined()` grows an image by its stroke width on every side, which can push a
    /// glyph past a fixed icon slot (the 24×24 checkbox/lock canvas) and clip its edges.
    /// Never scales up, so an already-small glyph keeps its authored size.
    func drawFitted(in box: CGFloat) {
        let s = min(1, min(box / size.width, box / size.height))
        let w = size.width * s, h = size.height * s
        draw(in: CGRect(x: (box - w) / 2, y: (box - h) / 2, width: w, height: h))
    }
}
