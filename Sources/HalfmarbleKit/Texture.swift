import UIKit

//  Procedural-texture rendering format (2026-08-09) — extracted after the same
//  three-line body was found hand-rolled FOUR times across the two shipped
//  apps: ViroFlick's `softTextureFormat()` and its share-card renderer,
//  StringFusor's cell material and cosmic field.

public enum HMTexture {

    /// The renderer format for procedurally generated images that get STRETCHED
    /// rather than displayed pixel-for-pixel — backdrops, gradients, glows, soft
    /// blobs, composed share cards.
    ///
    /// Scale 1, not the device's 2×/3×. `UIGraphicsImageRenderer` defaults to the
    /// main screen's scale, which is right for crisp UI artwork and wrong for
    /// every one of these: they are smooth gradients that the renderer resamples
    /// anyway, so the extra pixels buy no detail and cost resident memory
    /// quadratically. Measured in ViroFlick: the default 3× turned a full-screen
    /// backdrop into an 1800×3000 bitmap — 21 MB resident, a third of the whole
    /// app's footprint — for an image that is a two-stop radial gradient.
    ///
    /// Pass `opaque: true` when the image fills its own bounds edge to edge (a
    /// composed poster, a full-bleed backdrop): it drops the alpha channel, which
    /// is a further quarter off the buffer and lets the compositor skip blending.
    /// Leave it false for anything with transparency — a glow or a blob rendered
    /// opaque comes out on a black square.
    public static func softFormat(opaque: Bool = false) -> UIGraphicsImageRendererFormat {
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        f.opaque = opaque
        return f
    }
}
