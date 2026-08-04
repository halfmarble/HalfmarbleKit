import Foundation

//  Distribution-channel policy (2026-07-25) — extracted from ViroFlick's
//  FPSStrip ladder, because "which channel am I on" is release policy, not
//  FPS policy.

public enum HMReleaseChannel {
    /// A sandbox receipt — the standard runtime tell for a build that did NOT come
    /// from the public App Store.
    ///
    /// It does NOT isolate TestFlight. **App Review installs carry a sandbox receipt
    /// too** (so do local device builds), which is why this is named "pre-release"
    /// rather than "TestFlight". The distinction is not pedantic: while this was
    /// called `isTestFlight` it defaulted the FPS diagnostic strip ON, which put a
    /// black FPS pill over the Dynamic Island on every screen *for the App Store
    /// reviewer* — leftover-instrumentation territory (Guideline 2.2) on a release
    /// candidate, and the exact opposite of the ladder documented below.
    ///
    /// There is no receipt-based way to tell a tester from a reviewer. Anything that
    /// must be true for testers but false for review needs an explicit build-time
    /// signal, not this flag.
    public static let isPreRelease =
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
}

/// The FPS graph's availability ladder:
///   dev builds      → on   (DEBUG default)
///   everything else → OFF, with a SETTINGS toggle — customers would misread the
///                          red line, but Glass Box means anyone may look under
///                          the hood.
/// An explicit user choice (the stored HMDefaultsKeys.fpsGraph Bool) overrides
/// the channel default on every tier and persists.
///
/// TestFlight testers used to get it on by default, on the reasoning that testers
/// are collaborators and their hitch screenshots are free cross-device profiling
/// data. That reasoning still holds — but the receipt cannot tell a tester apart
/// from a reviewer, and the cost of guessing wrong lands on the submission. Testers
/// now switch it on in SETTINGS; the choice persists, so it costs a tester one tap
/// and the reviewer never sees it.
public enum HMFPSStrip {
    public static var channelDefault: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    public static var isEnabled: Bool {
        (UserDefaults.standard.object(forKey: HMDefaultsKeys.fpsGraph) as? Bool) ?? channelDefault
    }
    public static func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: HMDefaultsKeys.fpsGraph)
    }
}
