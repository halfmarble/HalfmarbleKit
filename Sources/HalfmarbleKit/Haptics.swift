import UIKit

//  The haptics tap every halfmarble app plays — one implementation for what
//  used to be three near-twin playHaptic bodies (ViroFlick's GameScene,
//  StringFusor's scene + mirror). Honors the shared haptics.enabled key
//  (absent = on), clamps intensity, and hops to main (UIFeedbackGenerator is
//  UIKit and game loops run on render threads).
//
//  Only iPhone/iPad have a Taptic Engine: UIImpactFeedbackGenerator is marked
//  unavailable on tvOS outright, and on Mac Catalyst it exists but does
//  nothing. So the generators are iOS-only and every entry point degrades to a
//  silent no-op elsewhere — callers stay unconditional, which is the whole
//  point of the kit owning this.

@MainActor
public enum HMHaptics {
    public enum Style { case light, medium, heavy }

    #if os(iOS)
    private static let generators: [Style: UIImpactFeedbackGenerator] = [
        .light: UIImpactFeedbackGenerator(style: .light),
        .medium: UIImpactFeedbackGenerator(style: .medium),
        .heavy: UIImpactFeedbackGenerator(style: .heavy),
    ]
    #endif

    /// The shared enable flag — absent = on (first-launch default). Settings
    /// screens write the same key they always did; this reads it live.
    public static var enabled: Bool {
        UserDefaults.standard.object(forKey: HMDefaultsKeys.hapticsEnabled) == nil
            || UserDefaults.standard.bool(forKey: HMDefaultsKeys.hapticsEnabled)
    }

    /// Warm a generator ahead of a burst (the Taptic Engine spin-up).
    nonisolated public static func prepare(style: Style = .light) {
        #if os(iOS)
        Task { @MainActor in generators[style]?.prepare() }
        #endif
    }

    /// Fire an impact. Safe from any thread; a no-op when haptics are off —
    /// or when the hardware has none (Mac, Apple TV).
    nonisolated public static func impact(_ intensity: CGFloat, style: Style = .light) {
        #if os(iOS)
        Task { @MainActor in
            guard enabled else { return }
            generators[style]?.impactOccurred(intensity: max(0, min(1, intensity)))
        }
        #endif
    }
}
