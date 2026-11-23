//
//  KResolve.swift
//  Kiln's bridge registry
//
//  How a call reaches a bridge: pick the overload by labels and argument
//  syntax, then by availability; evaluate each argument against its
//  parameter's kind; check what can be checked; hand the bridge a `KCall`.
//

import SwiftUI

extension KInterpreter {
    var registry: KRegistry { KRegistry.shared }

    /// Picks one of `overloads` for these arguments. Throws when none takes
    /// them, naming the ones there are.
    func pick(_ overloads: [KOverload], _ name: String, labels: [String?], syntax: [KArgSyntax], line: Int) throws -> (Int, [Int]) {
        var unavailable: KOverload?
        for (i, o) in overloads.enumerated() {
            guard let binding = o.bind(labels, syntax) else { continue }
            if let a = o.availability, !a.isAvailable { unavailable = unavailable ?? o; continue }
            return (i, binding)
        }
        if let u = unavailable {
            throw fail("\(u.display(name)) needs iOS \(u.availability?.iOSString ?? "later")", line)
        }
        let written = name + "(" + labels.map { ($0 ?? "_") + ":" }.joined() + ")"
        let known = overloads.filter { $0.availability?.isAvailable ?? true }.map { $0.display(name) }
        let list = known.count <= 1 ? (known.first ?? "") : known.dropLast().joined(separator: ", ") + " and " + known.last!
        throw fail("Kiln has no \(written); it has \(list)", line)
    }

    /// Evaluates a call's arguments for the overload they bind to.
    func evalBridgeArgs(_ o: KOverload, _ binding: [Int], _ argExprs: [KEArg], _ env: KEnv, name: String, line: Int) throws -> [KV] {
        var out: [KV] = []
        out.reserveCapacity(argExprs.count)
        for (i, a) in argExprs.enumerated() {
            let p = o.lenient ? nil : o.params[binding[i]]
            let kind = p?.kind ?? o.lenientKind(a.label)
            out.append(try evalArg(a.value, kind, env, optional: p?.optional ?? true, display: o.display(name), label: a.label, line: line))
        }
        return out
    }

    /// One argument, evaluated as its kind says.
    func evalArg(_ e: KEExpr, _ kind: KArgKind, _ env: KEnv, optional: Bool, display: String, label: String?, line: Int) throws -> KV {
        switch kind {
        case .title:
            // A string literal is a LocalizedStringKey: SwiftUI formats the numbers in it.
            if case .string(let segs) = e { return .string(try stringLiteral(segs, env, localized: true)) }
            return try eval(e, env)
        case .binding:
            let v = try eval(e, env, kind.expected)
            switch v {
            case .binding: return v
            case .nilValue where optional: return v
            case .native(.implicit("constant", let args)): return .binding(.constant(args.first ?? .void))
            default:
                throw fail("\(display): \(label.map { "'\($0)'" } ?? "the argument") needs a binding such as $value, not \(v.typeName)", line)
            }
        default:
            return try eval(e, env, kind.expected)
        }
    }

    /// A call to a bridge from code: picks the overload, evaluates the arguments.
    func bridgeCall(_ overloads: [KOverload], _ name: String, _ argExprs: [KEArg], _ env: KEnv, line: Int,
                    receiver: KV = .void) throws -> (Int, KCall) {
        let labels = argExprs.map(\.label)
        let (i, binding) = try pick(overloads, name, labels: labels, syntax: argExprs.map { KArgSyntax($0.value) }, line: line)
        let o = overloads[i]
        let args = try evalBridgeArgs(o, binding, argExprs, env, name: name, line: line)
        return (i, KCall(interp: self, name: name, line: line, args: args, labels: labels, overload: o,
                         slots: o.lenient ? [] : o.slots(binding), receiver: receiver))
    }

    /// A call from values the engine already has (`Int.init` used as a
    /// function, a method on a value): picks by labels and the values' kinds.
    func bridgeCall(_ overloads: [KOverload], _ name: String, values: [KV], labels: [String?], line: Int,
                    receiver: KV = .void) throws -> (Int, KCall) {
        let (i, binding) = try pick(overloads, name, labels: labels, syntax: values.map { KArgSyntax(value: $0) }, line: line)
        let o = overloads[i]
        return (i, KCall(interp: self, name: name, line: line, args: values, labels: labels, overload: o,
                         slots: o.lenient ? [] : o.slots(binding), receiver: receiver))
    }

    /// Runs a method or static method of a type bridge with evaluated values.
    func runBridge(_ methods: [KTypeBridge.Method], _ name: String, values: [KV], labels: [String?], line: Int,
                   receiver: KV = .void) throws -> (KV, KV?) {
        if methods.count == 1, methods[0].overload.lenient {
            // The common case, kept cheap: the standard library's methods.
            var c = KCall(interp: self, name: name, line: line, args: values, labels: labels, overload: methods[0].overload,
                          slots: [], receiver: receiver)
            let v = try methods[0].run(&c)
            return (v, c.mutated)
        }
        var (i, c) = try bridgeCall(methods.map(\.overload), name, values: values, labels: labels, line: line, receiver: receiver)
        let v = try methods[i].run(&c)
        return (v, c.mutated)
    }

    /// Runs a method of a type bridge, evaluating its arguments by kind.
    func runBridge(_ methods: [KTypeBridge.Method], _ name: String, _ argExprs: [KEArg], _ env: KEnv, line: Int,
                   receiver: KV = .void) throws -> (KV, KV?) {
        var (i, c) = try bridgeCall(methods.map(\.overload), name, argExprs, env, line: line, receiver: receiver)
        let v = try methods[i].run(&c)
        return (v, c.mutated)
    }
}
