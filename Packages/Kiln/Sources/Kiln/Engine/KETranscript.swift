//
//  KETranscript.swift
//  Kiln's engine
//
//  A deterministic, text record of everything a run can show: the view tree
//  each body evaluates to (a structural dump, not pixels), what the code
//  printed, the errors and warnings with their lines, and how all of that
//  changes after each scripted action (every `onAppear` and `.task`, then
//  each button and tap in turn).
//
//  `Tools/KilnDiff` runs it on two builds of Kiln and compares the text, so
//  a change to how code runs can be checked against the engine before it on
//  every input (PLAN.md §1.3). It only uses what both engines have, plus the
//  two calls in `KETranscriptShim.swift`.
//

import SwiftUI

extension Kiln {
    /// The transcript of a run (see KETranscript.swift). For tests and tools.
    @_spi(KilnTesting) @MainActor
    public static func transcript(_ code: String, steps: Int = 12) -> String {
        KTranscript.run(code, steps: steps)
    }
}

@MainActor
final class KTranscript {
    private let interp: KInterpreter
    private let root: KilnEngine.Root
    private var lines: [String] = []
    /// @State per hosted view, by its place in the tree, kept across dumps
    /// so an action's effect shows in the next one.
    private var storages: [String: KViewStorage] = [:]
    private var actions: [(label: String, fn: KFunction, args: [KV], appear: Bool, canWait: Bool)] = []
    private var visited = 0
    private var reportedErrors = 0
    private var reportedWarnings = 0
    private var consoleShown = 0

    private init(interp: KInterpreter, root: KilnEngine.Root) {
        self.interp = interp
        self.root = root
    }

    static func run(_ code: String, steps: Int) -> String {
        let compiled: KilnEngine.Compiled
        do {
            compiled = try KilnEngine.compile(code)
        } catch let f as KilnEngine.Failure {
            switch f {
            case .syntax(let m), .noView(let m): return "compile error: \(m)\n"
            }
        } catch {
            return "compile error: \(error)\n"
        }
        compiled.interp.budget = 2_000_000
        let t = KTranscript(interp: compiled.interp, root: compiled.root)
        t.section("start")
        t.dump()
        // Everything that runs when the screen appears, in tree order.
        let appear = t.actions.filter(\.appear)
        if !appear.isEmpty {
            for a in appear { t.fire(a.fn, a.args, canWait: a.canWait) }
            t.section("appeared (\(appear.map(\.label).joined(separator: ", ")))")
            t.dump()
        }
        // Then each other action, by its position in the current tree.
        for step in 0..<steps {
            let candidates = t.actions.filter { !$0.appear }
            guard !candidates.isEmpty else { break }
            let a = candidates[step % candidates.count]
            t.fire(a.fn, a.args, canWait: a.canWait)
            t.section("after \(a.label)")
            t.dump()
        }
        return t.lines.joined(separator: "\n") + "\n"
    }

    // MARK: Steps

    private func section(_ title: String) {
        lines.append("== " + title)
        let console = interp.console
        if console.count > consoleShown {
            let added = String(console.dropFirst(consoleShown))
            for l in added.split(separator: "\n", omittingEmptySubsequences: false).dropLast(added.hasSuffix("\n") ? 1 : 0) {
                lines.append("console: " + Self.normalize(String(l)))
            }
            consoleShown = console.count
        }
        for e in interp.errors.dropFirst(reportedErrors) { lines.append("error: " + Self.normalize(e)) }
        reportedErrors = interp.errors.count
        for w in interp.warnings.dropFirst(reportedWarnings) { lines.append("warning: " + Self.normalize(w)) }
        reportedWarnings = interp.warnings.count
    }

    private func fire(_ f: KFunction, _ args: [KV], canWait: Bool) {
        interp._transcriptFire(f, args, canWait: canWait)
        interp._transcriptDrain()
    }

    private func dump() {
        actions = []
        visited = 0
        do {
            let views = try KilnEngine.rootViews(root, interp)
            for (i, v) in views.enumerated() { walk(v, depth: 0, path: "\(i)") }
        } catch {
            interp.report(error)
        }
        // Errors raised while evaluating show right after the tree.
        for e in interp.errors.dropFirst(reportedErrors) { lines.append("error: " + Self.normalize(e)) }
        reportedErrors = interp.errors.count
        for w in interp.warnings.dropFirst(reportedWarnings) { lines.append("warning: " + Self.normalize(w)) }
        reportedWarnings = interp.warnings.count
    }

    private func emit(_ depth: Int, _ text: String) {
        lines.append(String(repeating: "  ", count: depth) + Self.normalize(text))
    }

    // MARK: The tree

    private func walk(_ v: KView, depth: Int, path: String) {
        guard depth < 60 else { emit(depth, "…"); return }
        switch v.kind {
        case .empty: emit(depth, "Empty")
        case .error(let m): emit(depth, "Error \(m)")
        case .image: emit(depth, "Image(native)")
        case .textConcat(let a, let b):
            emit(depth, "Text+")
            walk(a, depth: depth + 1, path: path + ".a")
            walk(b, depth: depth + 1, path: path + ".b")
        case .group(let vs):
            emit(depth, "Group")
            for (i, c) in vs.enumerated() { walk(c, depth: depth + 1, path: path + "/\(i)") }
        case .conditional(let b, let vs):
            emit(depth, "If \(b)")
            for (i, c) in vs.enumerated() { walk(c, depth: depth + 1, path: path + "/\(b ? "t" : "f")\(i)") }
        case .switchBranch(let n, let vs):
            emit(depth, "Case \(n)")
            for (i, c) in vs.enumerated() { walk(c, depth: depth + 1, path: path + "/s\(n).\(i)") }
        case .custom(let s):
            visited += 1
            guard visited < 300 else { emit(depth, "\(s.type.name) (not expanded)"); return }
            let key = path + ":" + s.type.name
            let storage: KViewStorage
            if let existing = storages[key] { storage = existing } else {
                storage = KViewStorage()
                storage.prepare(s, interp)
                storages[key] = storage
            }
            emit(depth, s.type.name + " " + fields(s, storage))
            let ctx = KSelfContext(type: s.type, location: .box(KBox(.structV(s))), storage: storage)
            let env = KEnv(parent: interp.globalEnv, selfContext: ctx)
            guard let body = s.type.computed["body"] else { emit(depth + 1, "(no body)"); return }
            do {
                let result = try interp.entry { try interp.runAccessor(body.getter ?? [], env: env, returns: body.type) }
                for (i, c) in KBuiltins.asViews(result, interp).enumerated() { walk(c, depth: depth + 1, path: key + "/\(i)") }
            } catch {
                interp.report(error)
                emit(depth + 1, "body failed")
            }
        case .modified(let base, let m):
            walk(base, depth: depth, path: path)
            emit(depth + 1, ".\(m.name)(\(arguments(m.args, m.labels)))")
            let label = "\(base.primitiveName ?? "view").\(m.name)@\(m.line)"
            if KProbe.actionModifiers.contains(m.name), case .function(let f)? = m.args.last {
                switch m.name {
                case "onAppear", "task":
                    actions.append((label, f, [], true, m.name == "task"))
                case "onReceive":
                    actions.append((label, f, [.native(.date(Date(timeIntervalSince1970: 0)))], false, false))
                case "onDelete":
                    actions.append((label, f, [.native(.indexSet(IndexSet(integer: 0)))], false, false))
                case "onChange", "onDisappear":
                    break   // fired by SwiftUI, not by a person
                default:
                    actions.append((label, f, [], false, m.name == "refreshable"))
                }
                return
            }
            for (i, arg) in m.args.enumerated() {
                switch arg {
                case .view(let inner):
                    walk(inner, depth: depth + 2, path: path + ".m\(m.name)\(i)")
                case .function(let f):
                    if m.labels[i] == "item" { continue }
                    content(f, [], depth: depth + 2, path: path + ".m\(m.name)\(i)")
                default:
                    continue
                }
            }
        case .primitive(let name, let args, let labels, let line):
            emit(depth, "\(name)(\(arguments(args, labels)))")
            let a = KArgs(args: args, labels: labels)
            if name == "ForEach" || name == "List" && a.first.map({ if case .function = $0 { return false }; return true }) == true {
                for (r, row) in KRenderer(interp: interp).forEachRows(a).enumerated() {
                    emit(depth + 1, "row \(show(row.id))")
                    for (i, c) in row.views.enumerated() { walk(c, depth: depth + 2, path: path + "/r\(r).\(i)") }
                }
                return
            }
            for (i, arg) in args.enumerated() {
                switch arg {
                case .view(let inner):
                    walk(inner, depth: depth + 1, path: path + "/a\(i)")
                case .function(let f):
                    let label = labels[i]
                    if let l = label, KProbe.actionLabels.contains(l) {
                        actions.append(("\(name)(\(l))@\(line)", f, [], false, false)); continue
                    }
                    if name == "Button", label == nil, i == 1 || (i == 0 && args.count > 1 && labels[1] == "label") {
                        actions.append(("Button[\(title(args))]@\(line)", f, [], false, false)); continue
                    }
                    if name == "ScrollViewReader" { continue }
                    var sample: [KV] = []
                    if name == "GeometryReader" { sample = [.tuple([.native(.size(393, 852))], ["size"])] }
                    if name == "AsyncImage" { sample = [.native(.asyncPhase("empty", KRef(nil)))] }
                    if name == "TimelineView" { sample = [.tuple([.native(.date(Date(timeIntervalSince1970: 0)))], ["date"])] }
                    content(f, sample, depth: depth + 1, path: path + "/a\(i)")
                default:
                    continue
                }
            }
        }
    }

    private func content(_ f: KFunction, _ args: [KV], depth: Int, path: String) {
        do {
            let views = try interp.entry { try interp.callBuilder(f, args) }
            for (i, c) in views.enumerated() { walk(c, depth: depth, path: path + "/\(i)") }
        } catch {
            interp.report(error)
            emit(depth, "content failed")
        }
    }

    private func title(_ args: [KV]) -> String {
        if let first = args.first, case .string(let s) = first { return s }
        return "…"
    }

    // MARK: Values

    private func fields(_ s: KStructValue, _ storage: KViewStorage) -> String {
        var parts: [String] = []
        for p in s.type.stored {
            if let box = storage.box(p.name) { parts.append("\(p.name)=\(show(box.value))") }
            else if let v = s.fields[p.name] { parts.append("\(p.name)=\(show(v))") }
        }
        return "{" + parts.joined(separator: ", ") + "}"
    }

    private func arguments(_ args: [KV], _ labels: [String?]) -> String {
        zip(args, labels).map { v, l in (l.map { $0 + ": " } ?? "") + show(v) }.joined(separator: ", ")
    }

    /// A value, the same way every run: no addresses, dates or random ids.
    private func show(_ v: KV, depth: Int = 0) -> String {
        guard depth < 6 else { return "…" }
        switch v {
        case .function: return "{fn}"
        case .view: return "<view>"
        case .binding(let b): return "$" + show(b.get(), depth: depth + 1)
        case .array(let a): return "[" + a.prefix(40).map { show($0, depth: depth + 1) }.joined(separator: ", ") + (a.count > 40 ? ", …" : "") + "]"
        case .set(let s): return "Set(" + s.map { show($0, depth: depth + 1) }.sorted().joined(separator: ", ") + ")"
        case .dict(let d): return "[" + d.map { show($0.key, depth: depth + 1) + ": " + show($0.value, depth: depth + 1) }.sorted().joined(separator: ", ") + "]"
        case .tuple(let vals, let labels):
            return "(" + vals.enumerated().map { i, x in ((i < labels.count ? labels[i] : nil).map { $0 + ": " } ?? "") + show(x, depth: depth + 1) }.joined(separator: ", ") + ")"
        case .structV(let s):
            return s.type.name + "(" + s.type.stored.compactMap { p in s.fields[p.name].map { "\(p.name): \(show($0, depth: depth + 1))" } }.joined(separator: ", ") + ")"
        case .object(let o):
            return o.type.name + "{" + o.type.stored.compactMap { p in o.fields[p.name].map { "\(p.name): \(show($0, depth: depth + 1))" } }.joined(separator: ", ") + "}"
        case .enumV(let e):
            return "." + e.caseName + (e.payload.isEmpty ? "" : "(" + e.payload.map { show($0, depth: depth + 1) }.joined(separator: ", ") + ")")
        case .native(let n):
            switch n {
            case .date: return "<date>"
            case .uuid: return "<uuid>"
            case .implicit(let name, let args): return "." + name + (args.isEmpty ? "" : "(" + args.map { show($0, depth: depth + 1) }.joined(separator: ", ") + ")")
            case .url(let u): return "URL(\(u.absoluteString))"
            case .size(let w, let h): return "Size(\(w), \(h))"
            case .point(let x, let y): return "Point(\(x), \(y))"
            case .angle(let d): return "\(d)°"
            case .object(let kind, _): return kind
            default: return n.kindName
            }
        default:
            return interp.describe(v, quoted: true)
        }
    }

    /// Random ids and clock times vary run to run; nothing else should.
    static func normalize(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#, with: "<uuid>", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\b\d{1,2}:\d{2}(:\d{2})?(\s?[AP]M)?"#, with: "<time>", options: .regularExpression)
        return out
    }
}
