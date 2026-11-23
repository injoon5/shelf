//
//  KEWrappers.swift
//  Kiln's engine
//
//  The app's own property wrappers (PLAN.md §1.6), as Swift lays them out:
//  `@Clamped(0...10) var volume = 5` stores the wrapper in `_volume`, built
//  with `init(wrappedValue: 5, 0...10)`; `volume` reads and writes its
//  `wrappedValue`; `$volume` is its `projectedValue`. On stored properties
//  of structs and classes, and on local variables.
//
//  SwiftUI's wrappers (`@State`, `@Binding`…) are the engine's own
//  (KViewStorage); a name is the app's wrapper only when the app declares a
//  `@propertyWrapper` type with it.
//

import SwiftUI

/// A property the app wraps: the wrapper's type and the attribute as written.
struct KWrapped {
    let type: KType
    let attribute: KEAttribute
}

extension KType {
    var isPropertyWrapper: Bool { attributes.contains { $0.name == "propertyWrapper" } }
}

extension KInterpreter {

    /// The app's wrapper on a declaration, if it has one.
    func customWrapper(_ decl: KEVarDecl) -> KWrapped? {
        guard !decl.attributes.isEmpty else { return nil }
        for a in decl.attributes where !KEVarDecl.wrappers.contains(a.name) {
            if let t = types[a.name], t.isPropertyWrapper { return KWrapped(type: t, attribute: a) }
        }
        return nil
    }

    /// The wrapper on a stored property of `t`.
    func wrapped(_ t: KType, _ name: String) -> KWrapped? {
        guard t.wrappedNames.contains(name) || !t.finalized, let d = t.storedDecl(name) else { return nil }
        return customWrapper(d)
    }

    /// `Wrapper(wrappedValue: v, <the attribute's arguments>)`, or with the
    /// attribute's arguments only when there's no value (`@Default var x: Int`).
    func makeWrapper(_ w: KWrapped, wrappedValue: KV?, env: KEnv, line: Int) throws -> KV {
        var args = try w.attribute.args.map { try eval($0.value, env) }
        var labels = w.attribute.args.map(\.label)
        if let v = wrappedValue, !labels.contains("wrappedValue") {
            args.insert(v, at: 0)
            labels.insert("wrappedValue", at: 0)
        }
        return try instantiate(w.type, args: args, labels: labels, line: line)
    }

    func wrapperField(_ name: String) -> String { "_" + name }

    /// `_volume`: where the wrapper of `volume` lives.
    func isWrapperStorage(_ t: KType, _ field: String) -> Bool {
        field.hasPrefix("_") && wrapped(t, String(field.dropFirst())) != nil
    }

    /// A wrapped property's value: its wrapper's `wrappedValue`.
    func readWrapped(_ wrapper: KV?, _ name: String, line: Int) throws -> KV {
        guard let wrapper, !wrapper.isNil else { throw fail("'\(name)' is used before its property wrapper is set", line) }
        return try member(wrapper, "wrappedValue", line: line)
    }

    /// `$name` on a value whose type wraps `name`.
    func projectedWrapped(_ base: KV, _ name: String, line: Int) throws -> KV? {
        guard let t = base.userType, let w = wrapped(t, name) else { return nil }
        let wrapper: KV?
        switch base {
        case .structV(let s): wrapper = s.fields[wrapperField(name)]
        case .object(let o): wrapper = o.fields[wrapperField(name)]
        default: wrapper = nil
        }
        guard let wrapper else { return nil }
        guard (wrapper.userType?.computed["projectedValue"] != nil || wrapper.userType?.storedDecl("projectedValue") != nil) else {
            throw fail("'\(w.type.name)' has no projectedValue, so '$\(name)' doesn't exist", line)
        }
        return try member(wrapper, "projectedValue", line: line)
    }

    /// Writing a wrapped property: through `wrappedValue`, or (in an `init`,
    /// before the wrapper exists) by building it with this value.
    func writeWrapped(_ owner: KLocation, _ w: KWrapped, _ name: String, _ newValue: KV, exists: Bool) throws {
        let field = wrapperField(name)
        if exists {
            try write(.member(.member(owner, field), "wrappedValue"), newValue)
        } else {
            try write(.member(owner, field), try makeWrapper(w, wrappedValue: newValue, env: KEnv(parent: globalEnv), line: 0))
        }
    }

    /// `@Clamped(0...10) var x = 5` inside a function: `_x` holds the wrapper,
    /// `x` and `$x` reach through it.
    func declareWrappedLocal(_ decl: KEVarDecl, _ w: KWrapped, _ env: KEnv) throws {
        let initial = try decl.initial.map { try eval($0, env, decl.type) }
        let box = KBox(try makeWrapper(w, wrappedValue: initial, env: env, line: decl.line))
        env.vars[wrapperField(decl.name)] = box
        env.vars[decl.name] = KBox(get: { [unowned self] in (try? self.member(box.value, "wrappedValue", line: decl.line)) ?? .nilValue },
                                   set: { [unowned self] v in try? self.write(.member(.box(box), "wrappedValue"), v) })
        env.vars["$" + decl.name] = KBox(get: { [unowned self] in (try? self.member(box.value, "projectedValue", line: decl.line)) ?? .nilValue },
                                         set: { _ in })
    }
}
