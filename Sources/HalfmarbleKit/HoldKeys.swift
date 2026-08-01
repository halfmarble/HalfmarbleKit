import UIKit

//  HMHoldKeys — a row of hold-to-act keys for macOS ("Designed for iPad"),
//  the keyboard transcription of fingers resting on glass. Designed for
//  ViroFlick's Triage case (gerard, 2026-08-01): V B N M map left-to-right
//  onto the four orbs, key-down is finger-down and key-up is finger-up, and
//  at most `maxHeld` keys act at once — the canonical 2 recreates the
//  two-thumb phone grip (left index on V/B, right index on N/M), so the cap
//  falls out of anatomy instead of feeling arbitrary. A key pressed past the
//  cap is IGNORED, exactly as a third finger "doesn't fit" on glass — under
//  tremor, ignoring is more predictable than newest-steals-oldest.
//
//  Two one-shot safety verbs ride along, both taking the kit's leading-edge
//  tremor debounce (HMMenu.acceptMenuTap — without it a tremor double-tap
//  pauses and instantly unpauses, which reads as "pause is broken"):
//
//      SPACE   pause/resume — the panic button on the key that cannot be
//              missed; a mis-press costs nothing. Firing keys are force-
//              released first, so nothing resumes firing on unpause unless
//              still physically down.
//      ESC     cancel/back — one consistent meaning everywhere: retreat one
//              level (dismiss the overlay, back a menu, open pause from raw
//              play — the host decides what "back" means where).
//
//  UIKit-core per the kit's architecture: the host view overrides
//  pressesBegan/Ended/Cancelled and forwards (ViroFlick's shell is UIKit).
//  UIKeyCommand cannot express the key-up half of a hold, hence UIPress.
//  UIPressesEvent does not auto-repeat, so no repeat filtering is needed.
//  A SwiftUI wrapper can join when a SwiftUI shell needs hold keys.
public final class HMHoldKeys {

    public struct Bindings {
        /// Lowercase key characters in orb order, left to right ("v","b","n","m").
        public var keys: [String]
        /// How many may act at once (Triage: 2 — one finger per hand).
        public var maxHeld: Int
        public var holdBegin: (_ index: Int) -> Void
        public var holdEnd: (_ index: Int) -> Void
        /// SPACE, debounced. Called AFTER the force-release of held keys.
        public var pause: (() -> Void)?
        /// ESC, debounced.
        public var cancel: (() -> Void)?

        public init(keys: [String], maxHeld: Int,
                    holdBegin: @escaping (_ index: Int) -> Void,
                    holdEnd: @escaping (_ index: Int) -> Void,
                    pause: (() -> Void)? = nil,
                    cancel: (() -> Void)? = nil) {
            self.keys = keys.map { $0.lowercased() }
            self.maxHeld = maxHeld
            self.holdBegin = holdBegin; self.holdEnd = holdEnd
            self.pause = pause; self.cancel = cancel
        }
    }

    public var bindings: Bindings
    /// Keys exist only on macOS by default; hosts may widen for iPad
    /// hardware keyboards.
    public var enabled: Bool

    /// Held key indices, in press order (first pressed first).
    public private(set) var held: [Int] = []

    public init(_ bindings: Bindings,
                enabled: Bool = ProcessInfo.processInfo.isiOSAppOnMac) {
        self.bindings = bindings
        self.enabled = enabled
    }

    /// Force-release every held key (holdEnd fires for each) — call on
    /// pause, scene teardown, or app resign so nothing keeps firing.
    public func releaseAll() {
        let releasing = held
        held.removeAll()
        for i in releasing { bindings.holdEnd(i) }
    }

    /// Silent state drop for host-side mass-clears (run teardown, quit):
    /// clears the held list WITHOUT firing holdEnd — for callers that have
    /// already cleared their own lane state wholesale, possibly under a lock
    /// the holdEnd closure would also want. Later key-ups simply no-op.
    public func reset() { held.removeAll() }

    /// Returns true when the press was consumed (host should not call super).
    @discardableResult
    public func pressesBegan(_ presses: Set<UIPress>) -> Bool {
        guard enabled else { return false }
        var consumed = false
        for press in presses {
            guard let key = press.key else { continue }
            switch key.keyCode {
            case .keyboardSpacebar:
                if let pause = bindings.pause {
                    if HMMenu.acceptMenuTap() { releaseAll(); pause() }
                    consumed = true
                }
            case .keyboardEscape:
                if let cancel = bindings.cancel {
                    if HMMenu.acceptMenuTap() { cancel() }
                    consumed = true
                }
            default:
                guard let i = bindings.keys.firstIndex(of: key.charactersIgnoringModifiers.lowercased()),
                      !key.modifierFlags.contains(.command) else { continue }
                consumed = true
                guard !held.contains(i), held.count < bindings.maxHeld else { continue }
                held.append(i)
                bindings.holdBegin(i)
            }
        }
        return consumed
    }

    @discardableResult
    public func pressesEnded(_ presses: Set<UIPress>) -> Bool {
        guard enabled else { return false }
        var consumed = false
        for press in presses {
            guard let key = press.key,
                  let i = bindings.keys.firstIndex(of: key.charactersIgnoringModifiers.lowercased()),
                  let at = held.firstIndex(of: i) else { continue }
            held.remove(at: at)
            bindings.holdEnd(i)
            consumed = true
        }
        return consumed
    }

    /// Cancelled presses release like ended ones — a hold must never stick.
    @discardableResult
    public func pressesCancelled(_ presses: Set<UIPress>) -> Bool {
        pressesEnded(presses)
    }
}
