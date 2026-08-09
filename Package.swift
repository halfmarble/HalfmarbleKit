// swift-tools-version: 5.9
import PackageDescription

// HalfmarbleKit — the shared UI chrome for every halfmarble app.
//
// Born 2026-07-25 when StringFusor's landing screen set out to pixel-match
// ViroFlick's: the menu buttons (pills + the big CTA, with the black-outline
// treatment, press feedback, tremor debounce, and the breathing pulse) and the
// FPS timeline strip now live HERE, once. ViroFlick is UIKit/SpriteKit and
// StringFusor is SwiftUI/RealityKit, so the kit's core is UIKit (hostable by
// both) with thin SwiftUI wrappers for the SwiftUI shells.
//
// THREE PLATFORMS, ONE UIKit CORE (2026-08-01): StringFusor added Mac and Apple
// TV. Both keep UIKit — the Mac ships as Mac CATALYST (native AppKit would mean
// a second implementation of every button, which is the one thing this package
// exists to prevent), and tvOS is UIKit natively. Catalyst needs no platform
// entry of its own: it inherits the iOS one. tvOS floors at 26 because that is
// where RealityKit arrives, and no halfmarble TV app can predate it.
let package = Package(
    name: "HalfmarbleKit",
    platforms: [.iOS(.v16), .tvOS("26.0")],
    products: [
        .library(name: "HalfmarbleKit", targets: ["HalfmarbleKit"]),
        // Test-only harnesses (imports XCTest) — app TEST targets depend on
        // this; app targets never do.
        .library(name: "HalfmarbleTestKit", targets: ["HalfmarbleTestKit"]),
    ],
    targets: [
        .target(
            name: "HalfmarbleKit",
            resources: [.process("Resources")]   // the halfmarble ring mark
        ),
        .target(name: "HalfmarbleTestKit"),
        // The kit's OWN contracts (run with an iOS-simulator destination —
        // the kit is iOS-only, so `swift test` on macOS cannot build it):
        //   xcodebuild test -scheme HalfmarbleKit-Package -destination 'platform=iOS Simulator,name=…'
        // The scheme is HalfmarbleKit-PACKAGE, not HalfmarbleKit: SwiftPM
        // generates a library scheme per product plus one whole-package scheme,
        // and only the latter includes the test targets. The library scheme
        // fails with "Scheme HalfmarbleKit is not currently configured for the
        // test action", which reads like a broken checkout rather than the
        // wrong scheme name.
        .testTarget(name: "HalfmarbleKitTests", dependencies: ["HalfmarbleKit"]),
    ]
)
