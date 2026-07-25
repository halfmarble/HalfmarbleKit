import Foundation

//  Distribution-channel policy (2026-07-25) — extracted from ViroFlick's
//  FPSStrip ladder, because "which channel am I on" is release policy, not
//  FPS policy.

public enum HMReleaseChannel {
    /// TestFlight installs carry a sandbox receipt — the standard runtime tell.
    public static let isTestFlight =
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
}

/// The FPS graph's three-tier availability ladder:
///   dev builds   → on           (DEBUG default)
///   TestFlight   → on           (testers are collaborators; hitch screenshots
///                                 are free profiling data across devices)
///   App Store    → OFF, with a Settings toggle — customers would misread the
///                                 red line, but Glass Box means anyone may look
///                                 under the hood.
/// An explicit user choice (the stored HMDefaultsKeys.fpsGraph Bool) overrides
/// the channel default on every tier and persists.
public enum HMFPSStrip {
    public static var channelDefault: Bool {
        #if DEBUG
        return true
        #else
        return HMReleaseChannel.isTestFlight
        #endif
    }
    public static var isEnabled: Bool {
        (UserDefaults.standard.object(forKey: HMDefaultsKeys.fpsGraph) as? Bool) ?? channelDefault
    }
    public static func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: HMDefaultsKeys.fpsGraph)
    }
}
