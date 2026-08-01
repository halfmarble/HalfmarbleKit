import SwiftUI

//  The arrow-cluster keyboard grammar for halfmarble games on macOS
//  ("Designed for iPad" on Apple silicon — ProcessInfo.isiOSAppOnMac).
//
//  The hand never leaves the arrows; modifiers are verb layers
//  (gerard, 2026-08-01, designed for StringFusor):
//
//      bare ← / →      the app's held walk (holdBegin/holdEnd — the app owns
//                      the cadence, so walk speed is the game's, not the
//                      keyboard's repeat rate)
//      bare ↑ / ↓      two one-shot verbs (e.g. FLIP / DROP)
//      ⇧ + ← / →       one secondary layer (e.g. SHIFT the board)
//      ⌥ + ← / →       another (e.g. ROTATE ccw/cw; Z/X alias it)
//      ⌘ + ANY arrow   ONE safe verb — canonically UNDO. All four arrows mean
//                      the same thing, so the chord cannot be pressed wrong.
//      ⌘Z              the same verb, as the native Mac idiom.
//
//  Two deliberate refusals, learned once so every app inherits them:
//  bare-modifier triggers are not offered (a lone ⌘ press is the first half
//  of every system chord — ⌘-Tab, ⌘-Q — so acting on it fires spuriously),
//  and key auto-repeat fires nothing except the bare ←/→ hold (commit verbs
//  must not machine-gun; undo especially, since it has no redo).
//
//  SwiftUI hosts attach `.hmArrowKeys(...)`. UIKit hosts (ViroFlick) will
//  need a pressesBegan/pressesEnded adapter when they grow keyboard support —
//  UIKeyCommand alone cannot express the key-up half of the held walk.

/// What the keys do — the app supplies its own verbs. Layers left nil are
/// simply ignored (their chords fall through untouched).
@available(iOS 18.0, *)
public struct HMArrowKeyBindings {
    public var holdBegin: (_ dir: Int) -> Void
    public var holdEnd: () -> Void
    public var up: () -> Void
    public var down: () -> Void
    public var shiftLayer: ((_ dir: Int) -> Void)?
    public var optionLayer: ((_ dir: Int) -> Void)?
    public var command: (() -> Void)?
    /// Unmodified Z / X trigger `optionLayer(-1)` / `optionLayer(1)` — the
    /// classic falling-piece rotate keys. On by default.
    public var zxAliases: Bool

    public init(holdBegin: @escaping (_ dir: Int) -> Void,
                holdEnd: @escaping () -> Void,
                up: @escaping () -> Void,
                down: @escaping () -> Void,
                shiftLayer: ((_ dir: Int) -> Void)? = nil,
                optionLayer: ((_ dir: Int) -> Void)? = nil,
                command: (() -> Void)? = nil,
                zxAliases: Bool = true) {
        self.holdBegin = holdBegin; self.holdEnd = holdEnd
        self.up = up; self.down = down
        self.shiftLayer = shiftLayer; self.optionLayer = optionLayer
        self.command = command; self.zxAliases = zxAliases
    }
}

@available(iOS 18.0, *)
public struct HMArrowKeys: ViewModifier {
    let bindings: HMArrowKeyBindings
    /// False on menu/chooser/replay screens — keys go inert rather than
    /// steering a hidden board.
    let active: Bool
    /// By default the keys exist only on macOS; pass false to also serve
    /// hardware keyboards on iPad.
    let macOnly: Bool
    @FocusState private var focused: Bool

    /// One check at launch: this never changes mid-run.
    private static let isMac = ProcessInfo.processInfo.isiOSAppOnMac

    public func body(content: Content) -> some View {
        if Self.isMac || !macOnly {
            content
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .onAppear { focused = true }
                .onChange(of: active) { _, isActive in if isActive { focused = true } }
                .onKeyPress(phases: [.down, .up, .repeat]) { handle($0) }
        } else {
            content
        }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard active else { return .ignored }
        let isArrow = press.key == .leftArrow || press.key == .rightArrow
                   || press.key == .upArrow || press.key == .downArrow
        // ⌘ + any arrow, checked before the per-arrow verbs so all four
        // arrows mean one safe thing under ⌘. Repeat ignored: fires once.
        if isArrow, press.modifiers.contains(.command), let command = bindings.command {
            if press.phase == .down { command() }
            return .handled
        }
        switch press.key {
        case .leftArrow, .rightArrow:
            let dir = press.key == .rightArrow ? 1 : -1
            if press.modifiers.contains(.shift), let shift = bindings.shiftLayer {
                if press.phase == .down { shift(dir) }
                return .handled
            }
            if press.modifiers.contains(.option), let opt = bindings.optionLayer {
                if press.phase == .down { opt(dir) }
                return .handled
            }
            switch press.phase {
            case .down: bindings.holdBegin(dir)
            case .up:   bindings.holdEnd()
            default:    break            // .repeat — the hold walks on its own
            }
            return .handled
        case .upArrow:
            if press.phase == .down { bindings.up() }
            return .handled
        case .downArrow:
            if press.phase == .down { bindings.down() }
            return .handled
        default:
            break
        }
        if press.phase == .down {
            if press.modifiers.contains(.command), press.characters.lowercased() == "z",
               let command = bindings.command {
                command(); return .handled
            }
            if bindings.zxAliases, let opt = bindings.optionLayer {
                switch press.characters.lowercased() {
                case "z": opt(-1); return .handled
                case "x": opt(1);  return .handled
                default:  break
                }
            }
        }
        return .ignored
    }
}

@available(iOS 18.0, *)
public extension View {
    /// Modifier-layered arrow-cluster keys (see HMArrowKeyBindings). Attach
    /// once to the game content; a no-op away from macOS unless `macOnly`
    /// is false.
    func hmArrowKeys(_ bindings: HMArrowKeyBindings,
                     active: Bool,
                     macOnly: Bool = true) -> some View {
        modifier(HMArrowKeys(bindings: bindings, active: active, macOnly: macOnly))
    }
}
