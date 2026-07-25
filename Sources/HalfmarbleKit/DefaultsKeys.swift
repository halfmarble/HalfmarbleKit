import Foundation

//  The UserDefaults keys every halfmarble app shares — the string VALUES are a
//  storage contract (they were deliberately identical literals in ViroFlick
//  and StringFusor; now the compiler enforces it). App-specific keys stay in
//  each app's own DefaultsKeys enum, which forwards these four.
//
//  IMPORTANT: never change a string value — a wrong read just returns the
//  type's zero value, silently orphaning every player's saved choice.

public enum HMDefaultsKeys {
    /// Audio: music on/off. Absent = on (first-launch default).
    public static let musicEnabled = "music.enabled"
    /// Audio: sound effects on/off. Absent = on (first-launch default).
    public static let sfxEnabled = "sfx.enabled"
    /// Haptics on/off. Absent = on (first-launch default).
    public static let hapticsEnabled = "haptics.enabled"
    /// FPS graph toggle. ABSENT = channel default (dev/TestFlight on, App
    /// Store off); a stored value is an explicit user choice and wins.
    public static let fpsGraph = "fpsGraph.enabled"
}
