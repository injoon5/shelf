//
//  Gestures.swift
//  Bridges: gestures, taps and long presses, hover and hit testing
//
//  A gesture is a description while the app's code runs, as a view is:
//  `DragGesture(minimumDistance: 0).onChanged { … }.onEnded { … }` is a
//  `DragGesture` primitive with two modifiers. `.gesture(_:)` and its kin
//  build the real SwiftUI gesture from it (`KGestureBuilder`), every one an
//  `AnyGesture<KV>`: each kind's value is mapped to Kiln's at its source, so
//  `onChanged`, `updating`, `simultaneously(with:)` and the rest compose
//  whatever the kinds.
//
//  `@GestureState` is the app's property; a real `GestureState` in the view
//  that attaches the gesture tells it when the gesture ends or is cancelled,
//  and then each property an `updating` wrote goes back to its initial value.
//
//  Shelf's close gestures (up from the bottom edge, down from the status
//  bar) are UIKit recognizers on the stage, which the app's recognizers wait
//  on (`shouldBeRequiredToFailBy`): a drag that starts there closes the
//  card, and one that starts anywhere else is the app's.
//

import SwiftUI

/// What `$offset` carries when `offset` is a `@GestureState`: its initial value.
struct KGestureStateReset {
    let initial: KV
}

@objc(KilnBridges_Gestures)
final class GesturesBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        gestures(r)
        values(r)
        composition(r)
        attaching(r)
        conveniences(r)
        hover(r)
    }

    // MARK: Gesture kinds

    static func gestures(_ r: KRegistry) {
        let kinds: [(String, [String], String?)] = [
            ("TapGesture", ["count:number?"], nil),
            ("SpatialTapGesture", ["count:number? coordinateSpace:any?"], "Its value has `location`."),
            ("LongPressGesture", ["minimumDuration:number? maximumDistance:number?"], nil),
            ("DragGesture", ["minimumDistance:number? coordinateSpace:any?"], nil),
            ("MagnifyGesture", ["minimumScaleDelta:number?"], nil),
            ("RotateGesture", ["minimumAngleDelta:Angle?"], nil),
            ("MagnificationGesture", ["minimumScaleDelta:number?"], nil),
            ("RotationGesture", ["minimumAngleDelta:Angle?"], nil),
            ("SpatialEventGesture", ["coordinateSpace:any?"], "Each touch in `events`: `id`, `location`, `phase` and `kind`."),
            ("AnyGesture", ["_:any"], nil),
            ("SimultaneousGesture", ["_:any _:any"], nil),
            ("SequenceGesture", ["_:any _:any"], nil),
            ("ExclusiveGesture", ["_:any _:any"], nil),
        ]
        for (name, sigs, notes) in kinds {
            r.view(name, .gestures, notes: notes) { v in
                v.manifestKind = "gesture"
                // Shown by `.gesture(_:)`, never as a view.
                v.forms(sigs) { _ in EmptyView() }
            }
        }
        r.protocolBridge("Gesture", .gestures, requirements: ["body"], support: .full,
                         notes: "Your own gesture: `var body: some Gesture` built from the others.")
    }

    // MARK: Gesture values

    static func values(_ r: KRegistry) {
        @MainActor func point(_ x: Double, _ y: Double) -> KV { .native(.point(x, y)) }
        r.type("DragGesture.Value", .gestures, support: .full) { t in
            t.internal()
            @MainActor func v(_ c: KCall) -> KDragValue { (c.receiver.boxed(KDragValue.self)) ?? KDragValue() }
            t.property("time") { c in .native(.date(v(c).time)) }
            t.property("location") { c in point(v(c).location.0, v(c).location.1) }
            t.property("startLocation") { c in point(v(c).start.0, v(c).start.1) }
            t.property("translation") { c in .native(.size(v(c).translation.0, v(c).translation.1)) }
            t.property("velocity") { c in .native(.size(v(c).velocity.0, v(c).velocity.1)) }
            t.property("predictedEndLocation") { c in point(v(c).predictedEnd.0, v(c).predictedEnd.1) }
            t.property("predictedEndTranslation") { c in .native(.size(v(c).predictedTranslation.0, v(c).predictedTranslation.1)) }
        }
        r.type("MagnifyGesture.Value", .gestures, support: .full) { t in
            t.internal()
            @MainActor func v(_ c: KCall) -> KScaleValue { (c.receiver.boxed(KScaleValue.self)) ?? KScaleValue() }
            t.property("time") { c in .native(.date(v(c).time)) }
            t.property("magnification") { c in .double(v(c).magnification) }
            t.property("velocity") { c in .double(v(c).velocity) }
            t.property("startAnchor") { c in .native(.implicit("unitPoint", [.double(v(c).anchor.0), .double(v(c).anchor.1)])) }
            t.property("startLocation") { c in point(v(c).start.0, v(c).start.1) }
        }
        r.type("RotateGesture.Value", .gestures, support: .full) { t in
            t.internal()
            @MainActor func v(_ c: KCall) -> KScaleValue { (c.receiver.boxed(KScaleValue.self)) ?? KScaleValue() }
            t.property("time") { c in .native(.date(v(c).time)) }
            t.property("rotation") { c in .native(.angle(v(c).magnification)) }
            t.property("velocity") { c in .native(.angle(v(c).velocity)) }
            t.property("startAnchor") { c in .native(.implicit("unitPoint", [.double(v(c).anchor.0), .double(v(c).anchor.1)])) }
            t.property("startLocation") { c in point(v(c).start.0, v(c).start.1) }
        }
        r.type("SpatialTapGesture.Value", .gestures, support: .full) { t in
            t.internal()
            t.property("location") { c in
                let p = c.receiver.boxed(KDragValue.self)?.location ?? (0, 0)
                return point(p.0, p.1)
            }
        }
        r.type("SpatialEventCollection.Event", .gestures, support: .full) { t in
            t.internal()
            @MainActor func v(_ c: KCall) -> KTouchValue { (c.receiver.boxed(KTouchValue.self)) ?? KTouchValue() }
            t.property("id") { c in .int(v(c).id) }
            t.property("location") { c in point(v(c).location.0, v(c).location.1) }
            t.property("phase") { c in .native(.implicit(v(c).phase, [])) }
            t.property("kind") { c in .native(.implicit(v(c).kind, [])) }
            t.property("timestamp") { c in .double(v(c).timestamp) }
        }
        r.type("Transaction", .drawing, support: .partial,
               notes: "`animation` and `disablesAnimations`, in `.transaction { }`, `withTransaction` and a gesture's `updating`.") { t in
            t.initializer("") { _ in .native(.object("Transaction", KRef(KTransactionBox(Transaction())))) }
            t.initializer("animation:Animation?") { c in
                .native(.object("Transaction", KRef(KTransactionBox(Transaction(animation: c.animation("animation"))))))
            }
            t.property("animation", { c in
                guard let box = c.object(KTransactionBox.self), let a = box.transaction.animation else { return .nilValue }
                return .native(.animation(KRef(a)))
            }, set: { c in c.object(KTransactionBox.self)?.transaction.animation = c.animation(0) })
            t.property("disablesAnimations", { c in .bool(c.object(KTransactionBox.self)?.transaction.disablesAnimations ?? false) },
                       set: { c in c.object(KTransactionBox.self)?.transaction.disablesAnimations = c.bool(0, default: false) })
            t.property("isContinuous") { c in .bool(c.object(KTransactionBox.self)?.transaction.isContinuous ?? false) }
        }
        r.function("withTransaction", .drawing, "_:any _:closure", owner: "SwiftUI") { c in
            guard let box = (c.args.first.flatMap { if case .native(.object(_, let ref)) = $0 { return ref.value as? KTransactionBox }; return nil }),
                  case .function(let body)? = c.last else { return .void }
            var result: KV = .void
            var thrown: Error?
            withTransaction(box.transaction) {
                do { result = try c.interp.call(body, [], []) } catch { thrown = error }
            }
            if let thrown { throw thrown }
            return result
        }
    }

    // MARK: On gestures

    static func composition(_ r: KRegistry) {
        let forms: [(String, String, String?)] = [
            ("onChanged", "_:closure", nil),
            ("onEnded", "_:closure", nil),
            ("updating", "_:binding body:closure", "Resets the `@GestureState` when the gesture ends or is cancelled."),
            ("map", "_:closure", nil),
            ("simultaneously", "with:any", nil),
            ("sequenced", "before:any", nil),
            ("exclusively", "before:any", nil),
        ]
        for (name, sig, notes) in forms {
            r.modifier(name, .gestures, notes: notes) { m in
                m.owner = "Gesture"
                m.form(sig, receiver: "Gesture") { _, view in view }
                // A check fires each with a value of the gesture's kind.
                m.probe { base, a, interp in
                    guard case .function(let fn)? = a.lastFunction else { return [] }
                    let sample = KGestureBuilder.sample(base, interp)
                    let wants = KRenderer(interp: interp).closureParamCount(.function(fn)) > 0
                    if name == "updating" {
                        guard case .binding(let state)? = a.first else { return [] }
                        let tx = KV.native(.object("Transaction", KRef(KTransactionBox(Transaction()))))
                        return [KProbeCall(fn: fn, args: [sample, .binding(.inOut(get: state.get, set: state.set)), .binding(.inOut(get: { tx }, set: { _ in }))],
                                           use: .action)]
                    }
                    return [KProbeCall(fn: fn, args: wants ? [sample] : [], use: .action)]
                }
            }
        }
    }

    // MARK: Attaching

    static func attaching(_ r: KRegistry) {
        for (name, priority) in [("gesture", KGesturePriority.normal), ("simultaneousGesture", .simultaneous), ("highPriorityGesture", .high)] {
            r.modifier(name, .gestures, notes: name == "gesture" ? "Any gesture, composed or your own; Shelf's close gestures win at the screen's edges." : nil) { m in
                m.form("_:any including:GestureMask?") { c, view in
                    KGestureAttach(content: view, gesture: c[0] ?? .void, priority: priority, mask: mask(c.symbol("including")), enabled: true, interp: c.interp)
                }
                m.form("_:any isEnabled:bool") { c, view in
                    KGestureAttach(content: view, gesture: c[0] ?? .void, priority: priority, mask: .all, enabled: c.bool("isEnabled", default: true), interp: c.interp)
                }
                m.form("_:any name:string isEnabled:bool?") { c, view in
                    KGestureAttach(content: view, gesture: c[0] ?? .void, priority: priority, mask: .all, enabled: c.bool("isEnabled", default: true), interp: c.interp)
                }
            }
        }
        r.modifier("allowsHitTesting", .gestures) { m in
            m.form("_:bool") { c, view in view.allowsHitTesting(c.bool(0, default: true)) }
        }
        r.modifier("contentShape", .gestures) { m in
            m.forms(["_:any eoFill:bool?", "_:any _:any eoFill:bool?"]) { c, view in
                if let shape = DrawingBridges.shapeArg(c.labels.count > 1 && (c.labels[1] ?? nil) == nil ? c[1] : c[0], c.r) {
                    view.contentShape(shape)
                } else {
                    view.contentShape(Rectangle())
                }
            }
        }
        r.modifier("defersSystemGestures", .gestures, support: .partial,
                   notes: "iOS's own edge gestures wait; Shelf's close gestures (up from the bottom, down from the top) still close the app.") { m in
            m.form("on:Edge.Set") { c, view in
                #if os(iOS)
                view.defersSystemGestures(on: c.edges("on"))
                #else
                view
                #endif
            }
        }
    }

    @MainActor static func mask(_ name: String?) -> GestureMask {
        switch name {
        case "gesture": return .gesture
        case "subviews": return .subviews
        case "none": return []
        default: return .all
        }
    }

    // MARK: Taps and long presses

    static func conveniences(_ r: KRegistry) {
        r.modifier("onTapGesture", .gestures, notes: "With a `CGPoint` parameter, the tap's location.") { m in
            m.forms(["count:number? perform:action", "count:number? coordinateSpace:any? perform:action"]) { c, view in
                tap(c, view)
            }
            m.probe { _, a, interp in
                guard case .function(let fn)? = a["perform"] ?? a.lastFunction else { return [] }
                let wants = KRenderer(interp: interp).closureParamCount(.function(fn)) > 0
                return [KProbeCall(fn: fn, args: wants ? [.native(.point(0, 0))] : [], use: .action)]
            }
        }
        r.modifier("onLongPressGesture", .gestures) { m in
            m.forms(["minimumDuration:number? maximumDistance:number? perform:action onPressingChanged:closure?",
                     "minimumDuration:number? maximumDistance:number? pressing:closure? perform:action",
                     "minimumDuration:number? perform:action onPressingChanged:closure?"]) { c, view in
                let interp = c.interp
                let pressing = c.function("onPressingChanged") ?? c.function("pressing")
                view.onLongPressGesture(minimumDuration: c.double("minimumDuration") ?? 0.5, maximumDistance: c.cg("maximumDistance") ?? 10,
                                        perform: c.action("perform"),
                                        onPressingChanged: { pressing.map { f in { interp.perform(f, [.bool($0)]) } }?($0) })
            }
            m.probe { _, a, _ in
                var calls: [KProbeCall] = []
                if case .function(let f)? = a["onPressingChanged"] ?? a["pressing"] { calls.append(KProbeCall(fn: f, args: [.bool(true)], use: .action)) }
                if case .function(let f)? = a["perform"] { calls.append(KProbeCall(fn: f, use: .action)) }
                return calls
            }
        }
    }

    @MainActor static func tap(_ c: KCall, _ view: AnyView) -> AnyView {
        let count = c.int("count") ?? 1
        guard case .function(let fn)? = c["perform"] else { return view }
        let interp = c.interp
        if c.r.closureParamCount(.function(fn)) == 0 {
            return AnyView(view.onTapGesture(count: count) { interp.perform(fn) })
        }
        return AnyView(view.onTapGesture(count: count, coordinateSpace: coordinateSpace(c["coordinateSpace"], c.r)) { p in
            interp.perform(fn, [.native(.point(p.x, p.y))])
        })
    }

    @MainActor static func coordinateSpace(_ v: KV?, _ r: KRenderer) -> CoordinateSpace {
        switch v {
        case .native(.implicit("global", _))?: return .global
        case .native(.implicit("named", let a))?: return .named(r.string(a.first).map { AnyHashable($0) } ?? AnyHashable(""))
        default: return .local
        }
    }

    // MARK: Hover, pencil, hinge

    static func hover(_ r: KRegistry) {
        r.modifier("onHover", .gestures, notes: "A pointer over the view (a trackpad or mouse with an iPad); never on an iPhone.") { m in
            m.form("perform:action") { c, view in
                let interp = c.interp
                if case .function(let fn)? = c["perform"] { AnyView(view.onHover { interp.perform(fn, [.bool($0)]) }) } else { view }
            }
        }
        r.modifier("onContinuousHover", .gestures) { m in
            m.form("coordinateSpace:any? perform:action") { c, view in
                let interp = c.interp
                if case .function(let fn)? = c["perform"] {
                    AnyView(view.onContinuousHover(coordinateSpace: coordinateSpace(c["coordinateSpace"], c.r)) { phase in
                        switch phase {
                        case .active(let p): interp.perform(fn, [.native(.implicit("active", [.native(.point(p.x, p.y))]))])
                        case .ended: interp.perform(fn, [.native(.implicit("ended", []))])
                        }
                    })
                } else {
                    view
                }
            }
        }
        r.modifier("hoverEffect", .gestures) { m in
            m.form("_:any? isEnabled:bool?") { c, view in
                #if os(iOS)
                let effect: HoverEffect = c.symbol(0) == "highlight" ? .highlight : (c.symbol(0) == "lift" ? .lift : .automatic)
                view.hoverEffect(effect, isEnabled: c.bool("isEnabled", default: true))
                #else
                view
                #endif
            }
        }
        r.modifier("hoverEffectDisabled", .gestures) { m in
            m.form("_:bool?") { c, view in
                #if os(iOS)
                view.hoverEffectDisabled(c.bool(0, default: true))
                #else
                view
                #endif
            }
        }
        r.modifier("defaultHoverEffect", .gestures) { m in
            m.form("_:any?") { c, view in
                #if os(iOS)
                if c.symbol(0) == nil { AnyView(view.defaultHoverEffect(nil)) }
                else { AnyView(view.defaultHoverEffect(c.symbol(0) == "highlight" ? .highlight : (c.symbol(0) == "lift" ? .lift : .automatic))) }
                #else
                view
                #endif
            }
        }
        r.modifier("handGestureShortcut", .gestures, introduced: "18.0", notes: "Apple Watch's double tap; on an iPhone, nothing.") { m in
            m.form("_:any isEnabled:bool?") { c, view in
                #if os(iOS)
                if #available(iOS 18, *) { AnyView(view.handGestureShortcut(.primaryAction, isEnabled: c.bool("isEnabled", default: true))) } else { view }
                #else
                view
                #endif
            }
        }
        r.modifier("onHingeChange", .gestures, introduced: "27.1", notes: "A foldable device's hinge; each context has `hinge`, nil when there's none.") { m in
            m.form("isEnabled:bool? _:closure") { c, view in
                #if os(iOS)
                if #available(iOS 27.1, *), case .function(let fn)? = c.a.lastFunction {
                    let interp = c.interp
                    AnyView(view.onHingeChange(isEnabled: c.bool("isEnabled", default: true)) { old, new in
                        func kv(_ ctx: DeviceHingeContext) -> KV { .tuple([ctx.hinge.map { .string(String(describing: $0)) } ?? .nilValue], ["hinge"]) }
                        interp.perform(fn, [kv(old), kv(new)])
                    })
                } else {
                    view
                }
                #else
                view
                #endif
            }
            m.probe { _, a, _ in
                guard case .function(let fn)? = a.lastFunction else { return [] }
                let none = KV.tuple([.nilValue], ["hinge"])
                return [KProbeCall(fn: fn, args: [none, none], use: .action)]
            }
        }
        r.modifier("onPencilDoubleTap", .gestures, notes: "An Apple Pencil's double tap, on an iPad.") { m in
            m.form("perform:action") { c, view in
                #if os(iOS)
                let interp = c.interp
                if case .function(let fn)? = c["perform"] {
                    AnyView(view.onPencilDoubleTap { value in
                        let hover = value.hoverPose.map { KV.native(.point($0.location.x, $0.location.y)) } ?? .nilValue
                        interp.perform(fn, [.tuple([hover], ["hoverPose"])])
                    })
                } else {
                    view
                }
                #else
                view
                #endif
            }
        }
        r.modifier("onPencilSqueeze", .gestures, notes: "An Apple Pencil Pro's squeeze, on an iPad: `.active` then `.ended`.") { m in
            m.form("perform:action") { c, view in
                #if os(iOS)
                let interp = c.interp
                if case .function(let fn)? = c["perform"] {
                    AnyView(view.onPencilSqueeze { phase in
                        switch phase {
                        case .active: interp.perform(fn, [.native(.implicit("active", []))])
                        case .ended: interp.perform(fn, [.native(.implicit("ended", []))])
                        case .failed: interp.perform(fn, [.native(.implicit("failed", []))])
                        @unknown default: break
                        }
                    })
                } else {
                    view
                }
                #else
                view
                #endif
            }
        }
    }
}

// MARK: - Values

/// `DragGesture.Value` (and a spatial tap's `location`), compared by value.
struct KDragValue: Hashable {
    var time = Date()
    var location: (Double, Double) = (0, 0)
    var start: (Double, Double) = (0, 0)
    var translation: (Double, Double) = (0, 0)
    var velocity: (Double, Double) = (0, 0)
    var predictedEnd: (Double, Double) = (0, 0)
    var predictedTranslation: (Double, Double) = (0, 0)

    init() {}
    init(_ v: DragGesture.Value) {
        time = v.time
        location = (v.location.x, v.location.y)
        start = (v.startLocation.x, v.startLocation.y)
        translation = (v.translation.width, v.translation.height)
        velocity = (v.velocity.width, v.velocity.height)
        predictedEnd = (v.predictedEndLocation.x, v.predictedEndLocation.y)
        predictedTranslation = (v.predictedEndTranslation.width, v.predictedEndTranslation.height)
    }

    static func == (a: KDragValue, b: KDragValue) -> Bool {
        a.time == b.time && a.location == b.location && a.translation == b.translation && a.start == b.start
    }
    func hash(into h: inout Hasher) {
        h.combine(time); h.combine(location.0); h.combine(location.1); h.combine(translation.0); h.combine(translation.1)
    }
}

/// `MagnifyGesture.Value` and `RotateGesture.Value` (degrees).
struct KScaleValue: Hashable {
    var time = Date()
    var magnification = 1.0
    var velocity = 0.0
    var anchor: (Double, Double) = (0.5, 0.5)
    var start: (Double, Double) = (0, 0)

    static func == (a: KScaleValue, b: KScaleValue) -> Bool {
        a.time == b.time && a.magnification == b.magnification && a.start == b.start
    }
    func hash(into h: inout Hasher) { h.combine(time); h.combine(magnification) }
}

/// One touch of a `SpatialEventGesture`.
struct KTouchValue: Hashable {
    var id = 0
    var location: (Double, Double) = (0, 0)
    var phase = "active"
    var kind = "touch"
    var timestamp = 0.0

    static func == (a: KTouchValue, b: KTouchValue) -> Bool {
        a.id == b.id && a.location == b.location && a.phase == b.phase && a.timestamp == b.timestamp
    }
    func hash(into h: inout Hasher) { h.combine(id); h.combine(location.0); h.combine(location.1); h.combine(phase) }
}

/// A `Transaction` the app's code reads and writes.
final class KTransactionBox: NSObject {
    var transaction: Transaction
    init(_ t: Transaction) { transaction = t }
}

extension KV {
    /// A boxed native value of `T` (`KBoxed`).
    func boxed<T>(_: T.Type) -> T? {
        if case .native(.boxed(let b)) = self { return b.get(T.self) }
        return nil
    }
}

// MARK: - Building the real gesture

enum KGesturePriority { case normal, simultaneous, high }

/// The `@GestureState` properties a gesture's `updating` wrote, reset when it ends.
@MainActor
final class KGestureResets {
    var entries: [(KBinding, KV)] = []
    func reset() {
        for (b, initial) in entries { b.set(initial) }
    }
}

/// Builds a real gesture from its description.
@MainActor
struct KGestureBuilder {
    let interp: KInterpreter
    /// The attaching view's own `GestureState`, which `updating` drives.
    let active: GestureState<Bool>
    let resets: KGestureResets

    func build(_ v: KV, depth: Int = 0) -> AnyGesture<KV>? {
        guard depth < 32 else { return nil }
        switch v {
        case .view(let view): return build(view, depth: depth)
        case .structV(let s) where s.type.conformances.contains("Gesture"):
            // The app's own `Gesture`: its `body`.
            guard let body = try? interp.member(v, "body", line: 0) else { return nil }
            return build(body, depth: depth + 1)
        default: return nil
        }
    }

    func build(_ view: KView, depth: Int) -> AnyGesture<KV>? {
        switch view.kind {
        case .modified(let base, let m):
            guard let g = build(base, depth: depth + 1) else { return nil }
            return apply(m, to: g, depth: depth)
        case .primitive(let name, let args, let labels, _):
            return primitive(name, KArgs(args: args, labels: labels), depth: depth)
        case .group(let vs) where vs.count == 1:
            return build(vs[0], depth: depth + 1)
        default:
            return nil
        }
    }

    func primitive(_ name: String, _ a: KArgs, depth: Int) -> AnyGesture<KV>? {
        let r = KRenderer(interp: interp)
        let space = GesturesBridges.coordinateSpace(a["coordinateSpace"], r)
        switch name {
        case "TapGesture":
            return AnyGesture(TapGesture(count: a["count"]?.asInt ?? 1).map { KV.void })
        case "SpatialTapGesture":
            return AnyGesture(SpatialTapGesture(count: a["count"]?.asInt ?? 1, coordinateSpace: space).map { v in
                var d = KDragValue()
                d.location = (v.location.x, v.location.y)
                return KV.native(.boxed(KBoxed("SpatialTapGesture.Value", d)))
            })
        case "LongPressGesture":
            return AnyGesture(LongPressGesture(minimumDuration: a["minimumDuration"]?.asDouble ?? 0.5,
                                               maximumDistance: a["maximumDistance"]?.cg ?? 10).map { KV.bool($0) })
        case "DragGesture":
            return AnyGesture(DragGesture(minimumDistance: a["minimumDistance"]?.cg ?? 10, coordinateSpace: space).map { v in
                KV.native(.boxed(KBoxed("DragGesture.Value", KDragValue(v))))
            })
        case "MagnifyGesture":
            return AnyGesture(MagnifyGesture(minimumScaleDelta: a["minimumScaleDelta"]?.cg ?? 0.01).map { v in
                KV.native(.boxed(KBoxed("MagnifyGesture.Value", KScaleValue(time: v.time, magnification: v.magnification, velocity: v.velocity,
                                                                              anchor: (v.startAnchor.x, v.startAnchor.y),
                                                                              start: (v.startLocation.x, v.startLocation.y)))))
            })
        case "RotateGesture":
            return AnyGesture(RotateGesture(minimumAngleDelta: r.angle(a["minimumAngleDelta"] ?? .native(.angle(1)))).map { v in
                KV.native(.boxed(KBoxed("RotateGesture.Value", KScaleValue(time: v.time, magnification: v.rotation.degrees, velocity: v.velocity.degrees,
                                                                             anchor: (v.startAnchor.x, v.startAnchor.y),
                                                                             start: (v.startLocation.x, v.startLocation.y)))))
            })
        case "MagnificationGesture":
            return AnyGesture(MagnifyGesture(minimumScaleDelta: a["minimumScaleDelta"]?.cg ?? 0.01).map { KV.double($0.magnification) })
        case "RotationGesture":
            return AnyGesture(RotateGesture(minimumAngleDelta: r.angle(a["minimumAngleDelta"] ?? .native(.angle(1)))).map { KV.native(.angle($0.rotation.degrees)) })
        case "SpatialEventGesture":
            if #available(iOS 18, macOS 15, *) {
                let eventSpace: any CoordinateSpaceProtocol = space == .global ? GlobalCoordinateSpace() : LocalCoordinateSpace()
                return AnyGesture(SpatialEventGesture(coordinateSpace: eventSpace).map { events in
                    KV.array(events.map { e in
                        let phase: String = switch e.phase {
                        case .active: "active"
                        case .ended: "ended"
                        case .cancelled: "cancelled"
                        @unknown default: "active"
                        }
                        let kind: String = switch e.kind {
                        case .touch: "touch"
                        case .directPinch: "directPinch"
                        case .indirectPinch: "indirectPinch"
                        case .pointer: "pointer"
                        case .pencil: "pencil"
                        @unknown default: "touch"
                        }
                        return KV.native(.boxed(KBoxed("SpatialEventCollection.Event",
                                                       KTouchValue(id: e.id.hashValue, location: (e.location.x, e.location.y), phase: phase, kind: kind,
                                                                   timestamp: e.timestamp))))
                    })
                })
            }
            return nil
        case "AnyGesture":
            return a.first.flatMap { build($0, depth: depth + 1) }
        case "SimultaneousGesture", "SequenceGesture", "ExclusiveGesture":
            guard let first = a.unlabeled(0).flatMap({ build($0, depth: depth + 1) }),
                  let second = a.unlabeled(1).flatMap({ build($0, depth: depth + 1) }) else { return nil }
            return combine(name, first, second)
        default:
            return nil
        }
    }

    /// A value like the one a gesture's closures get, for a check.
    static func sample(_ gesture: KView?, _ interp: KInterpreter) -> KV {
        guard let gesture else { return .void }
        switch gesture.kind {
        case .modified(let base, let m):
            switch m.name {
            case "simultaneously": return .tuple([sample(base, interp), sample(m.args.first.flatMap { if case .view(let v) = $0 { return v }; return nil }, interp)],
                                                 ["first", "second"])
            case "sequenced", "exclusively": return .native(.implicit("first", [sample(base, interp)]))
            case "map": return .nilValue
            default: return sample(base, interp)
            }
        case .primitive(let name, let args, let labels, _):
            switch name {
            case "TapGesture": return .void
            case "LongPressGesture": return .bool(true)
            case "DragGesture": return .native(.boxed(KBoxed("DragGesture.Value", KDragValue())))
            case "SpatialTapGesture": return .native(.boxed(KBoxed("SpatialTapGesture.Value", KDragValue())))
            case "MagnifyGesture": return .native(.boxed(KBoxed("MagnifyGesture.Value", KScaleValue())))
            case "RotateGesture": return .native(.boxed(KBoxed("RotateGesture.Value", KScaleValue(magnification: 0))))
            case "MagnificationGesture": return .double(1)
            case "RotationGesture": return .native(.angle(0))
            case "SpatialEventGesture": return .array([])
            case "AnyGesture":
                if case .view(let v)? = args.first { return sample(v, interp) }
                return .void
            default:
                let a = KArgs(args: args, labels: labels)
                let parts = [a.unlabeled(0), a.unlabeled(1)].map { v -> KV in if case .view(let g)? = v { return sample(g, interp) }; return .void }
                if name == "SimultaneousGesture" { return .tuple(parts, ["first", "second"]) }
                return .native(.implicit("first", [parts[0]]))
            }
        default:
            return .void
        }
    }

    func combine(_ kind: String, _ first: AnyGesture<KV>, _ second: AnyGesture<KV>) -> AnyGesture<KV> {
        switch kind {
        case "SequenceGesture":
            return AnyGesture(SequenceGesture(first, second).map { v in
                switch v {
                case .first(let a): return KV.native(.implicit("first", [a]))
                case .second(let a, let b): return KV.native(.implicit("second", [a, b ?? .nilValue]))
                }
            })
        case "ExclusiveGesture":
            return AnyGesture(ExclusiveGesture(first, second).map { v in
                switch v {
                case .first(let a): return KV.native(.implicit("first", [a]))
                case .second(let b): return KV.native(.implicit("second", [b]))
                }
            })
        default:
            return AnyGesture(SimultaneousGesture(first, second).map { v in
                KV.tuple([v.first ?? .nilValue, v.second ?? .nilValue], ["first", "second"])
            })
        }
    }

    func apply(_ m: KModifier, to g: AnyGesture<KV>, depth: Int) -> AnyGesture<KV> {
        let interp = self.interp
        let fn: KFunction? = m.args.last.flatMap { if case .function(let f) = $0 { return f }; return nil }
        let wantsValue = fn.map { KRenderer(interp: interp).closureParamCount(.function($0)) > 0 } ?? false
        switch m.name {
        case "onChanged":
            guard let fn else { return g }
            return AnyGesture(g.onChanged { v in interp.perform(fn, wantsValue ? [v] : []) })
        case "onEnded":
            guard let fn else { return g }
            return AnyGesture(g.onEnded { v in interp.perform(fn, wantsValue ? [v] : []) })
        case "updating":
            guard let fn, case .binding(let state)? = m.args.first else { return g }
            if let reset = state.native as? KGestureStateReset { resets.entries.append((state, reset.initial)) }
            return AnyGesture(g.updating(active) { v, isActive, transaction in
                isActive = true
                let box = KTransactionBox(transaction)
                let stateArg = KBinding.inOut(get: state.get, set: state.set)
                let txArg = KBinding.inOut(get: { .native(.object("Transaction", KRef(box))) }, set: { _ in })
                interp.perform(fn, [v, .binding(stateArg), .binding(txArg)])
                transaction = box.transaction
            })
        case "map":
            guard let fn else { return g }
            return AnyGesture(g.map { v in (try? interp.entry { try interp.call(fn, [v], [nil]) }) ?? .nilValue })
        case "simultaneously", "sequenced", "exclusively":
            guard let other = m.args.first.flatMap({ build($0, depth: depth + 1) }) else { return g }
            return combine(m.name == "simultaneously" ? "SimultaneousGesture" : (m.name == "sequenced" ? "SequenceGesture" : "ExclusiveGesture"), g, other)
        default:
            return g
        }
    }
}

/// Attaches the app's gesture. Its own `GestureState` drives every
/// `updating` in the gesture, and its reset is when the app's go back.
struct KGestureAttach: View {
    let content: AnyView
    let gesture: KV
    let priority: KGesturePriority
    let mask: GestureMask
    let enabled: Bool
    let interp: KInterpreter
    @GestureState private var active = false
    @State private var resets = KGestureResets()

    var body: some View {
        let builder = KGestureBuilder(interp: interp, active: $active, resets: resets)
        let _ = resets.entries.removeAll()
        let built = builder.build(gesture)
        if let built {
            attached(built)
                .onChange(of: active) { _, now in if !now { resets.reset() } }
        } else {
            content
        }
    }

    @ViewBuilder
    func attached(_ g: AnyGesture<KV>) -> some View {
        let mask = enabled ? self.mask : []
        switch priority {
        case .normal: content.gesture(g, including: mask)
        case .simultaneous: content.simultaneousGesture(g, including: mask)
        case .high: content.highPriorityGesture(g, including: mask)
        }
    }
}
