import Foundation

//  The build/version identity every halfmarble app stamps on its screens —
//  one implementation for what used to be three copies (ViroFlick's
//  versionStampText, StringFusor's PerfHUD.build + LandingView.version).

public enum HMVersion {
    /// The build number, from the bundled buildnumber.txt the build phase writes
    /// into resources, with CFBundleVersion as the fallback.
    ///
    /// THE "BLD 1" BUG THIS ORDER WAS WRITTEN FOR IS NOW FIXED AT THE SOURCE
    /// (2026-08-23) — in StringFusor (f77f54e) and ViroFlick (5607402). Worth
    /// recording what it was, because the workaround here is why it survived so
    /// long: with GENERATE_INFOPLIST_FILE, Xcode generates the product's Info.plist
    /// during packaging, AFTER the last build phase, from CURRENT_PROJECT_VERSION —
    /// which was hardcoded to 1. A phase that stamped the built plist therefore won
    /// on clean builds and lost on every incremental one, and lost silently: it
    /// could stamp the file, read the right value back, and still ship 1.
    ///
    /// Reading the bundled file first meant every SCREEN showed the right number
    /// throughout. It could not protect what was UPLOADED, which is the number that
    /// actually matters — CFBundleVersion is what App Store Connect ranks builds by.
    ///
    /// Those two apps now let an xcconfig own CURRENT_PROJECT_VERSION and have the
    /// phase read the value back, so the two numbers are equal by construction. This
    /// order is kept anyway: it costs nothing, it still covers an app that has not
    /// adopted the fix (DashTales hand-bumps and sets no CURRENT_PROJECT_VERSION),
    /// and a build number that disagrees with itself is exactly the failure the
    /// fallback exists to survive.
    ///
    /// NOTE FOR THE NEXT APP: the fix cannot live in this package. SPM cannot inject
    /// a build phase or an xcconfig into a host target, so BuildNumber.xcconfig and
    /// the phase are per-app by necessity — copy StringFusor's. Only this reader is
    /// shared. (Flutter apps — SteadyHeartBeat, AutophagyTracker — need nothing:
    /// their Runner already sets CURRENT_PROJECT_VERSION = $(FLUTTER_BUILD_NUMBER).)
    public static let build: String = {
        if let url = Bundle.main.url(forResource: "buildnumber", withExtension: "txt"),
           let n = try? String(contentsOf: url, encoding: .utf8)
               .trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            return n
        }
        return (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "—"
    }()

    /// CFBundleShortVersionString (MARKETING_VERSION via GENERATE_INFOPLIST_FILE).
    public static let marketing: String =
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"

    /// "v<marketing> (b<build>)", e.g. "v1.0.0 (b444)" — the footer stamp.
    public static var stamp: String { "v\(marketing) (b\(build))" }
}
