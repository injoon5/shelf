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
        r.wrapper("FocusState", .focus, support: .partial, notes: "Holds a value; it doesn't move the keyboard focus yet.")
        r.wrapper("Namespace", .environment, support: .stub)
        r.wrapper("GestureState", .gestures, support: .stub)
        r.wrapper("Bindable", .environment)
    }

    static func values(_ r: KRegistry) {
        r.environmentValue("dismiss", .environment) { _ in .native(.dismiss(KRef({}))) }
        r.environmentValue("presentationMode", .environment, support: .partial, notes: "`wrappedValue.dismiss()`; prefer `dismiss`.") { _ in .native(.dismiss(KRef({}))) }
        r.environmentValue("colorScheme", .environment) { _ in .native(.implicit("light", [])) }
        r.environmentValue("horizontalSizeClass", .environment, support: .partial, notes: "Always `.compact`.") { _ in .native(.implicit("compact", [])) }
        r.environmentValue("verticalSizeClass", .environment, support: .partial, notes: "Always `.compact`.") { _ in .native(.implicit("compact", [])) }
        r.environmentValue("locale", .environment) { _ in .native(.object("Locale", KRef(Locale.current as AnyObject))) }
        r.environmentValue("calendar", .environment) { _ in .native(.object("Calendar", KRef(Calendar.current as AnyObject))) }

        r.type("DismissAction", .environment) { t in
            t.method("callAsFunction") { c in
                if case .native(.dismiss(let action)) = c.receiver { action.value() }
                return .void
            }
        }
    }

    static func modifiers(_ r: KRegistry) {
        r.modifier("environment", .environment, support: .partial, notes: "`\\.colorScheme`, your own `@Entry` values, and `@Observable` objects read with `@Environment(Model.self)`.") { m in
            m.form("_:any _:any") { c, view in
                if case .native(.keyPath(let comps))? = c[0], comps.last == "colorScheme", let n = c.symbol(1) {
                    view.environment(\.colorScheme, n == "dark" ? .dark : .light)
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
        r.modifier("colorScheme", .environment, support: .stub) { m in m.stub(["_:ColorScheme"]) }
        r.modifier("dynamicTypeSize", .environment, support: .stub) { m in m.stub(["_:any"]) }
        r.modifier("redacted", .environment, support: .stub) { m in m.stub(["reason:any"]) }
        r.modifier("privacySensitive", .environment, support: .stub) { m in m.stub(["_:bool?"]) }
    }
}
