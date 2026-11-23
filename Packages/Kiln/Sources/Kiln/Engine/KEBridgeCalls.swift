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
        return try KBuiltins.callGlobal(name, argExprs, env, self, line, expected)
    }

    /// A view: the overload picked, its arguments evaluated, and the view's
    /// description (shown later by its bridge's `render`).
    func makeView(_ b: KViewBridge, _ argExprs: [KEArg], _ env: KEnv, _ line: Int) throws -> KV {
        let labels = argExprs.map(\.label)
        let (i, binding) = try pick(b.forms, { $0.overload }, b.name, labels: labels, syntax: argExprs.map { KArgSyntax($0.value) }, line: line)
        let o = b.forms[i].overload
        let args = try evalBridgeArgs(o, binding, argExprs, env, name: b.name, line: line)
        let bound = KBound(overload: o, slots: o.slots(binding))
        if let make = b.make {
            return try make(KCall(interp: self, name: b.name, line: line, args: args, labels: labels, overload: o, slots: bound.slots))
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
            return try KBuiltins.legacyViewMethod(self, v, name, argExprs, env, line)
        }
        let labels = argExprs.map(\.label)
        let display = "." + name
        let (i, binding) = try pick(b.forms, { $0.overload }, display, labels: labels, syntax: argExprs.map { KArgSyntax($0.value) }, line: line)
        let o = b.forms[i].overload
        let args = try evalBridgeArgs(o, binding, argExprs, env, name: display, line: line)
        return .view(.modified(v, KModifier(name: name, args: args, labels: labels, line: line, bound: KBound(overload: o, slots: o.slots(binding)))))
    }

    // MARK: Static members of native types

    /// `Type.name` for a native type: a static property, `Type.init` as a
    /// function, or a symbolic SwiftUI value (`Edge.Set.all`).
    func nativeStatic(_ typeName: String, _ name: String, _ line: Int) throws -> KV {
        if let t = registry.type(typeName) {
            if let p = t.staticProperties[name] {
                var c = KCall.values(self, "\(typeName).\(name)", line: line)
                return try p.get(&c)
            }
            if name == "init", !t.inits.isEmpty {
                // `.map(String.init)`.
                return .function(KFunction(.native(typeName + ".init") { [unowned self] args, labels in
                    try self.runBridge(t.inits, typeName, values: args, labels: labels, line: line).0
                }))
            }
            if let any = t.anyStatic {
                var c = KCall.values(self, "\(typeName).\(name)", line: line)
                if let v = try any(&c, name) { return v }
            }
        }
        return try KBuiltins.staticMember(typeName, name, self, line)
    }

    /// `Type.name(…)` for a native type.
    func nativeStaticCall(_ typeName: String, _ name: String, _ argExprs: [KEArg], _ env: KEnv, _ line: Int,
                          _ expected: KETypeRef?) throws -> KV {
        if let t = registry.type(typeName) {
            if let ms = t.staticMethods[name] {
                return try runBridge(ms, "\(typeName).\(name)", argExprs, env, line: line).0
            }
            if name == "init", !t.inits.isEmpty {
                return try runBridge(t.inits, typeName, argExprs, env, line: line).0
            }
            if let any = t.anyStaticMethod {
                let args = try evalArgs(argExprs, env)
                var c = KCall.values(self, "\(typeName).\(name)", args, argExprs.map(\.label), line: line)
                if let v = try any(&c, name) { return v }
            }
        }
        return try KBuiltins.callStatic(typeName, name, argExprs, env, self, line, expected)
    }

    // MARK: Members of native values

    /// The bridge for a value's type, then its fallbacks (a `String` is also
    /// a sequence of characters), each with the value as that type.
    private func bridgeChain(_ base: KV) throws -> [(KTypeBridge, KV, String)] {
        var out: [(KTypeBridge, KV, String)] = []
        var name = KRegistry.typeName(of: base)
        var value = base
        while let t = registry.type(name) {
            out.append((t, value, name))
            guard let fb = t.fallback, let conv = t.asFallback else { break }
            value = try conv(value, self)
            name = fb
        }
        return out
    }

    /// `value.name` on a native value.
    func nativeMember(_ base: KV, _ name: String, _ line: Int) throws -> KV {
        for (t, value, tn) in try bridgeChain(base) {
            if let p = t.properties[name] {
                var c = KCall.values(self, "\(tn).\(name)", line: line, receiver: value)
                return try p.get(&c)
            }
            if let any = t.anyProperty {
                var c = KCall.values(self, "\(tn).\(name)", line: line, receiver: value)
                if let v = try any(&c, name) { return v }
            }
        }
        return try KBuiltins.member(base, name, self, line)
    }

    /// `value.name(…)` on a native value. Returns the result and, for a
    /// mutating method, the receiver's new value.
    func nativeMethod(_ base: KV, _ name: String, _ argExprs: [KEArg], _ env: KEnv, _ line: Int) throws -> (KV, KV?) {
        // Optional.map on a present value (Kiln keeps optionals unwrapped):
        // `year.map(String.init)`, `date.map { $0.formatted() }`.
        if name == "map" || name == "flatMap", argExprs.count == 1 {
            switch base {
            case .int, .double, .bool, .structV, .enumV, .object, .native(.date), .native(.url), .native(.uuid), .native(.color):
                let f = try KBuiltins.applier(try eval(argExprs[0].value, env), self, line)
                return (try f(base), nil)
            default: break
            }
        }
        if case .nilValue = base { _ = try evalArgs(argExprs, env); return (.nilValue, nil) }
        let chain = try bridgeChain(base)
        for (k, (t, value, tn)) in chain.enumerated() {
            if let ms = t.methods[name] {
                let (v, mutated) = try runBridge(ms, "\(tn).\(name)", argExprs, env, line: line, receiver: value)
                // A fallback's methods don't mutate: the value was converted.
                return (v, k == 0 ? mutated : nil)
            }
        }
        for (k, (t, value, tn)) in chain.enumerated() {
            if let any = t.anyMethod {
                let args = try evalArgs(argExprs, env)
                var c = KCall.values(self, "\(tn).\(name)", args, argExprs.map(\.label), line: line, receiver: value)
                if let v = try any(&c, name) { return (v, k == 0 ? c.mutated : nil) }
            }
        }
        let args = try argExprs.map { try eval($0.value, env, nil) }
        return try KBuiltins.callMethod(base, name, args, argExprs.map(\.label), self, line)
    }

    /// `value.name = newValue` on a native reference (a formatter, a request).
    /// false when the type has no such property.
    func setNativeMember(_ n: KNative, _ name: String, _ value: KV) throws -> Bool {
        let base = KV.native(n)
        let tn = KRegistry.typeName(of: base)
        if let t = registry.type(tn) {
            if let set = t.properties[name]?.set {
                var c = KCall.values(self, "\(tn).\(name)", [value], line: 0, receiver: base)
                try set(&c)
                return true
            }
            if let any = t.anySetter {
                var c = KCall.values(self, "\(tn).\(name)", [value], line: 0, receiver: base)
                if try any(&c, name) { return true }
            }
        }
        return KBuiltins.setNativeMember(n, name, value)
    }

    /// Calling a native value: `dismiss()`, a stored `.degrees` called later.
    func callNativeValue(_ n: KNative, _ argExprs: [KEArg], _ env: KEnv, _ line: Int) throws -> KV {
        let base = KV.native(n)
        let tn = KRegistry.typeName(of: base)
        if let ms = registry.type(tn)?.methods["callAsFunction"] {
            return try runBridge(ms, "\(tn)()", argExprs, env, line: line, receiver: base).0
        }
        return try KBuiltins.callNative(n, try evalArgs(argExprs, env), argExprs.map(\.label), self, line)
    }

    // MARK: Implicit members

    /// `.name` or `.name(args)` where a native type is expected: `.red` for a
    /// `Color`, `.title` for a `Font`; with no type expected, the names that
    /// mean one thing anywhere (`.infinity`, `.degrees(90)`, `.red`).
    func resolveImplicit(_ name: String, _ args: [KV], expectedType: String?, labels: [String?] = []) -> KV? {
        if let e = expectedType, let f = registry.type(e)?.implicit, let v = f(name, args, labels) { return v }
        if let f = registry.contextFreeMember(name), let v = f(args, labels, expectedType) { return v }
        return KBuiltins.implicit(name, args, expectedType: expectedType, labels: labels)
    }

    // MARK: Environment and globals

    /// What `@Environment(\.key)` reads before SwiftUI's own values arrive.
    func environmentDefault(_ decl: KEVarDecl) -> KV {
        guard case .keyPath(_, let comps)? = decl.wrapperAttribute?.args.first?.value.keyPathComponents else { return .nilValue }
        if let b = registry.environment[comps.last ?? ""] { return b.value(self) }
        return KBuiltins.environmentDefault(decl, self)
    }

    /// A bare name the registry knows as a constant (`pi`).
    func nativeConstant(_ name: String) -> KV? {
        if let c = registry.constant(name) { return c(self) }
        return KBuiltins.globalConstant(name)
    }
}

extension KInterpreter {
    /// `pick` over any list whose elements carry an overload.
    func pick<C: RandomAccessCollection>(_ items: C, _ overload: (C.Element) -> KOverload, _ name: String, labels: [String?],
                                         syntax: [KArgSyntax], line: Int) throws -> (Int, [Int]) where C.Index == Int {
        if items.count == 1, let only = items.first {
            let o = overload(only)
            if let b = o.bind(labels, syntax), o.availability?.isAvailable ?? true { return (0, b) }
        }
        return try pick(items.map(overload), name, labels: labels, syntax: syntax, line: line)
    }
}

extension KInterpreter {
    /// Whether `name` is a modifier (so `Color.red.opacity(…)` is the view's).
    func isModifierName(_ name: String) -> Bool {
        registry.modifier(name) != nil || KBuiltins.modifierNames.contains(name)
    }
}

// MARK: - Rendering bridged views and modifiers

extension KRenderer {
    /// A view's bridge, shown: the overload picked when the code ran, or (for
    /// views the engine made) picked now from the values.
    func renderBridge(_ b: KViewBridge, _ a: KArgs, _ line: Int, _ bound: KBound?) -> AnyView {
        let form: KViewBridge.Form
        let slots: [Int]
        if let bound, let f = b.forms.first(where: { $0.overload === bound.overload }) {
            form = f
            slots = bound.slots
        } else {
            do {
                let (i, binding) = try interp.pick(b.forms, { $0.overload }, b.name, labels: a.labels,
                                                   syntax: a.args.map { KArgSyntax(value: $0) }, line: line)
                form = b.forms[i]
                slots = form.overload.slots(binding)
            } catch {
                interp.report(error)
                return AnyView(KErrorView(message: interp.describeError(error)))
            }
        }
        return form.render(KCall(interp: interp, name: b.name, line: line, args: a.args, labels: a.labels,
                                 overload: form.overload, slots: slots))
    }

    /// A modifier's bridge applied to the view it's on.
    func renderModifier(_ b: KModifierBridge, _ base: KView, _ m: KModifier) -> AnyView {
        // On a Text, a modifier that keeps it a Text does (so `Text + Text` works).
        if b.text != nil, case .primitive("Text", _, _, _)? = rootPrimitive(base), let t = text(.modified(base, m)) {
            return AnyView(t)
        }
        guard let (form, c) = modifierCall(b, base, m) else { return render(base) }
        return form.apply(c)
    }

    func modifierCall(_ b: KModifierBridge, _ base: KView, _ m: KModifier) -> (KModifierBridge.Form, KCall)? {
        let form: KModifierBridge.Form
        let slots: [Int]
        if let bound = m.bound, let f = b.forms.first(where: { $0.overload === bound.overload }) {
            form = f
            slots = bound.slots
        } else {
            do {
                let (i, binding) = try interp.pick(b.forms, { $0.overload }, "." + m.name, labels: m.labels,
                                                   syntax: m.args.map { KArgSyntax(value: $0) }, line: m.line)
                form = b.forms[i]
                slots = form.overload.slots(binding)
            } catch {
                interp.report(error)
                return nil
            }
        }
        return (form, KCall(interp: interp, name: "." + m.name, line: m.line, args: m.args, labels: m.labels,
                            overload: form.overload, slots: slots, base: base))
    }

    /// A modifier on a `Text` that keeps it one, or nil.
    func textModifier(_ t: Text, _ base: KView, _ m: KModifier) -> Text?? {
        guard let b = interp.registry.modifier(m.name) else { return .none }
        guard let f = b.text, let (_, c) = modifierCall(b, base, m) else { return .some(nil) }
        return .some(f(c, t))
    }
}
