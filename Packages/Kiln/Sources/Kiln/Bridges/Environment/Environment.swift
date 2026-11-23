//
//  Environment.swift
//  Bridges: property wrappers, environment values and the modifiers that set them
//
//  The wrappers themselves are the engine's (`KViewStorage`); they're declared
//  here so the manifest and the checker know them.
//

import SwiftUI

@objc(KilnBridges_Environment)
final class EnvironmentBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        wrappers(r)
        values(r)
        modifiers(r)
    }

    static func wrappers(_ r: KRegistry) {
        r.wrapper("State", .environment, notes: "Lives as long as the view, by SwiftUI's own identity rules.")
        r.wrapper("Binding", .environment)
        r.wrapper("StateObject", .environment)
        r.wrapper("ObservedObject", .environment)
        r.wrapper("EnvironmentObject", .environment, notes: "Set with `.environmentObject(_:)`.")
        r.wrapper("Environment", .environment, support: .partial, notes: "The key paths listed as environment values; not `@Environment(Model.self)`.")
        r.wrapper("Published", .environment)
        r.wrapper("AppStorage", .environment, notes: "Kept per app.")
        r.wrapper("SceneStorage", .environment, support: .partial, notes: "Kept while the app is open.")
        r.wrapper("FocusState", .focus, notes: "A `Bool` or an optional `Hashable` (an enum of fields); it moves the keyboard focus.")
        r.wrapper("Namespace", .environment, notes: "For `matchedGeometryEffect`, `glassEffectID` and the zoom transition; pass it down as `Namespace.ID`.")
        r.wrapper("GestureState", .gestures, notes: "Set in a gesture's `updating`; back to its initial value when the gesture ends.")
        r.wrapper("Bindable", .environment)
    }

    static func values(_ r: KRegistry) {
        r.environmentValue("dismiss", .environment) { _ in .native(.dismiss(KRef({}))) }
        r.environmentValue("presentationMode", .environment, support: .partial, notes: "`wrappedValue.dismiss()`; prefer `dismiss`.") { _ in .native(.dismiss(KRef({}))) }
        environmentValues(r)

        r.type("DismissAction", .environment) { t in
            t.method("callAsFunction") { c in
                if case .native(.dismiss(let action)) = c.receiver { action.value() }
                return .void
            }
            // `presentationMode.wrappedValue.dismiss()`, the older form.
            t.property("wrappedValue") { c in c.receiver }
            t.method("dismiss", "") { c in
                if case .native(.dismiss(let action)) = c.receiver { action.value() }
                return .void
            }
        }
    }

    static func modifiers(_ r: KRegistry) {
        r.modifier("environment", .environment, notes: "SwiftUI's values that can be set, your own `@Entry` values, and `@Observable` objects read with `@Environment(Model.self)`.") { m in
            m.form("_:any _:any") { c, view in
                if case .native(.keyPath(let comps))? = c[0], let key = comps.last, let write = c.interp.registry.environment[key]?.writeEnvironment {
                    // A SwiftUI value Values.swift bridges (`\.colorScheme`, `\.dynamicTypeSize`).
                    let value = c[1] ?? .nilValue, interp = c.interp
                    view.transformEnvironment(\.self) { env in MainActor.assumeIsolated { write(&env, value, interp) } }
                } else if case .native(.keyPath(let comps))? = c[0], let key = comps.last, let write = c.interp.registry.environment[key]?.write {
                    // A SwiftUI value another family bridges (`\.defaultMinListRowHeight`, `\.editMode`).
                    write(view, c[1] ?? .nilValue, c)
                } else if case .native(.keyPath(let comps))? = c[0], let key = comps.last, c.interp.registry.environment[key] == nil {
                    // The app's own value (`@Entry var accent`), for the `@Environment(\.accent)` below.
                    view.transformEnvironment(\.kilnObjects) { $0["\\." + key] = c.interp.coerce(c[1] ?? .nilValue, to: c.interp.userEnvironmentType(key)) }
                } else {
                    view
                }
            }
            m.form("_:any", notes: "An `@Observable` object, read with `@Environment(Model.self)`.") { c, view in
                if let obj = c[0], let typeName = obj.userType?.name {
                    view.transformEnvironment(\.kilnObjects) { $0[typeName] = obj }
                } else {
                    view
                }
            }
        }
        r.modifier("environmentObject", .environment) { m in
            m.form("_:any") { c, view in
                if let obj = c[0], let typeName = obj.userType?.name {
                    view.transformEnvironment(\.kilnObjects) { $0[typeName] = obj }
                } else {
                    view
                }
            }
        }
        r.modifier("preferredColorScheme", .environment) { m in
            m.form("_:ColorScheme?") { c, view in
                if let n = c.symbol(0) { view.preferredColorScheme(n == "dark" ? .dark : .light) } else { view }
            }
        }
        preferences(r)
        environmentModifiers(r)
    }
}
