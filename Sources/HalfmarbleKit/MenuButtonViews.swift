import SwiftUI
import UIKit

//  SwiftUI faces of the kit buttons, for the SwiftUI shells (StringFusor's
//  RealityKit shell first). One implementation — the UIKit buttons in
//  MenuButtons.swift — wrapped, so the two frameworks can never drift.

/// The big CTA capsule (ENTER REACTOR / BEGIN…), breathing pulse included.
/// Size it from outside with `.frame(width:height:)` — HMMenu.ctaButtonSize is
/// the cross-app standard.
public struct HMActionButton: UIViewRepresentable {
    let title: String
    let fontSize: CGFloat
    let bgAlpha: CGFloat
    let pulses: Bool
    let action: () -> Void

    public init(_ title: String, fontSize: CGFloat = 25, bgAlpha: CGFloat = 0.14,
                pulses: Bool = true, action: @escaping () -> Void) {
        self.title = title; self.fontSize = fontSize; self.bgAlpha = bgAlpha
        self.pulses = pulses; self.action = action
    }

    public func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    public func makeUIView(context: Context) -> UIButton {
        let b = HMMenu.makeActionButton(title, fontSize: fontSize,
                                        height: HMMenu.ctaButtonSize.height, bgAlpha: bgAlpha)
        b.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .primaryActionTriggered)
        if pulses {
            HMMenu.ctaPulse([b])
            // iOS strips repeating CA animations on backgrounding and never puts
            // them back — re-arm on foreground for as long as the button lives.
            context.coordinator.observer = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification, object: nil,
                queue: .main) { [weak b] _ in
                if let b, b.window != nil { HMMenu.ctaPulse([b]) }
            }
        }
        return b
    }
    public func updateUIView(_ b: UIButton, context: Context) {
        context.coordinator.action = action
    }

    @MainActor public final class Coordinator {
        var action: () -> Void
        var observer: NSObjectProtocol?
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
        deinit { if let o = observer { NotificationCenter.default.removeObserver(o) } }
    }
}

/// The coaching hint line ("new here?  start with  [symbol] LABEL") — the same
/// attributed UILabel ViroFlick renders, for SwiftUI hosts.
public struct HMHintLabel: UIViewRepresentable {
    let prefix: String
    let symbol: String
    let suffix: String

    public init(prefix: String, symbol: String, suffix: String) {
        self.prefix = prefix; self.symbol = symbol; self.suffix = suffix
    }

    public func makeUIView(context: Context) -> UILabel {
        HMMenu.makeHint(prefix, symbol: symbol, suffix: suffix)
    }
    public func updateUIView(_ l: UILabel, context: Context) {}
    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel,
                             context: Context) -> CGSize? {
        uiView.intrinsicContentSize
    }
}

/// The dark action pill (ORIENTATION / DEMO / TEXTBOOK…). Sizes itself to its
/// content at the shared kit height; width can be pinned with `.frame(width:)`.
public struct HMPillButton: UIViewRepresentable {
    let symbol: String
    let title: String
    /// Glyph + label colour together — see HMMenu.makePill. Defaults to house white.
    let tint: UIColor
    let action: () -> Void

    public init(symbol: String, title: String, tint: UIColor = .white,
                action: @escaping () -> Void) {
        self.symbol = symbol; self.title = title; self.tint = tint; self.action = action
    }

    public func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    public func makeUIView(context: Context) -> UIButton {
        let b = HMMenu.makePill(symbol: symbol, title: title, tint: tint)
        b.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .primaryActionTriggered)
        return b
    }
    public func updateUIView(_ b: UIButton, context: Context) {
        context.coordinator.action = action
        // The tint is STATE, not just construction: StringFusor's first-run guidance
        // ends the moment a score lands, and a pill built amber would stay amber for
        // the rest of the session without this. Written only on a real change —
        // assigning baseForegroundColor unconditionally rebuilds the configuration on
        // every SwiftUI update.
        if b.configuration?.baseForegroundColor != tint {
            b.configuration?.baseForegroundColor = tint
            // The GLYPH must be re-baked, not just re-coloured: pillSymbol renders
            // `.alwaysOriginal`, so the image carries its own colour and no
            // configuration change can reach it. Miss this and a tint change repaints
            // the label while the icon keeps the colour it was built with.
            b.configuration?.image = HMMenu.pillSymbol(symbol, tint: tint)
        }
    }
    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton,
                             context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width,
               height: HMMenu.pillHeight)
    }

    @MainActor public final class Coordinator {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}
