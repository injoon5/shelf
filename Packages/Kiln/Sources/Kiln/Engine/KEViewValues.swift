//
//  KEViewValues.swift
//  Kiln's engine
//
//  What the engine itself needs to know about values, whatever the bridges:
//  which values are views, which type's extensions a value gets, and
//  operators passed as functions (`sorted(by: <)`).
//

import SwiftUI

@MainActor
enum KBuiltins {
    // MARK: Views from values

    static func asViews(_ v: KV, _ interp: KInterpreter) -> [KView] {
        switch v {
        case .view(let view): return [view]
        case .structV(let s) where s.type.isView: return [.custom(s)]
        case .native(.color(let c)): return [.primitive("Color", [.native(.color(c))], [nil], line: 0)]
        case .native(.path): return [.primitive("PathShape", [v], [nil], line: 0)]
        case .structV(let s) where s.type.isShape: return [.primitive("UserShape", [v], [nil], line: 0)]
        case .native(.implicit(let n, _)) where KDrawing.colorNames[n] != nil:
            return [.primitive("Color", [.native(.color(KDrawing.colorNames[n]!))], [nil], line: 0)]
        case .enumV(let e) where e.type.isView:
            return []
        default: return []
        }
    }

    static func isViewLike(_ v: KV) -> Bool {
        switch v {
        case .view: return true
        case .structV(let s): return s.type.isView || s.type.isShape
        case .native(.color), .native(.path): return true
        default: return false
        }
    }

    /// Whether `name` is a method of the value itself (Color.opacity) rather than a view modifier.
    static func hasValueMethod(_ base: KV, _ name: String) -> Bool {
        switch base {
        case .native(.color): return ["opacity", "gradient", "mix", "description"].contains(name)
        default: return true
        }
    }

    static func extensionKey(_ v: KV) -> String {
        switch v {
        case .int: return "Int"
        case .double: return "Double"
        case .string: return "String"
        case .bool: return "Bool"
        case .array: return "Array"
        case .dict: return "Dictionary"
        case .set: return "Set"
        case .native(.color): return "Color"
        case .native(.date): return "Date"
        case .native(.font): return "Font"
        case .view: return "View"
        default: return v.typeName
        }
    }

    static func prefersBuiltinInit(_ name: String, _ labels: [String?]) -> Bool {
        // Keep SwiftUI's own Color(red:green:blue:) etc. even if the user also extended Color.
        if name == "Color", labels.first == "red" || labels.first == "hue" || labels.first == "white" || labels == [nil] { return true }
        return false
    }

    static func operatorFunction(_ name: String, _ interp: KInterpreter) -> KV? {
        let binaryOps: Set<String> = ["+", "-", "*", "/", "%", "<", ">", "<=", ">=", "==", "!=", "&&", "||"]
        guard binaryOps.contains(name) else { return nil }
        return .function(KFunction(.native(name) { [unowned interp] args, _ in
            guard args.count == 2 else { throw interp.fail("Operator \(name) needs two values") }
            switch name {
            case "<", ">", "<=", ">=": return .bool(try interp.compare(name, args[0], args[1], 0))
            case "==": return .bool(args[0] == args[1])
            case "!=": return .bool(args[0] != args[1])
            case "&&": return .bool(interp.truthy(args[0]) && interp.truthy(args[1]))
            case "||": return .bool(interp.truthy(args[0]) || interp.truthy(args[1]))
            default: return try interp.arithmetic(name, args[0], args[1], 0)
            }
        }))
    }
}

extension KEExpr {
    /// `\.dismiss` inside an attribute argument.
    var keyPathComponents: KEExpr? {
        if case .keyPath = self { return self }
        return nil
    }
}

