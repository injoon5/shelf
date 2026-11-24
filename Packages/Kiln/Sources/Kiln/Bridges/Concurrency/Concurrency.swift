//
//  Concurrency.swift
//  Bridges: Swift concurrency
//
//  `Task {}`, `Task.sleep`, `MainActor.run`, task groups, `AsyncStream`,
//  continuations and cancellation. The tasks themselves are the engine's
//  (Engine/KEAsync.swift): these bridges start them and hand back the
//  suspensions `await` waits on. Everything runs on the main actor.
//

import SwiftUI

@objc(KilnBridges_Concurrency)
final class ConcurrencyBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        tasks(r)
        groups(r)
        streams(r)
        combine(r)
        clocks(r)
    }

    @MainActor static func body(_ c: KCall) -> KFunction? {
        if case .function(let f)? = c.last { return f }
        return nil
    }

    // MARK: Task

    static func tasks(_ r: KRegistry) {
        r.type("Task", .concurrency, notes: "`Task.detached` runs on the main actor too.") { t in
            t.initializer(closuresCanWait: true) { c in
                guard let f = body(c) else { return .native(.object("Task", KRef(KTask(id: 0)))) }
                return .native(.object("Task", KRef(c.interp.startTask(f, [], parent: nil, reportsErrors: true))))
            }
            t.staticMethod("detached", closuresCanWait: true) { c in
                guard let f = body(c) else { return .native(.object("Task", KRef(KTask(id: 0)))) }
                return .native(.object("Task", KRef(c.interp.startTask(f, [], parent: nil, reportsErrors: true))))
            }
            t.staticMethod("sleep", notes: "`for: .seconds(n)`, `nanoseconds:`; really waits.", async: true) { c in
                if let n = c.arg("nanoseconds")?.asDouble { return KBuiltins.sleep(n / 1_000_000_000) }
                // A `Duration` value (`let d: Duration = .seconds(1)`, Clocks.swift).
                if case .native(.boxed)? = c.arg("for") ?? c.first, let d = KDuration.from(c.arg("for") ?? c.first) {
                    return KBuiltins.sleep(KDuration(d: d).seconds)
                }
                if let s = KBuiltins.seconds(c.arg("for") ?? c.arg("seconds") ?? c.first) { return KBuiltins.sleep(s) }
                if case .native(.date(let d))? = c.arg("until") { return KBuiltins.sleep(d.timeIntervalSinceNow) }
                return KBuiltins.sleep(0)
            }
            t.staticMethod("yield", async: true) { _ in KBuiltins.yieldNow() }
            t.staticMethod("checkCancellation") { c in
                if c.interp.currentTask?.isCancelled == true { throw KAsync.cancellationError }
                return .void
            }
            t.staticMethod("isCancelled") { c in .bool(c.interp.currentTask?.isCancelled ?? false) }
            t.staticProperty("isCancelled") { c in .bool(c.interp.currentTask?.isCancelled ?? false) }
            t.staticProperty("currentPriority") { _ in .native(.implicit("medium", [])) }
            t.properties(["value", "result"], async: true) { c, _ in
                guard let task = c.object(KTask.self) else { throw c.noMember() }
                return .suspension(c.interp.taskValue(task))
            }
            t.property("isCancelled") { c in .bool(c.object(KTask.self)?.isCancelled ?? false) }
            t.method("cancel") { c in c.object(KTask.self)?.cancel(); return .void }
        }

        r.type("MainActor", .concurrency) { t in
            t.namespace()
            t.staticMethod("run", async: true, closuresCanWait: true) { c in
                guard let f = body(c) else { throw c.interp.fail("MainActor.run needs a closure", c.line) }
                return try c.interp.call(f, [], [])
            }
        }

        for name in ["withCheckedContinuation", "withCheckedThrowingContinuation", "withUnsafeContinuation", "withUnsafeThrowingContinuation"] {
            r.function(name, .concurrency, async: true) { c in
                guard let f = body(c) else { throw c.interp.fail("\(name) needs a closure", c.line) }
                let interp = c.interp
                return .suspension(KSuspension.callback { _, resume in
                    let k = KContinuation(resume)
                    do {
                        _ = try interp.call(f, [.native(.object("CheckedContinuation", KRef(k)))], [nil])
                    } catch {
                        k.complete(.failure(error))
                    }
                    return nil
                })
            }
        }
        r.type("CheckedContinuation", .concurrency) { t in
            t.method("resume") { c in
                guard let k = c.object(KContinuation.self) else { throw c.noMember() }
                if let e = c.arg("throwing") { k.complete(.failure(KEThrown(value: e))) }
                else if let v = c.arg("returning") { k.complete(.success(v)) }
                else { k.complete(.success(c.first ?? .void)) }
                return .void
            }
        }
        r.alias("UnsafeContinuation", to: "CheckedContinuation")

        r.function("withTaskCancellationHandler", .concurrency, async: true, closuresCanWait: true) { c in
            // The operation runs as a call; the handler when the task is cancelled.
            guard case .function(let op)? = c.arg("operation") ?? c.first else { throw c.interp.fail("withTaskCancellationHandler needs an operation", c.line) }
            let handler: KFunction? = { if case .function(let f)? = c.arg("onCancel") { return f }; return nil }()
            let v = try c.interp.call(op, [], [])
            if let handler, c.interp.currentTask?.isCancelled == true { c.interp.perform(handler) }
            return v
        }
    }

    // MARK: Task groups

    static func groups(_ r: KRegistry) {
        for name in ["withTaskGroup", "withThrowingTaskGroup", "withDiscardingTaskGroup", "withThrowingDiscardingTaskGroup"] {
            r.function(name, .concurrency, async: true, closuresCanWait: true) { c in
                guard let f = body(c) else { throw c.interp.fail("\(name) needs a closure", c.line) }
                let group = KTaskGroup(interp: c.interp, throwing: name.contains("Throwing"), discarding: name.contains("Discarding"))
                let s = KSuspension(.frame { KGroupFrame(group, f) })
                s.name = name
                s.line = c.line
                return .suspension(s)
            }
        }
        r.type("TaskGroup", .concurrency) { t in
            t.property("isEmpty") { c in .bool(c.object(KTaskGroup.self)?.isEmpty ?? true) }
            t.property("isCancelled") { c in .bool(c.object(KTaskGroup.self)?.isCancelled ?? false) }
            t.methods(["addTask", "addTaskUnlessCancelled"], closuresCanWait: true) { c, name in
                guard let g = c.object(KTaskGroup.self), let f = body(c) else { throw c.interp.fail("addTask needs a closure", c.line) }
                if name == "addTaskUnlessCancelled", g.isCancelled { return .bool(false) }
                g.add(f)
                return name == "addTask" ? .void : .bool(true)
            }
            t.method("next", async: true) { c in
                guard let g = c.object(KTaskGroup.self) else { throw c.noMember() }
                return endAsNil { g.next() }
            }
            t.method("waitForAll", async: true) { c in
                guard let g = c.object(KTaskGroup.self) else { throw c.noMember() }
                return .suspension(g.waitForAll(rethrowing: g.throwing))
            }
            t.method("cancelAll") { c in c.object(KTaskGroup.self)?.cancelAll(); return .void }
        }
    }

    /// `next()` returns nil at the end.
    @MainActor static func endAsNil(_ next: @escaping @MainActor () -> KSuspension) -> KV {
        .suspension(KSuspension.callback { ctx, resume in
            let inner = next()
            guard case .native(let start) = inner.work else { return nil }
            return start(ctx) { r in
                if case .success(let v) = r, KAsync.isEnd(v) { resume(.success(.nilValue)) } else { resume(r) }
            }
        })
    }

    // MARK: Streams

    static func streams(_ r: KRegistry) {
        for name in ["AsyncStream", "AsyncThrowingStream"] {
            r.type(name, .concurrency, notes: name == "AsyncStream" ? "`yield`, `finish`, `onTermination` and `makeStream()`." : nil) { t in
                t.initializer { c in
                    guard let f = body(c) else { throw c.interp.fail("Cannot find '\(name)' in scope", c.line) }
                    let ch = KAsyncChannel(interp: c.interp)
                    c.interp.perform(f, [.native(.object("AsyncStream.Continuation", KRef(ch)))])
                    return .native(.object("AsyncStream", KRef(ch)))
                }
                t.staticMethod("makeStream") { c in
                    let ch = KAsyncChannel(interp: c.interp)
                    return .tuple([.native(.object("AsyncStream", KRef(ch))), .native(.object("AsyncStream.Continuation", KRef(ch)))],
                                  ["stream", "continuation"])
                }
                if name == "AsyncStream" {
                    t.method("makeAsyncIterator") { c in
                        guard let ch = c.object(KAsyncChannel.self) else { throw c.noMember() }
                        return .native(.object("AsyncIterator", KRef(ch.iterator())))
                    }
                }
            }
        }
        r.type("AsyncStream.Continuation", .concurrency) { t in
            t.method("yield") { c in
                guard let ch = c.object(KAsyncChannel.self) else { throw c.noMember() }
                ch.yield(c.first ?? .void)
                return .void
            }
            t.method("finish") { c in
                guard let ch = c.object(KAsyncChannel.self) else { throw c.noMember() }
                if let e = c.arg("throwing"), !e.isNil { ch.finish(throwing: KEThrown(value: e)) } else { ch.finish() }
                return .void
            }
            t.property("onTermination", { _ in .nilValue }, set: { c in
                guard let ch = c.object(KAsyncChannel.self) else { return }
                if case .function(let f)? = c.first { ch.onTermination = f } else { ch.onTermination = nil }
            })
        }
        r.type("AsyncIterator", .concurrency) { t in
            t.internal()
            t.method("next", async: true) { c in
                guard let it = c.object(KAsyncIterator.self) else { throw c.noMember() }
                return endAsNil { it.next() }
            }
        }
    }
}
