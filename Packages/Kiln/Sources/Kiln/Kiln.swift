//
//  Kiln.swift
//  Kiln — a Swift/SwiftUI interpreter you can embed in any iOS or macOS app.
//
//  Public API surface. The interpreter lives in `Engine/` (`KilnEngine`,
//  `KInterpreter`, `KRenderer` …); this file is the namespace hosts call.
//

import SwiftUI

/// Gated debug logging for the interpreter. OFF by default — the parser/runtime
/// emit very chatty traces (including full AST descriptions) that, when always
/// printed, both spam the console and noticeably slow execution (the giant
/// strings get built even when nobody reads them). The `@autoclosure` means the
/// message isn't even constructed unless logging is enabled.
public enum KilnLog {
    nonisolated(unsafe) public static var enabled = false
    @inline(__always) static func d(_ message: @autoclosure () -> String) {
        if enabled { print(message()) }
    }
}

// MARK: - Top-level namespace

/// Kiln runs Swift / SwiftUI source code at runtime inside your app.
///
/// ```swift
/// import Kiln
///
/// let result = Kiln.run("""
/// import SwiftUI
/// struct ContentView: View {
///     var body: some View { Text("Hello, Kiln!") }
/// }
/// """)
///
/// if let view = result.view {
///     // render `view` anywhere AnyView is accepted
/// }
/// ```
public enum Kiln {
    /// Host hook that resolves an `Image("name")` to a runtime SwiftUI image the
    /// host holds (e.g. a photo the user just picked, keyed by a token string).
    /// Returns nil to fall through to the normal asset-catalog lookup. The host
    /// returns a SwiftUI `Image` (not a UIImage) so Kiln stays platform-neutral.
    @MainActor public static var hostImageProvider: ((String) -> Image?)?

    /// Requests the host answers itself, at once, on the main actor, before
    /// `URLSession.shared.data(from:)`/`data(for:)` in the app's code go to the
    /// network: Shelf's `db://` store. Return nil to let a request through.
    /// Because the answer is immediate, the app gets it without waiting, even
    /// in code that can't wait.
    ///
    /// Temporary: PLAN.md §1.7 replaces it with a `DB` host bridge.
    @MainActor public static var hostRequestHandler: ((URLRequest) -> KilnHostResponse?)?

    /// Parse, evaluate, and render a Swift source string. Returns a
    /// `KilnResult` containing the rendered view (when the source produced
    /// one), any `print(...)` output, and any errors raised during parsing
    /// or evaluation.
    ///
    /// Safe to call from the main actor on any iOS 17+ / macOS 14+ device.
    /// No compilation step is involved — this is pure interpretation.
    @MainActor
    public static func run(_ code: String) -> KilnResult {
        KilnEngine.run(code)
    }

    /// Seeds `shuffled()`, `randomElement()`, `Int.random(in:)` and friends in
    /// code run after it is set, so a run can be repeated exactly. nil (the
    /// default) uses the system's random numbers. Native code gets the same
    /// numbers from `KilnRandom(seed:)` with the same seed. A host app
    /// launched with `-KilnRandomSeed N` (a UI test, a demo) starts seeded.
    @MainActor public static var randomSeed: UInt64? = UserDefaults.standard.string(forKey: "KilnRandomSeed").flatMap { UInt64($0) }

    /// Validate Swift source the way a real render + a burst of user input would,
    /// WITHOUT mounting a live SwiftUI view. Unlike `run`, which only constructs
    /// a lazy view wrapper (so render-time crashes, blank screens, and throwing
    /// handlers all look like success), `validate` eagerly evaluates the view
    /// body — running helper functions and firing lifecycle + interaction
    /// handlers (onAppear, onTapGesture, onReceive, Button actions) — and
    /// reports the runtime problems it hits plus whether anything actually
    /// rendered.
    ///
    /// - Parameters:
    ///   - code: the Swift/SwiftUI source (must define `struct ContentView`).
    ///   - ticks: how many times to fire each `onReceive` timer handler, so a
    ///     few frames of a timer-driven app run. Default 8.
    ///   - fuel: max interpreted steps before the run is aborted as a runaway
    ///     loop. Default 2,000,000 — ample for real phone UI/games, but bounded
    ///     so an infinite loop becomes a reported error instead of a hang.
    /// - Returns: a `KilnValidation` with parse + runtime errors, soft warnings,
    ///   and whether visible content was produced.
    @MainActor
    public static func validate(_ code: String, ticks: Int = 8, fuel: Int = 2_000_000) -> KilnValidation {
        KilnEngine.validate(code, ticks: ticks, fuel: fuel)
    }

    /// The Swift a chat reply contains, ready to run: every ```swift block in
    /// order, joined. Models often split one app across blocks (the model type in
    /// one, the view in the next); a later block that redeclares a type replaces
    /// the earlier one. Returns "" when the reply has no Swift blocks.
    public static func swiftSource(fromMarkdown markdown: String) -> String {
        swiftBlocks(in: markdown).joined(separator: "\n\n")
    }

    /// What to run when a person taps Run on one code block of a reply: that
    /// block, preceded by any other blocks of the same reply that declare types
    /// it uses but doesn't define (models often put `struct Habit` in one block
    /// and the view in the next). Alternative versions of the same view in other
    /// blocks are left out, so the tapped one is what runs.
    public static func swiftSource(running block: String, inReply markdown: String) -> String {
        let blocks = swiftBlocks(in: markdown)
        guard blocks.count > 1 else { return block }
        func declared(_ code: String) -> Set<String> {
            let pattern = #"(?:struct|class|enum|protocol|actor|typealias)\s+([A-Z][A-Za-z0-9_]*)"#
            guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
            let ns = code as NSString
            return Set(re.matches(in: code, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) })
        }
        func referenced(_ code: String) -> Set<String> {
            guard let re = try? NSRegularExpression(pattern: #"\b([A-Z][A-Za-z0-9_]*)\b"#) else { return [] }
            let ns = code as NSString
            return Set(re.matches(in: code, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) })
        }
        var included: [String] = []
        var have = declared(block)
        var needed = referenced(block).subtracting(have)
        var changed = true
        while changed {
            changed = false
            for other in blocks where other != block && !included.contains(other) {
                let provides = declared(other)
                if !provides.isDisjoint(with: needed) {
                    included.append(other)
                    have.formUnion(provides)
                    needed = needed.union(referenced(other)).subtracting(have)
                    changed = true
                }
            }
        }
        return (included + [block]).joined(separator: "\n\n")
    }

    static func swiftBlocks(in markdown: String) -> [String] {
        var blocks: [String] = []
        var current: [String]? = nil
        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if current == nil {
                if trimmed.hasPrefix("```"), trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("swift") { current = [] }
                continue
            }
            if trimmed.hasPrefix("```") { blocks.append(current!.joined(separator: "\n")); current = nil; continue }
            current?.append(line)
        }
        if let open = current { blocks.append(open.joined(separator: "\n")) }
        return blocks
    }

    /// Whether code reads as a whole app screen (navigation, lists, forms, tabs,
    /// or simply a program of 50 lines or more) rather than a small view, so a
    /// host can give it the full screen.
    public static func looksLikeApp(_ code: String) -> Bool {
        ["NavigationStack", "NavigationView", "NavigationSplitView", "List {", "List(", "Form {", "TabView", "ScrollView", ".toolbar"]
            .contains { code.contains($0) } || code.split(separator: "\n", omittingEmptySubsequences: true).count >= 50
    }

    /// Convenience flag: returns the latest known version of the Kiln
    /// public API. Bumped on breaking changes.
    public static let version: String = "0.2.1"
}

/// A request the host answered (`Kiln.hostRequestHandler`).
public struct KilnHostResponse {
    public var statusCode: Int
    public var body: Data?
    public init(statusCode: Int, body: Data? = nil) {
        self.statusCode = statusCode
        self.body = body
    }
}

// MARK: - Validation result

/// The outcome of `Kiln.validate(_:)` — a deeper check than `KilnResult` that
/// reflects what actually happened when the view body was evaluated and its
/// handlers fired, not just whether the source parsed.
public struct KilnValidation {
    /// Hard failures: parse errors, plus runtime errors hit while evaluating the
    /// body / firing handlers (undefined function, runaway loop, thrown error).
    public let errors: [String]

    /// Soft problems that don't necessarily break the app but usually indicate a
    /// bug (undefined variable read, missing object key). Surfaced separately so
    /// a caller can choose whether to treat them as blocking.
    public let warnings: [String]

    /// Whether the probe produced any visible content (drawn shapes, text,
    /// controls). `false` means a blank screen even though the source parsed.
    public let renderedContent: Bool

    /// Whether a `ContentView` view was produced at all (parse-level success).
    public let hasView: Bool

    /// The app is considered good when it produced a view, rendered visible
    /// content, and hit no hard errors.
    public var isValid: Bool { hasView && renderedContent && errors.isEmpty }

    public init(errors: [String], warnings: [String], renderedContent: Bool, hasView: Bool) {
        self.errors = errors
        self.warnings = warnings
        self.renderedContent = renderedContent
        self.hasView = hasView
    }
}

// MARK: - Result

/// The outcome of `Kiln.run(_:)`.
public struct KilnResult {
    /// The view produced by the source, if any. `nil` when the input was
    /// pure expression / declaration code (no `var body: some View`).
    public let view: AnyView?

    /// Anything the source emitted via `print(...)`.
    public let consoleOutput: String

    /// Lexer / parser / runtime errors. Empty on a successful run.
    public let errors: [String]

    /// `true` when `view` is non-nil — convenience for `if result.hasView { … }`.
    public var hasView: Bool { view != nil }

    /// The run behind `view`, for `tearDown` and `activeTaskCount`.
    var interp: KInterpreter?

    /// Stops the run: cancels every task the app started (`Task {}`,
    /// `.task {}`, `async let`, task groups), invalidates its timers, and runs
    /// none of its code again: no timer, delayed block or callback. For when
    /// the app's screen closes (PLAN.md §1.7). Safe to call more than once.
    @MainActor public func tearDown() { interp?.tearDown() }

    /// Tasks the app has started that haven't ended.
    @MainActor public var activeTaskCount: Int { interp?.activeTaskCount ?? 0 }

    public init(view: AnyView?, consoleOutput: String, errors: [String]) {
        self.view = view
        self.consoleOutput = consoleOutput
        self.errors = errors
    }
}

// MARK: - Drop-in SwiftUI view

/// `KilnView(code)` renders Swift source as a real SwiftUI view, inline.
///
/// ```swift
/// import Kiln
///
/// struct PreviewScreen: View {
///     @State var source: String = "Text(\"hi\")"
///     var body: some View {
///         VStack {
///             TextEditor(text: $source)
///             Divider()
///             KilnView(code: source)
///         }
///     }
/// }
/// ```
///
/// Re-runs the interpreter whenever `code` changes. Errors are shown
/// inline (override by passing a custom `errorContent`).
@MainActor
public struct KilnView<ErrorContent: View>: View {
    private let code: String
    private let errorContent: ([String]) -> ErrorContent

    @State private var result: KilnResult?

    /// Create a Kiln view with a default red error label.
    public init(code: String) where ErrorContent == _KilnDefaultErrorLabel {
        self.code = code
        self.errorContent = { _KilnDefaultErrorLabel(errors: $0) }
    }

    /// Create a Kiln view with a custom error renderer.
    public init(
        code: String,
        @ViewBuilder errorContent: @escaping ([String]) -> ErrorContent
    ) {
        self.code = code
        self.errorContent = errorContent
    }

    public var body: some View {
        Group {
            if let result = result {
                if let view = result.view {
                    view
                } else if !result.errors.isEmpty {
                    errorContent(result.errors)
                } else {
                    EmptyView()
                }
            } else {
                ProgressView()
            }
        }
        .task(id: code) {
            result?.tearDown()
            result = Kiln.run(code)
        }
    }
}

/// Default error renderer used by `KilnView(code:)`. Internal-ish — exposed
/// only so the public initializer can satisfy `ErrorContent: View`. Style
/// it via a custom `errorContent` closure if you want something else.
public struct _KilnDefaultErrorLabel: View {
    let errors: [String]
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(errors.enumerated()), id: \.offset) { _, msg in
                Text(msg)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.red)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
