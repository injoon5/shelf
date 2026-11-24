//
//  CallFormsAuditTests.swift
//  KilnTests
//
//  Every SwiftUI, Charts and PhotosUI initializer and modifier Kiln claims,
//  written the ways models write it, through Kiln's own overload binder.
//
//  `Tests/SDKCalls/sdk-calls.json` is the SDK half: each declaration's
//  parameters from the iOS SDK's `.swiftinterface` files, with whether each
//  has a default and whether a closure can reach it. `Tools/coverage.sh`
//  writes it (Tools/coverage/Sources/CoverageKit/CallForms.swift).
//
//  For each declaration of a symbol Kiln claims, this writes:
//    - the required arguments only;
//    - with the optional closures;
//    - with every optional argument, and with each one alone;
//  and each of those with its closures in parentheses (labeled), and as
//  trailing closures from each place they can start (the first unlabeled,
//  the rest labeled). It works out where Swift binds each argument (its
//  forward scan, SE-0286) and checks that Kiln's `KOverload.bind`, as `pick`
//  runs it, takes the call and binds each argument to the parameter with the
//  same label.
//
//  Kiln has no types, so where Swift picks between two declarations with the
//  same labels by type (a `SharePreview` closure or a label closure), the
//  audit only asks that Kiln binds the labels Swift would. Values are written
//  as models write them: a string literal for a `String` or
//  `LocalizedStringKey`, a number for a number, a closure for a function.
//
//  `KILN_CALL_FORMS_REPORT=/path/report.txt swift test --filter CallFormsAuditTests`
//  writes every finding, the excluded ones too.
//

import XCTest
@testable import Kiln

// MARK: - The SDK's calls

struct SDKCallFile: Decodable {
    struct Header: Decodable { var sdk: String }
    var header: Header
    var forms: [SDKCall]
}

struct SDKCall: Decodable {
    var id: String
    var receiver: String?
    var introduced: String?
    var deprecated: Bool
    var signature: String
    var params: [SDKParam]

    var kind: String { String(id.prefix { $0 != ":" }) }
    /// `ShareLink`, `sheet` (`modifier:ChartContent.foregroundStyle` → `foregroundStyle`).
    var name: String {
        let rest = id.drop { $0 != ":" }.dropFirst()
        return String(rest.split(separator: ".").last ?? rest)
    }
}

struct SDKParam: Decodable {
    var label: String
    var type: String
    var flags: String

    var swiftLabel: String? { label == "_" ? nil : label }
    var hasDefault: Bool { flags.contains("d") }
    var isFunction: Bool { flags.contains("f") }
    var takesTrailingClosure: Bool { flags.contains("t") }
    var isBuilder: Bool { flags.contains("b") }
    var isVariadic: Bool { flags.contains("v") }
    var isInout: Bool { flags.contains("i") }
    /// Swift needs an argument for it. A metatype with a default
    /// (`key: K.Type = K.self`) counts: nothing infers `K` without it.
    var isRequired: Bool { (!hasDefault && !isVariadic) || (hasDefault && type.hasSuffix(".Type")) }
    /// Never written by hand: `file: String = #fileID`, `line: Int = #line`.
    var isNeverWritten: Bool { hasDefault && ["file", "line", "fileID", "function", "column"].contains(label) }
}

// MARK: - Writing calls

enum CallFormsAudit {
    /// Which optional arguments a written call has.
    enum Variant: String, CaseIterable {
        /// The required arguments only.
        case required
        /// With the optional closures.
        case closures
        /// With every optional argument.
        case everything
        /// With one optional argument.
        case oneOptional = "one optional"
    }

    struct Arg {
        /// The SDK parameter it's written for.
        var param: Int
        var label: String?
        var syntax: KArgSyntax
        /// The first trailing closure: written with no label.
        var unlabeledTrailing = false
        /// A trailing closure (`{ … }` or `label: { … }` after the parentheses).
        var trailing = false
    }

    struct Written {
        var args: [Arg]
        var variant: Variant
        /// Where Swift binds each argument.
        var swift: [Int]
        var labels: [String?] { args.map(\.label) }
        var syntax: [KArgSyntax] { args.map(\.syntax) }
        var usesTrailingClosures: Bool { args.contains { $0.trailing } }

        func text(_ name: String, kind: String) -> String {
            var inParens: [String] = []
            var trailing: [String] = []
            for a in args {
                let v: String
                switch a.syntax {
                case .closureLiteral: v = "{ … }"
                case .stringLiteral: v = "\"…\""
                case .numberLiteral: v = "1"
                case .other: v = "…"
                }
                if a.trailing { trailing.append(a.unlabeledTrailing ? v : "\(a.label ?? "_"): \(v)") }
                else { inParens.append(a.label.map { "\($0): \(v)" } ?? v) }
            }
            var s = (kind == "modifier" ? "." : "") + name
            if !inParens.isEmpty || trailing.isEmpty { s += "(" + inParens.joined(separator: ", ") + ")" }
            if !trailing.isEmpty { s += " " + trailing.joined(separator: " ") }
            return s
        }
    }

    /// How a model writes an argument for this parameter.
    static func syntax(_ p: SDKParam, signature: String) -> KArgSyntax {
        if p.isFunction { return .closureLiteral }
        var t = p.type
        while t.hasSuffix("?") { t.removeLast() }
        if ["LocalizedStringKey", "String", "LocalizedStringResource", "some StringProtocol", "Substring"].contains(t) { return .stringLiteral }
        if ["CGFloat", "Double", "Float", "Int", "Int64", "UInt", "TimeInterval"].contains(t) { return .numberLiteral }
        if t.allSatisfy({ $0.isLetter || $0.isNumber }) {
            if signature.contains("\(t) : StringProtocol") { return .stringLiteral }
            if signature.contains("\(t) : BinaryFloatingPoint") || signature.contains("\(t) : BinaryInteger") { return .numberLiteral }
        }
        return .other
    }

    /// The calls a model could write for one declaration.
    static func forms(_ c: SDKCall) -> [Written] {
        let ps = c.params
        // `inout` parameters (`&x`) don't appear in initializers and modifiers models write.
        if ps.contains(where: \.isInout) { return [] }
        let required = ps.indices.filter { ps[$0].isRequired }
        let optional = ps.indices.filter { !ps[$0].isRequired && !ps[$0].isNeverWritten }
        var subsets: [(Variant, [Int])] = [(.required, [])]
        let optionalClosures = optional.filter { ps[$0].isFunction }
        if !optionalClosures.isEmpty { subsets.append((.closures, optionalClosures)) }
        if optional.count > optionalClosures.count { subsets.append((.everything, optional)) }
        for o in optional where optional.count > 1 || !ps[o].isFunction { subsets.append((.oneOptional, [o])) }

        var out: [Written] = []
        var seen = Set<String>()
        for (variant, extra) in subsets {
            let included = (required + extra).sorted()
            // Trailing closures can start at any argument after which every
            // argument is a closure; or there are none.
            var start = included.count
            while start > 0, ps[included[start - 1]].isFunction { start -= 1 }
            for split in start...included.count {
                // A closure after the first trailing one needs a label.
                if split < included.count, included[(split + 1)...].contains(where: { ps[$0].swiftLabel == nil }) { continue }
                var args: [Arg] = []
                for (k, p) in included.enumerated() {
                    var a = Arg(param: p, label: ps[p].swiftLabel, syntax: syntax(ps[p], signature: c.signature))
                    if k >= split {
                        a.trailing = true
                        if k == split { a.unlabeledTrailing = true; a.label = nil }
                    }
                    args.append(a)
                }
                guard let swift = swiftBinding(ps, args) else { continue }
                let key = args.map { "\($0.label ?? "_"):\($0.syntax):\($0.unlabeledTrailing)" }.joined(separator: " ")
                guard seen.insert(key).inserted else { continue }
                out.append(Written(args: args, variant: variant, swift: swift))
            }
        }
        return out
    }

    /// Where Swift binds each argument: labeled arguments in order, the
    /// unlabeled trailing closure by the forward scan (SE-0286). nil when
    /// Swift rejects the call.
    static func swiftBinding(_ ps: [SDKParam], _ args: [Arg]) -> [Int]? {
        var out = [Int](repeating: -1, count: args.count)
        var next = 0
        for (i, a) in args.enumerated() {
            var found = -1
            var j = next
            if a.unlabeledTrailing {
                // The next argument's label, where the "does a later parameter
                // need an argument" look stops.
                let stop: String?? = i + 1 < args.count ? .some(args[i + 1].label) : .none
                while j < ps.count {
                    let p = ps[j]
                    if !p.takesTrailingClosure { j += 1; continue }
                    if p.isRequired { found = j; break }
                    var laterNeedsOne = false
                    for k in (j + 1)..<max(j + 1, ps.count) {
                        if case .some(let label) = stop, ps[k].swiftLabel == label { break }
                        if ps[k].isRequired { laterNeedsOne = true; break }
                    }
                    if laterNeedsOne { j += 1; continue }
                    found = j
                    break
                }
            } else {
                while j < ps.count {
                    if ps[j].swiftLabel == a.label { found = j; break }
                    if ps[j].isRequired { return nil }
                    j += 1
                }
            }
            guard found >= 0 else { return nil }
            out[i] = found
            next = found + 1
        }
        for (k, p) in ps.enumerated() where p.isRequired && !out.contains(k) { return nil }
        return out
    }

    // MARK: Kiln's side

    /// The overloads a call to this symbol picks from, as the engine has them.
    @MainActor static func overloads(_ c: SDKCall, _ r: KRegistry) -> [KOverload]? {
        switch c.kind {
        case "modifier":
            return r.modifier(c.name)?.forms.map(\.overload)
        default:
            if let v = r.view(c.name), v.constructible { return v.forms.map(\.overload) }
            if let t = r.type(c.name), !t.inits.isEmpty { return t.inits.map(\.overload) }
            return nil
        }
    }

    /// The overload `pick` chooses for the call, and its binding.
    @MainActor static func pick(_ overloads: [KOverload], _ w: Written, _ interp: KInterpreter) -> (KOverload, [Int])? {
        guard let (i, b) = try? interp.pick(overloads, "audit", labels: w.labels, syntax: w.syntax, line: 0) else { return nil }
        return (overloads[i], b)
    }

    // MARK: Findings

    enum Problem: String, CaseIterable {
        /// No overload takes a call Swift takes.
        case rejected = "rejected"
        /// An overload takes it, but binds an argument to another parameter.
        case wrongParameter = "wrong parameter"
    }

    struct Finding {
        var id: String
        var problem: Problem
        var variant: Variant
        var written: String
        var trailing: Bool
        var signature: String
        var deprecated: Bool
        var introduced: String?
        var detail: String
        var excluded: String?

        var line: String {
            "\(written)    [\(problem.rawValue); \(variant.rawValue)\(trailing ? ", trailing" : "")\(deprecated ? ", deprecated" : "")\(introduced.map { ", iOS " + $0 } ?? "")]\n"
                + "        SDK: \(signature)\n" + (detail.isEmpty ? "" : "        Kiln: \(detail)\n")
                + (excluded.map { "        excluded: \($0)\n" } ?? "")
        }
    }

    /// A call two declarations take with different labels bound (Swift
    /// picks by type), and the one Kiln binds.
    struct TypeDecided {
        var id: String
        var written: String
        var swift: [String]
        var kiln: String
    }

    struct Report {
        var findings: [Finding] = []
        var typeDecided: [TypeDecided] = []
        var checked = 0
        var symbols = Set<String>()
        /// Kiln overloads with an SDK declaration's labels whose parameters
        /// differ from it: a default, or a closure kind.
        var registration: [String] = []
        /// Declarations left out, by why.
        var skipped: [String: Int] = [:]
    }

    /// How a Kiln overload with the same labels as an SDK declaration
    /// differs from it, parameter by parameter.
    static func registrationDiff(_ c: SDKCall, _ o: KOverload) -> [String] {
        var out: [String] = []
        for (p, k) in zip(c.params, o.params) {
            let name = p.label + ":"
            if p.isRequired && k.optional { out.append("\(name) is required in the SDK, optional in Kiln") }
            if !p.isRequired && !k.optional { out.append("\(name) has a default in the SDK, required in Kiln") }
            if p.isFunction && !k.kind.isClosure { out.append("\(name) is a function in the SDK, `\(k.kind.keyword)` in Kiln (a trailing closure can't reach it)") }
            if !p.isFunction && k.kind.isClosure && !p.type.isEmpty { out.append("\(name) is \(p.type) in the SDK, `\(k.kind.keyword)` in Kiln") }
            if p.isBuilder && k.kind != .content { out.append("\(name) is a result builder in the SDK, `\(k.kind.keyword)` in Kiln") }
        }
        return out
    }

    static func labelList(_ labels: [String?]) -> String { labels.map { ($0 ?? "_") + ":" }.joined() }

    @MainActor static func audit(_ file: SDKCallFile, _ r: KRegistry, _ interp: KInterpreter) -> Report {
        let manifest = r.manifest(includeHost: false).symbols
        let claimed = Dictionary(manifest.map { ($0.id, $0.support) }, uniquingKeysWith: { a, _ in a })
        var report = Report()
        // Each symbol's calls, written once however many declarations take
        // them (`LocalizedStringKey` and `LocalizedStringResource` titles).
        var calls: [String: [(String, [(SDKCall, Written)])]] = [:]
        var decls: [String: [SDKCall]] = [:]
        var order: [String] = []
        for c in file.forms {
            guard let support = claimed[c.id], support == "full" || support == "partial" else { continue }
            if let why = Exclusions.declaration(c) { report.skipped[why, default: 0] += 1; continue }
            // Kiln picks a modifier's form by its name alone, whatever it's on
            // (`.mask` on a view or on a chart mark), so its calls are checked together.
            let key = c.kind == "modifier" ? "modifier:" + c.name : c.id
            if calls[key] == nil { order.append(key); calls[key] = [] }
            decls[key, default: []].append(c)
            if let os = overloads(c, r) {
                for o in os where !o.lenient && o.params.map(\.label) == c.params.map(\.swiftLabel) {
                    for d in registrationDiff(c, o) { report.registration.append("\(c.id) \(o.display(c.name)): \(d)\(c.deprecated ? " (deprecated)" : "")") }
                }
            }
            for w in forms(c) {
                let written = w.args.map { "\($0.label ?? "_"):\($0.syntax):\($0.unlabeledTrailing)" }.joined(separator: " ")
                if let k = calls[key]!.firstIndex(where: { $0.0 == written }) { calls[key]![k].1.append((c, w)) }
                else { calls[key]!.append((written, [(c, w)])) }
            }
        }
        for id in order {
            let support = calls[id]!.first.flatMap { claimed[$0.1[0].0.id] } ?? "full"
            guard let first = calls[id]!.first?.1.first?.0, let overloads = overloads(first, r), !overloads.isEmpty else { continue }
            report.symbols.insert(id)
            for (_, takers) in calls[id]! {
                report.checked += 1
                let (c, w) = takers.first { !$0.0.deprecated } ?? takers[0]
                let written = w.text(c.name, kind: c.kind)
                // What Swift binds, for each declaration that takes the call:
                // those it was written for, and any other of the symbol's that
                // takes it with each closure on a function.
                var swift = Set(takers.map { c, w in labelList(w.swift.map { c.params[$0].swiftLabel }) })
                for d in decls[id] ?? [] {
                    guard let b = swiftBinding(d.params, w.args),
                          zip(w.args, b).allSatisfy({ ($0.syntax == .closureLiteral) == d.params[$1].isFunction }) else { continue }
                    swift.insert(labelList(b.map { d.params[$0].swiftLabel }))
                }
                func finding(_ p: Problem, _ detail: String) -> Finding {
                    var f = Finding(id: id, problem: p, variant: w.variant, written: written, trailing: w.usesTrailingClosures,
                                    signature: c.signature, deprecated: takers.allSatisfy { $0.0.deprecated },
                                    introduced: takers.compactMap(\.0.introduced).min { $0.compare($1, options: .numeric) == .orderedAscending }, detail: detail)
                    f.excluded = Exclusions.reason(f, c, support: support)
                    return f
                }
                guard let (o, binding) = pick(overloads, w, interp) else {
                    let known = overloads.filter { !$0.lenient }.map { $0.params.map { ($0.label ?? "_") + ":" + $0.kind.keyword + ($0.optional ? "?" : "") }.joined(separator: " ") }
                    report.findings.append(finding(.rejected, "has " + Set(known).sorted().joined(separator: " | ")))
                    continue
                }
                if o.lenient { continue }
                let kiln = labelList(binding.map { o.params[$0].label })
                if !swift.contains(kiln) {
                    report.findings.append(finding(.wrongParameter, "\(o.display(c.name)) binds \(kiln) (Swift: \(swift.sorted().joined(separator: " or ")))"))
                } else if swift.count > 1 {
                    report.typeDecided.append(TypeDecided(id: id, written: written, swift: swift.sorted(), kiln: kiln))
                }
            }
        }
        return report
    }
}

// MARK: - What's left out, and why

enum Exclusions {
    /// Declarations no Kiln app writes, by what's in them.
    static func declaration(_ c: SDKCall) -> String? {
        if c.params.contains(where: { $0.label.count > 1 && $0.label.hasPrefix("_") }) { return "SwiftUI's own (`_internalSystemName:`, `__isExpanded:`)" }
        if c.params.contains(where: { $0.type.hasSuffix("Configuration") }) { return "a style's configuration, which only `makeBody` has" }
        let sig = c.signature
        if sig.contains("ImageResource") { return "an asset catalog image: a Kiln app has no asset catalog" }
        if sig.contains("AppIntent") { return "an App Intent: a Kiln app has none" }
        if sig.contains("TaskExecutor") { return "a task executor" }
        if sig.contains("TableRow") || sig.contains("TableRowBuilder") { return "Table rows" }
        return nil
    }

    /// Calls Kiln doesn't take on purpose, by a piece of their SDK
    /// signature (and the call as written, when it's narrower). Each says why.
    static let calls: [(signature: String, written: String?, why: String)] = [
        ("for type: D.Type", nil, "a window for a value, opened with `openWindow(value:)`: a Kiln app has the one window"),
        ("textRanges: [Range<String.Index>]", nil, "a rotor over text ranges: Kiln's rotors take `entries:` content"),
        ("entryLabel: KeyPath<", nil, "a rotor over key paths: Kiln's rotors take `entries:` content (`AccessibilityRotorEntry`)"),
        ("body: (PlaceholderContentView<Self>)", nil, "an animation or transaction scoped to a body closure (iOS 17): `.animation(_:value:)` and `.transaction { }` work"),
        ("for guide: ContentMarginGuide", nil, "iOS 27.1's `ContentMarginGuide` margins: not bridged yet"),
        ("edges: Edge.Set = .all, alignment: Alignment?)", nil, "iOS 27's aligned `ignoresSafeArea`: not bridged yet"),
        ("strategy: Text.AlignmentStrategy", nil, "iOS 26's `Text.AlignmentStrategy`: not bridged yet"),
        ("ContextMenu<MenuItems>", nil, "the deprecated `ContextMenu` value: `.contextMenu { … }` works"),
        ("CGImage", nil, "a `CGImage`: a Kiln app has `UIImage` (`Image(uiImage:)`)"),
        ("init(_ name: String, bundle: Bundle? = nil, label: Text)", nil, "an asset catalog image: a Kiln app has none"),
        ("name: String, variableValue: Double?, bundle: Bundle?", nil, "an asset catalog image: a Kiln app has none (`Image(systemName:variableValue:)` works)"),
        ("renderer: @escaping (inout GraphicsContext)", nil, "an image drawn with a `GraphicsContext`: Kiln draws in a `Canvas`"),
        ("MeshGradient.Locations", nil, "`MeshGradient.Locations`: Kiln takes `points:` or `bezierPoints:` with `colors:`"),
        ("resolvedColors: [Color.Resolved]", nil, "resolved colors: Kiln takes `colors:`"),
        ("isActive: Binding<Bool>", nil, "the deprecated programmatic link: Kiln navigates with `NavigationStack(path:)` and `.navigationDestination(isPresented:)`"),
        ("tag: V, selection: Binding<V?>", nil, "the deprecated programmatic link: Kiln navigates with `NavigationStack(path:)` and `.navigationDestination(isPresented:)`"),
        ("payloadAction: @escaping ([NSItemProvider])", nil, "`NSItemProvider` payloads: Kiln's `PasteButton` takes `payloadType:`"),
        ("sources: C", nil, "a control over a collection's key paths (mixed state)"),
    ]

    static func reason(_ f: CallFormsAudit.Finding, _ c: SDKCall, support: String) -> String? {
        for e in calls where c.signature.contains(e.signature) && (e.written.map { f.written.contains($0) } ?? true) { return e.why }
        return nil
    }
}

// MARK: - The test

final class CallFormsAuditTests: XCTestCase {
    static var kilnRoot: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }

    static func loadCalls() throws -> SDKCallFile {
        let url = kilnRoot.appendingPathComponent("Tests/SDKCalls/sdk-calls.json")
        return try JSONDecoder().decode(SDKCallFile.self, from: Data(contentsOf: url))
    }

    @MainActor func testEveryFormSwiftTakesBindsTheSameWayInKiln() throws {
        let file = try Self.loadCalls()
        let interp = try KInterpreter(program: try KEParser.parse("let x = 1"), headless: true)
        let report = CallFormsAudit.audit(file, KRegistry.shared, interp)
        let findings = report.findings
        XCTAssertGreaterThan(report.symbols.count, 400, "the audit should reach every claimed view and modifier")
        XCTAssertGreaterThan(report.checked, 3000)

        if let path = ProcessInfo.processInfo.environment["KILN_CALL_FORMS_REPORT"] {
            var out = "Call forms audit, \(file.header.sdk): \(report.checked) calls of \(report.symbols.count) symbols; "
                + "\(findings.count) findings, \(findings.filter { $0.excluded == nil }.count) not excluded.\n\n"
            for (id, fs) in Dictionary(grouping: findings, by: { $0.id }).sorted(by: { $0.key < $1.key }) {
                out += "## \(id)\n"
                for f in fs { out += f.line }
                out += "\n"
            }
            out += "# Declarations left out\n\n"
            for (why, n) in report.skipped.sorted(by: { $0.key < $1.key }) { out += "\(n)  \(why)\n" }
            out += "\n# Registrations that differ from the SDK declaration with their labels\n\n"
            for l in Set(report.registration).sorted() { out += l + "\n" }
            out += "\n# Decided by type: two declarations take the call with different labels bound\n\n"
            for t in report.typeDecided { out += "\(t.written)    Kiln: \(t.kiln)  Swift: \(t.swift.joined(separator: " or "))\n" }
            try Data(out.utf8).write(to: URL(fileURLWithPath: path))
        }
        let open = findings.filter { $0.excluded == nil }
        XCTAssertTrue(open.isEmpty, "\(open.count) calls Swift takes that Kiln doesn't bind the same way:\n" + open.prefix(60).map { $0.line }.joined())
    }

    /// The oracle itself: Swift's forward scan on a few declarations.
    func testTheForwardScan() {
        func p(_ label: String, _ flags: String) -> SDKParam { SDKParam(label: label, type: "", flags: flags) }
        func trailing(_ labels: [String?]) -> [CallFormsAudit.Arg] {
            labels.enumerated().map { i, l in
                CallFormsAudit.Arg(param: 0, label: i == 0 ? nil : l, syntax: .closureLiteral, unlabeledTrailing: i == 0, trailing: true)
            }
        }
        // ShareLink(items:subject:message:preview:label:): preview gets the first closure when label: follows.
        let share = [p("items", "t"), p("subject", "d"), p("message", "d"), p("preview", "ft"), p("label", "ftb")]
        let items = CallFormsAudit.Arg(param: 0, label: "items", syntax: .other)
        XCTAssertEqual(CallFormsAudit.swiftBinding(share, [items] + trailing([nil, "label"])), [0, 3, 4])
        // .sheet(isPresented:onDismiss:content:): one closure is the content.
        let sheet = [p("isPresented", ""), p("onDismiss", "dft"), p("content", "ftb")]
        let bound = CallFormsAudit.Arg(param: 0, label: "isPresented", syntax: .other)
        XCTAssertEqual(CallFormsAudit.swiftBinding(sheet, [bound] + trailing([nil])), [0, 2])
        XCTAssertEqual(CallFormsAudit.swiftBinding(sheet, [bound] + trailing([nil, "content"])), [0, 1, 2])
        // Two optional closures: the first takes it.
        let two = [p("a", "dft"), p("b", "dft")]
        XCTAssertEqual(CallFormsAudit.swiftBinding(two, trailing([nil])), [0])
    }
}
