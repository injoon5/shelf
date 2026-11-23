//
//  KRegistry.swift
//  Kiln's bridge registry (PLAN.md §1.4)
//
//  Every native thing an app can name is a bridge, declared once, in the
//  folder of its family (`Bridges/<Family>/`):
//
//  - a view (`Toggle`), with overloads: label lists with argument kinds;
//  - a modifier (`.padding`), declared the same way;
//  - a type (`Date`, `URLSession`): initializers, static members, methods and
//    properties; an `async` method returns a suspension;
//  - a global function (`print`, `withAnimation`);
//  - a protocol an app's types adopt (§1.5 adds the proxies);
//  - an environment value or a property wrapper, as declarations the engine
//    already implements.
//
//  The engine asks the registry instead of switching on names. Overloads are
//  picked by labels and argument kinds (a closure literal, a string literal),
//  then by availability on the running OS; arguments are evaluated against
//  each parameter's kind (that's how `.red` resolves) and the bridge gets
//  values. Anything the registry doesn't know is an error with its line.
//
//  Families find themselves: a family's folder defines one class named
//  `KilnBridges_<Family>` (see `KBridgeFamily`), so adding a bridge, or a whole
//  family, never touches a file another family owns. `Docs/bridges.md` is the
//  guide.
//

import SwiftUI

// MARK: - Families

/// Where a bridge lives: its folder under `Bridges/`, and its family in the
/// coverage report (`Tools/coverage/families.json`) and the prompt.
public enum KilnFamily: String, CaseIterable, Sendable {
    // SwiftUI and the frameworks the plan bridges (families.json).
    case core = "Core"
    case controls = "Controls"
    case text = "Text"
    case layout = "Layout"
    case lists = "Lists"
    case navigation = "Navigation"
    case gestures = "Gestures"
    case drawing = "Drawing"
    case focus = "Focus & Keyboard"
    case environment = "Environment"
    case accessibility = "Accessibility"
    case charts = "Charts"
    case scenes = "Scenes"
    case haptics = "Haptics"
    case sharing = "Sharing"
    case units = "Units"
    case audio = "Audio"
    case web = "Web"
    case chart3D = "Chart3D"
    case files = "Files"
    case photos = "Photos"
    case camera = "Camera"
    case motion = "Motion"
    case location = "Location"
    case vision = "Vision"
    case intelligence = "Intelligence"
    case widgets = "Widgets"
    // What isn't SwiftUI: Swift's standard library, Foundation, concurrency
    // and networking. Not in the coverage report, which reads SwiftUI's SDK.
    case language = "Language"
    case foundation = "Foundation"
    case concurrency = "Concurrency"
    case networking = "Networking"
    // Registered by the app hosting Kiln (Shelf's `DB`).
    case host = "Host"

    /// What the family covers, for app authors: the prompt lists a family
    /// with no bridges yet as "not in Kiln yet" with this line, and one with
    /// bridges by its symbols. Round 1–5 keep it true as families fill in.
    public var summary: String {
        switch self {
        case .core: return "views' life cycle: appearing, tasks, changes, timelines"
        case .controls: return "buttons, toggles, pickers, sliders, text fields and the other controls"
        case .text: return "text and fonts"
        case .layout: return "stacks, grids, scroll views, frames and padding"
        case .lists: return "lists, forms and sections"
        case .navigation: return "navigation stacks, tabs, toolbars, sheets and alerts"
        case .gestures: return "taps, long presses, drags, pinches and rotations"
        case .drawing: return "shapes, paths, colors, gradients, images, effects and animation"
        case .focus: return "keyboard focus, submit and keyboard types"
        case .environment: return "state, bindings, observable models and environment values"
        case .accessibility: return "accessibility labels, hints and values"
        case .charts: return "Swift Charts"
        case .scenes: return "the app's scene"
        case .haptics: return "haptic feedback"
        case .sharing: return "the share sheet and the clipboard"
        case .units: return "measurements and unit conversion"
        case .audio: return "playing sounds"
        case .web: return "web views and web pages"
        case .chart3D: return "3D charts"
        case .files: return "importing and exporting files"
        case .photos: return "the photo picker"
        case .camera: return "taking photos with the camera"
        case .motion: return "Core Motion: the accelerometer, the gyroscope and the pedometer"
        case .location: return "the user's location and geocoding"
        case .vision: return "Vision: text and barcode recognition"
        case .intelligence: return "on-device Foundation Models"
        case .widgets: return "widgets on Shelf's Home Screen"
        case .language: return "Swift's standard library"
        case .foundation: return "dates, formatters, JSON, files and settings"
        case .concurrency: return "tasks, async/await, task groups and streams"
        case .networking: return "URLSession requests"
        case .host: return "what the app hosting Kiln adds"
        }
    }

    /// The folder under `Sources/Kiln/Bridges/`, and the suffix of its class.
    var folder: String {
        switch self {
        case .focus: return "Focus"
        default: return rawValue
        }
    }
}

/// How much of a symbol works (the manifest's `support`).
public enum KilnSupport: String, Sendable {
    /// Every listed overload behaves as in SwiftUI.
    case full
    /// Some forms work; the notes say which.
    case partial
    /// Accepted so the code runs, with no effect.
    case stub
}

/// The minimum OS an overload or symbol needs. Checked against the running
/// OS when an overload is picked.
public struct KilnAvailability: Sendable, Equatable {
    public var iOS: OperatingSystemVersion?
    public var macOS: OperatingSystemVersion?

    public init(iOS: String? = nil, macOS: String? = nil) {
        self.iOS = iOS.map(Self.parse)
        self.macOS = macOS.map(Self.parse)
    }

    static func parse(_ s: String) -> OperatingSystemVersion {
        let p = s.split(separator: ".").map { Int($0) ?? 0 }
        return OperatingSystemVersion(majorVersion: p.first ?? 0, minorVersion: p.count > 1 ? p[1] : 0, patchVersion: p.count > 2 ? p[2] : 0)
    }

    /// Whether the running OS has it.
    var isAvailable: Bool {
        #if os(iOS) || os(visionOS) || os(tvOS)
        guard let v = iOS else { return true }
        #else
        guard let v = macOS else { return true }
        #endif
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(v)
    }

    var iOSString: String? { iOS.map { "\($0.majorVersion).\($0.minorVersion)" } }

    public static func == (a: KilnAvailability, b: KilnAvailability) -> Bool {
        a.iOSString == b.iOSString && a.macOS?.majorVersion == b.macOS?.majorVersion && a.macOS?.minorVersion == b.macOS?.minorVersion
    }

    public static func iOS(_ v: String) -> KilnAvailability { KilnAvailability(iOS: v) }
}

// MARK: - Argument kinds

/// What a parameter takes. The kind decides the expected type the argument is
/// evaluated against, which argument syntax it accepts when overloads are
/// picked, and what's checked before the bridge runs.
///
/// In a signature string (see `KSignature`) a kind is a lowercase keyword
/// below, or a capitalized type name for `.typed`.
enum KArgKind: Equatable {
    /// Anything; evaluated with no expected type.
    case any
    /// Evaluated against a type, so implicit members resolve: `Color` makes
    /// `.red` a color, `HorizontalAlignment` makes `.leading` an alignment.
    case typed(String)
    /// A `LocalizedStringKey` or a `String`: a string literal is localized,
    /// so `"\(n) pages"` reads "1,400 pages", as in SwiftUI.
    case title
    /// Values checked when the bridge reads them (`c.string`, `c.double`…).
    /// Numbers stay as written until then (`1` is still an `Int`).
    case string, number, bool
    /// `$value`. `.constant(v)` is accepted too.
    case binding
    /// A `@ViewBuilder` closure: views, built when they're shown.
    case content
    /// A closure the bridge calls.
    case closure
    /// A closure run on an event (a tap, appearing). `validate` fires it.
    case action
    /// A view value (`Text("…")`, `Image(…)`).
    case view
    /// An array of a type (`colors:[Color]`): each element evaluated against it.
    case typedArray(String)

    /// The expected type the engine evaluates the argument against.
    var expected: KETypeRef? {
        if case .typed(let n) = self { return .named(n, []) }
        if case .typedArray(let n) = self { return .array(.named(n, [])) }
        if case .binding = self { return .named("Binding", []) }
        return nil
    }

    var isClosure: Bool {
        switch self {
        case .content, .closure, .action: return true
        default: return false
        }
    }

    /// Whether an argument written this way can bind to this kind.
    func accepts(_ s: KArgSyntax) -> Bool {
        switch (self, s) {
        case (.content, .stringLiteral), (.closure, .stringLiteral), (.action, .stringLiteral): return false
        case (.content, .numberLiteral), (.closure, .numberLiteral), (.action, .numberLiteral): return false
        case (.title, .closureLiteral), (.string, .closureLiteral), (.number, .closureLiteral), (.bool, .closureLiteral): return false
        case (.typed, .closureLiteral), (.typedArray, .closureLiteral), (.binding, .closureLiteral), (.view, .stringLiteral), (.view, .numberLiteral): return false
        case (.binding, .stringLiteral), (.binding, .numberLiteral), (.number, .stringLiteral): return false
        default: return true
        }
    }

    var keyword: String {
        switch self {
        case .any: return "any"
        case .typed(let n): return n
        case .title: return "title"
        case .string: return "string"
        case .number: return "number"
        case .bool: return "bool"
        case .binding: return "binding"
        case .content: return "content"
        case .closure: return "closure"
        case .action: return "action"
        case .view: return "view"
        case .typedArray(let n): return "[\(n)]"
        }
    }

    init(keyword k: String) {
        switch k {
        case "any", "": self = .any
        case "title": self = .title
        case "string": self = .string
        case "number", "double", "int", "cgfloat": self = .number
        case "bool": self = .bool
        case "binding": self = .binding
        case "content": self = .content
        case "closure": self = .closure
        case "action": self = .action
        case "view": self = .view
        default:
            if k.hasPrefix("["), k.hasSuffix("]") { self = .typedArray(String(k.dropFirst().dropLast())); return }
            precondition(k.first?.isUppercase == true, "Unknown argument kind '\(k)' in a bridge signature")
            self = .typed(k)
        }
    }
}

/// How an argument is written, which is all overload resolution can see
/// before evaluating it.
enum KArgSyntax: Equatable {
    case closureLiteral, stringLiteral, numberLiteral, other

    init(_ e: KEExpr) {
        switch e {
        case .closure: self = .closureLiteral
        case .string: self = .stringLiteral
        case .int, .double: self = .numberLiteral
        default: self = .other
        }
    }

    /// From an evaluated value (an engine-made view, a render-time lookup).
    init(value v: KV) {
        switch v {
        case .function: self = .closureLiteral
        case .string: self = .stringLiteral
        case .int, .double: self = .numberLiteral
        default: self = .other
        }
    }
}

struct KParam: Equatable {
    var label: String?
    var kind: KArgKind { didSet { expected = kind.expected } }
    var optional = false
    var variadic = false
    /// The kind's expected type, made once.
    private(set) var expected: KETypeRef?

    init(label: String?, kind: KArgKind, optional: Bool = false, variadic: Bool = false) {
        self.label = label
        self.kind = kind
        self.optional = optional
        self.variadic = variadic
        self.expected = kind.expected
    }

    var display: String { (label ?? "_") + ":" }
}

/// A list of parameters, written as a string so a bridge is one line:
///
///     "_:title isOn:binding"                       Toggle("Wi-Fi", isOn: $on)
///     "alignment:HorizontalAlignment? spacing:number? content:content"
///     "_:any... separator:string? terminator:string?"
///
/// Each parameter is `label:kind`, `_` for no label, `?` when it has a
/// default, `...` when variadic. Kinds are `KArgKind`'s keywords, or a type
/// name. A trailing closure keeps its label (`content`, `label`), as in
/// SwiftUI's declarations; the first trailing closure is written without one,
/// and binds to the first closure parameter left.
enum KSignature {
    static func parse(_ s: String) -> [KParam] {
        s.split(separator: " ").map { token in
            var t = String(token)
            var p = KParam(label: nil, kind: .any)
            if t.hasSuffix("...") { p.variadic = true; p.optional = true; t.removeLast(3) }
            if t.hasSuffix("?") { p.optional = true; t.removeLast() }
            let parts = t.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            precondition(parts.count == 2, "A bridge parameter is label:kind, got '\(token)'")
            p.label = parts[0] == "_" ? nil : parts[0]
            p.kind = KArgKind(keyword: parts[1])
            return p
        }
    }
}

// MARK: - Overloads

/// One form of a bridge: its parameters, when it's available, and notes.
/// `lenient` overloads take any labels and read arguments by label themselves
/// (the standard library's methods, which Kiln has always taken loosely).
final class KOverload {
    let params: [KParam]
    let lenient: Bool
    /// For a lenient overload: kinds by label (`nil` key: unlabeled), for the
    /// expected types arguments are evaluated against.
    let lenientKinds: [String?: KArgKind]
    let availability: KilnAvailability?
    let notes: String?
    /// The receiver a modifier is bridged on (`Shape`, `Text`), for the manifest.
    let receiver: String?
    /// The call waits: `Kiln.check` says so when it isn't `await`ed
    /// (`Task.sleep`, `URLSession.data`). Set with `async: true`.
    var isAsync = false
    /// The closures passed to it run where they can wait (`Task {}`, `.task {}`,
    /// `.refreshable {}`, a task group). Elsewhere `Kiln.check` says an `await`
    /// in a closure argument can't wait. Set with `closuresCanWait: true`.
    var closuresCanWait = false
    /// Accepted with no effect (`stub(_:)`): `Kiln.check` warns.
    var isStub = false

    init(params: [KParam], lenient: Bool = false, lenientKinds: [String?: KArgKind] = [:],
         availability: KilnAvailability? = nil, notes: String? = nil, receiver: String? = nil) {
        self.params = params
        self.lenient = lenient
        self.lenientKinds = lenientKinds
        self.availability = availability
        self.notes = notes
        self.receiver = receiver
    }

    /// `Toggle(_:isOn:)`.
    func display(_ name: String) -> String {
        if lenient { return name + "(…)" }
        return name + "(" + params.map(\.display).joined() + ")"
    }

    /// The labels for the manifest: `["_", "isOn"]`.
    var manifestLabels: [String] { params.map { $0.label ?? "_" } }

    /// The kind an argument is evaluated as, for a lenient overload.
    func lenientKind(_ label: String?) -> KArgKind { lenientKinds[label] ?? .any }

    /// Which parameter each argument binds to, or nil if this overload doesn't
    /// take these arguments.
    func bind(_ labels: [String?], _ syntax: [KArgSyntax]) -> [Int]? { bind(labels) { syntax[$0] } }

    func bind(_ labels: [String?], _ syntaxOf: (Int) -> KArgSyntax) -> [Int]? {
        if lenient { return Array(labels.indices) }
        var out = [Int](repeating: -1, count: labels.count)
        var p = 0                 // the next parameter that can take an argument
        var variadicOpen = -1     // a variadic parameter still taking unlabeled arguments
        for (i, label) in labels.enumerated() {
            let syntax = syntaxOf(i)
            if variadicOpen >= 0, label == nil, params[variadicOpen].kind.accepts(syntax) {
                out[i] = variadicOpen
                continue
            }
            variadicOpen = -1
            var j = p
            var found = -1
            while j < params.count {
                let param = params[j]
                // A trailing closure (unlabeled) binds a labeled closure parameter;
                // one with a default is passed over when a later closure parameter
                // needs an argument (Swift's forward scan, SE-0286).
                let trailing = label == nil && syntax == .closureLiteral && param.kind.isClosure && param.label != nil
                    && !(param.optional && params[(j + 1)...].contains { $0.kind.isClosure && !$0.optional })
                let labelMatches = param.label == label || trailing
                if labelMatches && param.kind.accepts(syntax) { found = j; break }
                // Only a parameter with a default can be skipped.
                if !param.optional { return nil }
                j += 1
            }
            guard found >= 0 else { return nil }
            out[i] = found
            if params[found].variadic && label == params[found].label { variadicOpen = found }
            p = found + 1
        }
        // Whatever's left must have a default.
        if params[p...].contains(where: { !$0.optional }) { return nil }
        return out
    }

}

/// An overload picked for a call, kept on the view or modifier it made so the
/// renderer doesn't pick again.
struct KBound {
    let overload: KOverload
    /// The parameter each argument binds to.
    let binding: [Int]
}

// MARK: - Bridges

/// What every bridge has, for errors and the manifest.
class KBridge {
    let name: String
    let family: KilnFamily
    var support: KilnSupport
    var introduced: String?
    var notes: String?
    /// The file it's declared in (`Bridges/Controls/Toggle.swift`).
    var source: String
    /// Kept out of the manifest: engine-made helpers (`UserShape`).
    var isInternal = false

    init(name: String, family: KilnFamily, support: KilnSupport, introduced: String?, notes: String?, source: String) {
        self.name = name
        self.family = family
        self.support = support
        self.introduced = introduced
        self.notes = notes
        self.source = source
    }
}

/// A SwiftUI view (or chart mark, toolbar item, tab): how it's built from a
/// call, and how it's shown.
final class KViewBridge: KBridge {
    struct Form {
        let overload: KOverload
        /// Builds the real view, inside the SwiftUI `body` that shows it.
        let render: @MainActor (KCall) -> AnyView
    }
    var forms: [Form] = []
    /// The manifest's kind: `view`, `content` (marks, toolbar items, tabs) or `gesture`.
    var manifestKind = "view"
    var owner: String?
    /// Whether code can write `Name(…)` (engine-made views like `UserShape` can't).
    var constructible = true
    /// Makes the value a call evaluates to. Default: the view description
    /// (`.primitive`), which the renderer shows with `render`.
    var make: (@MainActor (KCall) throws -> KV)?
    /// How a check runs its closures (KProbeCall); nil: each as content, with no arguments.
    var probe: KProbe.Hook?
}

/// A modifier: how its arguments are taken, and how it changes a view.
final class KModifierBridge: KBridge {
    /// `.name`, for messages.
    lazy var display = "." + name
    struct Form {
        let overload: KOverload
        /// The view with the modifier applied. `c.base` is the description of
        /// the view it's applied to (a shape, a `ForEach`). The view itself is
        /// the second argument when the renderer already has it (an image
        /// rebuilt with its chain), else `c.view` shows it.
        let apply: @MainActor (KCall, AnyView?) -> AnyView
    }
    var forms: [Form] = []
    /// The same modifier on a `Text` that stays a `Text` (so `Text + Text`
    /// and `Text` in a `Label` keep it). nil: applying it makes a view.
    var text: (@MainActor (KCall, Text) -> Text?)?
    /// For styles: the style protocol and its members (`ButtonStyle`: `bordered`…).
    var styles: (owner: String, names: [String])?
    var owner: String?
    /// How a check runs its closures (KProbeCall); nil: each as content, with no arguments.
    var probe: KProbe.Hook?
}

/// A closure a check (`Kiln.validate`) or the transcript runs, with
/// arguments like the ones SwiftUI passes: a `Canvas` renderer gets a context
/// and a size, a drag's `onChanged` a drag value.
struct KProbeCall {
    enum Use {
        /// It makes views: they're walked.
        case content
        /// An event fires it: it runs once, after the walk.
        case action
    }
    let fn: KFunction
    var args: [KV] = []
    var use: Use = .content
    var canWait = false
}

extension KProbe {
    /// For a modifier, `base` is the view (or gesture) it's on.
    typealias Hook = @MainActor (_ base: KView?, _ args: KArgs, _ interp: KInterpreter) -> [KProbeCall]
}

/// A native type: initializers, static members, properties and methods.
final class KTypeBridge: KBridge {
    typealias Fn = @MainActor (inout KCall) throws -> KV
    struct Method {
        let overload: KOverload
        let run: Fn
    }
    struct Property {
        let get: Fn
        /// `c.args[0]` is the new value; `c.receiver` the object.
        let set: (@MainActor (inout KCall) throws -> Void)?
        let notes: String?
        let support: KilnSupport
        /// Reading it waits (`task.value`).
        var isAsync = false
    }
    var inits: [Method] = []
    var staticProperties: [String: Property] = [:]
    var staticMethods: [String: [Method]] = [:]
    var properties: [String: Property] = [:]
    var methods: [String: [Method]] = [:]
    /// Members not listed by name: `.format` styles that grow with each
    /// call, symbolic SwiftUI values (`Edge.Set.all`). nil when there's none.
    var anyProperty: (@MainActor (inout KCall, String) throws -> KV?)?
    var anyMethod: (@MainActor (inout KCall, String) throws -> KV?)?
    var anyStatic: (@MainActor (inout KCall, String) throws -> KV?)?
    var anyStaticMethod: (@MainActor (inout KCall, String) throws -> KV?)?
    var anySetter: (@MainActor (inout KCall, String) throws -> Bool)?
    /// `.name` where this type is expected: `.red` for a `Color`.
    var implicit: (@MainActor (String, [KV], [String?]) -> KV?)?
    /// Another type whose members this one also has (`Set` → `Sequence`).
    var fallback: String?
    /// Turns a value of this type into the fallback's (a `String` into its characters).
    var asFallback: (@MainActor (KV, KInterpreter) throws -> KV)?
    /// The manifest kind: `type`, or `view` for `Color` and the gradients.
    var manifestKind = "type"
    /// Statics are listed in the manifest as `member:Type.name` (colors,
    /// fonts, animations); otherwise they're part of the type.
    var membersInManifest = false
    /// How `init` is written for the manifest (`Date.init` vs `Date(…)`).
    var isNamespace = false
}

/// A global function: `print`, `min`, `withAnimation`, `withTaskGroup`.
final class KFunctionBridge: KBridge {
    var forms: [KTypeBridge.Method] = []
    /// The namespace it's listed under in the manifest (`Swift`, `SwiftUI`).
    var owner = "Swift"
}

/// A protocol an app's own types can adopt (PLAN.md §1.5). With a `proxy`,
/// native code can use the app's value as the real protocol: the proxy is a
/// native type conforming to it that forwards each requirement to the app's
/// member (`Engine/KEProxies.swift`, `Docs/bridges.md`, "A protocol proxy").
final class KProtocolBridge: KBridge {
    /// What an adopting type must declare: `body`, `path(in:)`. A trailing `?`
    /// marks one with a default (`animatableData?`), which isn't required.
    /// `Kiln.check` and the manifest read these.
    var requirements: [String] = []
    /// The same, parsed: static, `async` and optional ones marked.
    var members: [KRequirement] = []
    /// Makes the native proxy for an app value whose type adopts the protocol
    /// (an `AnyShape`, a `Layout`, an `NSObject` delegate…). nil: a
    /// declaration only, which the engine implements itself (`Identifiable`).
    var proxy: (@MainActor (KAppValue) -> Any)?
    /// For a delegate protocol: the Objective-C protocols the proxy object
    /// conforms to, and how it maps selectors (`KDelegateProxy`).
    var delegate: KDelegateSpec?

    var asyncRequirements: [String] { members.filter(\.isAsync).map(\.display) }
}

/// An `@Environment` value: its default, before the view sees SwiftUI's.
final class KEnvironmentBridge: KBridge {
    var value: @MainActor (KInterpreter) -> KV = { _ in .nilValue }
    /// SwiftUI's own value, read where the view is shown (KEHostInputs).
    var read: (@MainActor (EnvironmentValues, KInterpreter) -> KV)?
    /// `.environment(\.key, v)`: sets SwiftUI's value for the views inside.
    var write: (@MainActor (inout EnvironmentValues, KV, KInterpreter) -> Void)?
}

/// A property wrapper the engine implements (`@State`, `@AppStorage`).
final class KWrapperBridge: KBridge {}

/// A macro the engine reads as a declaration (`@Entry`, `@Animatable`; KEMacros).
final class KMacroBridge: KBridge {}

// MARK: - The registry

@MainActor
final class KRegistry {
    /// Kiln's own bridges plus the host's.
    static let shared: KRegistry = {
        let r = KRegistry()
        r.loadFamilies()
        return r
    }()

    private(set) var views: [String: KViewBridge] = [:]
    private(set) var modifiers: [String: KModifierBridge] = [:]
    private(set) var types: [String: KTypeBridge] = [:]
    private(set) var functions: [String: KFunctionBridge] = [:]
    private(set) var protocols: [String: KProtocolBridge] = [:]
    private(set) var environment: [String: KEnvironmentBridge] = [:]
    private(set) var wrappers: [String: KWrapperBridge] = [:]
    private(set) var macros: [String: KMacroBridge] = [:]
    /// Result builders bridges declare (`RegexComponentBuilder`), by attribute name (KEBuilders).
    private(set) var resultBuilders: [String: KNativeBuilder] = [:]
    /// `.name` with no expected type, by name (`.infinity`, `.degrees(…)`, `.red`).
    private(set) var contextFree: [String: @MainActor ([KV], [String?], String?) -> KV?] = [:]
    /// Type names that are aliases of another (`CGFloat` → `Double`).
    private(set) var aliases: [String: String] = [:]
    /// Bare names that are values (`pi`).
    private(set) var constants: [String: @MainActor (KInterpreter) -> KV] = [:]
    /// Every symbol, by its manifest id, so two families can't both claim one.
    private var owners: [String: String] = [:]

    /// Finds each family's class (`KilnBridges_Controls`…) and lets it register.
    private func loadFamilies() {
        for f in KilnFamily.allCases {
            guard let cls = NSClassFromString("KilnBridges_" + f.folder.replacingOccurrences(of: " ", with: "")) as? KBridgeFamily.Type else { continue }
            cls.register(into: self)
        }
    }

    func removeClaim(_ id: String) { owners[id] = nil }

    private func claim(_ id: String, _ family: KilnFamily, _ source: String) {
        if let prior = owners[id] {
            preconditionFailure("Kiln bridge \(id) is registered twice: in \(prior) and in \(source)")
        }
        owners[id] = source
    }

    // MARK: Lookups

    func view(_ name: String) -> KViewBridge? { views[name] }
    func modifier(_ name: String) -> KModifierBridge? { modifiers[name] }
    func type(_ name: String) -> KTypeBridge? { types[name] ?? aliases[name].flatMap { types[$0] } }
    func function(_ name: String) -> KFunctionBridge? { functions[name] }
    func contextFreeMember(_ name: String) -> (@MainActor ([KV], [String?], String?) -> KV?)? { contextFree[name] }
    func constant(_ name: String) -> (@MainActor (KInterpreter) -> KV)? { constants[name] }

    // MARK: Registration (see the builders in KRegistryBuilders.swift)

    func add(_ b: KViewBridge) {
        claim("view:" + b.name, b.family, b.source)
        views[b.name] = b
    }

    func add(_ b: KModifierBridge) {
        claim("modifier:" + (b.owner.map { $0 + "." } ?? "") + b.name, b.family, b.source)
        modifiers[b.name] = b
    }

    func add(_ b: KTypeBridge) {
        claim("type:" + b.name, b.family, b.source)
        types[b.name] = b
    }

    func add(_ b: KFunctionBridge) {
        claim("function:" + b.name, b.family, b.source)
        functions[b.name] = b
    }

    func add(_ b: KProtocolBridge) {
        claim("protocol:" + b.name, b.family, b.source)
        protocols[b.name] = b
    }

    func add(_ b: KEnvironmentBridge) {
        claim("environment:" + b.name, b.family, b.source)
        environment[b.name] = b
    }

    func add(_ b: KWrapperBridge) {
        claim("wrapper:" + b.name, b.family, b.source)
        wrappers[b.name] = b
    }

    func add(_ b: KMacroBridge) {
        claim("macro:" + b.name, b.family, b.source)
        macros[b.name] = b
    }

    func addResultBuilder(_ b: KNativeBuilder) {
        resultBuilders[b.name] = b
    }

    func addContextFree(_ name: String, _ resolve: @escaping @MainActor ([KV], [String?], String?) -> KV?) {
        contextFree[name] = resolve
    }

    /// Another name for a type. An engine-only one (`ColorOrStyle`, what a
    /// shape-style argument is evaluated against) stays out of the manifest.
    func alias(_ name: String, to target: String, engineOnly: Bool = false) {
        aliases[name] = target
        if engineOnly { hiddenAliases.insert(name) }
    }
    private(set) var hiddenAliases: Set<String> = []

    func addConstant(_ name: String, _ value: @escaping @MainActor (KInterpreter) -> KV) { constants[name] = value }

    /// Every bridge, for the manifest.
    var allBridges: [KBridge] {
        Array(views.values) as [KBridge] + Array(modifiers.values) + Array(types.values) + Array(functions.values)
            + Array(protocols.values) + Array(environment.values) + Array(wrappers.values) + Array(macros.values)
    }

    // MARK: Values → types

    /// The type a value's members are looked up on.
    static func typeName(of v: KV) -> String {
        switch v {
        case .void: return "Void"
        case .nilValue: return "Optional"
        case .bool: return "Bool"
        case .int: return "Int"
        case .double: return "Double"
        case .string: return "String"
        case .array: return "Array"
        case .dict: return "Dictionary"
        case .set: return "Set"
        case .tuple: return "Tuple"
        case .range: return "Range"
        case .structV(let s): return s.type.name
        case .enumV(let e): return e.type.name
        case .object(let o): return o.type.name
        case .function: return "Function"
        case .type: return "Type"
        case .view: return "View"
        case .binding: return "Binding"
        case .native(let n):
            switch n {
            case .color: return "Color"
            case .font: return "Font"
            case .date: return "Date"
            case .uuid: return "UUID"
            case .angle: return "Angle"
            case .implicit: return "ImplicitMember"
            case .keyPath: return "KeyPath"
            case .indexSet: return "IndexSet"
            case .url: return "URL"
            case .gridItem: return "GridItem"
            case .format: return "FormatStyle"
            case .strokeStyle: return "StrokeStyle"
            case .animation: return "Animation"
            case .timer: return "Timer"
            case .publisher: return "Timer.TimerPublisher"
            case .dismiss: return "DismissAction"
            case .asyncPhase: return "AsyncImagePhase"
            case .object(let kind, _): return kind
            case .size: return "CGSize"
            case .point: return "CGPoint"
            case .transition: return "AnyTransition"
            case .shape: return "AnyShape"
            case .path: return "Path"
            case .rect: return "CGRect"
            case .suspension: return "Suspension"
            case .boxed(let b): return b.type
            }
        }
    }
}

/// A family's bridges. Each family folder defines exactly one subclass, named
/// with `@objc(KilnBridges_<Folder>)`, and the registry finds it by that name:
///
///     @objc(KilnBridges_Controls)
///     final class ControlsBridges: KBridgeFamily {
///         override class func register(into r: KRegistry) { … }
///     }
///
/// So families never share a file. The folder is `KilnFamily.folder`.
@MainActor
class KBridgeFamily: NSObject {
    @MainActor class func register(into r: KRegistry) {}
}
