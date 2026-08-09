# HalfmarbleKit

The shared iOS/tvOS layer behind [halfmarble](https://halfmarble.com)'s apps — the chrome, the
plumbing, and the hard-won platform workarounds that every one of them needs and none of them
should own a private copy of.

Extracted 2026-07-25, when a second app's landing screen set out to pixel-match the first's and the
two menu-button implementations had already drifted apart.

## What's in it

| | |
|---|---|
| `AudioHost` | The `AVAudioEngine` host: engine graph, session config, interruption / route-change / media-services-reset recovery, and a 20 Hz fader that doubles as an engine watchdog. Apps supply the content; the host renders it through one callback. |
| `StoreUnlock` | StoreKit 2 one-time unlock: product load, the lifelong `Transaction.updates` listener, exact entitlement reconciliation (revocation- and absence-aware), purchase with verify-then-finish, and three-state restore. |
| `MenuButtons` / `MenuButtonViews` | The house buttons — pills and the big CTA, black-outline treatment, press feedback, tremor tap-debounce, breathing pulse. UIKit core with thin SwiftUI wrappers. |
| `Brand` / `BrandSplash` | Wordmark, ring mark, the charitable-giving pledge, and the lockup metrics both splash choreographies share. |
| `GameCenter` | Authentication, leaderboard and achievement submission, with the app supplying its own IDs. |
| `ArrowKeys` / `HoldKeys` | Hardware-keyboard and game-controller input, including hold-to-repeat. |
| `Frost` / `Outline` / `OutlineSwiftUI` | The two blur recipes and the outline treatment, so every surface matches. |
| `PerfProbe` / `FPSTimelineView` / `StartupProf` | The FPS · RAM · BUILD diagnostic strip and startup profiling. |
| `Haptics` / `UISound` / `DefaultsKeys` / `Version` / `ReleaseChannel` | The small shared utilities. |
| `HalfmarbleTestKit` | Test-only harnesses (imports XCTest). App **test** targets depend on this; app targets never do. |

## Using it

```swift
.package(url: "https://github.com/halfmarble/HalfmarbleKit.git", from: "1.0.0")
```

Platforms are iOS 16+ and tvOS 26+. The Mac ships as Mac Catalyst, which inherits the iOS entry —
native AppKit would mean a second implementation of every button, which is the one thing this
package exists to prevent.

## Building and testing

The kit is iOS-only, so `swift build` / `swift test` on macOS cannot build it. Use an iOS simulator
destination:

```bash
xcodebuild test -scheme HalfmarbleKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## A note on the comments

Many of the comments in here are longer than the code they sit above, and they name dates, field
reports and the reasoning behind a specific constant. That is deliberate: nearly every non-obvious
line in this package exists because something failed on a real device, and the comment is the
record of what. Please keep that style — a value with a reason is maintainable, a magic number is
not.

## Prior art

The tremor debounce in `MenuButtons.swift` — an input filter whose window is derived from the
characteristic frequency of a hand tremor, scoped per control so it never eats a fast deliberate
sequence — is published as a defensive publication and **dedicated to the public domain**:
[PRIOR_ART_TREMOR_DEBOUNCE.md](PRIOR_ART_TREMOR_DEBOUNCE.md).

It is there so the method stays freely practicable by anyone and cannot be patented by a third
party. It is an accessibility technique and makes no health claim.

## License

[Apache 2.0](LICENSE). The halfmarble name and ring mark are trademarks of Halfmarble LLC and are
not licensed for use by the Apache 2.0 grant — fork the code freely, but ship it under your own
brand.
