//
//  Representables.swift
//  Bridges: `UIViewControllerRepresentable` and `UIViewRepresentable` (PLAN.md §1.5)
//
//  The app's representable struct is shown by a native representable that
//  calls the app's `makeCoordinator()`, `makeUIViewController(context:)` and
//  `updateUIViewController(_:context:)` (or the `UIView` forms). What the app
//  returns must be a UIKit object Kiln bridges and **allows**: the allowlist
//  is every class declared with `r.representableController(…)` or
//  `r.representableView(…)` (Round 3's `UIImagePickerController`, here
//  `UIVisualEffectView` and `UIActivityIndicatorView`). Anything else is an
//  error naming what's allowed.
//
//  The coordinator is the app's object (a class, often adopting a delegate
//  protocol that `KDelegates` forwards); `context.coordinator` is it.
//  `@Environment(\.dismiss)` in the struct is SwiftUI's real one, so a
//  coordinator calling `parent.dismiss()` closes the sheet.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The UIKit classes a representable may return, by bridge name.
@MainActor
enum KRepresentables {
    static var controllers: [String: AnyClass] = [:]
    static var views: [String: AnyClass] = [:]

    static func allowed(_ names: [String: AnyClass]) -> String {
        KInterpreter.list(names.keys.sorted())
    }
}

extension KRegistry {
    /// Lets the app's `UIViewControllerRepresentable` return this controller
    /// (whose type bridge the family declares too).
    func representableController(_ cls: AnyClass, _ name: String) {
        KRepresentables.controllers[name] = cls
        nativeClass(cls, name)
    }

    /// Lets the app's `UIViewRepresentable` return this view.
    func representableView(_ cls: AnyClass, _ name: String) {
        KRepresentables.views[name] = cls
        nativeClass(cls, name)
    }
}

/// The representable's coordinator: what the app's `makeCoordinator()` made.
final class KCoordinator {
    var value: KV = .nilValue
}

/// `context` in the app's make and update methods.
final class KRepresentableContext {
    let coordinator: KV
    let transaction: Transaction
    init(coordinator: KV, transaction: Transaction) {
        self.coordinator = coordinator
        self.transaction = transaction
    }
}

extension CoreBridges {
    static func representables(_ r: KRegistry) {
        let controllerNotes = "For the UIKit controllers Kiln allows (`UIImagePickerController`): `makeUIViewController(context:)`, `updateUIViewController(_:context:)`, and `makeCoordinator()` with your `Coordinator` class as the controller's delegate."
        r.protocolBridge("UIViewControllerRepresentable", .core,
                         requirements: ["makeUIViewController(context:)", "updateUIViewController(_:context:)", "makeCoordinator()?"],
                         support: .partial, notes: controllerNotes) { app in
            #if os(iOS) || os(visionOS)
            return AnyView(KControllerRepresentable(app: app))
            #else
            return AnyView(KErrorView(message: "\(app.type.name) needs UIKit"))
            #endif
        }
        r.protocolBridge("UIViewRepresentable", .core,
                         requirements: ["makeUIView(context:)", "updateUIView(_:context:)", "makeCoordinator()?"],
                         support: .partial,
                         notes: "For the UIKit views Kiln allows: `UIVisualEffectView` (with `UIBlurEffect(style:)`) and `UIActivityIndicatorView`.") { app in
            #if os(iOS) || os(visionOS)
            return AnyView(KViewRepresentable(app: app))
            #else
            return AnyView(KErrorView(message: "\(app.type.name) needs UIKit"))
            #endif
        }
        r.type("UIViewControllerRepresentableContext", .core, notes: "`context.coordinator`.") { t in
            t.property("coordinator") { c in context(c)?.coordinator ?? .nilValue }
        }
        r.alias("UIViewRepresentableContext", to: "UIViewControllerRepresentableContext", engineOnly: true)

        // The allowlist's UIKit views (cheap ones models write for a blur or a spinner).
        r.type("UIBlurEffect", .core, notes: "`UIBlurEffect(style:)` for a `UIVisualEffectView`.") { t in
            t.initializer("style:any") { c in
                #if canImport(UIKit) && !os(watchOS)
                return .native(.object("UIBlurEffect", KRef(UIBlurEffect(style: blurStyle(c.symbol("style"))))))
                #else
                throw c.fail("needs UIKit")
                #endif
            }
        }
        r.type("UIVisualEffectView", .core, notes: "`UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))` in a `UIViewRepresentable`.") { t in
            t.initializer("effect:any") { c in
                #if canImport(UIKit) && !os(watchOS)
                let effect = KCall.objectValue(c.args[0]) as? UIVisualEffect
                return .native(.object("UIVisualEffectView", KRef(UIVisualEffectView(effect: effect))))
                #else
                throw c.fail("needs UIKit")
                #endif
            }
            t.property("effect", { c in
                #if canImport(UIKit) && !os(watchOS)
                if let v = c.object(UIVisualEffectView.self), let e = v.effect { return .native(.object("UIBlurEffect", KRef(e))) }
                #endif
                return .nilValue
            }, set: { c in
                #if canImport(UIKit) && !os(watchOS)
                c.object(UIVisualEffectView.self)?.effect = KCall.objectValue(c.args[0]) as? UIVisualEffect
                #endif
            })
        }
        r.type("UIActivityIndicatorView", .core, notes: "`UIActivityIndicatorView(style:)`, `startAnimating()`, `stopAnimating()`, `color`.") { t in
            for sig in ["", "style:any"] {
                t.initializer(sig) { c in
                    #if canImport(UIKit) && !os(watchOS)
                    let v = UIActivityIndicatorView(style: c.symbol("style") == "large" ? .large : .medium)
                    return .native(.object("UIActivityIndicatorView", KRef(v)))
                    #else
                    throw c.fail("needs UIKit")
                    #endif
                }
            }
            t.method("startAnimating", "") { c in
                #if canImport(UIKit) && !os(watchOS)
                c.object(UIActivityIndicatorView.self)?.startAnimating()
                #endif
                return .void
            }
            t.method("stopAnimating", "") { c in
                #if canImport(UIKit) && !os(watchOS)
                c.object(UIActivityIndicatorView.self)?.stopAnimating()
                #endif
                return .void
            }
            t.property("isAnimating") { c in
                #if canImport(UIKit) && !os(watchOS)
                return .bool(c.object(UIActivityIndicatorView.self)?.isAnimating ?? false)
                #else
                return .bool(false)
                #endif
            }
            t.property("color", { _ in .nilValue }, set: { c in
                #if canImport(UIKit) && !os(watchOS)
                if let color = c.color(0) { c.object(UIActivityIndicatorView.self)?.color = UIColor(color) }
                #endif
            })
        }
        #if canImport(UIKit) && !os(watchOS)
        r.representableView(UIVisualEffectView.self, "UIVisualEffectView")
        r.representableView(UIActivityIndicatorView.self, "UIActivityIndicatorView")
        r.nativeClass(UIBlurEffect.self, "UIBlurEffect")
        #endif
    }

    @MainActor static func context(_ c: KCall) -> KRepresentableContext? {
        if case .native(.object(_, let ref)) = c.receiver { return ref.value as? KRepresentableContext }
        return nil
    }

    #if canImport(UIKit) && !os(watchOS)
    static func blurStyle(_ name: String?) -> UIBlurEffect.Style {
        switch name {
        case "systemUltraThinMaterial": return .systemUltraThinMaterial
        case "systemThinMaterial": return .systemThinMaterial
        case "systemThickMaterial": return .systemThickMaterial
        case "systemChromeMaterial": return .systemChromeMaterial
        case "light": return .light
        case "dark": return .dark
        case "extraLight": return .extraLight
        case "regular": return .regular
        case "prominent": return .prominent
        default: return .systemMaterial
        }
    }
    #endif
}

extension KAppValue {
    /// The struct with SwiftUI's environment in its `@Environment` properties:
    /// `dismiss` (and `presentationMode`) close what presented it.
    func withEnvironment(dismiss: @escaping () -> Void) -> KAppValue {
        var a = self
        for p in type.stored where p.wrapper == "Environment" {
            if case .native(.dismiss)? = a.structValue?.fields[p.name] {
                a.setField(p.name, .native(.dismiss(KRef(dismiss))))
            }
        }
        return a
    }

    /// The coordinator the app makes, if it has `makeCoordinator()`.
    func makeCoordinator() -> KCoordinator {
        let box = KCoordinator()
        if implements("makeCoordinator", labels: []) {
            var a = self
            box.value = a.callReporting("makeCoordinator", [], labels: [], fallback: .nilValue)
        }
        return box
    }

    func representableContext(_ coordinator: KCoordinator, _ transaction: Transaction) -> KV {
        .native(.object("UIViewControllerRepresentableContext", KRef(KRepresentableContext(coordinator: coordinator.value, transaction: transaction))))
    }
}

extension KCall {
    /// The native object a value holds (`.native(.object(_, ref))`).
    static func objectValue(_ v: KV?) -> AnyObject? {
        if case .native(.object(_, let ref))? = v { return ref.value }
        return nil
    }
}

#if os(iOS) || os(visionOS)
/// The app's `UIViewControllerRepresentable`, shown.
struct KControllerRepresentable: UIViewControllerRepresentable {
    let app: KAppValue
    @SwiftUI.Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> KCoordinator {
        app.withEnvironment(dismiss: { [dismiss] in dismiss() }).makeCoordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        var a = app.withEnvironment(dismiss: { [dismiss] in dismiss() })
        let v = a.callReporting("makeUIViewController", [a.representableContext(context.coordinator, context.transaction)], labels: ["context"], fallback: .nilValue)
        if case .native(.object(let name, let ref)) = v, KRepresentables.controllers[name] != nil, let vc = ref.value as? UIViewController {
            return vc
        }
        a.interp.report(a.interp.fail("\(app.type.name).makeUIViewController(context:) must return a controller Kiln allows (\(KRepresentables.allowed(KRepresentables.controllers))), not \(v.typeName)", app.type.line))
        return UIHostingController(rootView: KErrorView(message: "\(app.type.name) can't be shown"))
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {
        guard app.implements("updateUIViewController", labels: [nil, "context"]) else { return }
        var a = app.withEnvironment(dismiss: { [dismiss] in dismiss() })
        _ = a.callReporting("updateUIViewController", [KNativeValues.kv(from: vc), a.representableContext(context.coordinator, context.transaction)],
                            labels: [nil, "context"])
    }
}

/// The app's `UIViewRepresentable`, shown.
struct KViewRepresentable: UIViewRepresentable {
    let app: KAppValue
    @SwiftUI.Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> KCoordinator {
        app.withEnvironment(dismiss: { [dismiss] in dismiss() }).makeCoordinator()
    }

    func makeUIView(context: Context) -> UIView {
        var a = app.withEnvironment(dismiss: { [dismiss] in dismiss() })
        let v = a.callReporting("makeUIView", [a.representableContext(context.coordinator, context.transaction)], labels: ["context"], fallback: .nilValue)
        if case .native(.object(let name, let ref)) = v, KRepresentables.views[name] != nil, let view = ref.value as? UIView {
            return view
        }
        a.interp.report(a.interp.fail("\(app.type.name).makeUIView(context:) must return a view Kiln allows (\(KRepresentables.allowed(KRepresentables.views))), not \(v.typeName)", app.type.line))
        return UIView()
    }

    func updateUIView(_ view: UIView, context: Context) {
        guard app.implements("updateUIView", labels: [nil, "context"]) else { return }
        var a = app.withEnvironment(dismiss: { [dismiss] in dismiss() })
        _ = a.callReporting("updateUIView", [KNativeValues.kv(from: view), a.representableContext(context.coordinator, context.transaction)],
                            labels: [nil, "context"])
    }
}
#endif
