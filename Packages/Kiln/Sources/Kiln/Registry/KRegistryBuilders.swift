//
//  KRegistryBuilders.swift
//  Kiln's bridge registry
//
//  The short way to declare a bridge. A family's `register(into:)` calls these:
//
//      r.view("Toggle", .controls) { v in
//          v.form("_:title isOn:binding") { c in Toggle(c.title(0), isOn: c.binding("isOn", Bool.self)) }
//          v.form("isOn:binding label:content") { c in Toggle(isOn: c.binding("isOn", Bool.self)) { c.content("label") } }
//      }
//
//      r.modifier("padding", .layout) { m in
//          m.form("") { _, view in view.padding() }
//          m.form("_:number") { c, view in view.padding(c.cg(0)) }
//      }
//
//      r.type("Date", .foundation) { t in
//          t.staticProperty("now") { _ in .native(.date(Date())) }
//          t.method("addingTimeInterval", "_:number") { c in .native(.date(c.date(.receiver).addingTimeInterval(c.double(0)))) }
//      }
//
//  Docs/bridges.md walks through one of each.
//

import SwiftUI

extension KRegistry {
    @discardableResult
    func view(_ name: String, _ family: KilnFamily, support: KilnSupport = .full, introduced: String? = nil,
              notes: String? = nil, file: String = #fileID, _ build: @MainActor (KViewBuilder) -> Void) -> KViewBridge {
        let b = KViewBridge(name: name, family: family, support: support, introduced: introduced, notes: notes, source: Self.source(file))
        build(KViewBuilder(b))
        add(b)
        return b
    }

    @discardableResult
    func modifier(_ name: String, _ family: KilnFamily, support: KilnSupport = .full, introduced: String? = nil,
                  notes: String? = nil, file: String = #fileID, _ build: @MainActor (KModifierBuilder) -> Void) -> KModifierBridge {
        let b = KModifierBridge(name: name, family: family, support: support, introduced: introduced, notes: notes, source: Self.source(file))
        build(KModifierBuilder(b))
        add(b)
        return b
    }

    @discardableResult
    func type(_ name: String, _ family: KilnFamily, support: KilnSupport = .partial, introduced: String? = nil,
              notes: String? = nil, file: String = #fileID, _ build: @MainActor (KTypeBuilder) -> Void) -> KTypeBridge {
        let b = KTypeBridge(name: name, family: family, support: support, introduced: introduced, notes: notes, source: Self.source(file))
        build(KTypeBuilder(b))
        add(b)
        return b
    }

    /// More members for a type another file declared (in the same family, or
    /// a later family adding to a type: `URL` gains file members in Files).
    func extend(_ name: String, _ build: @MainActor (KTypeBuilder) -> Void) {
        guard let b = types[name] else { preconditionFailure("Kiln: extend(\(name)) before \(name) is registered") }
        build(KTypeBuilder(b))
    }

    @discardableResult
    func function(_ name: String, _ family: KilnFamily, _ signature: String? = nil, owner: String = "Swift",
                  support: KilnSupport = .full, introduced: String? = nil, notes: String? = nil, file: String = #fileID,
                  kinds: [String?: KArgKind] = [:], async: Bool = false, closuresCanWait: Bool = false,
                  _ run: @escaping KTypeBridge.Fn) -> KFunctionBridge {
        let b = functions[name] ?? {
            let f = KFunctionBridge(name: name, family: family, support: support, introduced: introduced, notes: notes, source: Self.source(file))
            f.owner = owner
            add(f)
            return f
        }()
        b.forms.append(.init(overload: KTypeBuilder.overload(signature, kinds: kinds, introduced: introduced, notes: nil,
                                                             async: async, closuresCanWait: closuresCanWait), run: run))
        return b
    }

    /// A protocol the app's types adopt. `requirements` are written as the
    /// app writes them (`"path(in:)"`, `"animatableData?"` with a default,
    /// `"static transferRepresentation"`, `"async perform()"`); a missing
    /// required one is an error with the type's line. `proxy` makes the native
    /// value that stands for the app's (`KEProxies.swift`).
    @discardableResult
    func protocolBridge(_ name: String, _ family: KilnFamily, requirements: [String] = [], support: KilnSupport = .partial,
                        introduced: String? = nil, notes: String? = nil, file: String = #fileID,
                        proxy: (@MainActor (KAppValue) -> Any)? = nil) -> KProtocolBridge {
        let b = KProtocolBridge(name: name, family: family, support: support, introduced: introduced, notes: notes, source: Self.source(file))
        b.members = requirements.map(KRequirement.init(parsing:))
        b.requirements = b.members.map(\.declared)
        b.proxy = proxy
        add(b)
        return b
    }

    /// Gives a protocol another family declared its proxy (`Shape` is declared
    /// with the app's protocols in Core; Drawing has its proxy).
    func proxy(_ name: String, _ make: @escaping @MainActor (KAppValue) -> Any) {
        guard let b = protocols[name] else { preconditionFailure("Kiln: proxy(\(name)) before \(name) is registered") }
        b.proxy = make
    }

    func environmentValue(_ name: String, _ family: KilnFamily, support: KilnSupport = .full, notes: String? = nil,
                          file: String = #fileID, _ value: @escaping @MainActor (KInterpreter) -> KV) {
        let b = KEnvironmentBridge(name: name, family: family, support: support, introduced: nil, notes: notes, source: Self.source(file))
        b.value = value
        add(b)
    }

    /// An environment value SwiftUI has: `read` gives the app SwiftUI's value
    /// where the view is shown, and `write` is what `.environment(\.name, v)`
    /// sets. `value` is what a check (and a view before it's shown) reads.
    func environmentValue(_ name: String, _ family: KilnFamily, support: KilnSupport = .full, notes: String? = nil,
                          file: String = #fileID, value: @escaping @MainActor (KInterpreter) -> KV = { _ in .nilValue },
                          read: @escaping @MainActor (EnvironmentValues, KInterpreter) -> KV,
                          write: (@MainActor (inout EnvironmentValues, KV, KInterpreter) -> Void)? = nil) {
        let b = KEnvironmentBridge(name: name, family: family, support: support, introduced: nil, notes: notes, source: Self.source(file))
        b.value = value
        b.live = read
        b.writeEnvironment = write
        add(b)
    }

    /// An environment value read from SwiftUI's own environment where the
    /// view is shown, and optionally written by `.environment(\.name, v)`.
    func liveEnvironment(_ name: String, _ family: KilnFamily, support: KilnSupport = .full, notes: String? = nil,
                         file: String = #fileID, read: @escaping @MainActor (EnvironmentValues, KInterpreter) -> KV,
                         write: (@MainActor (AnyView, KV, KCall) -> AnyView)? = nil) {
        let b = KEnvironmentBridge(name: name, family: family, support: support, introduced: nil, notes: notes, source: Self.source(file))
        b.value = { interp in read(EnvironmentValues(), interp) }
        b.live = read
        b.write = write
        add(b)
    }

    /// A Swift macro the engine reads (`@Entry`, `@Animatable`): the manifest lists it as `macro:Name`.
    func macro(_ name: String, _ family: KilnFamily, support: KilnSupport = .full, notes: String? = nil, file: String = #fileID) {
        add(KMacroBridge(name: name, family: family, support: support, introduced: nil, notes: notes, source: Self.source(file)))
    }

    func wrapper(_ name: String, _ family: KilnFamily, support: KilnSupport = .full, notes: String? = nil, file: String = #fileID) {
        add(KWrapperBridge(name: name, family: family, support: support, introduced: nil, notes: notes, source: Self.source(file)))
    }

    /// A result builder a bridge provides, used where code writes `@Name`
    /// (Engine/KEBuilders.swift has the transform):
    ///
    ///     r.resultBuilder("RegexComponentBuilder", .text) { b in
    ///         b.method("buildBlock") { parts, _, _ in … }
    ///         b.method("buildEither") { args, labels, _ in … }   // labels: ["first"] or ["second"]
    ///     }
    func resultBuilder(_ name: String, _ family: KilnFamily, _ build: @MainActor (KNativeBuilder) -> Void) {
        let b = KNativeBuilder(name: name, family: family)
        build(b)
        addResultBuilder(b)
    }

    /// `Kiln/Bridges/Controls/Toggle.swift` → `Sources/Kiln/Bridges/Controls/Toggle.swift`.
    static func source(_ fileID: String) -> String {
        let path = fileID.split(separator: "/", maxSplits: 1).last.map(String.init) ?? fileID
        return "Sources/Kiln/" + path
    }
}

@MainActor
struct KViewBuilder {
    let bridge: KViewBridge
    init(_ b: KViewBridge) { bridge = b }

    /// One overload: its signature, and the real view it shows.
    func form<V: View>(_ signature: String, introduced: String? = nil, notes: String? = nil,
                       @ViewBuilder _ render: @escaping @MainActor (KCall) -> V) {
        bridge.forms.append(.init(overload: KOverload(params: KSignature.parse(signature),
                                                      availability: introduced.map { .iOS($0) }, notes: notes),
                                  render: { AnyView(render($0)) }))
    }

    /// Several overloads shown the same way (the render reads what's there).
    func forms<V: View>(_ signatures: [String], @ViewBuilder _ render: @escaping @MainActor (KCall) -> V) {
        for s in signatures { form(s, render) }
    }

    /// How a call becomes a value, when it isn't the usual view description.
    func make(_ f: @escaping @MainActor (KCall) throws -> KV) { bridge.make = f }

    var manifestKind: String { get { bridge.manifestKind } nonmutating set { bridge.manifestKind = newValue } }
    var owner: String? { get { bridge.owner } nonmutating set { bridge.owner = newValue } }
    /// How a check runs its closures, with the arguments SwiftUI would pass.
    func probe(_ hook: @escaping KProbe.Hook) { bridge.probe = hook }
    /// Engine-made: shown by the renderer, never written by an app.
    func engineOnly() {
        bridge.constructible = false
        bridge.isInternal = true
    }
}

@MainActor
struct KModifierBuilder {
    let bridge: KModifierBridge
    init(_ b: KModifierBridge) { bridge = b }

    /// One overload: its signature, and the view with it applied.
    func form<V: View>(_ signature: String, receiver: String? = nil, introduced: String? = nil, notes: String? = nil,
                       @ViewBuilder _ apply: @escaping @MainActor (KCall, AnyView) -> V) {
        bridge.forms.append(.init(overload: KOverload(params: KSignature.parse(signature),
                                                      availability: introduced.map { .iOS($0) }, notes: notes, receiver: receiver),
                                  apply: { c, v in AnyView(apply(c, v ?? c.view)) }))
    }

    /// An overload that works on the description of the view it's applied to
    /// (`c.base`): a shape's `fill`, `onDelete` on a `ForEach`. `c.view` shows
    /// the base when it's needed.
    func formOnBase<V: View>(_ signature: String, receiver: String? = nil, introduced: String? = nil, notes: String? = nil,
                             @ViewBuilder _ apply: @escaping @MainActor (KCall) -> V) {
        bridge.forms.append(.init(overload: KOverload(params: KSignature.parse(signature),
                                                      availability: introduced.map { .iOS($0) }, notes: notes, receiver: receiver),
                                  apply: { c, _ in AnyView(apply(c)) }))
    }

    func forms<V: View>(_ signatures: [String], receiver: String? = nil, @ViewBuilder _ apply: @escaping @MainActor (KCall, AnyView) -> V) {
        for s in signatures { form(s, receiver: receiver, apply) }
    }

    /// Accepted, with no effect (the manifest says `stub`, and `Kiln.check` warns).
    func stub(_ signatures: [String], receiver: String? = nil) {
        for s in signatures {
            form(s, receiver: receiver) { _, view in view }
            bridge.forms.last?.overload.isStub = true
        }
    }

    /// Its closures run where they can `await` (`.task`, `.refreshable`), so
    /// `Kiln.check` doesn't call an `await` in them an error. Call it after the forms.
    func closuresCanWait() {
        for f in bridge.forms { f.overload.closuresCanWait = true }
    }

    /// On a `Text`, the modifier keeps it a `Text`.
    func text(_ f: @escaping @MainActor (KCall, Text) -> Text?) { bridge.text = f }

    func styles(_ owner: String, _ names: [String]) { bridge.styles = (owner, names) }
    /// Sample arguments `Kiln.validate` passes a closure argument, by label.
    func probe(_ f: @escaping @MainActor (String?, KInterpreter) -> [KV]?) { bridge.sampleArgs = f }
    var owner: String? { get { bridge.owner } nonmutating set { bridge.owner = newValue } }
    /// How a check runs its closures, with the arguments SwiftUI would pass.
    func probe(_ hook: @escaping KProbe.Hook) { bridge.probe = hook }
}

@MainActor
struct KTypeBuilder {
    let bridge: KTypeBridge
    init(_ b: KTypeBridge) { bridge = b }

    /// `async`: the call must be awaited (`Kiln.check` says so when it isn't).
    /// `closuresCanWait`: closures passed to it may `await` (`Task {}`).
    static func overload(_ signature: String?, kinds: [String?: KArgKind] = [:], introduced: String?, notes: String?,
                         async: Bool = false, closuresCanWait: Bool = false) -> KOverload {
        let o: KOverload
        if let signature {
            o = KOverload(params: KSignature.parse(signature), availability: introduced.map { .iOS($0) }, notes: notes)
        } else {
            o = KOverload(params: [], lenient: true, lenientKinds: kinds, availability: introduced.map { .iOS($0) }, notes: notes)
        }
        o.isAsync = async
        o.closuresCanWait = closuresCanWait
        return o
    }

    /// `Type(…)`. A nil signature takes any labels; the bridge reads them.
    func initializer(_ signature: String? = nil, kinds: [String?: KArgKind] = [:], introduced: String? = nil,
                     notes: String? = nil, closuresCanWait: Bool = false, _ run: @escaping KTypeBridge.Fn) {
        bridge.inits.append(.init(overload: Self.overload(signature, kinds: kinds, introduced: introduced, notes: notes,
                                                          closuresCanWait: closuresCanWait), run: run))
    }

    func staticProperty(_ name: String, notes: String? = nil, support: KilnSupport = .full, _ get: @escaping KTypeBridge.Fn) {
        bridge.staticProperties[name] = .init(get: get, set: nil, notes: notes, support: support)
    }

    /// Several static members at once: `Color.red`, `.blue`….
    func staticProperties(_ values: [String: KV]) {
        for (name, v) in values { bridge.staticProperties[name] = .init(get: { _ in v }, set: nil, notes: nil, support: .full) }
    }

    func staticMethod(_ name: String, _ signature: String? = nil, kinds: [String?: KArgKind] = [:], introduced: String? = nil,
                      notes: String? = nil, async: Bool = false, closuresCanWait: Bool = false, _ run: @escaping KTypeBridge.Fn) {
        bridge.staticMethods[name, default: []].append(.init(overload: Self.overload(signature, kinds: kinds, introduced: introduced, notes: notes,
                                                                                     async: async, closuresCanWait: closuresCanWait), run: run))
    }

    /// `async`: reading it waits (`task.value`).
    func property(_ name: String, notes: String? = nil, support: KilnSupport = .full, async: Bool = false, _ get: @escaping KTypeBridge.Fn,
                  set: (@MainActor (inout KCall) throws -> Void)? = nil) {
        bridge.properties[name] = .init(get: get, set: set, notes: notes, support: support, isAsync: async)
    }

    /// An instance method. A nil signature takes any labels.
    func method(_ name: String, _ signature: String? = nil, kinds: [String?: KArgKind] = [:], introduced: String? = nil,
                notes: String? = nil, async: Bool = false, closuresCanWait: Bool = false, _ run: @escaping KTypeBridge.Fn) {
        bridge.methods[name, default: []].append(.init(overload: Self.overload(signature, kinds: kinds, introduced: introduced, notes: notes,
                                                                               async: async, closuresCanWait: closuresCanWait), run: run))
    }

    /// The same body for several method names (`uppercased`, `lowercased`).
    func methods(_ names: [String], async: Bool = false, closuresCanWait: Bool = false,
                 _ run: @escaping @MainActor (inout KCall, String) throws -> KV) {
        for n in names { method(n, async: async, closuresCanWait: closuresCanWait) { c in try run(&c, n) } }
    }

    func properties(_ names: [String], async: Bool = false, _ get: @escaping @MainActor (inout KCall, String) throws -> KV) {
        for n in names { property(n, async: async) { c in try get(&c, n) } }
    }

    func anyProperty(_ f: @escaping @MainActor (inout KCall, String) throws -> KV?) { bridge.anyProperty = f }
    func anyMethod(_ f: @escaping @MainActor (inout KCall, String) throws -> KV?) { bridge.anyMethod = f }
    func anyStatic(_ f: @escaping @MainActor (inout KCall, String) throws -> KV?) { bridge.anyStatic = f }
    func anyStaticMethod(_ f: @escaping @MainActor (inout KCall, String) throws -> KV?) { bridge.anyStaticMethod = f }
    func anySetter(_ f: @escaping @MainActor (inout KCall, String) throws -> Bool) { bridge.anySetter = f }
    func implicit(_ f: @escaping @MainActor (String, [KV], [String?]) -> KV?) { bridge.implicit = f }

    func fallback(_ type: String, _ convert: @escaping @MainActor (KV, KInterpreter) throws -> KV) {
        bridge.fallback = type
        bridge.asFallback = convert
    }

    var manifestKind: String { get { bridge.manifestKind } nonmutating set { bridge.manifestKind = newValue } }
    var membersInManifest: Bool { get { bridge.membersInManifest } nonmutating set { bridge.membersInManifest = newValue } }
    func namespace() { bridge.isNamespace = true }
    /// Engine-made: kept out of the manifest.
    func `internal`() { bridge.isInternal = true }
}
