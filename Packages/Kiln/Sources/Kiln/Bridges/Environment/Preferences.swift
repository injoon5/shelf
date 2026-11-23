//
//  Preferences.swift
//  Bridges: preferences, and the modifiers that set environment values
//
//  The app's `PreferenceKey`s go through one real one (`KPreferences`): each
//  view's value is kept under its key's name, siblings' lists are joined in
//  order, and whoever reads a key folds the list with the app's own
//  `defaultValue` and `reduce(value:nextValue:)`, as SwiftUI would.
//

import SwiftUI

/// Every app preference, by key name, in view order.
struct KPreferences: PreferenceKey {
    static let defaultValue: [String: [KV]] = [:]
    static func reduce(value: inout [String: [KV]], nextValue: () -> [String: [KV]]) {
        value.merge(nextValue()) { $0 + $1 }
    }
}

extension EnvironmentBridges {
    static func preferences(_ r: KRegistry) {
        r.protocolBridge("PreferenceKey", .environment, requirements: ["static defaultValue", "static reduce(value:nextValue:)"], support: .full,
                         notes: "Set with `.preference(key:value:)`; read with `.onPreferenceChange` or `.overlayPreferenceValue`.")
        r.protocolBridge("EnvironmentKey", .environment, requirements: ["static defaultValue"], support: .full,
                         notes: "Or `@Entry` in `extension EnvironmentValues`.")
        r.modifier("preference", .environment) { m in
            m.form("key:any value:any") { c, view in
                if let key = KPreferenceFold.key(c["key"]) {
                    let v = c["value"] ?? .nilValue
                    view.transformPreference(KPreferences.self) { $0[key] = [v] }
                } else {
                    view
                }
            }
        }
        r.modifier("transformPreference", .environment) { m in
            m.form("_:any _:closure") { c, view in
                if let key = KPreferenceFold.key(c[0]), case .function(let fn)? = c[1] {
                    let interp = c.interp, type = c[0]
                    view.transformPreference(KPreferences.self) { prefs in
                        MainActor.assumeIsolated {
                            var value = KPreferenceFold.fold(type, prefs[key] ?? [], interp)
                            _ = try? interp.entry { try interp.call(fn, [.binding(.inOut(get: { value }, set: { value = $0 }))], [nil]) }
                            prefs[key] = [value]
                        }
                    }
                } else {
                    view
                }
            }
        }
        r.modifier("onPreferenceChange", .environment) { m in
            m.form("_:any perform:closure") { c, view in
                if let key = KPreferenceFold.key(c[0]), case .function(let fn)? = c["perform"] {
                    KPreferenceReader(key: key, type: c[0] ?? .nilValue, content: view, interp: c.interp) { value in c.interp.perform(fn, [value]) }
                } else {
                    view
                }
            }
            m.probe { _, a, interp in
                guard case .function(let fn)? = a["perform"] else { return [] }
                return [KProbeCall(fn: fn, args: [KPreferenceFold.fold(a.first, [], interp)], use: .action)]
            }
        }
        for name in ["overlayPreferenceValue", "backgroundPreferenceValue"] {
            r.modifier(name, .environment) { m in
                m.form("_:any alignment:Alignment? _:closure") { c, view in
                    if case .function(let fn)? = c.a.lastFunction, let key = KPreferenceFold.key(c[0]) {
                        let interp = c.interp, type = c[0], align = c.alignment("alignment")
                        let make: ([String: [KV]]) -> AnyView = { prefs in
                            MainActor.assumeIsolated { KRenderer(interp: interp).renderContent(.function(fn), [KPreferenceFold.fold(type, prefs[key] ?? [], interp)]) }
                        }
                        if name == "overlayPreferenceValue" {
                            AnyView(view.overlayPreferenceValue(KPreferences.self, alignment: align) { make($0) })
                        } else {
                            AnyView(view.backgroundPreferenceValue(KPreferences.self, alignment: align) { make($0) })
                        }
                    } else {
                        view
                    }
                }
                m.probe { _, a, interp in
                    guard case .function(let fn)? = a.lastFunction else { return [] }
                    return [KProbeCall(fn: fn, args: [KPreferenceFold.fold(a.first, [], interp)])]
                }
            }
        }
    }

    static func environmentModifiers(_ r: KRegistry) {
        r.modifier("transformEnvironment", .environment) { m in
            m.form("_:any transform:closure") { c, view in
                if case .native(.keyPath(let comps))? = c[0], let key = comps.last, let bridge = c.interp.registry.environment[key],
                   let read = bridge.read, let write = bridge.write, case .function(let fn)? = c["transform"] {
                    let interp = c.interp
                    view.transformEnvironment(\.self) { env in
                        MainActor.assumeIsolated {
                            var value = read(env, interp)
                            _ = try? interp.entry { try interp.call(fn, [.binding(.inOut(get: { value }, set: { value = $0 }))], [nil]) }
                            write(&env, value, interp)
                        }
                    }
                } else if case .native(.keyPath(let comps))? = c[0], let key = comps.last, case .function(let fn)? = c["transform"] {
                    // The app's own `@Entry` value.
                    let interp = c.interp
                    view.transformEnvironment(\.kilnObjects) { objects in
                        MainActor.assumeIsolated {
                            var value = objects["\\." + key] ?? interp.userEnvironmentValue(key, owner: "EnvironmentValues", overrides: objects) ?? .nilValue
                            _ = try? interp.entry { try interp.call(fn, [.binding(.inOut(get: { value }, set: { value = $0 }))], [nil]) }
                            objects["\\." + key] = value
                        }
                    }
                } else {
                    view
                }
            }
            m.probe { _, a, _ in
                guard case .function(let fn)? = a["transform"] else { return [] }
                var v = KV.nilValue
                return [KProbeCall(fn: fn, args: [.binding(.inOut(get: { v }, set: { v = $0 }))], use: .action)]
            }
        }
        r.modifier("colorScheme", .environment, notes: "Deprecated in SwiftUI: prefer `.environment(\\.colorScheme, .dark)`.") { m in
            m.form("_:ColorScheme") { c, view in view.environment(\.colorScheme, c.symbol(0) == "dark" ? .dark : .light) }
        }
        r.modifier("dynamicTypeSize", .text) { m in
            m.form("_:any") { c, view in
                switch c[0] {
                case .range(let lo, let hi, let closed)?:
                    let l = KDynamicType.size(lo), h = KDynamicType.size(hi)
                    if let l, let h {
                        if closed { AnyView(view.dynamicTypeSize(l...h)) } else { AnyView(view.dynamicTypeSize(l..<h)) }
                    } else if let h {
                        if closed { AnyView(view.dynamicTypeSize(...h)) } else { AnyView(view.dynamicTypeSize(..<h)) }
                    } else if let l {
                        AnyView(view.dynamicTypeSize(l...))
                    } else {
                        view
                    }
                case let v?:
                    if let s = KDynamicType.size(v) { AnyView(view.dynamicTypeSize(s)) } else { view }
                default:
                    view
                }
            }
        }
        r.modifier("redacted", .environment) { m in
            m.form("reason:any") { c, view in
                switch c.symbol("reason") {
                case "privacy": AnyView(view.redacted(reason: .privacy))
                case "invalidated": AnyView(view.redacted(reason: .invalidated))
                case "placeholder": AnyView(view.redacted(reason: .placeholder))
                default: AnyView(view.redacted(reason: []))
                }
            }
        }
        r.modifier("unredacted", .environment) { m in m.form("") { _, view in view.unredacted() } }
        r.modifier("privacySensitive", .environment) { m in m.form("_:bool?") { c, view in view.privacySensitive(c.bool(0, default: true)) } }
        r.modifier("interactionActivityTrackingTag", .environment) { m in
            m.form("_:string") { c, view in view.interactionActivityTrackingTag(c.string(0) ?? "") }
        }
    }
}

/// An app preference key's value: the list, folded with its `reduce`.
@MainActor
enum KPreferenceFold {
    static func key(_ v: KV?) -> String? {
        if case .type(let t)? = v { return t.name }
        return nil
    }

    static func fold(_ keyType: KV?, _ values: [KV], _ interp: KInterpreter) -> KV {
        guard case .type(.user(let t))? = keyType else { return values.last ?? .nilValue }
        var acc = (try? interp.staticValue(t, "defaultValue")) ?? .nilValue
        guard let reduce = t.staticMethods["reduce"]?.first else { return values.last ?? acc }
        for next in values {
            let item = KFunction(.native("nextValue") { _, _ in next })
            _ = try? interp.entry {
                try interp.invoke(reduce, args: [.binding(.inOut(get: { acc }, set: { acc = $0 })), .function(item)], labels: ["value", "nextValue"],
                                  selfContext: KSelfContext(type: t, location: .box(KBox(.void)), isStatic: true), parent: interp.globalEnv)
            }
        }
        return acc
    }
}

/// `onPreferenceChange`: calls the app only when its own key's value changes.
struct KPreferenceReader: View {
    let key: String
    let type: KV
    let content: AnyView
    let interp: KInterpreter
    let perform: (KV) -> Void
    @State private var last: KV?

    var body: some View {
        content.onPreferenceChange(KPreferences.self) { prefs in
            MainActor.assumeIsolated {
                let value = KPreferenceFold.fold(type, prefs[key] ?? [], interp)
                guard value != last else { return }
                last = value
                perform(value)
            }
        }
    }
}
