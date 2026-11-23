//
//  Core.swift
//  Bridges: the app and view protocols, lifecycle, and symbolic values
//
//  `Group`, `EmptyView`, `AnyView`, `TimelineView`; `onAppear`, `.task`,
//  `onChange`, `onReceive`, `.id` and `.modifier`; the protocols an app's
//  types adopt; `Binding`; and the symbolic values (`.leading`, `.segmented`)
//  that SwiftUI types read when they're shown.
//

import SwiftUI

@objc(KilnBridges_Core)
final class CoreBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        views(r)
        lifecycle(r)
        protocols(r)
        representables(r)
        values(r)
    }

    // MARK: Views

    static func views(_ r: KRegistry) {
        r.view("Group", .core) { v in
            v.form("content:content") { c in Group { c.content() } }
            // `Group(subviews: content) { subviews in … }` (Layout/Subviews.swift).
            v.forms(["subviews:any transform:content", "sections:any transform:content"]) { c in LayoutBridges.groupSubviews(c) }
        }
        r.view("EmptyView", .core) { v in
            v.form("") { _ in EmptyView() }
        }
        r.view("AnyView", .core) { v in
            v.form("_:any") { c in c.r.renderList(KBuiltins.asViews(c[0] ?? .void, c.interp)) }
        }
        r.view("TimelineView", .core, support: .partial, notes: "`.periodic(from:by:)` and `.everyMinute`; the closure gets `context.date`.") { v in
            v.form("_:any content:content") { c in
                let fn = c.contentValue(nil)
                let interval: Double = {
                    if case .native(.implicit(_, let pa))? = c[0], let by = pa.last?.asDouble { return by }
                    return 1
                }()
                TimelineView(.periodic(from: .now, by: interval)) { ctx in
                    c.r.renderContent(fn, [.tuple([.native(.date(ctx.date))], ["date"])])
                }
            }
        }
    }

    // MARK: Lifecycle

    static func lifecycle(_ r: KRegistry) {
        r.modifier("onAppear", .core) { m in
            m.form("perform:action?") { c, view in view.onAppear(perform: c.action("perform")) }
        }
        r.modifier("onDisappear", .core) { m in
            m.form("perform:action?") { c, view in view.onDisappear(perform: c.action("perform")) }
        }
        r.modifier("task", .core, notes: "Cancelled when the view goes away, and restarted when `id` changes.") { m in
            m.forms(["priority:any? _:action", "id:any priority:any? _:action"]) { c, view in
                if case .function(let fn)? = c.last {
                    let interp = c.interp
                    if let id = c["id"] {
                        view.task(id: id) { await interp.runViewTask(fn) }
                    } else {
                        view.task { await interp.runViewTask(fn) }
                    }
                } else {
                    view
                }
            }
            m.closuresCanWait()
        }
        r.modifier("onChange", .core) { m in
            m.form("of:any initial:bool? _:action") { c, view in
                if case .function(let fn)? = c.last {
                    let interp = c.interp
                    let n = c.r.closureParamCount(.function(fn))
                    view.onChange(of: c["of"] ?? .void, initial: c.bool("initial", default: false)) { old, new in
                        interp.perform(fn, n == 0 ? [] : (n == 1 ? [new] : [old, new]))
                    }
                } else {
                    view
                }
            }
            // `onChange(of:perform:)`, deprecated but common.
            m.form("of:any perform:action") { c, view in
                if case .function(let fn)? = c.last {
                    let interp = c.interp
                    let n = c.r.closureParamCount(.function(fn))
                    view.onChange(of: c["of"] ?? .void) { old, new in
                        interp.perform(fn, n == 0 ? [] : (n == 1 ? [new] : [old, new]))
                    }
                } else {
                    view
                }
            }
        }
        r.modifier("onReceive", .core, support: .partial, notes: "Timer publishers only: `Timer.publish(every:on:in:).autoconnect()`.") { m in
            m.form("_:any perform:action") { c, view in
                if case .function(let fn)? = c.last, case .native(.publisher(let interval))? = c[0] {
                    let interp = c.interp
                    KTimerReceiver(interval: interval, action: { interp.perform(fn, [.native(.date(Date()))]) }, content: view)
                } else {
                    view
                }
            }
        }
        r.modifier("id", .core) { m in
            m.form("_:any") { c, view in view.id(c[0] ?? .nilValue) }
        }
        r.modifier("modifier", .core, notes: "Your own `ViewModifier` structs: `body(content:)` runs with the view, with its own `@State`; an `Animatable` one animates.") { m in
            m.form("_:any") { c, view in
                if let proxy = c.interp.proxy(for: c[0] ?? .void, as: "ViewModifier") as? KModifierProxy {
                    view.modifier(proxy)
                } else {
                    view
                }
            }
        }
        // SwiftUI's own content, handed to the app's `body(content:)` (KNativeContent).
        r.view("NativeContent", .core) { v in
            v.engineOnly()
            v.form("_:any") { c in
                if case .native(.object(_, let ref))? = c[0], let box = ref.value as? KAnyViewBox { box.view } else { EmptyView() }
            }
        }
    }

    // MARK: Protocols

    static func protocols(_ r: KRegistry) {
        r.protocolBridge("View", .core, requirements: ["body"], support: .full, notes: "Each of your views is hosted by a real SwiftUI view that owns its `@State`.")
        r.protocolBridge("App", .core, requirements: ["body"], support: .partial, notes: "Kiln shows its `WindowGroup`'s content.")
        r.protocolBridge("ViewModifier", .core, requirements: ["body(content:)"], support: .full,
                         notes: "`.modifier(Card())`, or `modifier(Card())` in your `extension View`; it can have `@State`.") { app in
            KModifierProxy(app: app)
        }
        r.protocolBridge("PreviewProvider", .core, requirements: ["static previews"])
        r.protocolBridge("Shape", .drawing, requirements: ["path(in:)"], support: .full)
        r.protocolBridge("InsettableShape", .drawing, requirements: ["path(in:)", "inset(by:)"])
        r.protocolBridge("Identifiable", .language, requirements: ["id"], notes: "`id` is read by `ForEach` and `List`, which need it (or `id:`).")
        r.protocolBridge("Hashable", .language, notes: "Synthesized from stored properties, or your own `hash(into:)`.")
        r.protocolBridge("Equatable", .language, notes: "Synthesized from stored properties, or your own `==`; `==` needs it.")
        r.protocolBridge("Comparable", .language, requirements: ["<"], notes: "`<`, `sorted()`, `min()` and `max()` on your types need it.")
        r.protocolBridge("CaseIterable", .language, requirements: ["allCases"], notes: "Synthesized for enums without payloads; `allCases` needs it.")
        r.protocolBridge("Codable", .foundation, notes: "Stored properties with `CodingKeys`, or your own `init(from:)` and `encode(to:)`.")
        r.protocolBridge("Decodable", .foundation)
        r.protocolBridge("Encodable", .foundation)
        r.protocolBridge("Error", .language)
        r.protocolBridge("LocalizedError", .foundation, requirements: ["errorDescription?"])
        r.protocolBridge("CustomStringConvertible", .language, requirements: ["description"])
        r.protocolBridge("ObservableObject", .environment, support: .full, notes: "`@Published` and plain properties both refresh the views that read them.")
    }

    // MARK: Values

    static func values(_ r: KRegistry) {
        // `.segmented`, `.leading`, `.degrees(90)` before the view reading it decides what it is.
        r.type("ImplicitMember", .core) { t in
            t.internal()
            @MainActor func chainBase(_ c: KCall, _ base: String, _ args: [KV]) -> KNative? {
                let expected = KDrawing.colorNames[base] != nil ? "Color" : (KTextBridges.fontStyles[base] != nil ? "Font" : nil)
                if let resolved = c.interp.resolveImplicit(base, args, expectedType: expected), case .native(let r) = resolved,
                   case .native(let n) = c.receiver, r != n { return r }
                return nil
            }
            // A chain on a symbolic value: `.white.opacity`, `.title2.bold`, `.number.precision`.
            t.anyProperty { c, name in
                guard case .native(.implicit(let base, let args)) = c.receiver else { return nil }
                if let p = c.interp.registry.implicitProperties[name], let v = p(base, args) { return v }
                if let r = chainBase(c, base, args) { return try c.interp.nativeMember(.native(r), name, c.line) }
                return .native(.implicit(base + "." + name, args))
            }
            t.anyMethod { c, name in
                guard case .native(.implicit(let base, let args)) = c.receiver else { return nil }
                if let r = chainBase(c, base, args) {
                    return try c.interp.nativeMethodValues(.native(r), name, c.args, c.labels, c.line)
                }
                return .native(.implicit(base + "." + name, c.args))
            }
            // `.degrees(…)` stored, then called.
            t.method("callAsFunction") { c in
                guard case .native(.implicit(let name, _)) = c.receiver else { return .nilValue }
                return c.interp.resolveImplicit(name, c.args, expectedType: nil, labels: c.labels) ?? .native(.implicit(name, c.args))
            }
        }

        r.type("Binding", .environment, notes: "`Binding(get:set:)`, `.constant(_:)` and `.animation(_:)`.") { t in
            t.initializer { c in
                if case .function(let g)? = c.arg("get"), case .function(let s)? = c.arg("set") {
                    let interp = c.interp
                    return .binding(KBinding(get: { (try? interp.call(g, [], [])) ?? .nilValue },
                                             set: { v in _ = try? interp.call(s, [v], [nil]) }))
                }
                return .binding(.constant(c.first ?? .nilValue))
            }
            t.staticMethod("constant") { c in .binding(.constant(c.first ?? .nilValue)) }
            // `Toggle("On", isOn: $on.animation())`: writes through it animate.
            t.method("animation", "_:Animation?") { c in
                guard case .binding(let b) = c.receiver else { return c.receiver }
                var anim: Animation? = .default
                if case .native(.animation(let a))? = c.first { anim = a.value }
                else if case .native(.implicit(let n, let a))? = c.first { anim = KDrawing.animation(n, a, []) ?? .default }
                return .binding(KBinding(get: b.get, set: { v in withAnimation(anim) { b.set(v) } }))
            }
            t.implicit { name, args, _ in name == "constant" ? .binding(.constant(args.first ?? .void)) : nil }
        }
    }
}

extension KInterpreter {
    /// A method of a native value, with evaluated arguments.
    func nativeMethodValues(_ base: KV, _ name: String, _ args: [KV], _ labels: [String?], _ line: Int) throws -> KV {
        try nativeMethod(base, name, args.map { KEArg(label: nil, value: .value($0)) }.enumerated().map { i, a in
            KEArg(label: labels[i], value: a.value)
        }, KEnv(parent: globalEnv), line).0
    }
}
