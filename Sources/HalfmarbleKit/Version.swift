import Foundation

//  The build/version identity every halfmarble app stamps on its screens —
//  one implementation for what used to be three copies (ViroFlick's
//  versionStampText, StringFusor's PerfHUD.build + LandingView.version).

public enum HMVersion {
    /// The build number. Read from the bundled buildnumber.txt the bump script
    /// copies into resources — NOT CFBundleVersion: with GENERATE_INFOPLIST_FILE,
    /// Xcode's plist-generation step can run AFTER the stamp script and regenerate
    /// the plist from the static CURRENT_PROJECT_VERSION (= 1), clobbering the
    /// stamp (the on-device "BLD 1" bug). The bundled file is written directly by
    /// the script, so it always carries the real number; the plist is the fallback.
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
