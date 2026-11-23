//
//  Scrolling.swift
//  Bridges: scroll position, paging, scroll transitions and scroll events
//
//  `.scrollPosition($position)` with a `ScrollPosition` the app moves
//  (`position.scrollTo(edge: .top)`), or `.scrollPosition(id: $selected)`;
//  `.scrollTargetBehavior(.paging)` and `.viewAligned` with
//  `.scrollTargetLayout()`; `.scrollTransition { content, phase in … }`;
//  `onScrollGeometryChange`, `onScrollPhaseChange` and the visibility events.
//

import SwiftUI

/// Kiln's values are compared and hashed as Swift values, so SwiftUI may keep
/// them as scroll ids (`ScrollPosition`, `scrollPosition(id:)`).
extension KV: @unchecked Sendable {}

/// A `ScrollPosition`, a value: each change makes a new box.
@available(iOS 18.0, macOS 15.0, *)
final class KScrollPositionBox {
    let position: ScrollPosition
    init(_ position: ScrollPosition) { self.position = position }
    var kv: KV { .native(.object("ScrollPosition", KRef(self))) }
}

extension LayoutBridges {
    static func scrolling(_ r: KRegistry) {
        scrollTypes(r)
        scrollModifiers(r)
        scrollEvents(r)
    }

    // MARK: Values

    static func scrollTypes(_ r: KRegistry) {
        if #available(iOS 18.0, macOS 15.0, *) { scrollPositionType(r) }
        for name in ["ScrollPhase", "ScrollTransitionPhase", "ScrollBounceBehavior", "ScrollIndicatorVisibility", "ContentMarginPlacement", "ScrollAnchorRole"] {
            r.type(name, .layout) { t in
                t.internal()
                t.anyStatic { _, member in .native(.implicit(member, [])) }
            }
        }
        r.type("ScrollTargetBehavior", .layout) { t in
            t.membersInManifest = true
            t.staticProperty("paging") { _ in .native(.implicit("paging", [])) }
            t.staticProperty("viewAligned") { _ in .native(.implicit("viewAligned", [])) }
            t.staticMethod("viewAligned", "limitBehavior:any? anchor:UnitPoint?") { c in .native(.implicit("viewAligned", c.args)) }
        }

        // `phase.isScrolling`, `phase.isIdentity`, `phase.value`.
        r.implicitProperties["isScrolling"] = { base, _ in
            ["idle", "tracking", "interacting", "decelerating", "animating"].contains(base) ? .bool(base != "idle") : nil
        }
        r.implicitProperties["isIdentity"] = { base, _ in
            ["identity", "topLeading", "bottomTrailing"].contains(base) ? .bool(base == "identity") : nil
        }
        r.implicitProperties["value"] = { base, _ in
            switch base {
            case "topLeading": return .double(-1)
            case "identity": return .double(0)
            case "bottomTrailing": return .double(1)
            default: return nil
            }
        }
    }

    @available(iOS 18.0, macOS 15.0, *)
    static func scrollPositionType(_ r: KRegistry) {
        r.type("ScrollPosition", .layout, support: .full,
               notes: "`ScrollPosition(edge:)`, `(id:)`, `(x:y:)`; `scrollTo(id:)`, `scrollTo(edge:)`, `scrollTo(x:y:)`; `viewID`, `edge`, `point`, `isPositionedByUser`.") { t in
            t.initializer("idType:any?") { _ in KScrollPositionBox(ScrollPosition()).kv }
            t.initializer("idType:any? edge:Edge") { c in KScrollPositionBox(ScrollPosition(edge: edge(c["edge"]))).kv }
            t.initializer("idType:any? point:CGPoint") { c in KScrollPositionBox(ScrollPosition(point: point(c["point"]))).kv }
            t.initializer("idType:any? x:number") { c in KScrollPositionBox(ScrollPosition(x: c.cg("x") ?? 0)).kv }
            t.initializer("idType:any? y:number") { c in KScrollPositionBox(ScrollPosition(y: c.cg("y") ?? 0)).kv }
            t.initializer("idType:any? x:number y:number") { c in KScrollPositionBox(ScrollPosition(x: c.cg("x") ?? 0, y: c.cg("y") ?? 0)).kv }
            t.initializer("id:any anchor:UnitPoint?") { c in KScrollPositionBox(ScrollPosition(id: c["id"] ?? .nilValue, anchor: c.unitPoint("anchor"))).kv }
            @MainActor func pos(_ c: KCall) -> ScrollPosition {
                if case .native(.object(_, let ref)) = c.receiver, let b = ref.value as? KScrollPositionBox { return b.position }
                return ScrollPosition()
            }
            // Mutating: the receiver gets the moved position.
            @MainActor func move(_ c: inout KCall, _ f: (inout ScrollPosition) -> Void) -> KV {
                var p = pos(c)
                f(&p)
                c.mutated = KScrollPositionBox(p).kv
                return .void
            }
            t.method("scrollTo", "id:any anchor:UnitPoint?") { c in
                let id = c["id"] ?? .nilValue, anchor = c.unitPoint("anchor")
                return move(&c) { $0.scrollTo(id: id, anchor: anchor) }
            }
            t.method("scrollTo", "edge:Edge") { c in let e = edge(c["edge"]); return move(&c) { $0.scrollTo(edge: e) } }
            t.method("scrollTo", "point:CGPoint") { c in let p = point(c["point"]); return move(&c) { $0.scrollTo(point: p) } }
            t.method("scrollTo", "x:number") { c in let x = c.cg("x") ?? 0; return move(&c) { $0.scrollTo(x: x) } }
            t.method("scrollTo", "y:number") { c in let y = c.cg("y") ?? 0; return move(&c) { $0.scrollTo(y: y) } }
            t.method("scrollTo", "x:number y:number") { c in let x = c.cg("x") ?? 0, y = c.cg("y") ?? 0; return move(&c) { $0.scrollTo(x: x, y: y) } }
            t.property("isPositionedByUser") { c in .bool(pos(c).isPositionedByUser) }
            t.property("viewID") { c in (pos(c).viewID as? KV) ?? .nilValue }
            t.method("viewID", "type:any") { c in (pos(c).viewID as? KV) ?? .nilValue }
            t.property("edge") { c in
                guard let e = pos(c).edge else { return .nilValue }
                return .native(.implicit(e == .top ? "top" : (e == .bottom ? "bottom" : (e == .leading ? "leading" : "trailing")), []))
            }
            t.property("point") { c in pos(c).point.map { .native(.point($0.x, $0.y)) } ?? .nilValue }
        }

    }

    @MainActor static func edge(_ v: KV?) -> Edge {
        guard case .native(.implicit(let n, _))? = v else { return .top }
        switch n {
        case "bottom": return .bottom
        case "leading": return .leading
        case "trailing": return .trailing
        default: return .top
        }
    }

    @MainActor static func point(_ v: KV?) -> CGPoint {
        if case .native(.point(let x, let y))? = v { return CGPoint(x: x, y: y) }
        return .zero
    }

    // MARK: Modifiers

    static func scrollModifiers(_ r: KRegistry) {
        r.modifier("scrollPosition", .layout, notes: "A `ScrollPosition` binding, or `id:` bound to the id of the view at the top (with `.scrollTargetLayout()`).") { m in
            m.form("_:binding anchor:UnitPoint?") { c, view in
                if #available(iOS 18.0, macOS 15.0, *), let b = c.kbinding(0) {
                    let position = Binding<ScrollPosition>(get: {
                        if case .native(.object(_, let ref)) = b.get(), let box = ref.value as? KScrollPositionBox { return box.position }
                        return ScrollPosition()
                    }, set: { b.set(KScrollPositionBox($0).kv) })
                    AnyView(view.scrollPosition(position, anchor: c.unitPoint("anchor")))
                } else { view }
            }
            m.form("id:binding anchor:UnitPoint?") { c, view in
                if let b = c.kbinding("id") {
                    let id = Binding<KV?>(get: { let v = b.get(); return v.isNil ? nil : v }, set: { b.set($0 ?? .nilValue) })
                    AnyView(view.scrollPosition(id: id, anchor: c.unitPoint("anchor")))
                } else { view }
            }
        }
        r.modifier("scrollTargetBehavior", .layout, notes: "`.paging`, or `.viewAligned` with `.scrollTargetLayout()` on the stack inside.") { m in
            m.form("_:ScrollTargetBehavior") { c, view in
                switch c.symbol(0) {
                case "paging": AnyView(view.scrollTargetBehavior(.paging))
                case "viewAligned":
                    if case .native(.implicit(_, let args))? = c[0], args.contains(where: { if case .native(.implicit("never", _)) = $0 { return true }; return false }) {
                        AnyView(view.scrollTargetBehavior(.viewAligned(limitBehavior: .never)))
                    } else if case .native(.implicit(_, let args))? = c[0], args.contains(where: { if case .native(.implicit("always", _)) = $0 { return true }; return false }) {
                        AnyView(view.scrollTargetBehavior(.viewAligned(limitBehavior: .always)))
                    } else {
                        AnyView(view.scrollTargetBehavior(.viewAligned))
                    }
                default: view
                }
            }
        }
        r.modifier("scrollTargetLayout", .layout) { m in
            m.form("isEnabled:bool?") { c, view in view.scrollTargetLayout(isEnabled: c.bool("isEnabled", default: true)) }
        }
        r.modifier("defaultScrollAnchor", .layout) { m in
            m.form("_:UnitPoint?") { c, view in view.defaultScrollAnchor(c.unitPoint(0)) }
            m.form("_:UnitPoint? for:ScrollAnchorRole") { c, view in
                if #available(iOS 18.0, macOS 15.0, *) {
                    switch c.symbol("for") {
                    case "initialOffset": AnyView(view.defaultScrollAnchor(c.unitPoint(0), for: .initialOffset))
                    case "sizeChanges": AnyView(view.defaultScrollAnchor(c.unitPoint(0), for: .sizeChanges))
                    default: AnyView(view.defaultScrollAnchor(c.unitPoint(0), for: .alignment))
                    }
                } else { AnyView(view.defaultScrollAnchor(c.unitPoint(0))) }
            }
        }
        r.modifier("scrollDisabled", .layout) { m in m.form("_:bool") { c, view in view.scrollDisabled(c.bool(0, default: true)) } }
        r.modifier("scrollClipDisabled", .layout) { m in m.form("_:bool?") { c, view in view.scrollClipDisabled(c.bool(0, default: true)) } }
        r.modifier("scrollBounceBehavior", .layout) { m in
            m.form("_:ScrollBounceBehavior axes:Axis.Set?") { c, view in
                let axes = c["axes"].map { KLayout.axes($0) } ?? .vertical
                switch c.symbol(0) {
                case "basedOnSize": view.scrollBounceBehavior(.basedOnSize, axes: axes)
                case "always": view.scrollBounceBehavior(.always, axes: axes)
                default: view.scrollBounceBehavior(.automatic, axes: axes)
                }
            }
        }
        r.modifier("scrollIndicatorsFlash", .layout) { m in
            m.form("onAppear:bool") { c, view in view.scrollIndicatorsFlash(onAppear: c.bool("onAppear", default: true)) }
            m.form("trigger:any") { c, view in view.scrollIndicatorsFlash(trigger: c["trigger"] ?? .nilValue) }
        }
        r.modifier("scrollEdgeEffectHidden", .layout, introduced: "26.0") { m in
            m.form("_:bool? for:Edge.Set?") { c, view in
                if #available(iOS 26.0, macOS 26.0, *) {
                    AnyView(view.scrollEdgeEffectHidden(c.bool(0, default: true), for: c["for"] == nil ? .all : c.edges("for")))
                } else { view }
            }
        }
        r.modifier("scrollInputBehavior", .layout, introduced: "18.0", notes: "Hand-gesture and look input are visionOS and watchOS; on iPhone it changes nothing.") { m in
            m.form("_:ScrollInputBehavior for:ScrollInputKind") { _, view in view }
        }
        r.modifier("scrollTransition", .layout, support: .partial,
                   notes: "The closure's `content` takes `opacity`, `scaleEffect`, `offset`, `rotationEffect`, `blur`, `brightness`, `saturation`, `contrast`, `hueRotation` and `grayscale`, by `phase.isIdentity` or `phase.value`.") { m in
            m.forms(["transition:closure", "axis:Axis transition:closure", "_:any axis:Axis? transition:closure",
                     "topLeading:any bottomTrailing:any axis:Axis? transition:closure"]) { c, view in scrollTransition(c, view) }
            m.probe { _, _ in [.view(.empty), .native(.implicit("identity", []))] }
        }
    }

    /// The effects a scroll transition's closure applies, per phase.
    struct KTransitionEffect: Sendable {
        var opacity = 1.0, scaleX = 1.0, scaleY = 1.0, x = 0.0, y = 0.0, rotation = 0.0
        var blur = 0.0, brightness = 0.0, saturation = 1.0, contrast = 1.0, hue = 0.0, grayscale = 0.0
    }

    @MainActor static func scrollTransition(_ c: KCall, _ view: AnyView) -> AnyView {
        guard case .function(let f)? = c.last else { return view }
        let interp = c.interp, r = c.r
        // Run the app's closure once per phase, now; SwiftUI interpolates between them.
        func effect(_ phase: String) -> KTransitionEffect {
            var e = KTransitionEffect()
            guard let out = try? interp.entry({ try interp.call(f, [.view(.empty), .native(.implicit(phase, []))], [nil, nil]) }),
                  case .view(var v) = out else { return e }
            var mods: [KModifier] = []
            while case .modified(let base, let m) = v.kind { mods.insert(m, at: 0); v = base }
            for m in mods {
                switch m.name {
                case "opacity": e.opacity = m.first?.asDouble ?? 1
                case "scaleEffect":
                    if let s = m.first?.asDouble, m.labels.first == .some(nil) { e.scaleX = s; e.scaleY = s }
                    else if case .native(.size(let w, let h))? = m.first { e.scaleX = w; e.scaleY = h }
                    else { e.scaleX = m.arg("x")?.asDouble ?? 1; e.scaleY = m.arg("y")?.asDouble ?? 1 }
                case "offset":
                    if case .native(.size(let w, let h))? = m.first { e.x = w; e.y = h }
                    else { e.x = m.arg("x")?.asDouble ?? 0; e.y = m.arg("y")?.asDouble ?? 0 }
                case "rotationEffect": e.rotation = r.angle(m.first).degrees
                case "blur": e.blur = m.arg("radius")?.asDouble ?? 0
                case "brightness": e.brightness = m.first?.asDouble ?? 0
                case "saturation": e.saturation = m.first?.asDouble ?? 1
                case "contrast": e.contrast = m.first?.asDouble ?? 1
                case "hueRotation": e.hue = r.angle(m.first).degrees
                case "grayscale": e.grayscale = m.first?.asDouble ?? 0
                default: break
                }
            }
            return e
        }
        let lead = effect("topLeading"), identity = effect("identity"), trail = effect("bottomTrailing")
        let axis = KLayout.axis(c["axis"])
        let apply: @Sendable (EmptyVisualEffect, ScrollTransitionPhase) -> _ = { content, phase in
            let e = phase == .identity ? identity : (phase == .topLeading ? lead : trail)
            return content
                .opacity(e.opacity)
                .scaleEffect(x: e.scaleX, y: e.scaleY)
                .offset(x: e.x, y: e.y)
                .rotationEffect(.degrees(e.rotation))
                .blur(radius: e.blur)
                .brightness(e.brightness)
                .saturation(e.saturation)
                .contrast(e.contrast)
                .hueRotation(.degrees(e.hue))
                .grayscale(e.grayscale)
        }
        if c["topLeading"] != nil {
            return AnyView(view.scrollTransition(topLeading: transitionConfig(c["topLeading"]), bottomTrailing: transitionConfig(c["bottomTrailing"]), axis: axis, transition: apply))
        }
        return AnyView(view.scrollTransition(transitionConfig(c[0]), axis: axis, transition: apply))
    }

    @MainActor static func transitionConfig(_ v: KV?) -> ScrollTransitionConfiguration {
        guard case .native(.implicit(let n, _))? = v else { return .interactive }
        if n.hasPrefix("animated") { return .animated }
        if n.hasPrefix("identity") { return .identity }
        return .interactive
    }

    // MARK: Events

    static func scrollEvents(_ r: KRegistry) {
        if #available(iOS 18.0, macOS 15.0, *) { scrollGeometryType(r) }
        scrollEventModifiers(r)
    }

    @available(iOS 18.0, macOS 15.0, *)
    static func scrollGeometryType(_ r: KRegistry) {
        r.type("ScrollGeometry", .layout, support: .full) { t in
            t.internal()
            @MainActor func g(_ c: KCall) -> ScrollGeometry? {   // nil when only checked: zeros
                if case .native(.object(_, let ref)) = c.receiver { return (ref.value as? KScrollGeometryBox)?.geometry }
                return nil
            }
            t.property("contentOffset") { c in let p = g(c)?.contentOffset ?? .zero; return .native(.point(p.x, p.y)) }
            t.property("contentSize") { c in let s = g(c)?.contentSize ?? .zero; return .native(.size(s.width, s.height)) }
            t.property("containerSize") { c in let s = g(c)?.containerSize ?? .zero; return .native(.size(s.width, s.height)) }
            t.property("visibleRect") { c in KLayout.rect(g(c)?.visibleRect ?? .zero) }
            t.property("bounds") { c in KLayout.rect(g(c)?.bounds ?? .zero) }
            t.property("contentInsets") { c in KLayout.insets(g(c)?.contentInsets ?? EdgeInsets()) }
        }
    }

    static func scrollEventModifiers(_ r: KRegistry) {
        r.modifier("onScrollGeometryChange", .layout, introduced: "18.0", notes: "`of:` reads `contentOffset`, `contentSize`, `containerSize`, `visibleRect` or `bounds`.") { m in
            m.forms(["for:any of:closure action:closure", "for:any of:closure _:closure"]) { c, view in onScrollGeometryChange(c, view) }
            m.probe { label, _ in label == "action" ? [.double(0), .double(0)] : [.native(.object("ScrollGeometry", KRef(NSObject())))] }
        }
        r.modifier("onScrollPhaseChange", .layout, introduced: "18.0", notes: "`old` and `new` are `.idle`, `.tracking`, `.interacting`, `.decelerating` or `.animating`; `isScrolling`.") { m in
            m.form("_:closure") { c, view in
                if #available(iOS 18.0, macOS 15.0, *), case .function(let f)? = c[0] {
                    let interp = c.interp
                    AnyView(view.onScrollPhaseChange { old, new in interp.perform(f, [phaseName(old), phaseName(new)]) })
                } else { view }
            }
            m.probe { _, _ in [.native(.implicit("idle", [])), .native(.implicit("tracking", []))] }
        }
        r.modifier("onScrollVisibilityChange", .layout, introduced: "18.0") { m in
            m.form("threshold:number? _:closure") { c, view in
                if #available(iOS 18.0, macOS 15.0, *), case .function(let f)? = c.last {
                    let interp = c.interp
                    AnyView(view.onScrollVisibilityChange(threshold: c.double("threshold") ?? 0.5) { visible in interp.perform(f, [.bool(visible)]) })
                } else { view }
            }
            m.probe { _, _ in [.bool(true)] }
        }
        r.modifier("onScrollTargetVisibilityChange", .layout, introduced: "18.0", notes: "The ids of the views of the `.scrollTargetLayout()` on screen.") { m in
            m.form("idType:any threshold:number? _:closure") { c, view in
                if #available(iOS 18.0, macOS 15.0, *), case .function(let f)? = c.last {
                    let interp = c.interp
                    AnyView(view.onScrollTargetVisibilityChange(idType: KV.self, threshold: c.double("threshold") ?? 0.5) { ids in interp.perform(f, [.array(ids)]) })
                } else { view }
            }
            m.probe { _, _ in [.array([])] }
        }
    }

    @available(iOS 18.0, macOS 15.0, *)
    @MainActor static func phaseName(_ p: ScrollPhase) -> KV {
        switch p {
        case .idle: return .native(.implicit("idle", []))
        case .tracking: return .native(.implicit("tracking", []))
        case .interacting: return .native(.implicit("interacting", []))
        case .decelerating: return .native(.implicit("decelerating", []))
        case .animating: return .native(.implicit("animating", []))
        @unknown default: return .native(.implicit("idle", []))
        }
    }

    @MainActor static func onScrollGeometryChange(_ c: KCall, _ view: AnyView) -> AnyView {
        guard #available(iOS 18.0, macOS 15.0, *), case .function(let transform)? = c["of"], case .function(let action)? = c.last else { return view }
        let interp = c.interp
        let n = c.r.closureParamCount(.function(action))
        return AnyView(view.onScrollGeometryChange(for: KEquatable.self, of: { geo in
            MainActor.assumeIsolated {
                KEquatable((try? interp.entry { try interp.call(transform, [.native(.object("ScrollGeometry", KRef(KScrollGeometryBox(geo))))], [nil]) }) ?? .nilValue)
            }
        }, action: { old, new in
            interp.perform(action, n >= 2 ? [old.value, new.value] : [new.value])
        }))
    }
}

@available(iOS 18.0, macOS 15.0, *)
final class KScrollGeometryBox {
    let geometry: ScrollGeometry
    init(_ geometry: ScrollGeometry) { self.geometry = geometry }
}
