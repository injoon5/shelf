//
//  Combine.swift
//  Bridges: Combine (Round 2C)
//
//  Publishers as Kiln values: subjects, `Just`, `Future`, `Fail`, a
//  sequence's `.publisher`, `NotificationCenter`'s, a timer's, an
//  `@Published` property's `$name` and an `ObservableObject`'s
//  `objectWillChange`; the common operators; `sink`, `assign(to:on:)` and
//  `AnyCancellable` (cancelled when it's no longer kept, as Combine's).
//  Delivery is synchronous on the main actor, as `receive(on: .main)` makes
//  it; `debounce`, `throttle` and `delay` wait on the main run loop. SwiftUI's
//  `.onReceive` takes any of them (`KCombineBridge`).
//

import SwiftUI
import Combine

enum KPubCompletion { case finished, failure(KV) }

/// What a publisher delivers to.
@MainActor
final class KSub {
    let onValue: (KV) throws -> Void
    let onCompletion: (KPubCompletion) throws -> Void
    init(onValue: @escaping (KV) throws -> Void, onCompletion: @escaping (KPubCompletion) throws -> Void = { _ in }) {
        self.onValue = onValue
        self.onCompletion = onCompletion
    }
}

/// One subscription: cancelling it stops delivery and whatever it started upstream.
@MainActor
final class KSubToken {
    private(set) var cancelled = false
    private var onCancel: [() -> Void] = []
    func add(_ f: @escaping () -> Void) { if cancelled { f() } else { onCancel.append(f) } }
    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        let fs = onCancel
        onCancel = []
        fs.forEach { $0() }
    }
}

/// A publisher. Subclasses deliver to each subscriber.
@MainActor
class KPub {
    /// The Kiln type it's shown as (`PassthroughSubject`, `AnyPublisher`).
    var kind: String { "AnyPublisher" }
    func subscribe(_ s: KSub) -> KSubToken { fatalError("abstract") }
    var kv: KV { .native(.object(kind, KRef(self))) }

    static func from(_ v: KV?) -> KPub? {
        if case .native(.object(_, let ref))? = v { return ref.value as? KPub }
        return nil
    }
}

/// `PassthroughSubject` and `CurrentValueSubject`.
@MainActor
final class KSubject: KPub {
    var current: KV?
    let isCurrentValue: Bool
    private var subs: [(KSub, KSubToken)] = []
    private var completion: KPubCompletion?
    init(current: KV?) {
        self.current = current
        isCurrentValue = current != nil
    }
    override var kind: String { isCurrentValue ? "CurrentValueSubject" : "PassthroughSubject" }

    override func subscribe(_ s: KSub) -> KSubToken {
        let token = KSubToken()
        if let completion {
            try? s.onCompletion(completion)
            return token
        }
        subs.append((s, token))
        if let current { try? s.onValue(current) }
        return token
    }

    func send(_ v: KV) throws {
        guard completion == nil else { return }
        if isCurrentValue { current = v }
        subs.removeAll { $0.1.cancelled }
        for (s, t) in subs where !t.cancelled { try s.onValue(v) }
    }

    func send(completion c: KPubCompletion) throws {
        guard completion == nil else { return }
        completion = c
        let live = subs.filter { !$0.1.cancelled }
        subs = []
        for (s, _) in live { try s.onCompletion(c) }
    }
}

/// A publisher made by a closure per subscriber (`Just`, a sequence's, an operator's).
@MainActor
final class KMadePub: KPub {
    let name: String
    let make: (KSub, KSubToken) throws -> Void
    init(_ name: String = "AnyPublisher", _ make: @escaping (KSub, KSubToken) throws -> Void) {
        self.name = name
        self.make = make
    }
    override var kind: String { name }
    override func subscribe(_ s: KSub) -> KSubToken {
        let token = KSubToken()
        do { try make(s, token) } catch { KCombine.report(error) }
        return token
    }
}

/// `Future { promise in … }`: runs once, now, and gives every subscriber its result.
@MainActor
final class KFuture: KPub {
    var result: KPubCompletion?
    var value: KV?
    private var waiting: [(KSub, KSubToken)] = []
    override var kind: String { "Future" }
    override func subscribe(_ s: KSub) -> KSubToken {
        let token = KSubToken()
        if let value { try? s.onValue(value) }
        if let result { try? s.onCompletion(result) } else { waiting.append((s, token)) }
        return token
    }
    func resolve(_ v: KV?, _ c: KPubCompletion) {
        guard result == nil else { return }
        value = v
        result = c
        for (s, t) in waiting where !t.cancelled {
            if let v { try? s.onValue(v) }
            try? s.onCompletion(c)
        }
        waiting = []
    }
}

/// `AnyCancellable`: cancels its subscription when cancelled, or when nothing keeps it.
@MainActor
final class KCancellable: Hashable {
    let token: KSubToken
    init(_ token: KSubToken) { self.token = token }
    func cancel() { token.cancel() }
    nonisolated static func == (a: KCancellable, b: KCancellable) -> Bool { a === b }
    nonisolated func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }
    deinit {
        let t = token
        MainActor.assumeIsolated { t.cancel() }
    }
    var kv: KV { .native(.object("AnyCancellable", KRef(self))) }
}

/// What an `@Published` property and `objectWillChange` hear: a write to the object.
@MainActor
final class KObjectHooks {
    var published: [String: KSubject] = [:]
    var willChange: KSubject?
}

@MainActor
enum KCombine {
    static func report(_ error: Error) {
        // Errors from the app's closures surface where the value was sent; one
        // from a subscription made in a view's body has no caller to throw to.
    }

    /// `model.$count`: the property's publisher, which gives the current value first.
    static func published(_ o: KObject, _ name: String) -> KV {
        let hooks = o.combineHooks ?? KObjectHooks()
        o.combineHooks = hooks
        let subject = hooks.published[name] ?? KSubject(current: nil)
        hooks.published[name] = subject
        return KMadePub("Published.Publisher") { s, token in
            try s.onValue(o.fields[name] ?? .nilValue)
            let inner = subject.subscribe(s)
            token.add { inner.cancel() }
        }.kv
    }

    /// `model.objectWillChange`.
    static func objectWillChange(_ o: KObject) -> KV {
        let hooks = o.combineHooks ?? KObjectHooks()
        o.combineHooks = hooks
        let subject = hooks.willChange ?? KSubject(current: nil)
        hooks.willChange = subject
        return KMadePub("ObservableObjectPublisher") { s, token in
            let inner = subject.subscribe(s)
            token.add { inner.cancel() }
        }.kv
    }

    /// Called by the engine before an object's property is set (as `@Published` sends in `willSet`).
    static func willSet(_ o: KObject, _ name: String, _ value: KV) throws {
        guard let hooks = o.combineHooks else { return }
        let isPublished = o.type.storedDecl(name)?.wrapper == "Published"
        if isPublished || o.type.conformances.contains("ObservableObject") { try hooks.willChange?.send(.void) }
        if isPublished, let s = hooks.published[name] { try s.send(value) }
    }

    // MARK: Operators

    /// A publisher from `upstream`, each subscriber's values passed through `transform`.
    static func op(_ upstream: KPub, _ transform: @escaping (KSub, KSubToken) -> KSub) -> KV {
        KMadePub { s, token in
            let inner = upstream.subscribe(transform(s, token))
            token.add { inner.cancel() }
        }.kv
    }

    /// `combineLatest`, `merge`, `zip`: several upstreams into one subscriber.
    static func many(_ ups: [KPub], _ make: @escaping (KSub, KSubToken) -> [KSub]) -> KV {
        KMadePub { s, token in
            let downs = make(s, token)
            for (u, d) in zip(ups, downs) {
                let inner = u.subscribe(d)
                token.add { inner.cancel() }
            }
        }.kv
    }
}

/// A Kiln publisher as Combine's, for SwiftUI's `.onReceive`.
struct KCombineBridge: Publisher {
    typealias Output = KV
    typealias Failure = Never
    let pub: KPub
    func receive<S: Subscriber>(subscriber: S) where S.Input == KV, S.Failure == Never {
        let subject = PassthroughSubject<KV, Never>()
        let pub = self.pub
        var token: KSubToken?
        subject.handleEvents(receiveCancel: { MainActor.assumeIsolated { token?.cancel() } }).receive(subscriber: subscriber)
        token = MainActor.assumeIsolated {
            pub.subscribe(KSub(onValue: { subject.send($0) }, onCompletion: { _ in subject.send(completion: .finished) }))
        }
    }
}

extension ConcurrencyBridges {
    static func combine(_ r: KRegistry) {
        r.type("CancellationError", .concurrency, support: .full) { t in
            t.initializer("") { _ in KAsync.cancellationValue }
        }

        // What every publisher has.
        r.type("Publisher", .concurrency, support: .partial,
               notes: "Combine runs synchronously on the main actor: subjects, `Just`, `Future`, `@Published`'s `$name`, `.publisher` of a sequence and of `NotificationCenter`; `map`, `filter`, `compactMap`, `removeDuplicates`, `scan`, `debounce`, `throttle`, `delay`, `combineLatest`, `merge`, `sink`, `assign(to:on:)`, `store(in:)`; `.onReceive` takes them.") { t in
            t.namespace()
            @MainActor func up(_ c: KCall) throws -> KPub {
                guard let p = KPub.from(c.receiver) else { throw c.fail("isn't a publisher") }
                return p
            }
            @MainActor func fn(_ c: KCall, _ i: Int = 0) throws -> (KV) throws -> KV {
                guard i < c.args.count else { throw c.fail("needs a closure") }
                return try c.interp.applier(c.args[i], c.line)
            }
            t.method("sink", "receiveValue:closure") { c in
                let f = try fn(c)
                return KCancellable(try up(c).subscribe(KSub(onValue: { _ = try f($0) }))).kv
            }
            t.method("sink", "receiveCompletion:closure receiveValue:closure") { c in
                let fc = try fn(c, 0), fv = try fn(c, 1)
                return KCancellable(try up(c).subscribe(KSub(onValue: { _ = try fv($0) }, onCompletion: { done in
                    switch done {
                    case .finished: _ = try fc(.native(.implicit("finished", [])))
                    case .failure(let e): _ = try fc(.native(.implicit("failure", [e])))
                    }
                }))).kv
            }
            t.method("assign", "to:any on:any") { c in
                guard case .native(.keyPath(let path))? = c["to"], let target = c["on"] else { throw c.fail("needs a key path and an object") }
                let interp = c.interp
                return KCancellable(try up(c).subscribe(KSub(onValue: { v in
                    var loc: KLocation = .box(KBox(target))
                    for p in path where p != "self" { loc = try interp.memberLocation(loc, p) }
                    try interp.write(loc, v)
                }))).kv
            }
            t.method("map", "_:any") { c in
                let f = try fn(c)
                return KCombine.op(try up(c)) { s, _ in KSub(onValue: { try s.onValue(try f($0)) }, onCompletion: s.onCompletion) }
            }
            t.method("tryMap", "_:any") { c in
                let f = try fn(c)
                return KCombine.op(try up(c)) { s, _ in KSub(onValue: { try s.onValue(try f($0)) }, onCompletion: s.onCompletion) }
            }
            t.method("filter", "_:closure") { c in
                let f = try fn(c), interp = c.interp
                return KCombine.op(try up(c)) { s, _ in KSub(onValue: { if interp.truthy(try f($0)) { try s.onValue($0) } }, onCompletion: s.onCompletion) }
            }
            t.method("compactMap", "_:any") { c in
                let f = try fn(c)
                return KCombine.op(try up(c)) { s, _ in KSub(onValue: { let v = try f($0); if !v.isNil { try s.onValue(v) } }, onCompletion: s.onCompletion) }
            }
            t.method("removeDuplicates", "") { c in
                KCombine.op(try up(c)) { s, _ in
                    var last: KV?
                    return KSub(onValue: { v in if last != v { last = v; try s.onValue(v) } }, onCompletion: s.onCompletion)
                }
            }
            t.method("removeDuplicates", "by:closure") { c in
                guard case .function(let f)? = c.first else { throw c.fail("needs a closure") }
                let interp = c.interp
                return KCombine.op(try up(c)) { s, _ in
                    var last: KV?
                    return KSub(onValue: { v in
                        if let l = last, interp.truthy(try interp.call(f, [l, v], [nil, nil])) { return }
                        last = v
                        try s.onValue(v)
                    }, onCompletion: s.onCompletion)
                }
            }
            t.method("scan", "_:any _:closure") { c in
                guard case .function(let f)? = c.at(1) else { throw c.fail("needs a closure") }
                let initial = c.at(0) ?? .nilValue, interp = c.interp
                return KCombine.op(try up(c)) { s, _ in
                    var acc = initial
                    return KSub(onValue: { v in acc = try interp.call(f, [acc, v], [nil, nil]); try s.onValue(acc) }, onCompletion: s.onCompletion)
                }
            }
            t.method("reduce", "_:any _:closure") { c in
                guard case .function(let f)? = c.at(1) else { throw c.fail("needs a closure") }
                let initial = c.at(0) ?? .nilValue, interp = c.interp
                return KCombine.op(try up(c)) { s, _ in
                    var acc = initial
                    return KSub(onValue: { v in acc = try interp.call(f, [acc, v], [nil, nil]) }, onCompletion: { done in
                        if case .finished = done { try s.onValue(acc) }
                        try s.onCompletion(done)
                    })
                }
            }
            t.method("collect", "") { c in
                KCombine.op(try up(c)) { s, _ in
                    var items: [KV] = []
                    return KSub(onValue: { items.append($0) }, onCompletion: { done in
                        if case .finished = done { try s.onValue(.array(items)) }
                        try s.onCompletion(done)
                    })
                }
            }
            t.method("collect", "_:number") { c in
                let n = max(1, c.int(0) ?? 1)
                return KCombine.op(try up(c)) { s, _ in
                    var items: [KV] = []
                    return KSub(onValue: { items.append($0); if items.count == n { let b = items; items = []; try s.onValue(.array(b)) } },
                                onCompletion: { done in
                                    if case .finished = done, !items.isEmpty { try s.onValue(.array(items)) }
                                    try s.onCompletion(done)
                                })
                }
            }
            t.method("prefix", "_:number") { c in
                let n = c.int(0) ?? 0
                return KCombine.op(try up(c)) { s, token in
                    var count = 0
                    return KSub(onValue: { v in
                        guard count < n else { return }
                        count += 1
                        try s.onValue(v)
                        if count == n { try s.onCompletion(.finished); token.cancel() }
                    }, onCompletion: { if count < n { try s.onCompletion($0) } })
                }
            }
            t.method("dropFirst", "_:number?") { c in
                let n = c.int(0) ?? 1
                return KCombine.op(try up(c)) { s, _ in
                    var seen = 0
                    return KSub(onValue: { v in if seen < n { seen += 1 } else { try s.onValue(v) } }, onCompletion: s.onCompletion)
                }
            }
            t.method("first", "") { c in
                KCombine.op(try up(c)) { s, token in
                    var done = false
                    return KSub(onValue: { v in
                        guard !done else { return }
                        done = true
                        try s.onValue(v)
                        try s.onCompletion(.finished)
                        token.cancel()
                    }, onCompletion: { if !done { try s.onCompletion($0) } })
                }
            }
            t.method("last", "") { c in
                KCombine.op(try up(c)) { s, _ in
                    var last: KV?
                    return KSub(onValue: { last = $0 }, onCompletion: { done in
                        if case .finished = done, let last { try s.onValue(last) }
                        try s.onCompletion(done)
                    })
                }
            }
            t.method("replaceNil", "with:any") { c in
                let r = c["with"] ?? .nilValue
                return KCombine.op(try up(c)) { s, _ in KSub(onValue: { try s.onValue($0.isNil ? r : $0) }, onCompletion: s.onCompletion) }
            }
            t.method("replaceError", "with:any") { c in
                let r = c["with"] ?? .nilValue
                return KCombine.op(try up(c)) { s, _ in KSub(onValue: s.onValue, onCompletion: { done in
                    if case .failure = done { try s.onValue(r); try s.onCompletion(.finished) } else { try s.onCompletion(done) }
                }) }
            }
            t.method("catch", "_:closure") { c in
                guard case .function(let f)? = c.first else { throw c.fail("needs a closure") }
                let interp = c.interp
                return KCombine.op(try up(c)) { s, token in
                    KSub(onValue: s.onValue, onCompletion: { done in
                        guard case .failure(let e) = done else { try s.onCompletion(done); return }
                        guard let replacement = KPub.from(try interp.call(f, [e], [nil])) else { try s.onCompletion(.finished); return }
                        let inner = replacement.subscribe(s)
                        token.add { inner.cancel() }
                    })
                }
            }
            t.method("handleEvents", "receiveSubscription:closure? receiveOutput:closure? receiveCompletion:closure? receiveCancel:closure? receiveRequest:closure?") { c in
                let out = c["receiveOutput"], done = c["receiveCompletion"], interp = c.interp
                return KCombine.op(try up(c)) { s, _ in
                    KSub(onValue: { v in
                        if case .function(let f)? = out { _ = try interp.call(f, [v], [nil]) }
                        try s.onValue(v)
                    }, onCompletion: { d in
                        if case .function(let f)? = done { _ = try interp.call(f, [.native(.implicit("finished", []))], [nil]) }
                        try s.onCompletion(d)
                    })
                }
            }
            t.method("flatMap", "_:closure") { c in
                guard case .function(let f)? = c.first else { throw c.fail("needs a closure") }
                let interp = c.interp
                return KCombine.op(try up(c)) { s, token in
                    KSub(onValue: { v in
                        guard let inner = KPub.from(try interp.call(f, [v], [nil])) else { return }
                        let t2 = inner.subscribe(KSub(onValue: s.onValue))
                        token.add { t2.cancel() }
                    }, onCompletion: s.onCompletion)
                }
            }
            t.method("combineLatest", "_:any") { c in try combineLatest(c, [try up(c)] + [KPub.from(c.first)].compactMap { $0 }, transform: nil) }
            t.method("combineLatest", "_:any _:closure") { c in try combineLatest(c, [try up(c)] + [KPub.from(c.first)].compactMap { $0 }, transform: c.at(1)) }
            t.method("combineLatest", "_:any _:any") { c in try combineLatest(c, [try up(c), KPub.from(c.at(0)), KPub.from(c.at(1))].compactMap { $0 }, transform: nil) }
            t.method("zip", "_:any") { c in
                guard let other = KPub.from(c.first) else { throw c.fail("needs a publisher") }
                return KCombine.many([try up(c), other]) { s, _ in
                    var a: [KV] = [], b: [KV] = []
                    func emit() throws { while !a.isEmpty && !b.isEmpty { try s.onValue(.tuple([a.removeFirst(), b.removeFirst()], [nil, nil])) } }
                    return [KSub(onValue: { a.append($0); try emit() }, onCompletion: s.onCompletion),
                            KSub(onValue: { b.append($0); try emit() }, onCompletion: { _ in })]
                }
            }
            t.method("merge", "with:any") { c in
                guard let other = KPub.from(c["with"]) else { throw c.fail("needs a publisher") }
                return KCombine.many([try up(c), other]) { s, _ in
                    var finished = 0
                    let done: (KPubCompletion) throws -> Void = { d in
                        if case .failure = d { try s.onCompletion(d); return }
                        finished += 1
                        if finished == 2 { try s.onCompletion(.finished) }
                    }
                    return [KSub(onValue: s.onValue, onCompletion: done), KSub(onValue: s.onValue, onCompletion: done)]
                }
            }
            // Delivery is on the main actor already: these keep the chain as written.
            for name in ["receive", "subscribe", "eraseToAnyPublisher", "share", "setFailureType", "assertNoFailure", "print", "makeConnectable", "autoconnect"] {
                t.method(name, nil) { c in
                    guard let p = KPub.from(c.receiver) else { return c.receiver }
                    return KMadePub { s, token in let inner = p.subscribe(s); token.add { inner.cancel() } }.kv
                }
            }
            for name in ["debounce", "throttle", "delay"] {
                t.method(name, nil) { c in
                    let seconds = KCombineTime.seconds(c["for"] ?? c["by"] ?? c.first)
                    let latest = c.bool("latest", default: true)
                    return KCombine.op(try up(c)) { s, token in
                        var pending: DispatchWorkItem?
                        var last: Date?
                        var held: KV?
                        return KSub(onValue: { v in
                            switch name {
                            case "delay":
                                let item = DispatchWorkItem { MainActor.assumeIsolated { if !token.cancelled { try? s.onValue(v) } } }
                                DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
                                token.add { item.cancel() }
                            case "throttle":
                                if let l = last, Date().timeIntervalSince(l) < seconds {
                                    held = latest ? v : (held ?? v)
                                    if pending == nil {
                                        let item = DispatchWorkItem { MainActor.assumeIsolated {
                                            pending = nil
                                            if let h = held, !token.cancelled { held = nil; last = Date(); try? s.onValue(h) }
                                        } }
                                        pending = item
                                        DispatchQueue.main.asyncAfter(deadline: .now() + seconds - Date().timeIntervalSince(l), execute: item)
                                        token.add { item.cancel() }
                                    }
                                } else {
                                    last = Date()
                                    try s.onValue(v)
                                }
                            default:
                                pending?.cancel()
                                let item = DispatchWorkItem { MainActor.assumeIsolated { if !token.cancelled { try? s.onValue(v) } } }
                                pending = item
                                DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
                                token.add { item.cancel() }
                            }
                        }, onCompletion: s.onCompletion)
                    }
                }
            }
            // `for await value in publisher.values`.
            t.property("values") { c in
                guard let p = KPub.from(c.receiver) else { return .nilValue }
                return .array(KCombineValues.collect(p))
            }
        }

        let subjectNote = "`send(_:)`, `send(completion:)`; a `CurrentValueSubject` has `value`."
        r.type("PassthroughSubject", .concurrency, support: .full, notes: subjectNote) { t in
            t.initializer("") { _ in KSubject(current: nil).kv }
            subjectMembers(t)
        }
        r.type("CurrentValueSubject", .concurrency, support: .full, notes: subjectNote) { t in
            t.initializer("_:any") { c in KSubject(current: c.first ?? .nilValue).kv }
            subjectMembers(t)
            t.property("value", { c in (KPub.from(c.receiver) as? KSubject)?.current ?? .nilValue }, set: { c in
                try (KPub.from(c.receiver) as? KSubject)?.send(c.first ?? .nilValue)
            })
        }
        for name in ["AnyPublisher", "Published.Publisher", "ObservableObjectPublisher", "Future", "Just", "Fail", "Empty", "Publishers.Sequence",
                     "NotificationCenter.Publisher"] {
            r.type(name, .concurrency, support: .full) { t in
                switch name {
                case "Just": t.initializer("_:any") { c in let v = c.first ?? .nilValue; return KMadePub("Just") { s, _ in try s.onValue(v); try s.onCompletion(.finished) }.kv }
                case "Fail": t.initializer("error:any") { c in let e = c["error"] ?? .nilValue; return KMadePub("Fail") { s, _ in try s.onCompletion(.failure(e)) }.kv }
                case "Empty":
                    t.initializer("") { _ in KMadePub("Empty") { s, _ in try s.onCompletion(.finished) }.kv }
                    t.initializer("completeImmediately:bool") { c in
                        let now = c.bool("completeImmediately", default: true)
                        return KMadePub("Empty") { s, _ in if now { try s.onCompletion(.finished) } }.kv
                    }
                case "Future":
                    t.initializer("_:closure") { c in
                        guard case .function(let f)? = c.first else { throw c.fail("needs a closure") }
                        let future = KFuture()
                        let promise = KV.function(KFunction(.native("promise") { args, _ in
                            MainActor.assumeIsolated {
                                if case .enumV(let e)? = args.first, e.caseName == "failure" { future.resolve(nil, .failure(e.payload.first ?? .nilValue)) }
                                else if case .native(.implicit("failure", let p))? = args.first { future.resolve(nil, .failure(p.first ?? .nilValue)) }
                                else if case .native(.implicit("success", let p))? = args.first { future.resolve(p.first ?? .void, .finished) }
                                else if case .enumV(let e)? = args.first, e.caseName == "success" { future.resolve(e.payload.first ?? .void, .finished) }
                                else { future.resolve(args.first ?? .void, .finished) }
                            }
                            return .void
                        }))
                        _ = try c.interp.call(f, [promise], [nil])
                        return future.kv
                    }
                default: break
                }
                t.fallback("Publisher") { v, _ in v }
            }
        }
        r.type("AnyCancellable", .concurrency, support: .full, notes: "Cancelled by `cancel()`, or when nothing keeps it (keep it in a property or `store(in: &cancellables)`).") { t in
            t.initializer("_:closure") { c in
                let token = KSubToken()
                if case .function(let f)? = c.first { let interp = c.interp; token.add { _ = try? interp.call(f, [], []) } }
                return KCancellable(token).kv
            }
            @MainActor func me(_ c: KCall) -> KCancellable? { c.object(KCancellable.self) }
            t.method("cancel", "") { c in me(c)?.cancel(); return .void }
            t.method("store", "in:binding") { c in
                guard case .binding(let b)? = c["in"] else { throw c.fail("needs a set or array, as `&cancellables`") }
                switch b.get() {
                case .array(var xs): xs.append(c.receiver); b.set(.array(xs))
                default:
                    var s: Set<KV> = []
                    if case .set(let old) = b.get() { s = old }
                    s.insert(c.receiver)
                    b.set(.set(s))
                }
                return .void
            }
        }

        // A sequence's `.publisher`.
        r.extend("Sequence") { t in
            t.property("publisher") { c in
                let items = c.receiver.asArray ?? []
                return KMadePub("Publishers.Sequence") { s, token in
                    for x in items where !token.cancelled { try s.onValue(x) }
                    if !token.cancelled { try s.onCompletion(.finished) }
                }.kv
            }
        }
        // `Timer.publish(every:on:in:).autoconnect()` as a publisher (`sink`, `map`…).
        r.extend("Timer.TimerPublisher") { t in
            t.fallback("Publisher") { v, interp in
                guard case .native(.publisher(let interval)) = v else { return v }
                return KMadePub("Timer.TimerPublisher") { s, token in
                    let timer = Timer(timeInterval: interval, repeats: true) { _ in
                        MainActor.assumeIsolated { if !token.cancelled { try? s.onValue(.native(.date(Date()))) } }
                    }
                    RunLoop.main.add(timer, forMode: .common)
                    token.add { timer.invalidate() }
                    let stop = interp.context.onTearDown { token.cancel() }
                    token.add { stop.cancel() }
                }.kv
            }
        }
    }

    @MainActor static func subjectMembers(_ t: KTypeBuilder) {
        @MainActor func me(_ c: KCall) throws -> KSubject {
            guard let s = KPub.from(c.receiver) as? KSubject else { throw c.noMember() }
            return s
        }
        t.method("send", "_:any") { c in try me(c).send(c.first ?? .void); return .void }
        t.method("send", "") { c in try me(c).send(.void); return .void }
        t.method("send", "completion:any") { c in
            let s = try me(c)
            switch c["completion"] {
            case .native(.implicit("failure", let p))?: try s.send(completion: .failure(p.first ?? .nilValue))
            default: try s.send(completion: .finished)
            }
            return .void
        }
        t.fallback("Publisher") { v, _ in v }
    }

    @MainActor static func combineLatest(_ c: KCall, _ ups: [KPub], transform: KV?) throws -> KV {
        guard ups.count >= 2 else { throw c.fail("needs a publisher") }
        let interp = c.interp
        return KCombine.many(ups) { s, _ in
            var latest: [KV?] = Array(repeating: nil, count: ups.count)
            var finished = 0
            return ups.indices.map { i in
                KSub(onValue: { v in
                    latest[i] = v
                    guard latest.allSatisfy({ $0 != nil }) else { return }
                    let values = latest.map { $0! }
                    if case .function(let f)? = transform { try s.onValue(try interp.call(f, values, values.map { _ in nil })) }
                    else { try s.onValue(.tuple(values, values.map { _ in nil })) }
                }, onCompletion: { d in
                    if case .failure = d { try s.onCompletion(d); return }
                    finished += 1
                    if finished == ups.count { try s.onCompletion(.finished) }
                })
            }
        }
    }
}

/// `for: .milliseconds(300)`, `.seconds(1)`, a number of seconds.
@MainActor
enum KCombineTime {
    static func seconds(_ v: KV?) -> Double {
        switch v {
        case .native(.implicit(let unit, let args))?:
            let n = args.first?.asDouble ?? 0
            switch unit {
            case "milliseconds": return n / 1000
            case "microseconds": return n / 1_000_000
            case "nanoseconds": return n / 1_000_000_000
            default: return n
            }
        case .native(.boxed(let b))?:
            if let d = b.value.base as? KDuration { return d.seconds }
            return 0
        default: return v?.asDouble ?? 0
        }
    }
}

/// `publisher.values`: what it has sent synchronously, to loop over.
@MainActor
enum KCombineValues {
    /// What a check passes `.onReceive`'s closure: the values a Combine
    /// publisher gives at once (a `CurrentValueSubject`'s, `Just`'s, `$name`'s),
    /// none for a `PassthroughSubject`. nil when it isn't a Kiln publisher.
    static func sample(_ v: KV) -> [KV]? {
        guard let p = KPub.from(v) else { return nil }
        return collect(p)
    }

    static func collect(_ p: KPub) -> [KV] {
        var out: [KV] = []
        let token = p.subscribe(KSub(onValue: { out.append($0) }))
        token.cancel()
        return out
    }
}
