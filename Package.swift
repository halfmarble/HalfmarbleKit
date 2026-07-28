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
let package = Package(
    name: "HalfmarbleKit",
    platforms: [.iOS(.v16)],
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
        //   xcodebuild test -scheme HalfmarbleKit -destination 'platform=iOS Simulator,name=…'
        .testTarget(name: "HalfmarbleKitTests", dependencies: ["HalfmarbleKit"]),
    ]
)
