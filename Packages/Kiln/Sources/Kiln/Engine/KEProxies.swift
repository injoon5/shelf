//
//  KEProxies.swift
//  Kiln's engine
//
//  Native code calling the app's code (PLAN.md §1.5). A protocol the
//  registry bridges (`Shape`, `Layout`, `UIImagePickerControllerDelegate`…)
//  can have a **proxy**: a native type that conforms to the real protocol and
//  forwards each requirement to the matching member of the app's value.
//
//  - `KAppValue` is the app's value as a proxy holds it: it calls a
//    requirement (with its own step budget), reads and writes properties, and
//    runs an `async` requirement as a VM task that native code awaits.
//  - `KRequirement` is one requirement, parsed from the registry's
//    declaration (`"path(in:)"`, `"animatableData?"`, `"async perform()"`).
//  - The app's types are checked against the registry's requirements when the
//    program loads, so a `Shape` without `path(in:)` is an error with its line.
//  - `KAnimVector` is the `VectorArithmetic` every proxy's `animatableData`
//    is: the app's numbers, flattened (`AnimatablePair`, `CGPoint`, `Angle`…).
//

import SwiftUI

// MARK: - Requirements

/// One requirement of a bridged protocol, as the registry declares it:
///
///     "path(in:)"                          a method, required
///     "animatableData?"                    a property with a default (`?`)
///     "static transferRepresentation"      a static member
///     "async perform()"                    an async requirement: a VM task native code awaits
///     "makeCoordinator()?"                 an optional method
struct KRequirement: Equatable {
    let name: String
    /// A method's labels (`[nil, "context"]`); nil for a property.
    let labels: [String?]?
    let isStatic: Bool
    let isOptional: Bool
    let isAsync: Bool

    var isMethod: Bool { labels != nil }

    /// `path(in:)`, `animatableData`: how `Kiln.check` and the manifest write it.
    var display: String {
        guard let labels else { return name }
        return name + "(" + labels.map { ($0 ?? "_") + ":" }.joined() + ")"
    }

    /// The form `KProtocolBridge.requirements` keeps (§1.8's checker reads it):
    /// the display, with `?` when it has a default.
    var declared: String { display + (isOptional ? "?" : "") }

    init(name: String, labels: [String?]?, isStatic: Bool = false, isOptional: Bool = false, isAsync: Bool = false) {
        self.name = name
        self.labels = labels
        self.isStatic = isStatic
        self.isOptional = isOptional
        self.isAsync = isAsync
    }

    init(parsing spec: String) {
        var s = spec.trimmingCharacters(in: .whitespaces)
        var isStatic = false, isAsync = false, isOptional = false
        while true {
            if s.hasPrefix("static ") { isStatic = true; s.removeFirst(7) }
            else if s.hasPrefix("async ") { isAsync = true; s.removeFirst(6) }
            else if s.hasPrefix("optional ") { isOptional = true; s.removeFirst(9) }
            else { break }
        }
        if s.hasSuffix("?") { isOptional = true; s.removeLast() }
        if let open = s.firstIndex(of: "("), s.hasSuffix(")") {
            let inner = s[s.index(after: open)..<s.index(before: s.endIndex)]
            let labels = inner.split(separator: ":", omittingEmptySubsequences: true).map { l -> String? in
                let t = l.trimmingCharacters(in: .whitespaces)
                return t == "_" ? nil : t
            }
            self.init(name: String(s[..<open]), labels: labels, isStatic: isStatic, isOptional: isOptional, isAsync: isAsync)
        } else {
            self.init(name: s, labels: nil, isStatic: isStatic, isOptional: isOptional, isAsync: isAsync)
        }
    }
}

// MARK: - The app's value, as a proxy holds it

/// An app value seen from native code. A struct is copied in, as Swift
/// copies it into a generic `T: Shape`; a mutating requirement changes the
/// copy the proxy holds. A class instance is shared.
@MainActor
struct KAppValue {
    let interp: KInterpreter
    private(set) var value: KV
    let type: KType

    init?(_ v: KV, _ interp: KInterpreter) {
        guard let t = v.userType else { return nil }
        self.interp = interp
        self.value = v
        self.type = t
    }

    init(type: KType, value: KV, _ interp: KInterpreter) {
        self.interp = interp
        self.value = value
        self.type = type
    }

    var structValue: KStructValue? { if case .structV(let s) = value { return s }; return nil }

    /// Whether the app's type has this member itself (or from a protocol
    /// extension it adopts), as opposed to the native protocol's default.
    func implements(_ name: String, labels: [String?]? = nil) -> Bool {
        if let labels { return method(name, labels) != nil }
        return type.storedDecl(name) != nil || type.computed[name] != nil || type.methods[name] != nil
    }

    func implementsStatic(_ name: String) -> Bool {
        type.staticDecls[name] != nil || type.staticMethods[name] != nil
    }

    func implements(_ r: KRequirement) -> Bool {
        if r.isStatic { return implementsStatic(r.name) }
        return implements(r.name, labels: r.labels)
    }

    private func method(_ name: String, _ labels: [String?]) -> KEFuncDecl? {
        let ms = type.methods[name] ?? []
        return ms.first { $0.params.map(\.label) == labels } ?? KInterpreter.fit(ms, labels)
    }

    /// Sets a stored property directly, as SwiftUI sets an `@Environment`
    /// one before calling a requirement (a representable's `dismiss`).
    mutating func setField(_ name: String, _ v: KV) {
        switch value {
        case .structV(var s): s.fields[name] = v; value = .structV(s)
        case .object(let o): o.fields[name] = v
        default: break
        }
    }

    private func context(_ box: KBox) -> KSelfContext {
        KSelfContext(type: type, location: .box(box))
    }

    /// Calls a synchronous requirement with its own step budget, as SwiftUI
    /// calls `path(in:)` or `sizeThatFits`. A mutating one changes this copy.
    mutating func call(_ name: String, _ args: [KV], labels: [String?]) throws -> KV {
        guard let m = method(name, labels) else {
            throw interp.fail("'\(type.name)' has no \(name)(\(labels.map { ($0 ?? "_") + ":" }.joined()))", type.line)
        }
        let box = KBox(value)
        let ctx = context(box)
        let interp = self.interp
        let r = try interp.entry { try interp.invoke(m, args: args, labels: labels, selfContext: ctx, parent: interp.globalEnv) }
        if case .structV = value { value = box.value }
        if let s = r.asSuspension {
            _ = s
            throw interp.fail("\(type.name).\(m.signature) waits (it uses 'await'), but \(name) can't wait here", m.line)
        }
        return r
    }

    /// The same, for a call SwiftUI makes that can't fail: an error is
    /// reported with its line, and `fallback` is used.
    mutating func callReporting(_ name: String, _ args: [KV], labels: [String?], fallback: KV = .void) -> KV {
        do { return try call(name, args, labels: labels) } catch {
            interp.report(error)
            return fallback
        }
    }

    /// A property, stored or computed.
    func get(_ name: String) throws -> KV {
        let interp = self.interp
        return try interp.entry { try interp.read(.member(.box(KBox(value)), name)) }
    }

    /// Writes a property (a computed one runs its setter) on this copy.
    mutating func set(_ name: String, _ v: KV) throws {
        let box = KBox(value)
        let interp = self.interp
        try interp.entry { try interp.write(.member(.box(box), name), v) }
        if case .structV = value { value = box.value }
    }

    /// A static member: `transferRepresentation`, `readableContentTypes`.
    func getStatic(_ name: String) throws -> KV {
        let interp = self.interp
        let t = type
        return try interp.entry { try interp.staticValue(t, name) }
    }

    /// An `async` requirement (`perform()`, a tool's `call`): it runs as a VM
    /// task on the main actor, and native code awaits it. Cancelling the
    /// awaiting Swift task cancels the VM task. A synchronous requirement is
    /// called the same way and returns at once.
    func callAsync(_ name: String, _ args: [KV], labels: [String?]) async throws -> KV {
        guard let m = method(name, labels) else {
            throw interp.fail("'\(type.name)' has no \(name)(\(labels.map { ($0 ?? "_") + ":" }.joined()))", type.line)
        }
        let task = interp.startTask(m, args: args, labels: labels, selfContext: context(KBox(value)), reportsErrors: false)
        let box = KUnsafeSendable(task)
        let completion = await withTaskCancellationHandler {
            await task.completion()
        } onCancel: {
            Task { @MainActor in box.value.cancel() }
        }
        switch completion {
        case .value(let v): return v
        case .error(let e): throw e
        case .flow: return .void
        }
    }
}

// MARK: - Checking the app's types against the registry

extension KInterpreter {
    /// Requirements Swift fills in itself (the same rules as `Kiln.check`'s).
    nonisolated static func synthesized(_ proto: String, _ r: KRequirement, _ t: KType) -> Bool {
        switch (proto, r.name) {
        case ("Identifiable", "id"): return t.isClass
        case ("CaseIterable", "allCases"): return t.isEnum
        case ("Comparable", _): return t.isEnum
        // A representable is a View with no `body`: its proxy shows it.
        case ("View", "body"): return t.isRepresentable
        default: return false
        }
    }

    /// A type that adopts one of the registry's protocols has each of its
    /// required members; a missing one is an error with the type's line,
    /// worded like the app's own protocols' (KEProtocols).
    func checkNativeRequirements(_ t: KType) {
        for name in t.conformances.sorted() where protocols[name] == nil {
            guard let bridge = registry.protocols[name], !bridge.members.isEmpty else { continue }
            for r in bridge.members where !r.isOptional && !Self.synthesized(name, r, t) {
                if has(t, r) { continue }
                var has = (r.isStatic ? t.staticMethods[r.name] : t.methods[r.name])?.map(\.signature) ?? []
                if r.isMethod, has.isEmpty, t.computed[r.name] != nil { has = [r.name] }
                report(fail("'\(t.name)' doesn't conform to '\(name)': it has no \(r.display)\(has.isEmpty ? "" : "; it has " + KInterpreter.list(has))", t.line))
            }
        }
    }

    private func has(_ t: KType, _ r: KRequirement) -> Bool {
        // Operators are static in Swift, and their parameters have no labels: `static func <`.
        if r.name.first.map({ !$0.isLetter && $0 != "_" }) == true {
            return t.staticMethods[r.name] != nil || t.methods[r.name] != nil
        }
        if r.isStatic {
            return t.staticDecls[r.name] != nil || t.staticMethods[r.name] != nil || t.enumCase(r.name) != nil
        }
        if r.name == "init", let labels = r.labels {
            return (t.inits + t.extensionInits).contains { $0.params.map(\.label) == labels }
        }
        guard let labels = r.labels else {
            // A property; a static one counts too, as `Kiln.check` counts it (`previews`).
            return t.storedDecl(r.name) != nil || t.computed[r.name] != nil || t.staticDecls[r.name] != nil
        }
        return (t.methods[r.name] ?? []).contains { $0.params.map(\.label) == labels }
    }

    // MARK: Proxies

    /// The registry's proxy for the app's value `v` as protocol `name`, if
    /// the value's type adopts it and the protocol has one.
    func proxy(for v: KV, as name: String) -> Any? {
        guard let t = v.userType, t.conformances.contains(name), let make = registry.protocols[name]?.proxy,
              let app = KAppValue(v, self) else { return nil }
        return make(app)
    }

    /// The view a proxied app view is shown as: a representable's controller
    /// or view, or an `Animatable` view that interpolates.
    func viewProxy(_ s: KStructValue) -> AnyView? {
        for name in ["UIViewControllerRepresentable", "UIViewRepresentable", "Animatable"] where s.type.conformances.contains(name) {
            if let v = proxy(for: .structV(s), as: name) as? AnyView { return v }
        }
        return nil
    }

    /// Native code awaiting what the app's code returned: a suspension (an
    /// `async` closure called, a requirement that waits) runs as a VM task.
    func awaitValue(_ v: KV) async throws -> KV {
        guard let s = v.asSuspension else { return v }
        let task = startTask(s, parent: nil, reportsErrors: false)
        let box = KUnsafeSendable(task)
        let completion = await withTaskCancellationHandler {
            await task.completion()
        } onCancel: {
            Task { @MainActor in box.value.cancel() }
        }
        switch completion {
        case .value(let v): return v
        case .error(let e): throw e
        case .flow: return .void
        }
    }

    /// Calls the app's closure from native code that can wait for it.
    func callAwaiting(_ f: KFunction, _ args: [KV]) async throws -> KV {
        try await awaitValue(try entry { try call(f, args, args.map { _ in nil }) })
    }

    /// Starts a requirement as a task: what `KAppValue.callAsync` awaits.
    func startTask(_ decl: KEFuncDecl, args: [KV], labels: [String?], selfContext: KSelfContext, reportsErrors: Bool) -> KTask {
        startTask(frame: { try self.userFrame(decl, args: args, labels: labels, selfContext: selfContext, parent: self.globalEnv) },
                  parent: nil, reportsErrors: reportsErrors)
    }
}

// MARK: - Animatable data

/// What a proxy's `animatableData` is: the app's animatable numbers in
/// order. SwiftUI interpolates it; the proxy writes it back into the app's
/// value in the shape the value has (`AnimatablePair`, `CGPoint`, `Angle`).
struct KAnimVector: VectorArithmetic {
    var values: [Double]

    init(_ values: [Double] = []) { self.values = values }

    static var zero: KAnimVector { KAnimVector() }

    private static func zip(_ a: KAnimVector, _ b: KAnimVector, _ f: (Double, Double) -> Double) -> KAnimVector {
        let n = max(a.values.count, b.values.count)
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n { out[i] = f(i < a.values.count ? a.values[i] : 0, i < b.values.count ? b.values[i] : 0) }
        return KAnimVector(out)
    }

    static func + (a: KAnimVector, b: KAnimVector) -> KAnimVector { zip(a, b, +) }
    static func - (a: KAnimVector, b: KAnimVector) -> KAnimVector { zip(a, b, -) }
    static func += (a: inout KAnimVector, b: KAnimVector) { a = a + b }
    static func -= (a: inout KAnimVector, b: KAnimVector) { a = a - b }
    mutating func scale(by rhs: Double) { values = values.map { $0 * rhs } }
    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }
    static func == (a: KAnimVector, b: KAnimVector) -> Bool {
        let n = max(a.values.count, b.values.count)
        for i in 0..<n where (i < a.values.count ? a.values[i] : 0) != (i < b.values.count ? b.values[i] : 0) { return false }
        return true
    }
}

@MainActor
enum KAnimatable {
    /// The numbers in an animatable value, in order. nil: it isn't one.
    static func flatten(_ v: KV) -> [Double]? {
        switch v {
        case .double(let d): return [d]
        case .int(let i): return [Double(i)]
        case .tuple(let vals, _):
            var out: [Double] = []
            for x in vals { guard let f = flatten(x) else { return nil }; out += f }
            return out
        case .native(.point(let x, let y)), .native(.size(let x, let y)): return [x, y]
        case .native(.rect(let x, let y, let w, let h)): return [x, y, w, h]
        case .native(.angle(let d)): return [d]
        case .void: return []
        case .native(.boxed(let b)) where b.type == "EmptyAnimatableData": return []
        default: return nil
        }
    }

    /// `template` with its numbers replaced, in order, from `values`.
    static func unflatten(_ template: KV, _ values: inout ArraySlice<Double>) -> KV {
        func next() -> Double { values.isEmpty ? 0 : values.removeFirst() }
        switch template {
        case .double, .int: return .double(next())
        case .tuple(let vals, let labels): return .tuple(vals.map { unflatten($0, &values) }, labels)
        case .native(.point): let x = next(); return .native(.point(x, next()))
        case .native(.size): let w = next(); return .native(.size(w, next()))
        case .native(.rect): let x = next(), y = next(), w = next(); return .native(.rect(x, y, w, next()))
        case .native(.angle): return .native(.angle(next()))
        default: return template
        }
    }

    /// The app value's `animatableData`: its own (hand-written, or the
    /// default from an `extension Animatable`), else `@Animatable`'s
    /// properties. Empty when it has neither (`EmptyAnimatableData`).
    static func data(_ app: KAppValue) -> KAnimVector {
        if app.implements("animatableData") {
            guard let v = try? app.get("animatableData"), let f = flatten(v) else { return .zero }
            return KAnimVector(f)
        }
        var out: [Double] = []
        for name in app.type.animatableProperties {
            if let v = try? app.get(name), let f = flatten(v) { out += f }
        }
        return KAnimVector(out)
    }

    /// Writes interpolated data back into the app's value.
    static func setData(_ app: inout KAppValue, _ data: KAnimVector) {
        var values = data.values[...]
        if app.implements("animatableData") {
            guard let template = try? app.get("animatableData") else { return }
            do { try app.set("animatableData", unflatten(template, &values)) } catch { app.interp.report(error) }
            return
        }
        for name in app.type.animatableProperties {
            guard let template = try? app.get(name) else { continue }
            try? app.set(name, unflatten(template, &values))
        }
    }

    /// Whether the app's type animates anything (so a proxy bothers).
    static func animates(_ t: KType) -> Bool {
        !t.animatableProperties.isEmpty || t.computed["animatableData"] != nil || t.storedDecl("animatableData") != nil
    }
}
