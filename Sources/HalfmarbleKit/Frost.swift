import SwiftUI

//  THE FROSTED GLASS — every halfmarble app's blur, in one place.
//
//  TWO RECIPES AND ONLY TWO (gerard, 2026-08-04: "I want a consistent look
//  throughout. I also want everyone to use the exact same parameters, islands
//  can use a different parameters, but then all islands use the same recipe"):
//
//    BACKDROP — one full-screen sheet of frost over the animating background,
//               so the whole world reads softened while the play layer above
//               it stays sharp.
//    ISLAND   — the card every panel, sheet and overlay wears: the same glass,
//               a shade, a hairline, a corner.
//
//  They share the MATERIAL and its fade deliberately: the glass is what the eye
//  reads as "the app's look", so it must not vary from screen to screen. Only
//  the shade behind it differs, and only because a backdrop is a whole screen
//  while an island is a card that has to hold text.
//
//  MATERIAL, NEVER `.blur()`. A `Material` re-samples what is behind it every
//  frame, so a drifting cosmos stays alive through the glass; `.blur()`
//  snapshots its input and freezes it. There is also no radius knob here on
//  purpose — SwiftUI Materials pick their own, and the tuning surface is which
//  material, how far it is faded, and how dark the shade is. Those are the
//  three numbers below, and changing one changes every screen in every app.
//
//  ALWAYS DARK (gerard, 2026-08-04: "use dark mode for frost"). SwiftUI
//  Materials follow the colour scheme, so on a device set to Light the glass
//  rendered WHITE — the Fusion Core sheet came out a pale slab with the amber
//  washed off it, and the same app looked like two different apps depending on
//  a system setting nobody thinks about while playing. The dark environment is
//  pinned on the GLASS LAYER ONLY, never on the content, so text and icons keep
//  whatever scheme the app gave them.
//
//  The recipe came from ViroFlick's score card, went to StringFusor's landing
//  island, and drifted the moment it was copied a third time (three call sites,
//  three different shades). This file exists so it cannot drift again.

@available(iOS 16.0, tvOS 26.0, *)
public enum HMFrost {

    // MARK: - The glass (shared by BOTH recipes — never vary this per screen)

    /// The thinnest system material: it blurs and lifts without inventing a
    /// colour of its own, which is what lets a red vessel and a black cosmos
    /// wear the same glass.
    public static let material: Material = .ultraThinMaterial
    /// …faded, not replaced. Half strength keeps the world legible underneath
    /// (gerard: "we need to see what's underneath, however barely"). Fading a
    /// Material dilutes its blur AND its grey tint together, which is why the
    /// darkening below is a separate layer.
    public static let materialOpacity: Double = 0.55

    // MARK: - Backdrop

    /// Pure black over the whole screen. Heavier than an island's shade because
    /// it is doing a different job: pushing a live, moving background far enough
    /// down that foreground chrome reads against it.
    public static let backdropShade: Double = 0.30

    // MARK: - Island

    /// Near-black rather than black: an island already sits ON the backdrop
    /// frost, so it is darkening a darkened thing, and 4% white keeps it from
    /// going flat.
    public static let islandTint = Color(white: 0.04)
    /// Light on purpose. The landing island was tuned to this and the exam panel
    /// to 0.30; ONE of them had to win, and this is the one with the design note
    /// attached — the planet's limb should ghost through the glass, not be
    /// buried by it. Islands over the backdrop frost are already double-shaded.
    public static let islandShade: Double = 0.18
    public static let islandStroke: Double = 0.12
    public static let islandStrokeWidth: CGFloat = 1
    public static let islandCornerRadius: CGFloat = 16
}

/// The full-screen BACKDROP frost. Put it over the layer that animates (the
/// cosmos, the vessel) and keep the play layer above it so the board stays
/// sharp. Never hit-tests — it is glass, not a wall.
@available(iOS 16.0, tvOS 26.0, *)
public struct HMFrostBackdrop: View {
    public init() {}
    public var body: some View {
        ZStack {
            Rectangle().fill(HMFrost.material.opacity(HMFrost.materialOpacity))
            Color.black.opacity(HMFrost.backdropShade)
        }
        .environment(\.colorScheme, .dark)   // the glass is dark on a Light device too
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

@available(iOS 16.0, tvOS 26.0, *)
public extension View {

    /// Lay the BACKDROP frost over this view.
    func hmFrostedBackdrop() -> some View {
        overlay(HMFrostBackdrop())
    }

    /// Wear the ISLAND frost: glass, shade, hairline, corner — the card every
    /// panel and sheet uses. `cornerRadius` is the one dial a call site may
    /// turn, and only because a pill-shaped island is a different shape, not a
    /// different recipe.
    func hmFrostedIsland(cornerRadius: CGFloat = HMFrost.islandCornerRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        // The glass goes in its OWN dark-scheme layer: putting .environment on
        // the whole modified view would drag the island's text and icons into
        // dark mode with it.
        return background {
            shape.fill(HMFrost.material.opacity(HMFrost.materialOpacity))
                .environment(\.colorScheme, .dark)
        }
            .background(shape.fill(HMFrost.islandTint.opacity(HMFrost.islandShade)))
            .overlay(shape.stroke(.white.opacity(HMFrost.islandStroke),
                                  lineWidth: HMFrost.islandStrokeWidth))
    }
}
