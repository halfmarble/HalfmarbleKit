// The in-app console: everything the app printed, readable ON the device.
//
// Moved here 2026-08-14 from an app whose every diagnosis went through a Mac
// tethered with `devicectl --console`. That is slow, it dies when the session
// is killed, and killing enough of them wedged the device's developer disk
// image badly enough to need a reboot. A console INSIDE the app removes the
// tether — a tester in the field can read the log back and share it, with no
// Mac anywhere near them.
//
// THE IMPLEMENTATION CHOICE THAT MATTERS: it TEES stdout/stderr, it does not
// redirect them. The original descriptor is duplicated first and every captured
// chunk is written straight back to it, so a tethered `devicectl --console`
// keeps working exactly as before — the in-app view is an addition, never a
// replacement. Debugging a bug by removing the other debugger is a bad trade.
//
// Teeing the DESCRIPTOR rather than wrapping a log call also captures
// third-party prints — a vendored engine's own chatter, an ML runtime's
// warnings — which a per-call-site logger never sees. Those lines are usually
// the ones that explain the crash.
import Foundation
import SwiftUI

@MainActor
public final class ConsoleLog: ObservableObject {
    public static let shared = ConsoleLog()

    /// Ring buffer — a two-hour session must not grow an unbounded view.
    public static let capacity = 600
    @Published public private(set) var lines: [String] = []

    private var pipe: Pipe?
    private var originalStdout: Int32 = -1
    private var partial = ""

    private init() {}

    /// Begin capturing. Idempotent — a second call is a no-op rather than a
    /// second pipe, because installing two would lose the first one's tee.
    public func start() {
        guard pipe == nil else { return }
        // Keep a handle on the REAL stdout before hijacking it, so anything
        // tethered still receives everything.
        originalStdout = dup(STDOUT_FILENO)
        setvbuf(stdout, nil, _IONBF, 0)          // no buffering: live lines

        let p = Pipe()
        let w = p.fileHandleForWriting.fileDescriptor
        dup2(w, STDOUT_FILENO)
        dup2(w, STDERR_FILENO)
        let out = originalStdout
        p.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            // Tee straight back to the original descriptor.
            if out >= 0 { data.withUnsafeBytes { _ = write(out, $0.baseAddress, data.count) } }
            guard let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in ConsoleLog.shared.ingest(text) }
        }
        pipe = p
        print("[console] in-app console attached")
    }

    /// Chunks arrive on arbitrary boundaries — hold the tail until its newline,
    /// or half a line shows up as a line and the next one starts mid-word.
    func ingest(_ text: String) {
        partial += text
        while let nl = partial.firstIndex(of: "\n") {
            let line = String(partial[partial.startIndex..<nl])
            partial = String(partial[partial.index(after: nl)...])
            if !line.isEmpty { append(line) }
        }
        // A very long unterminated chunk still shows rather than hiding — a
        // progress bar written with no newline is exactly when you are watching.
        if partial.count > 2000 { append(partial); partial = "" }
    }

    private func append(_ line: String) {
        lines.append(line)
        if lines.count > Self.capacity { lines.removeFirst(lines.count - Self.capacity) }
    }

    public func clear() { lines.removeAll() }

    /// Everything currently held, for the share sheet — see `Share`.
    public var exportText: String { lines.joined(separator: "\n") }

    // MARK: - Colour

    /// Tag prefixes the app wants picked out, in priority order.
    ///
    /// THE KIT CANNOT KNOW YOUR TAGS. This started life with one app's
    /// `[qwen]`/`[kokoro]`/`[tool]` hardcoded, which is useless to the next app
    /// and slightly worse than useless — it colours nothing and looks broken.
    /// Apps set this once at startup:
    /// ```swift
    /// ConsoleLog.tints = [("[tool]", .green), ("[brain]", .orange)]
    /// ```
    public nonisolated(unsafe) static var tints: [(prefix: String, colour: Color)] = []

    /// Substrings that make a line loud regardless of its tag. Defaulted
    /// because "the error lines should be red" is true in every app anybody
    /// has ever written.
    public nonisolated(unsafe) static var alarmWords = ["ERROR", "REFUSED", "WARNING", "!!"]

    /// Colour for one line. The field eye wants the interesting tags to stand
    /// out from the framework chatter without reading every line.
    public nonisolated static func tint(_ line: String) -> Color {
        if alarmWords.contains(where: { line.contains($0) }) { return .red }
        for t in tints where line.hasPrefix(t.prefix) { return t.colour }
        return .secondary
    }
}

#if os(iOS)
/// The console, on screen. iOS only: `textSelection` and the button toggle
/// style are not tvOS API, and a scrolling wall of log text is not a thing
/// anybody wants to drive with a Siri Remote.
@available(iOS 17.0, *)
public struct ConsoleView: View {
    @ObservedObject private var log = ConsoleLog.shared
    @State private var pinToBottom = true

    public init() {}

    public var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("console · \(log.lines.count) lines")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Toggle("follow", isOn: $pinToBottom)
                    .toggleStyle(.button).font(.caption2)
                Button("clear") { log.clear() }.font(.caption2)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(log.lines.enumerated()), id: \.offset) { i, line in
                            Text(line)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(ConsoleLog.tint(line))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                }
                .onChange(of: log.lines.count) { _, _ in
                    guard pinToBottom else { return }
                    proxy.scrollTo("end", anchor: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
