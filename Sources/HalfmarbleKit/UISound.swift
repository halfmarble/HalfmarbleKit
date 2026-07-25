import Foundation

//  The house UI SOUNDS — synthesized, deterministic, dependency-free (2026-07-25).
//
//  Both shipped games synthesize their own identical-recipe button tap inside
//  their palettes (ViroFlick's Swift synth, StringFusor's C core), and those
//  stay put — their exports are pinned bit-for-bit against shipped wavs. THIS
//  is the same tap for the NEXT app: the "drum tap" click (a snappy pitch-drop
//  sine thump with a tiny noise transient — boomy, not a beep), rendered as a
//  plain [Float] the app's mixer plays however it likes.
//
//  Deterministic by construction: the noise draws from a fixed-seed SplitMix64
//  (the house generator), so every build of every app renders the identical
//  click.

public enum HMUISound {

    /// The house button tap (~0.11s @ `sampleRate` mono). Low-passed at 600Hz
    /// to sit with the bass-forward house palettes; peak ≈ 0.7.
    public static func click(sampleRate: Double = 22_050) -> [Float] {
        var rng = SplitMix(seed: 0xC11C_0000_0000_0001)
        let dur = 0.11
        let count = Int(dur * sampleRate)
        var out = [Float](repeating: 0, count: count)
        let alpha = Float(1 - exp(-2 * Double.pi * 600 / sampleRate))
        var y: Float = 0
        var peak: Float = 0
        for i in 0..<count {
            let t = Double(i) / sampleRate
            // Fast pitch-drop sine thump ("tuk"), 145→58Hz over the whole tap.
            let k = (58.0 - 145.0) / dur
            let phase = 2 * Double.pi * (145.0 * t + 0.5 * k * t * t)
            let body = Float(sin(phase)) * env(t, dur, atk: 0.001, decay: 2.4)
            // A tiny noise click for the attack transient.
            let click = rng.bipolar() * env(t, 0.0035, atk: 0.0003, decay: 2.0)
            let x = max(-1, min(1, 0.6 * body + 0.14 * click))
            y += alpha * (x - y)
            out[i] = y
            peak = max(peak, abs(y))
        }
        let gain: Float = peak > 0 ? min(1.6, 0.7 / peak) : 1
        for i in 0..<count { out[i] *= gain }
        return out
    }

    /// Quadratic decay envelope with a short linear attack (the house shape).
    private static func env(_ t: Double, _ dur: Double, atk: Double, decay: Double) -> Float {
        if t >= dur || t < 0 { return 0 }
        if t < atk { return Float(t / atk) }
        let d = (t - atk) / (dur - atk)
        return Float(pow(1 - d, decay))
    }

    /// SplitMix64 — the house cross-platform-stable generator.
    private struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func bipolar() -> Float {
            Float(next() >> 40) * (2.0 / 16_777_216.0) - 1.0
        }
    }
}
