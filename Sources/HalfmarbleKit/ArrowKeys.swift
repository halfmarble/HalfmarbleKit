import SwiftUI

//  The arrow-cluster keyboard grammar for halfmarble games on macOS — BOTH
//  ways a halfmarble game reaches a Mac: "Designed for iPad" on Apple silicon,
//  and (since 2026-08-01) a real Mac CATALYST build. See `isMac` below.
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
    /// ⇧ + ← / →  (dir -1 / +1)
    public var shiftLayer: ((_ dir: Int) -> Void)?
    /// ⇧ + ↑ / ↓  (dir -1 = up, +1 = down). Nil leaves ⇧+↑/↓ falling through
    /// to the bare `up`/`down` verbs, which is the pre-2026-08-02 behaviour.
    public var shiftVertical: ((_ dir: Int) -> Void)?
    /// ⌥ + ← / →  (dir -1 / +1). An app that binds only one direction simply
    /// ignores the other — StringFusor's ⌥+← is undo and ⌥+→ does nothing.
    public var optionLayer: ((_ dir: Int) -> Void)?
    /// ⌥ + ↑ / ↓  (dir -1 = up, +1 = down).
    public var optionVertical: ((_ dir: Int) -> Void)?
    /// ⌘ + ANY arrow — one safe verb on all four, canonically undo. Nil
    /// disables the arrow chords without disabling ⌘Z (see `commandZ`).
    public var command: (() -> Void)?
    /// ⌘Z specifically. Nil falls back to `command`, so existing callers keep
    /// the Mac idiom for free; set it to keep ⌘Z when `command` is nil.
    public var commandZ: (() -> Void)?
    /// Unmodified Z / X trigger `optionLayer(-1)` / `optionLayer(1)` — the
    /// classic falling-piece rotate keys. On by default.
    public var zxAliases: Bool
    /// Where unmodified Z / X route when `zxAliases` is on. Nil uses
    /// `optionLayer` (the original behaviour); set it when the app has moved
    /// rotate off ⌥, as StringFusor did on 2026-08-02.
    public var zxLayer: ((_ dir: Int) -> Void)?

    public init(holdBegin: @escaping (_ dir: Int) -> Void,
                holdEnd: @escaping () -> Void,
                up: @escaping () -> Void,
                down: @escaping () -> Void,
                shiftLayer: ((_ dir: Int) -> Void)? = nil,
                shiftVertical: ((_ dir: Int) -> Void)? = nil,
                optionLayer: ((_ dir: Int) -> Void)? = nil,
                optionVertical: ((_ dir: Int) -> Void)? = nil,
                command: (() -> Void)? = nil,
                commandZ: (() -> Void)? = nil,
                zxAliases: Bool = true,
                zxLayer: ((_ dir: Int) -> Void)? = nil) {
        self.holdBegin = holdBegin; self.holdEnd = holdEnd
        self.up = up; self.down = down
        self.shiftLayer = shiftLayer; self.shiftVertical = shiftVertical
        self.optionLayer = optionLayer; self.optionVertical = optionVertical
        self.command = command; self.commandZ = commandZ
        self.zxAliases = zxAliases; self.zxLayer = zxLayer
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
    ///
    /// `isMacCatalystApp` is the WIDER of the two flags — true for a real
    /// Catalyst build AND for an iOS app running on Apple silicon — so it
    /// alone answers "is there a Mac keyboard in front of this window?".
    /// `isiOSAppOnMac` would miss the Catalyst build entirely, which is how
    /// the Mac port shipped its first build with dead arrow keys.
    private static let isMac = ProcessInfo.processInfo.isMacCatalystApp

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
        case .upArrow, .downArrow:
            let dir = press.key == .downArrow ? 1 : -1
            // The vertical layers are checked BEFORE the bare verbs, so a
            // modified ↑/↓ never also fires flip/drop. Nil layers fall
            // through to the bare verbs (the original behaviour).
            if press.modifiers.contains(.shift), let shiftV = bindings.shiftVertical {
                if press.phase == .down { shiftV(dir) }
                return .handled
            }
            if press.modifiers.contains(.option), let optV = bindings.optionVertical {
                if press.phase == .down { optV(dir) }
                return .handled
            }
            if press.phase == .down { press.key == .upArrow ? bindings.up() : bindings.down() }
            return .handled
        default:
            break
        }
        if press.phase == .down {
            if press.modifiers.contains(.command), press.characters.lowercased() == "z",
               let undo = bindings.commandZ ?? bindings.command {
                undo(); return .handled
            }
            if bindings.zxAliases, let rot = bindings.zxLayer ?? bindings.optionLayer {
                switch press.characters.lowercased() {
                case "z": rot(-1); return .handled
                case "x": rot(1);  return .handled
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
