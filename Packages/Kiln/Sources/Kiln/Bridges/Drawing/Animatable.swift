//
//  Animatable.swift
//  Bridges: the app's own Shape, Animatable and Transition types (PLAN.md §1.5)
//
//  Each is a protocol proxy: a native type conforming to SwiftUI's protocol
//  that forwards to the app's value (Engine/KEProxies.swift).
//
//  - `Shape`: `KUserShape` (Shapes.swift) draws with the app's `path(in:)`.
//  - `Animatable`: a shape's, a view's or a modifier's `animatableData` (its
//    own, `AnimatablePair`s of numbers, or `@Animatable`'s properties) is a
//    `KAnimVector` SwiftUI interpolates, written back into the app's value
//    each frame.
//  - `Transition` (iOS 17): `body(content:phase:)` runs with SwiftUI's content
//    and phase; `.transition(MyTransition())` and `.transition(.mine)` both work.
//

import SwiftUI

extension DrawingBridges {
    static func animatable(_ r: KRegistry) {
        r.proxy("Shape") { app in AnyShape(KUserShape(app: app)) }
        r.proxy("InsettableShape") { app in AnyShape(KUserShape(app: app)) }

        r.protocolBridge("Animatable", .drawing, requirements: ["animatableData?"], support: .full,
                         notes: "A shape, view or `ViewModifier` with `animatableData` (a number, `AnimatablePair`, `CGPoint`, `Angle`…) or `@Animatable` is interpolated frame by frame inside `withAnimation`.") { app in
            AnyView(KAnimatableView(app: app))
        }
        r.type("AnimatablePair", .drawing, notes: "`AnimatablePair(a, b)`, with `.first` and `.second`; pairs nest.") { t in
            t.initializer("_:any _:any") { c in .tuple([c.args[0], c.args[1]], ["first", "second"]) }
        }
        r.type("EmptyAnimatableData", .drawing) { t in
            t.initializer("") { _ in .native(.boxed(KBoxed("EmptyAnimatableData", 0))) }
        }

        // `Transition` the protocol (iOS 17); `Transition` the type (Drawing.swift) has its static members.
        r.protocolBridge("Transition", .drawing, requirements: ["body(content:phase:)"], support: .full, introduced: "17.0",
                         notes: "Your own transition: `body(content:phase:)` runs with the view and its `TransitionPhase`. Use it with `.transition(MyTransition())`, or add `extension Transition where Self == MyTransition { static var mine: Self { … } }`.") { app in
            KTransitionProxy(app: app)
        }
        r.type("TransitionPhase", .drawing, notes: "`.willAppear`, `.identity`, `.didDisappear`; `isIdentity` and `value` (-1, 0, 1).") { t in
            for name in ["willAppear", "identity", "didDisappear"] {
                t.staticProperty(name) { _ in phase(name) }
            }
            t.implicit { name, _, _ in ["willAppear", "identity", "didDisappear"].contains(name) ? phase(name) : nil }
            t.property("isIdentity") { c in .bool(phaseName(c.receiver) == "identity") }
            t.property("value") { c in
                switch phaseName(c.receiver) {
                case "willAppear": return .double(-1)
                case "didDisappear": return .double(1)
                default: return .double(0)
                }
            }
        }
    }

    static func phase(_ name: String) -> KV { .native(.boxed(KBoxed("TransitionPhase", name, caseName: name))) }
    static func phase(_ p: TransitionPhase) -> KV { phase(p == .identity ? "identity" : (p == .willAppear ? "willAppear" : "didDisappear")) }
    static func phaseName(_ v: KV) -> String? { if case .native(.boxed(let b)) = v { return b.caseName }; return nil }
}

/// The app's `Animatable` view: SwiftUI interpolates its `animatableData`,
/// and each frame's value is shown by the usual host (with its `@State`).
struct KAnimatableView: View, Animatable {
    var app: KAppValue

    nonisolated var animatableData: KAnimVector {
        get { MainActor.assumeIsolated { KAnimatable.data(app) } }
        set { MainActor.assumeIsolated { KAnimatable.setData(&app, newValue) } }
    }

    var body: some View {
        if let s = app.structValue { KHostView(value: s, interp: app.interp) }
    }
}

/// The app's `Transition`: SwiftUI hands it the view and the phase, and the
/// app's `body(content:phase:)` says how the view looks in that phase.
struct KTransitionProxy: Transition, @unchecked Sendable {
    let app: KAppValue

    func body(content: Content, phase: TransitionPhase) -> some View {
        KTransitionBody(app: app, content: AnyView(content), phase: phase)
    }
}

/// Its own view, so the app's code runs inside a SwiftUI `body` (observation, errors).
struct KTransitionBody: View {
    let app: KAppValue
    let content: AnyView
    let phase: TransitionPhase

    var body: some View {
        var a = app
        let v = a.callReporting("body", [KNativeContent.value(content), DrawingBridges.phase(phase)], labels: ["content", "phase"], fallback: .nilValue)
        return KRenderer(interp: app.interp).render(.group(KBuiltins.asViews(v, app.interp)))
    }
}

/// SwiftUI's own content handed to the app's code (a `ViewModifier`'s
/// `content`, a `Transition`'s): a view the app modifies like any other.
@MainActor
enum KNativeContent {
    static func value(_ view: AnyView) -> KV {
        .view(.primitive("NativeContent", [.native(.object("AnyView", KRef(KAnyViewBox(view))))], [nil], line: 0))
    }
}

final class KAnyViewBox {
    let view: AnyView
    init(_ view: AnyView) { self.view = view }
}
