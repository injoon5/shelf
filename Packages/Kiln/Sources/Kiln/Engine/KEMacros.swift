//
//  KEMacros.swift
//  Kiln's engine
//
//  Macros Kiln reads as declarations (PLAN.md §1.6). An interpreter can't
//  expand a macro, but most of the ones apps write only declare something:
//
//      @Observable         the class is observed (views reading it refresh)
//      @Animatable         the type is Animatable; its animatable properties
//                          are listed for the proxy that animates them (§1.5)
//      @AnimatableIgnored, @ObservationIgnored   markers, no effect here
//      @Entry              a value in EnvironmentValues, FocusedValues,
//                          ContainerValues or Transaction, with its default
//      #Preview            ignored (KEParser drops it)
//
//  Adding one is a line in `typeMacros` or `propertyMacros`. Round 4 adds
//  `@Generable` and `@Guide` here.
//

import SwiftUI

@MainActor
enum KMacros {
    /// An attached macro on a type: what it adds to the type.
    typealias TypeMacro = @MainActor (_ type: KType, _ attribute: KEAttribute, _ interp: KInterpreter) -> Void
    /// An attached macro on a property in an extension of a native type
    /// (`extension EnvironmentValues { @Entry var accent = Color.blue }`).
    /// Returns true when it declared the property, so it isn't added as a member.
    typealias PropertyMacro = @MainActor (_ decl: KEVarDecl, _ owner: String, _ attribute: KEAttribute, _ interp: KInterpreter) -> Bool

    static var typeMacros: [String: TypeMacro] = [
        "Observable": { t, _, _ in t.conformances.insert("ObservableObject") },
        "Animatable": { t, _, interp in
            t.conformances.insert("Animatable")
            // The stored properties a value can animate: numbers, not marked @AnimatableIgnored.
            t.animatableProperties = t.stored.filter { p in
                !p.attributes.contains { $0.name == "AnimatableIgnored" } && !p.isLet
                    && ["Double", "CGFloat", "Float", "Int", "Angle", "CGPoint", "CGSize", "CGRect"].contains(p.type?.name ?? (p.initial.map { if case .double = $0 { return "Double" }; return "" } ?? ""))
            }.map(\.name)
        },
    ]

    static var propertyMacros: [String: PropertyMacro] = [
        "Entry": { decl, owner, _, interp in
            guard ["EnvironmentValues", "FocusedValues", "ContainerValues", "Transaction"].contains(owner) else { return false }
            interp.entries[owner, default: [:]][decl.name] = decl
            return true
        },
    ]

    /// Markers that mean nothing to Kiln but must not be read as property wrappers.
    static let ignored: Set<String> = ["ObservationIgnored", "AnimatableIgnored", "ObservationTracked", "Previewable"]

    static func applyTypeMacros(_ t: KType, _ attributes: [KEAttribute], _ interp: KInterpreter) {
        for a in attributes { typeMacros[a.name]?(t, a, interp) }
    }

    /// Whether a macro declared `decl` (so it's not an ordinary member).
    static func applyPropertyMacros(_ decl: KEVarDecl, owner: String, _ interp: KInterpreter) -> Bool {
        for a in decl.attributes {
            if let m = propertyMacros[a.name], m(decl, owner, a, interp) { return true }
        }
        return false
    }
}

extension KInterpreter {

    /// `@Environment(\.accent)` (or `@FocusedValue(\.x)`): an `@Entry` the app
    /// declared, or a property it added to EnvironmentValues the older way
    /// (`get { self[AccentKey.self] }`), given what's been set above the view.
    func userEnvironmentValue(_ key: String, owner: String = "EnvironmentValues", overrides: [String: KV] = [:]) -> KV? {
        if let v = overrides["\\." + key] { return v }
        if let decl = entries[owner]?[key] {
            guard let initial = decl.initial else { return decl.type?.isOptional == true ? .nilValue : nil }
            return (try? coerce(eval(initial, globalEnv, decl.type), to: decl.type)) ?? .nilValue
        }
        if let p = builtinExtensions[owner]?.computed[key] {
            let values = KV.native(.object(owner, KRef(KEnvironmentValuesBox(overrides))))
            let ctx = KSelfContext(type: KType.standIn(owner), location: .box(KBox(values)))
            return try? runGetter(p, env: KEnv(parent: globalEnv, selfContext: ctx))
        }
        return nil
    }

    /// The type an `@Entry` or EnvironmentValues property declares, to coerce what `.environment(\.key, v)` sets.
    func userEnvironmentType(_ key: String) -> KETypeRef? {
        entries["EnvironmentValues"]?[key]?.type ?? builtinExtensions["EnvironmentValues"]?.computed[key]?.type
    }
}

/// `self` in an EnvironmentValues extension's getter: `self[AccentKey.self]`
/// is AccentKey's `defaultValue`.
final class KEnvironmentValuesBox {
    let overrides: [String: KV]
    init(_ overrides: [String: KV]) { self.overrides = overrides }
}
