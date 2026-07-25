import UIKit

//  The haptics tap every halfmarble app plays — one implementation for what
//  used to be three near-twin playHaptic bodies (ViroFlick's GameScene,
//  StringFusor's scene + mirror). Honors the shared haptics.enabled key
//  (absent = on), clamps intensity, and hops to main (UIFeedbackGenerator is
//  UIKit and game loops run on render threads).

@MainActor
public enum HMHaptics {
    public enum Style { case light, medium, heavy }

    private static let generators: [Style: UIImpactFeedbackGenerator] = [
        .light: UIImpactFeedbackGenerator(style: .light),
        .medium: UIImpactFeedbackGenerator(style: .medium),
        .heavy: UIImpactFeedbackGenerator(style: .heavy),
    ]

    /// The shared enable flag — absent = on (first-launch default). Settings
    /// screens write the same key they always did; this reads it live.
    public static var enabled: Bool {
        UserDefaults.standard.object(forKey: HMDefaultsKeys.hapticsEnabled) == nil
            || UserDefaults.standard.bool(forKey: HMDefaultsKeys.hapticsEnabled)
    }

    /// Warm a generator ahead of a burst (the Taptic Engine spin-up).
    nonisolated public static func prepare(style: Style = .light) {
        Task { @MainActor in generators[style]?.prepare() }
    }

    /// Fire an impact. Safe from any thread; a no-op when haptics are off.
    nonisolated public static func impact(_ intensity: CGFloat, style: Style = .light) {
        Task { @MainActor in
            guard enabled else { return }
            generators[style]?.impactOccurred(intensity: max(0, min(1, intensity)))
        }
    }
}
