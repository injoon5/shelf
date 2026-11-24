//
//  KEEngine.swift
//  Kiln's engine
//
//  Entry points: compile a source file, find the view to show, run it, and
//  validate it headlessly. Kiln.run and Kiln.validate call straight through.
//

import SwiftUI

@MainActor
enum KilnEngine {

    /// What to render: a view type, an App, a preview block, or bare views.
    enum Root {
        case view(KType)
        case app(KType)
        case preview([KEStmt])
        case staticPreview(KType)
        case snippet([KEStmt])
    }

    struct Compiled {
        let interp: KInterpreter
        let root: Root
    }

    enum Failure: Error {
        case syntax(String)
        case noView(String)
    }

    static func compile(_ code: String, headless: Bool = false, context: KilnContext? = nil) throws -> Compiled {
        try compile(KilnParsedSource(code), headless: headless, context: context)
    }

    /// Builds the interpreter for source already parsed (`Kiln.parse`, off
    /// the main thread): declares its types and runs its globals.
    static func compile(_ parsed: KilnParsedSource, headless: Bool = false, context: KilnContext? = nil) throws -> Compiled {
        let code = parsed.source
        let program: KEProgram
        switch parsed.program {
        case .success(let p): program = p
        case .failure(let e): throw Failure.syntax(formatSyntaxError(e, code))
        }
        let interp = try KInterpreter(program: program, headless: headless, context: context)
        guard let root = findRoot(program, interp, code) else {
            let views = program.types.filter { $0.inherits.contains("View") }.map(\.name)
            if views.isEmpty {
                throw Failure.noView("No SwiftUI view found. Write a `struct ContentView: View { var body: some View { … } }`.")
            }
            throw Failure.noView("Couldn't tell which view to show among \(views.joined(separator: ", ")). Name the main one ContentView.")
        }
        return Compiled(interp: interp, root: root)
    }

    static func formatSyntaxError(_ e: KESyntaxError, _ code: String) -> String {
        let lines = code.components(separatedBy: "\n")
        var out = "Line \(e.line): \(e.message)"
        if e.line > 0, e.line <= lines.count {
            out += "\n  \(e.line) | \(lines[e.line - 1].trimmingCharacters(in: .whitespaces))"
        }
        return out
    }

    static func findRoot(_ program: KEProgram, _ interp: KInterpreter, _ code: String) -> Root? {
        if let t = interp.type(named: "ContentView"), t.isView { return .view(t) }
        if let app = program.types.first(where: { $0.inherits.contains("App") || $0.attributes.contains { $0.name == "main" } }),
           let t = interp.type(named: app.name) { return .app(t) }
        if let p = program.previews.last { return .preview(p) }
        if let pp = program.types.first(where: { $0.inherits.contains("PreviewProvider") }), let t = interp.type(named: pp.name) {
            return .staticPreview(t)
        }
        // The view no other view uses: the screen the code builds up to.
        let views = program.types.filter { $0.inherits.contains("View") && $0.kind == .structType }
        if !views.isEmpty {
            let unused = views.filter { v in
                let uses = code.components(separatedBy: v.name + "(").count - 1 + code.components(separatedBy: v.name + " {").count - 1
                return uses == 0 || (uses == 1 && code.contains("\(v.name)()") && code.contains("#Preview"))
            }
            let pick = (unused.isEmpty ? views : unused).max { a, b in
                let sa = a.properties.count + a.methods.count, sb = b.properties.count + b.methods.count
                return sa == sb ? a.line < b.line : sa < sb
            }
            if let pick, let t = interp.type(named: pick.name) { return .view(t) }
        }
        let snippet = program.globals.filter { if case .expr = $0 { return true }; if case .ifStmt = $0 { return true }; return false }
        if !snippet.isEmpty { return .snippet(program.globals) }
        return nil
    }

    // MARK: - Run

    static func run(_ parsed: KilnParsedSource, context: KilnContext) -> KilnResult {
        context.begin()
        do {
            let compiled = try compile(parsed, context: context)
            let interp = compiled.interp
            // Closing the app's screen stops its tasks and timers first.
            context.onTearDown { [weak interp] in interp?.tearDown() }
            let view = AnyView(KRootView(compiled: compiled))
            // Errors from the top-level code (its globals) are the run's too, not only `onError`'s.
            var result = KilnResult(view: view, consoleOutput: interp.console, errors: interp.errors)
            result.interp = interp
            result.context = context
            return result
        } catch {
            let message: String
            switch error {
            case Failure.syntax(let m), Failure.noView(let m): message = m
            default: message = "\(error)"
            }
            context.record(KilnError(phase: .check, reported: message))
            var result = KilnResult(view: nil, consoleOutput: "", errors: [message])
            result.context = context
            return result
        }
    }

    // MARK: - Validate

    static func validate(_ code: String, ticks: Int, fuel: Int, context: KilnContext) -> KilnValidation {
        context.begin()
        // Whatever happens, nothing the check started runs after it, and a
        // stub context's throwaway folder and defaults go.
        defer { context.tearDown() }
        let compiled: Compiled
        do {
            compiled = try compile(code, headless: true, context: context)
        } catch {
            let message: String
            switch error {
            case Failure.syntax(let m), Failure.noView(let m): message = m
            default: message = "\(error)"
            }
            context.record(KilnError(phase: .check, reported: message))
            return KilnValidation(errors: [message], warnings: [], renderedContent: false, hasView: false)
        }
        let interp = compiled.interp
        context.onTearDown { [weak interp] in interp?.tearDown() }
        interp.budget = fuel
        let probe = KProbe(interp: interp, ticks: ticks)
        probe.run(compiled.root)
        // Nothing the check started may run after it.
        interp.tearDown()
        return KilnValidation(errors: interp.errors, warnings: interp.warnings,
                              renderedContent: probe.renderedContent, hasView: true)
    }

    /// The root's view description (for the probe and the root view).
    static func rootViews(_ root: Root, _ interp: KInterpreter) throws -> [KView] {
        switch root {
        case .view(let t), .app(let t):
            let v = try interp.entry { try interp.instantiate(t, args: [], labels: [], line: 0) }
            if case .structV(let s) = v { return [.custom(s)] }
            return []
        case .preview(let stmts):
            return try interp.entry { try interp.evalBuilder(stmts, KEnv(parent: interp.globalEnv)) }
        case .staticPreview(let t):
            let v = try interp.entry { try interp.staticValue(t, "previews") }
            return KBuiltins.asViews(v, interp)
        case .snippet(let stmts):
            return try interp.entry { try interp.evalBuilder(stmts, KEnv(parent: interp.globalEnv)) }
        }
    }
}

/// Holds the interpreter for the lifetime of the shown view.
struct KRootView: View {
    let compiled: KilnEngine.Compiled
    @StateObject private var refresher = KRootRefresher()

    var body: some View {
        _ = refresher.version
        compiled.interp.onGlobalChange = { [weak refresher] in refresher?.bump() }
        return rootContent.modifier(KRunEnvironment(context: compiled.interp.context))
    }

    @ViewBuilder
    private var rootContent: some View {
        switch compiled.root {
        case .app(let t), .view(let t):
            if case .structV(let s)? = instantiateRoot(t) {
                KHostView(value: s, interp: compiled.interp)
            } else {
                KErrorView(message: compiled.interp.errors.first ?? "Couldn't create \(t.name)")
            }
        default:
            let views = (try? KilnEngine.rootViews(compiled.root, compiled.interp)) ?? []
            KRenderer(interp: compiled.interp).render(.group(views))
        }
    }
}

extension KRootView {
    /// The root view's value. Failing to make it (its `init` throws, a
    /// property's default fails) is the body failing: the host hears of it.
    func instantiateRoot(_ t: KType) -> KV? {
        let interp = compiled.interp
        interp.context.bodyDepth += 1
        defer { interp.context.bodyDepth -= 1 }
        do {
            return try interp.entry { try interp.instantiate(t, args: [], labels: [], line: 0) }
        } catch {
            interp.report(error)
            return nil
        }
    }
}

@MainActor
final class KRootRefresher: ObservableObject {
    @Published var version = 0
    func bump() { version += 1 }
}

// MARK: - Probe

/// Headless validation: evaluate every view, build every row and closure, and
/// fire each action once, without mounting SwiftUI.
@MainActor
final class KProbe {
    let interp: KInterpreter
    let ticks: Int
    var renderedContent = false
    private var actions: [(KFunction, [KV], Bool)] = []
    private var visitedTypes = 0

    init(interp: KInterpreter, ticks: Int) {
        self.interp = interp
        self.ticks = ticks
    }

    static let visible: Set<String> = ["Text", "Image", "Label", "Button", "Toggle", "Slider", "Stepper", "TextField",
        "SecureField", "TextEditor", "Picker", "DatePicker", "ProgressView", "Circle", "Rectangle", "RoundedRectangle",
        "Capsule", "Ellipse", "Color", "LinearGradient", "RadialGradient", "AngularGradient", "Chart", "Gauge", "Link",
        "ContentUnavailableView", "AsyncImage", "ColorPicker", "Menu", "LabeledContent", "Canvas", "MeshGradient", "ConcentricRectangle",
        "AnyShape", "PhaseAnimator", "KeyframeAnimator"]

    static let actionLabels: Set<String> = ["action", "perform", "onIncrement", "onDecrement", "onCommit", "onDismiss"]
    static let actionModifiers: Set<String> = ["onTapGesture", "onAppear", "task", "onChange", "onReceive", "onSubmit",
        "refreshable", "onLongPressGesture", "onDelete", "onMove", "onDisappear"]

    func run(_ root: KilnEngine.Root) {
        do {
            let views = try KilnEngine.rootViews(root, interp)
            views.forEach { walk($0, depth: 0) }
        } catch {
            interp.report(error)
        }
        // Tasks the globals or the views' construction started.
        interp.drain()
        // Fire every action once (onReceive timers `ticks` times). `.task`
        // and `.refreshable` may wait; their tasks run to their end (or to
        // a wait nothing headless answers) before the next action.
        var fired = 0
        while !actions.isEmpty, fired < 400 {
            let (f, args, canWait) = actions.removeFirst()
            fired += 1
            interp.runAction(f, args, canWait: canWait)
        }
    }

    func walk(_ v: KView, depth: Int) {
        guard depth < 60 else { return }
        switch v.kind {
        case .group(let vs), .conditional(_, let vs), .switchBranch(_, let vs):
            vs.forEach { walk($0, depth: depth + 1) }
        case .textConcat, .image:
            renderedContent = true
        case .custom(let s):
            visitedTypes += 1
            guard visitedTypes < 300 else { return }
            let ctx = KSelfContext(type: s.type, location: .box(KBox(.structV(s))), storage: probeStorage(s))
            let env = KEnv(parent: interp.globalEnv, selfContext: ctx)
            guard let body = s.type.computed["body"] else { return }
            do {
                let result = try interp.entry { try interp.runAccessor(body.getter ?? [], env: env, returns: body.type) }
                KBuiltins.asViews(result, interp).forEach { walk($0, depth: depth + 1) }
            } catch {
                interp.report(error)
            }
        case .primitive(let name, let args, let labels, _):
            if Self.visible.contains(name) { renderedContent = true }
            let a = KArgs(args: args, labels: labels)
            if KRenderer.eachRowNames.contains(name) || name == "List" && a.firstIsUnlabeled && a.first.map({ if case .function = $0 { return false }; return true }) == true {
                for row in KRenderer(interp: interp).forEachRows(a) {
                    row.views.forEach { walk($0, depth: depth + 1) }
                }
                return
            }
            if let hook = interp.registry.view(name)?.probe {
                run(hook(nil, KProbe.labeled(args, labels, v.bound), interp), depth: depth)
                for arg in args { if case .view(let inner) = arg { walk(inner, depth: depth + 1) } }
                return
            }
            for (i, arg) in args.enumerated() {
                guard case .function(let f) = arg else { continue }
                let label = labels[i]
                if let l = label, Self.actionLabels.contains(l) { actions.append((f, [], false)); continue }
                if name == "Button", label == nil, i == 1 || (i == 0 && args.count > 1 && labels[1] == "label") {
                    actions.append((f, [], false)); continue
                }
                var sample: [KV] = []
                if name == "GeometryReader" { sample = [KGeometry.sample.kv] }
                if name == "Group", label == "transform" {
                    sample = [a["sections"] != nil ? KSubviews.headlessSections(a["sections"], interp) : KSubviews.headlessCollection(a["subviews"], interp)]
                }
                if name == "AsyncImage" { sample = [.native(.asyncPhase("empty", KRef(nil)))] }
                if name == "TimelineView" { sample = [.tuple([.native(.date(Date()))], ["date"])] }
                if name == "ScrollViewReader" { continue }
                do {
                    let views = try interp.entry { try interp.callBuilder(f, sample) }
                    views.forEach { walk($0, depth: depth + 1) }
                } catch {
                    interp.report(error)
                }
            }
        case .modified(let base, let m):
            walk(base, depth: depth + 1)
            if let hook = interp.registry.modifier(m.name)?.probe {
                run(hook(base, KProbe.labeled(m.args, m.labels, m.bound), interp), depth: depth)
                for arg in m.args { if case .view(let inner) = arg { walk(inner, depth: depth + 1) } }
                return
            }
            if Self.actionModifiers.contains(m.name), case .function(let f)? = m.args.last {
                switch m.name {
                case "onReceive": for _ in 0..<max(1, ticks) { actions.append((f, [.native(.date(Date()))], false)) }
                case "onDelete": actions.append((f, [.native(.indexSet(IndexSet(integer: 0)))], false))
                case "onChange":
                    let n = KRenderer(interp: interp).closureParamCount(.function(f))
                    let v = m.arg("of") ?? .nilValue
                    actions.append((f, n == 0 ? [] : (n == 1 ? [v] : [v, v]), false))
                case "task", "refreshable": actions.append((f, [], true))
                default: actions.append((f, [], false))
                }
                return
            }
            for (i, arg) in m.args.enumerated() {
                guard case .function(let f) = arg else {
                    if case .view(let inner) = arg { walk(inner, depth: depth + 1) }
                    continue
                }
                if m.labels[i] == "item" { continue }
                let sample = interp.registry.modifier(m.name)?.sampleArgs?(m.labels[i], interp) ?? []
                do {
                    let views = try interp.entry { try interp.callBuilder(f, sample) }
                    views.forEach { walk($0, depth: depth + 1) }
                } catch {
                    interp.report(error)
                }
            }
        case .empty, .error:
            break
        }
    }

    /// A bridge's own closures, with the arguments SwiftUI would pass them.
    private func run(_ calls: [KProbeCall], depth: Int) {
        for call in calls {
            switch call.use {
            case .action: actions.append((call.fn, call.args, call.canWait))
            case .content:
                do {
                    let views = try interp.entry { try interp.callBuilder(call.fn, call.args) }
                    views.forEach { walk($0, depth: depth + 1) }
                } catch {
                    interp.report(error)
                }
            }
        }
    }

    private var storages: [KViewStorage] = []

    private func probeStorage(_ s: KStructValue) -> KViewStorage {
        let storage = KViewStorage()
        storage.prepare(s, interp)
        storages.append(storage)
        return storage
    }
}
