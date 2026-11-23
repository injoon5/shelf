//
//  KEHost.swift
//  Kiln's engine
//
//  Every interpreted View struct is hosted by a real SwiftUI view (KHostView)
//  whose storage object owns that instance's @State, so SwiftUI's own identity
//  rules decide when state lives and dies, the same as compiled SwiftUI. The
//  body is evaluated inside that view's real `body`, so SwiftUI's observation
//  tracking sees what it reads (native `@Observable` objects included).
//

import SwiftUI
import Combine

// MARK: - Host

/// One hosted view's @State, @AppStorage, @StateObject and environment values.
@MainActor
final class KViewStorage: ObservableObject {
    private(set) var boxes: [String: KBox] = [:]
    private var prepared = false
    private var subscriptions: [ObjectIdentifier: AnyCancellable] = [:]
    private var defaultsWatch: AnyCancellable?

    func box(_ name: String) -> KBox? { boxes[name] }

    func prepare(_ value: KStructValue, _ interp: KInterpreter) {
        guard !prepared else { return }
        prepared = true
        for p in value.type.stored {
            guard let w = p.wrapper else { continue }
            switch w {
            case "State", "StateObject", "FocusState", "GestureState", "SceneStorage", "Namespace":
                let box = KBox(value.fields[p.name] ?? (p.type?.isOptional == true ? .nilValue : .void), type: p.type)
                box.onChange = { [weak self] in self?.objectWillChange.send() }
                boxes[p.name] = box
            case "ScaledMetric":
                // Scaled once for the text size (Bridges/Layout/Geometry.swift).
                let style = p.wrapperAttribute?.args.first(where: { $0.label == "relativeTo" }).flatMap { a -> String? in
                    if case .implicitMember(let n, _) = a.value { return n }
                    return nil
                }
                boxes[p.name] = KBox(LayoutBridges.scaled(value.fields[p.name] ?? .double(0), relativeTo: style), type: p.type)
            case "ObservedObject", "Bindable":
                // Owned when the view creates it itself (`= Model()`); otherwise read from the view value.
                if p.initial != nil {
                    boxes[p.name] = KBox(value.fields[p.name] ?? .nilValue, type: p.type)
                }
            case "AppStorage":
                // The run's own defaults (§1.7): each app has a suite, so the
                // key is the app's as written, and `UserDefaults.standard`
                // in the same app reads the same value.
                let key = p.wrapperAttribute?.args.first.flatMap { arg -> String? in
                    if case .string(let segs) = arg.value, case .text(let t)? = segs.first { return t }
                    return nil
                } ?? p.name
                let defaults = interp.context.defaults
                let fallback = value.fields[p.name] ?? .nilValue
                let box = KBox(get: {
                    guard let stored = defaults.object(forKey: key) else { return fallback }
                    switch fallback {
                    case .int: return .int((stored as? Int) ?? 0)
                    case .double: return .double((stored as? Double) ?? 0)
                    case .bool: return .bool((stored as? Bool) ?? false)
                    default: return .string((stored as? String) ?? "")
                    }
                }, set: { [weak self] v in
                    switch v {
                    case .int(let i): defaults.set(i, forKey: key)
                    case .double(let d): defaults.set(d, forKey: key)
                    case .bool(let b): defaults.set(b, forKey: key)
                    case .string(let s): defaults.set(s, forKey: key)
                    default: break
                    }
                    self?.objectWillChange.send()
                })
                boxes[p.name] = box
                watch(defaults)
            default:
                break
            }
        }
    }

    /// Another view, or `UserDefaults.standard` in an action, changed a
    /// setting: views showing an `@AppStorage` value redraw, as SwiftUI's do.
    private func watch(_ defaults: UserDefaults) {
        guard defaultsWatch == nil else { return }
        defaultsWatch = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: defaults)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    /// @Environment and @EnvironmentObject values, refreshed every render.
    func setEnvironment(_ value: KStructValue, dismiss: DismissAction, colorScheme: ColorScheme, objects: [String: KV],
                        live: EnvironmentValues? = nil, interp: KInterpreter) {
        for p in value.type.stored {
            if p.wrapper == "Environment" {
                var v = interp.environmentDefault(p, overrides: objects)
                if let live, let read = interp.liveEnvironmentReader(p) { v = read(live, interp) }
                if case .native(.dismiss) = v { v = .native(.dismiss(KRef({ dismiss() }))) }
                if case .keyPath(_, let comps)? = p.wrapperAttribute?.args.first?.value, comps.last == "colorScheme" {
                    v = .native(.implicit(colorScheme == .dark ? "dark" : "light", []))
                }
                boxes[p.name] = KBox(v)
            } else if p.wrapper == "EnvironmentObject", let typeName = p.type?.name, let obj = objects[typeName] {
                boxes[p.name] = KBox(obj)
            }
        }
    }

    /// Re-render when any class instance read by the last body changes.
    func observe(_ objects: [ObjectIdentifier: KObject]) {
        for (id, obj) in objects where subscriptions[id] == nil {
            subscriptions[id] = obj.changed.sink { [weak self] _ in self?.objectWillChange.send() }
        }
    }
}

struct KEnvironmentObjectsKey: EnvironmentKey {
    static let defaultValue: [String: KV] = [:]
}

extension EnvironmentValues {
    var kilnObjects: [String: KV] {
        get { self[KEnvironmentObjectsKey.self] }
        set { self[KEnvironmentObjectsKey.self] = newValue }
    }
}

/// A user View struct, hosted.
struct KHostView: View {
    let value: KStructValue
    let interp: KInterpreter
    @StateObject private var storage = KViewStorage()
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @SwiftUI.Environment(\.colorScheme) private var colorScheme
    @SwiftUI.Environment(\.kilnObjects) private var objects

    var body: some View {
        storage.prepare(value, interp)
        // A view that reads `\.editMode` or `\.isSearching` reads SwiftUI's
        // real environment; the others don't depend on all of it.
        if interp.readsLiveEnvironment(value.type) {
            return AnyView(KLiveEnvironment { env in render(env) })
        }
        return render(nil)
    }

    private func render(_ live: EnvironmentValues?) -> AnyView {
        storage.setEnvironment(value, dismiss: dismiss, colorScheme: colorScheme, objects: objects, live: live, interp: interp)
        let tracker = KReadTracker()
        let content = interp.renderBody(of: value, storage: storage, tracker: tracker)
        storage.observe(tracker.objects)
        return content
    }
}

/// SwiftUI's whole environment, for the views (and styles) that read live values.
struct KLiveEnvironment: View {
    @SwiftUI.Environment(\.self) private var environment
    let content: (EnvironmentValues) -> AnyView
    var body: some View { content(environment) }
}

extension KInterpreter {
    /// The live reader for an `@Environment(\.key)` property, if its key has one.
    func liveEnvironmentReader(_ p: KEVarDecl) -> (@MainActor (EnvironmentValues, KInterpreter) -> KV)? {
        guard case .keyPath(_, let comps)? = p.wrapperAttribute?.args.first?.value, let key = comps.last else { return nil }
        return registry.environment[key]?.live
    }

    /// Whether a type has an `@Environment` property SwiftUI must supply live.
    func readsLiveEnvironment(_ t: KType) -> Bool {
        if let known = liveEnvironmentTypes[ObjectIdentifier(t)] { return known }
        let reads = t.stored.contains { $0.wrapper == "Environment" && liveEnvironmentReader($0) != nil }
        liveEnvironmentTypes[ObjectIdentifier(t)] = reads
        return reads
    }

    /// A value (a style) with its `@Environment` properties read from `env`.
    func withLiveEnvironment(_ s: KStructValue, _ env: EnvironmentValues) -> KStructValue {
        var out = s
        for p in s.type.stored where p.wrapper == "Environment" {
            if let read = liveEnvironmentReader(p) { out.fields[p.name] = read(env, self) }
        }
        return out
    }
}

/// Content evaluated lazily inside SwiftUI (sheet content, navigation
/// destinations): re-evaluates whenever SwiftUI asks for it.
struct KLazyView: View {
    let make: () -> AnyView
    var body: some View { make() }
}

/// A timer that calls back into interpreted code at a fixed interval.
@MainActor
final class KTicker: ObservableObject {
    var action: (() -> Void)?
    private var timer: Timer?
    private var interval: Double = 0

    func start(_ interval: Double) {
        guard timer == nil || self.interval != interval else { return }
        timer?.invalidate()
        self.interval = interval
        timer = Timer.scheduledTimer(withTimeInterval: max(0.01, interval), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.action?() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

struct KTimerReceiver: View {
    let interval: Double
    let action: () -> Void
    let content: AnyView
    @StateObject private var ticker = KTicker()

    var body: some View {
        ticker.action = action
        return content
            .onAppear { ticker.start(interval) }
            .onDisappear { ticker.stop() }
    }
}

/// Shown in place of a part of the view that failed to evaluate.
struct KErrorView: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
            .padding(8)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Body evaluation

extension KInterpreter {
    func renderBody(of value: KStructValue, storage: KViewStorage?, tracker: KReadTracker?) -> AnyView {
        let ctx = KSelfContext(type: value.type, location: .box(KBox(.structV(value))), storage: storage)
        let env = KEnv(parent: globalEnv, selfContext: ctx)
        let saved = readTracker
        readTracker = tracker
        // An error from here on is the body's: the host shows its error screen.
        context.bodyDepth += 1
        defer { readTracker = saved; context.bodyDepth -= 1 }
        guard let bodyDecl = value.type.computed["body"] else {
            if value.type.isApp, let scenes = value.type.computed["body"] { _ = scenes }
            return AnyView(KErrorView(message: "\(value.type.name) has no body"))
        }
        do {
            let v = try entry { try runAccessor(bodyDecl.getter ?? [], env: env, returns: bodyDecl.type) }
            return KRenderer(interp: self).render(.group(KBuiltins.asViews(v, self)))
        } catch {
            report(error)
            return AnyView(KErrorView(message: describeError(error)))
        }
    }

    func describeError(_ error: Error) -> String {
        switch error {
        case let e as KERuntimeError: return e.description
        case let t as KEThrown: return "Uncaught error: \(describe(t.value))"
        default: return "\(error)"
        }
    }

    /// Run interpreted code from a UI event (a tap, a timer) with its own budget.
    /// A closure that uses `await` is an error here (it would have to wait);
    /// after teardown, nothing runs.
    func perform(_ f: KFunction?, _ args: [KV] = []) {
        guard let f else { return }
        runAction(f, args, canWait: false)
    }
}

