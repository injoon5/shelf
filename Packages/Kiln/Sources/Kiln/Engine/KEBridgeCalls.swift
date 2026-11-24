//
//  KEBridgeCalls.swift
//  Kiln's engine
//
//  Where the engine meets the bridge registry (Registry/, Bridges/): a name
//  that isn't the app's own is a view, a function or a type's initializer; a
//  member of a native value is a property or method of its type's bridge; a
//  modifier is a modifier bridge. Nothing here knows any particular name.
//

import SwiftUI

extension KInterpreter {

    // MARK: Calls by name

    /// `Name(…)` where `Name` isn't declared by the app: a view, a global
    /// function, or a native type's initializer.
    func callNamed(_ name: String, _ argExprs: [KEArg], _ env: KEnv, _ line: Int, _ expected: KETypeRef?) throws -> KV {
        if let b = registry.view(name), b.constructible { return try makeView(b, argExprs, env, line) }
        if let f = registry.function(name) {
            return try runBridge(f.forms, name, argExprs, env, line: line).0
        }
        if let t = registry.type(name), !t.inits.isEmpty {
            return try runBridge(t.inits, name, argExprs, env, line: line).0
        }
        // `SegmentedPickerStyle()` is `.segmented`.
        if let style = Self.styleName(name) {
            return .native(.implicit(style, try evalArgs(argExprs, env)))
        }
        _ = try evalArgs(argExprs, env)
        throw fail("Cannot find '\(name)' in scope", line)
    }

    /// A view: the overload picked, its arguments evaluated, and the view's
    /// description (shown later by its bridge's `render`).
    func makeView(_ b: KViewBridge, _ argExprs: [KEArg], _ env: KEnv, _ line: Int) throws -> KV {
        let labels = argExprs.map(\.label)
        let (i, binding) = try pick(b.forms, { $0.overload }, b.name, labels: labels, syntax: { KArgSyntax(argExprs[$0].value) }, line: line)
        let o = b.forms[i].overload
        let args = try evalBridgeArgs(o, binding, argExprs, env, name: b.name, line: line)
        let bound = KBound(overload: o, binding: binding)
        if let make = b.make {
            var c = KCall(interp: self, name: b.name, line: line, args: args, labels: labels, overload: o, binding: bound.binding)
            c.syntax = argExprs.map { KArgSyntax($0.value) }
            return try make(c)
        }
        return .view(KView(.primitive(b.name, args, labels, line: line), bound: bound))
    }

    /// `SegmentedPickerStyle` → `segmented`, `InsetGroupedListStyle` → `insetGrouped`.
    static func styleName(_ name: String) -> String? {
        let suffixes = ["ListStyle", "PickerStyle", "ButtonStyle", "TextFieldStyle", "ToggleStyle", "ProgressViewStyle",
                        "DatePickerStyle", "LabelStyle", "GaugeStyle", "TabViewStyle", "IndexViewStyle", "NavigationViewStyle",
                        "MenuStyle", "GroupBoxStyle", "FormStyle", "ControlGroupStyle", "DisclosureGroupStyle"]
        guard let suffix = suffixes.first(where: { name.hasSuffix($0) && name.count > $0.count }) else { return nil }
        var base = String(name.dropLast(suffix.count))
        if base == "Default" || base == "Automatic" { return "automatic" }
        if base == "Switch" { return "switch" }
        base = base.prefix(1).lowercased() + base.dropFirst()
        return base
    }

    // MARK: Modifiers

    /// `.name(…)` on a view: the modifier's bridge, its arguments evaluated.
    func applyModifier(_ v: KView, _ name: String, _ argExprs: [KEArg], _ env: KEnv, _ line: Int) throws -> KV {
        guard let b = registry.modifier(name) else {
            throw fail("Kiln doesn't support the .\(name)() modifier", line)
        }
        let labels = argExprs.map(\.label)
        let display = b.display
        let (i, binding) = try pick(b.forms, { $0.overload }, display, labels: labels, syntax: { KArgSyntax(argExprs[$0].value) }, line: line)
        let o = b.forms[i].overload
        let args = try evalBridgeArgs(o, binding, argExprs, env, name: display, line: line)
        return .view(.modified(v, KModifier(name: name, args: args, labels: labels, line: line, bound: KBound(overload: o, binding: binding))))
    }

    // MARK: Static members of native types

    /// `Type.name` for a native type: a static property, `Type.init` as a
    /// function, or a symbolic SwiftUI value (`Edge.Set.all`).
    func nativeStatic(_ typeName: String, _ name: String, _ line: Int) throws -> KV {
        if let t = registry.type(typeName) {
            if let p = t.staticProperties[name] {
                var c = KCall.values(self, name, owner: typeName, line: line)
                return try p.get(&c)
            }
            if name == "init", !t.inits.isEmpty {
                // `.map(String.init)`.
                return .function(KFunction(.native(typeName + ".init") { [unowned self] args, labels in
                    try self.runBridge(t.inits, typeName, values: args, labels: labels, line: line).0
                }))
            }
            if let any = t.anyStatic {
                var c = KCall.values(self, name, owner: typeName, line: line)
                if let v = try any(&c, name) { return v }
            }
        }
        if name == "self" { return .type(.builtin(typeName)) }
        // A nested native type: `NSTextCheckingResult.CheckingType`, `UIImpactFeedbackGenerator.FeedbackStyle`.
        if name.first?.isUppercase == true, registry.type(typeName + "." + name) != nil { return .type(.builtin(typeName + "." + name)) }
        // Other members of SwiftUI's types are symbolic until a view reads them (`Edge.Set.all`).
        return .native(.implicit(name, []))
    }

    /// `Type.name(…)` for a native type.
    func nativeStaticCall(_ typeName: String, _ name: String, _ argExprs: [KEArg], _ env: KEnv, _ line: Int,
                          _ expected: KETypeRef?) throws -> KV {
        if let t = registry.type(typeName) {
            if let ms = t.staticMethods[name] {
                return try runBridge(ms, name, owner: typeName, argExprs, env, line: line).0
            }
            if name == "init", !t.inits.isEmpty {
                return try runBridge(t.inits, typeName, argExprs, env, line: line).0
            }
            if let any = t.anyStaticMethod {
                let args = try evalArgs(argExprs, env)
                var c = KCall.values(self, name, owner: typeName, args, argExprs.map(\.label), line: line)
                if let v = try any(&c, name) { return v }
            }
        }
        let args = try evalArgs(argExprs, env)
        if name == "init" { return try callNamedValues(typeName, args, argExprs.map(\.label), line) }
        // An unknown static call on a SwiftUI type: a symbolic value (`.degrees(90)` written in full).
        return .native(.implicit(name, args))
    }

    // MARK: Members of native values

    /// `value.name` on a native value: its type's property, else a fallback's
    /// (a `String` is also a sequence of characters), converted only then.
    func nativeMember(_ base: KV, _ name: String, _ line: Int) throws -> KV {
        var tn = KRegistry.typeName(of: base)
        var value = base
        while let t = registry.type(tn) {
            if let p = t.properties[name] {
                var c = KCall.values(self, name, owner: tn, line: line, receiver: value)
                return try p.get(&c)
            }
            if let any = t.anyProperty {
                var c = KCall.values(self, name, owner: tn, line: line, receiver: value)
                if let v = try any(&c, name) { return v }
            }
            guard let fb = t.fallback, let conv = t.asFallback else { break }
            value = try conv(value, self)
            tn = fb
        }
        // `[Todo].self` and `[String: Todo].self`: the literal is already the type's description.
        if name == "self" { return base }
        throw fail("Value of type '\(KRegistry.typeName(of: base))' has no member '\(name)'", line)
    }

    /// `value.name(…)` on a native value. Returns the result and, for a
    /// mutating method, the receiver's new value.
    func nativeMethod(_ base: KV, _ name: String, _ argExprs: [KEArg], _ env: KEnv, _ line: Int) throws -> (KV, KV?) {
        // Optional.map on a present value (Kiln keeps optionals unwrapped):
        // `year.map(String.init)`, `date.map { $0.formatted() }`.
        if name == "map" || name == "flatMap", argExprs.count == 1 {
            switch base {
            case .int, .double, .bool, .structV, .enumV, .object, .native(.date), .native(.url), .native(.uuid), .native(.color):
                let f = try applier(try eval(argExprs[0].value, env), line)
                return (try f(base), nil)
            default: break
            }
        }
        if case .nilValue = base { _ = try evalArgs(argExprs, env); return (.nilValue, nil) }
        // The type's own methods, then each fallback's (converted only when reached).
        var tn = KRegistry.typeName(of: base)
        var value = base
        var own = true
        var dynamic: [(KTypeBridge, KV, String, Bool)] = []
        while let t = registry.type(tn) {
            if let ms = t.methods[name] {
                let (v, mutated) = try runBridge(ms, name, owner: tn, argExprs, env, line: line, receiver: value)
                // A fallback's methods don't mutate: the value was converted.
                return (v, own ? mutated : nil)
            }
            if t.anyMethod != nil { dynamic.append((t, value, tn, own)) }
            guard let fb = t.fallback, let conv = t.asFallback else { break }
            value = try conv(value, self)
            tn = fb
            own = false
        }
        if !dynamic.isEmpty {
            let args = try evalArgs(argExprs, env)
            for (t, value, tn, own) in dynamic {
                var c = KCall.values(self, name, owner: tn, args, argExprs.map(\.label), line: line, receiver: value)
                if let v = try t.anyMethod!(&c, name) { return (v, own ? c.mutated : nil) }
            }
            throw fail("Value of type '\(KRegistry.typeName(of: base))' has no method '\(name)'", line)
        }
        _ = try evalArgs(argExprs, env)
        throw fail("Value of type '\(KRegistry.typeName(of: base))' has no method '\(name)'", line)
    }

    /// `value.name = newValue` on a native reference (a formatter, a request).
    /// false when the type has no such property.
    func setNativeMember(_ n: KNative, _ name: String, _ value: KV) throws -> Bool {
        let base = KV.native(n)
        let tn = KRegistry.typeName(of: base)
        if let t = registry.type(tn) {
            if let set = t.properties[name]?.set {
                var c = KCall.values(self, name, owner: tn, [value], line: 0, receiver: base)
                try set(&c)
                lastNativeMutation = c.mutated
                return true
            }
            if let any = t.anySetter {
                var c = KCall.values(self, name, owner: tn, [value], line: 0, receiver: base)
                if try any(&c, name) { return true }
            }
        }
        return false
    }

    /// Calling a native value: `dismiss()`, a stored `.degrees` called later.
    func callNativeValue(_ n: KNative, _ argExprs: [KEArg], _ env: KEnv, _ line: Int) throws -> KV {
        let base = KV.native(n)
        let tn = KRegistry.typeName(of: base)
        if let ms = registry.type(tn)?.methods["callAsFunction"] {
            return try runBridge(ms, "callAsFunction", owner: tn, argExprs, env, line: line, receiver: base).0
        }
        _ = try evalArgs(argExprs, env)
        throw fail("\(n.kindName) is not a function", line)
    }

    // MARK: Implicit members

    /// `.name` or `.name(args)` where a native type is expected: `.red` for a
    /// `Color`, `.title` for a `Font`; with no type expected, the names that
    /// mean one thing anywhere (`.infinity`, `.degrees(90)`, `.red`).
    func resolveImplicit(_ name: String, _ args: [KV], expectedType: String?, labels: [String?] = []) -> KV? {
        if let e = expectedType, let f = registry.type(e)?.implicit, let v = f(name, args, labels) { return v }
        if let f = registry.contextFreeMember(name), let v = f(args, labels, expectedType) { return v }
        return nil
    }

    // MARK: Environment and globals

    /// What `@Environment(\.key)` reads before SwiftUI's own values arrive.
    /// `overrides` is what views above set (`.environment(\.accent, .red)`,
    /// `.environment(model)`), keyed `\.accent` and by type name.
    func environmentDefault(_ decl: KEVarDecl, overrides: [String: KV] = [:]) -> KV {
        guard let arg = decl.wrapperAttribute?.args.first?.value else { return .nilValue }
        if case .keyPath(_, let comps) = arg {
            let key = comps.last ?? ""
            if let b = registry.environment[key] { return b.value(self) }
            // The app's own: `@Entry` or an EnvironmentValues extension (KEMacros).
            return userEnvironmentValue(key, owner: decl.wrapper == "FocusedValue" ? "FocusedValues" : "EnvironmentValues", overrides: overrides) ?? .nilValue
        }
        // `@Environment(Model.self)`: the object `.environment(model)` put there.
        if case .member(.ident(let typeName, _), "self", _) = arg { return overrides[typeName] ?? .nilValue }
        return .nilValue
    }

    /// A bare name the registry knows as a constant (`pi`).
    func nativeConstant(_ name: String) -> KV? {
        registry.constant(name).map { $0(self) }
    }
}

extension KInterpreter {
    /// `pick` over any list whose elements carry an overload.
    func pick<C: RandomAccessCollection>(_ items: C, _ overload: (C.Element) -> KOverload, _ name: String, labels: [String?],
                                         syntax: (Int) -> KArgSyntax, line: Int) throws -> (Int, [Int]) where C.Index == Int {
        // The first overload that takes these arguments and the OS has; the
        // slow path only to say why none does.
        for (i, item) in items.enumerated() {
            let o = overload(item)
            if let b = o.bind(labels, syntax), o.availability?.isAvailable ?? true { return (i, b) }
        }
        return try pick(items.map(overload), name, labels: labels, syntax: labels.indices.map(syntax), line: line)
    }
}

extension KInterpreter {
    /// Whether `name` is a modifier (so `Color.red.opacity(…)` is the view's).
    func isModifierName(_ name: String) -> Bool {
        registry.modifier(name) != nil
    }
}

// MARK: - Rendering bridged views and modifiers

extension KRenderer {
    /// A view's bridge, shown: the overload picked when the code ran, or (for
    /// views the engine made) picked now from the values.
    func renderBridge(_ b: KViewBridge, _ a: KArgs, _ line: Int, _ bound: KBound?) -> AnyView {
        let form: KViewBridge.Form
        let argParams: [Int]
        if let bound, let f = b.forms.first(where: { $0.overload === bound.overload }) {
            form = f
            argParams = bound.binding
        } else {
            do {
                let (i, binding) = try interp.pick(b.forms, { $0.overload }, b.name, labels: a.labels,
                                                   syntax: { KArgSyntax(value: a.args[$0]) }, line: line)
                form = b.forms[i]
                argParams = binding
            } catch {
                interp.report(error)
                return AnyView(KErrorView(message: interp.describeError(error)))
            }
        }
        return form.render(KCall(interp: interp, name: b.name, line: line, args: a.args, labels: a.labels,
                                 overload: form.overload, binding: argParams))
    }

    /// A modifier's bridge applied to the view it's on.
    func renderModifier(_ b: KModifierBridge, _ base: KView, _ m: KModifier) -> AnyView {
        // On a Text, a modifier that keeps it a Text does (so `Text + Text` works).
        if b.text != nil, case .primitive("Text", _, _, _)? = rootPrimitive(base), let t = text(.modified(base, m)) {
            return AnyView(t)
        }
        guard let (form, c) = modifierCall(b, base, m) else { return render(base) }
        return form.apply(c, nil)
    }

    /// A modifier applied to a view the renderer already built.
    func applyModifier(_ m: KModifier, to view: AnyView, base: KView) -> AnyView {
        guard let b = interp.registry.modifier(m.name), let (form, c) = modifierCall(b, base, m) else { return view }
        return form.apply(c, view)
    }

    func modifierCall(_ b: KModifierBridge, _ base: KView, _ m: KModifier) -> (KModifierBridge.Form, KCall)? {
        let form: KModifierBridge.Form
        let argParams: [Int]
        if let bound = m.bound, let f = b.forms.first(where: { $0.overload === bound.overload }) {
            form = f
            argParams = bound.binding
        } else {
            do {
                let (i, binding) = try interp.pick(b.forms, { $0.overload }, b.display, labels: m.labels,
                                                   syntax: { KArgSyntax(value: m.args[$0]) }, line: m.line)
                form = b.forms[i]
                argParams = binding
            } catch {
                interp.report(error)
                return nil
            }
        }
        return (form, KCall(interp: interp, name: b.display, line: m.line, args: m.args, labels: m.labels,
                            overload: form.overload, binding: argParams, base: base))
    }

    /// A modifier on a `Text` that keeps it one, or nil.
    func textModifier(_ t: Text, _ base: KView, _ m: KModifier) -> Text? {
        guard let b = interp.registry.modifier(m.name), let f = b.text, let (_, c) = modifierCall(b, base, m) else { return nil }
        return f(c, t)
    }
}

extension KInterpreter {
    /// `[Habit]()`, `[String: Int]()`, `Set<Int>()`: a type written as an expression, called.
    func constructType(_ t: KETypeRef, _ args: [KV], _ labels: [String?], _ line: Int) throws -> KV {
        switch t.core {
        case .array:
            if let r = labels.firstIndex(of: "repeating") {
                return .array(Array(repeating: args[r], count: labels.firstIndex(of: "count").flatMap { args[$0].asInt } ?? 0))
            }
            if let f = args.first { return .array(try sequence(f)) }
            return .array([])
        case .dictionary: return .dict([:])
        case .named(let n, _):
            if n == "Set" { return .set(Set(try args.first.map { try sequence($0) } ?? [])) }
            return try callNamedValues(n, args, labels, line)
        default:
            return .nilValue
        }
    }
}
