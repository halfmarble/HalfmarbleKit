import SwiftUI

//  The cold-start BRAND SPLASH for SwiftUI hosts — moved here from StringFusor
//  (2026-07-25; ViroFlick runs the same choreography in UIKit off the same
//  HMBrand metrics): the halfmarble ring mark + lowercase wordmark fade in big
//  and centred on a dark cover, hold a beat (the loading screen), then MORPH —
//  shrink and travel — into the host's small lockup while the cover dissolves.
//  One continuous motion, so the brand "settles" into the header the moment
//  the app appears (no cut).
//
//  The host's lockup (HMBrandLockup, or any view reporting
//  BrandLockupFramesKey) publishes its logo/name frames; this overlay
//  animates onto those exact rects, then onDone hands off.

/// THE HANDOFF — ViroFlick's rule, factored out so no host can get it wrong.
///
/// ViroFlick (UIKit, GameView+HomeScreen) builds its menu lockup at `alpha = 0`
/// and only sets it to 1 inside the morph animation's completion block, in the
/// same beat the splash view is removed. So the mark is never on screen twice,
/// and never blinks out between the two. StringFusor had the same choreography
/// but not that rule: its static lockup sat at the destination the whole time
/// the animated one flew toward it.
///
/// It is an ObservableObject on purpose. Handing the host a plain `Bool` is not
/// enough — StringFusor tried exactly that first and the landing view never
/// re-rendered when it flipped (proven with a body-level print: the splash's
/// onDone fired and the landing's body never ran again), so the mark stayed
/// hidden forever. Observation invalidates whoever READ the flag, wherever it
/// was read, which is the behaviour this needs.
@MainActor
public final class HMBrandHandoff: ObservableObject {
    @Published public private(set) var revealed: Bool

    public init(revealed: Bool = false) { self.revealed = revealed }

    /// Reveal with no splash involved — the host arrived at this screen from
    /// somewhere else (ViroFlick's `presentStartScreen(revealBrand: true)`).
    public func reveal() { revealed = true }

    /// For hosts with no cold-start splash at all: the lockup is simply up.
    public static let alwaysVisible = HMBrandHandoff(revealed: true)
}

/// Global (screen-space) target rects for the two halves of the host lockup.
public struct BrandLockupFrames: Equatable {
    public var logo: CGRect = .zero
    public var name: CGRect = .zero
    public init(logo: CGRect = .zero, name: CGRect = .zero) {
        self.logo = logo; self.name = name
    }
}

public struct BrandLockupFramesKey: PreferenceKey {
    public static let defaultValue = BrandLockupFrames()
    public static func reduce(value: inout BrandLockupFrames, nextValue: () -> BrandLockupFrames) {
        let n = nextValue()
        if n.logo != .zero { value.logo = n.logo }
        if n.name != .zero { value.name = n.name }
    }
}

/// The small header/landing lockup — ring mark + wordmark — reporting its
/// frames up through BrandLockupFramesKey so the splash can morph onto it.
public struct HMBrandLockup: View {
    @ObservedObject private var handoff: HMBrandHandoff

    public init(handoff: HMBrandHandoff = .alwaysVisible) { self.handoff = handoff }

    public var body: some View {
        HStack(spacing: HMBrand.lockupGap - 3) {   // visual gap incl. the mark's padding
            HMBrand.logoImage
                .resizable().scaledToFit()
                .frame(width: HMBrand.logoSmall, height: HMBrand.logoSmall)
                .foregroundStyle(.white)
                .background(GeometryReader { g in
                    Color.clear.preference(key: BrandLockupFramesKey.self,
                                           value: BrandLockupFrames(logo: g.frame(in: .global)))
                })
            Text(HMBrand.name)
                .font(.custom("AvenirNext-Medium", size: HMBrand.nameSmallFont))
                .foregroundStyle(.white.opacity(HMBrand.nameAlpha))
                .background(GeometryReader { g in
                    Color.clear.preference(key: BrandLockupFramesKey.self,
                                           value: BrandLockupFrames(name: g.frame(in: .global)))
                })
        }
        // OPACITY, never `if` or .hidden(): hidden or not, the lockup has to stay
        // laid out and keep publishing BrandLockupFramesKey, because those rects
        // are what the splash morphs onto. Remove it and the splash has no target
        // and falls back to a plain dissolve.
        .opacity(handoff.revealed ? 1 : 0)
    }
}

public struct HMBrandSplash: View {
    let targets: BrandLockupFrames
    let handoff: HMBrandHandoff?
    let onDone: () -> Void

    public init(targets: BrandLockupFrames,
                handoff: HMBrandHandoff? = nil,
                onDone: @escaping () -> Void) {
        self.targets = targets; self.handoff = handoff; self.onDone = onDone
    }

    @State private var lockupIn = false
    @State private var docked = false

    public var body: some View {
        // The GeometryReader ignores the safe area, so its local space IS the
        // screen — matching the .global rects the host lockup reports.
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            ZStack {
                Color(HMBrand.coverColor)
                    .opacity(docked ? 0 : 1)
                HMBrand.logoImage
                    .resizable().scaledToFit()
                    .frame(width: HMBrand.logoBig, height: HMBrand.logoBig)
                    .foregroundStyle(.white)
                    .scaleEffect(docked && targets.logo != .zero
                                 ? targets.logo.width / HMBrand.logoBig : 1)
                    .position(docked && targets.logo != .zero
                              ? CGPoint(x: targets.logo.midX, y: targets.logo.midY)
                              : CGPoint(x: W / 2, y: H * 0.42 - HMBrand.logoBig / 2 - 6))
                    .opacity(lockupIn ? 1 : 0)
                Text(HMBrand.name)
                    .font(.custom("AvenirNext-Medium", size: HMBrand.nameBigFont))
                    .foregroundStyle(.white)
                    .scaleEffect(docked ? HMBrand.nameSmallFont / HMBrand.nameBigFont : 1)
                    .position(docked && targets.name != .zero
                              ? CGPoint(x: targets.name.midX, y: targets.name.midY)
                              : CGPoint(x: W / 2, y: H * 0.42 + 18))
                    .opacity(lockupIn ? (docked ? HMBrand.nameAlpha : 1) : 0)
            }
            .contentShape(Rectangle())      // swallow taps until the app is revealed
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: HMBrand.splashFadeIn)
                            .delay(HMBrand.splashFadeDelay)) { lockupIn = true }
            // Hold the lockup as the loading screen (the host's warm-up
            // completes inside this beat), then morph. splashHold is that fade
            // PLUS splashMinHold, so the lockup is fully up and STILL for a
            // whole second before it travels.
            DispatchQueue.main.asyncAfter(deadline: .now() + HMBrand.splashHold) {
                withAnimation(.easeInOut(duration: HMBrand.splashMorph)) { docked = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + HMBrand.splashMorph + 0.04) {
                    // Reveal the host's static lockup FIRST, then leave — one beat,
                    // the way ViroFlick's completion block sets alpha 1 and then
                    // removes the splash view.
                    handoff?.reveal()
                    onDone()
                }
            }
        }
    }
}
