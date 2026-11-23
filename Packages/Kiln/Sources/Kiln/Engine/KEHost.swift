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
    /// SwiftUI's own projections of the app's properties (a `@FocusState`'s), by name.
    private var natives: [String: Any] = [:]
    /// `@GestureState` initial values, which a gesture's end resets to.
    private(set) var initials: [String: KV] = [:]

    func box(_ name: String) -> KBox? { boxes[name] }
    func setNative(_ name: String, _ value: Any) { natives[name] = value }
    func setBox(_ name: String, _ box: KBox) { boxes[name] = box }
    func native(_ name: String) -> Any? { natives[name] }

    func prepare(_ value: KStructValue, _ interp: KInterpreter) {
        guard !prepared else { return }
        prepared = true
        for p in value.type.stored {
            guard let w = p.wrapper else { continue }
            switch w {
            case "State", "StateObject", "FocusState", "GestureState", "SceneStorage", "Namespace", "AccessibilityFocusState":
                let initial = value.fields[p.name] ?? (p.type?.isOptional == true ? .nilValue : .void)
                if w == "GestureState" { initials[p.name] = initial }
                let box = KBox(initial, type: p.type)
                box.onChange = { [weak self] in self?.objectWillChange.send() }
                boxes[p.name] = box
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
    func setEnvironment(_ value: KStructValue, dismiss: DismissAction, colorScheme: ColorScheme, objects: [String: KV], interp: KInterpreter,
                        inputs: KHostInputValues? = nil) {
        if let inputs { connect(value, inputs, interp) }
        for p in value.type.stored {
            if p.wrapper == "Environment" {
                var v = interp.environmentDefault(p, overrides: objects)
                if let inputs, case .keyPath(_, let comps)? = p.wrapperAttribute?.args.first?.value, let key = comps.last,
                   let read = interp.registry.environment[key]?.read {
                    v = read(inputs.environment, interp)
                }
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
        let _ = storage.prepare(value, interp)
        if interp.needsHostInputs(value.type) {
            let storage = self.storage, value = self.value, interp = self.interp, dismiss = self.dismiss, objects = self.objects
            KHostInputs(readsFocusedValues: interp.readsFocusedValues(value.type)) { inputs in
                storage.setEnvironment(value, dismiss: dismiss, colorScheme: inputs.environment.colorScheme, objects: objects, interp: interp,
                                       inputs: inputs)
                return Self.render(value, interp, storage)
            }
        } else {
            let _ = storage.setEnvironment(value, dismiss: dismiss, colorScheme: colorScheme, objects: objects, interp: interp)
            Self.render(value, interp, storage)
        }
    }

    @MainActor static func render(_ value: KStructValue, _ interp: KInterpreter, _ storage: KViewStorage, content: KV? = nil) -> AnyView {
        let tracker = KReadTracker()
        let out = interp.renderBody(of: value, storage: storage, tracker: tracker, content: content)
        storage.observe(tracker.objects)
        return out
    }
}

/// The app's `ViewModifier` (PLAN.md §1.5): SwiftUI's content goes to its
/// `body(content:)`. Animatable, so an `Animatable` modifier interpolates.
struct KModifierProxy: ViewModifier, Animatable {
    let app: KAppValue
    /// Kept, not the app's code: SwiftUI interpolates it on its render thread.
    var data: KAnimVector

    init(app: KAppValue) {
        self.app = app
        data = KAnimatable.data(app)
    }

    nonisolated var animatableData: KAnimVector {
        get { data }
        set { data = newValue }
    }

    func body(content: Content) -> some View {
        if let s = KAnimatable.applied(app, data).structValue {
            KModifierHost(value: s, interp: app.interp, content: AnyView(content))
        } else {
            content
        }
    }
}

/// Hosts a `ViewModifier`'s `body(content:)` like `KHostView` hosts a view's
/// `body`: the modifier's `@State` lives as long as the view it's on.
struct KModifierHost: View {
    let value: KStructValue
    let interp: KInterpreter
    let content: AnyView
    @StateObject private var storage = KViewStorage()
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @SwiftUI.Environment(\.colorScheme) private var colorScheme
    @SwiftUI.Environment(\.kilnObjects) private var objects

    var body: some View {
        let _ = storage.prepare(value, interp)
        if interp.needsHostInputs(value.type) {
            let storage = self.storage, value = self.value, interp = self.interp, dismiss = self.dismiss, objects = self.objects
            let content = KNativeContent.value(self.content)
            KHostInputs(readsFocusedValues: interp.readsFocusedValues(value.type)) { inputs in
                storage.setEnvironment(value, dismiss: dismiss, colorScheme: inputs.environment.colorScheme, objects: objects, interp: interp,
                                       inputs: inputs)
                return KHostView.render(value, interp, storage, content: content)
            }
        } else {
            let _ = storage.setEnvironment(value, dismiss: dismiss, colorScheme: colorScheme, objects: objects, interp: interp)
            KHostView.render(value, interp, storage, content: KNativeContent.value(content))
        }
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
    /// `content`: a `ViewModifier`'s `body(content:)` is run with it.
    func renderBody(of value: KStructValue, storage: KViewStorage?, tracker: KReadTracker?, content: KV? = nil) -> AnyView {
        let ctx = KSelfContext(type: value.type, location: .box(KBox(.structV(value))), storage: storage)
        let env = KEnv(parent: globalEnv, selfContext: ctx)
        let saved = readTracker
        readTracker = tracker
        // An error from here on is the body's: the host shows its error screen.
        context.bodyDepth += 1
        defer { readTracker = saved; context.bodyDepth -= 1 }
        if let content {
            guard let m = value.type.method("body", labels: ["content"]) else {
                return AnyView(KErrorView(message: "\(value.type.name) has no body(content:)"))
            }
            do {
                let v = try entry { try invoke(m, args: [content], labels: ["content"], selfContext: ctx, parent: globalEnv) }
                return KRenderer(interp: self).render(.group(KBuiltins.asViews(v, self)))
            } catch {
                report(error)
                return AnyView(KErrorView(message: describeError(error)))
            }
        }
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

