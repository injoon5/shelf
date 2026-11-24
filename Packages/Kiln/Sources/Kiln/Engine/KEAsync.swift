//
//  KEAsync.swift
//  Kiln's engine
//
//  Code that can wait (PLAN.md §1.3).
//
//  Code with no `await` in it runs on the tree-walker as before, straight
//  through, on the Swift stack. A function or closure whose body has an
//  `await` runs here instead, as a task: a stack of frames on the heap
//  (`KFrame`), each a small state machine over one statement or expression.
//  A frame steps until it needs a child frame, finishes, or waits on a
//  `KSuspension`; when the suspension can't answer at once, the task parks
//  with its frames intact and resumes on the main actor when it does. Code
//  without an `await` inside a waiting function still runs on the
//  tree-walker, a statement at a time.
//
//  Everything runs on the main actor, like a SwiftUI app's own code. There is
//  no parallelism: tasks take turns at their `await`s.
//
//  - Calling a function or closure that has an `await` doesn't run it: it
//    returns a suspension (`.native(.suspension)`) that `await` runs, in the
//    awaiting task's own frames. So `body`, computed properties, `init` and
//    any other code the tree-walker runs can't wait; an `await` there is an
//    error with its line, and a call that needed `await` says so.
//  - Natives that wait (`Task.sleep`, `URLSession.data`, a continuation, the
//    next element of a stream) return a `KSuspension`. §1.4's type bridges
//    return one from an `async` method; see `KSuspension.async`.
//  - The step budget (`fuel`) is reset at the start of each stretch between
//    two waits, so a task that waits between steps runs forever and a loop
//    that never waits is still stopped, with its line.
//  - `validate` runs headless: sleeps return at once, the network fails at
//    once (unless the host answers), and the tasks the probe starts are
//    driven to completion before it returns, then torn down.
//

import SwiftUI

// MARK: - Suspensions (the API for natives that wait)

/// What `await` waits on. Natives that wait return one wrapped in a value,
/// `.native(.suspension(KRef(s)))` (see `KV.suspension`).
@MainActor
final class KSuspension {
    /// Called once, on the main actor, now or later, with the result.
    typealias Resume = @MainActor (Result<KV, Error>) -> Void
    /// Stops the work when the waiting task is cancelled or torn down. It
    /// should still resume (usually with `KAsync.cancellationError`).
    typealias Cancel = @MainActor () -> Void

    enum Work {
        /// Native work: start it, and resume when it's done. The context says
        /// which task waits and whether the run is headless.
        case native(@MainActor (KSuspendContext, @escaping Resume) -> Cancel?)
        /// Interpreted work: the waiting task runs this frame itself (a call to
        /// the app's own `async` function or closure, a task group's body).
        case frame(@MainActor () throws -> KFrame)
    }

    let work: Work
    /// For messages: the function this is a deferred call to, and its line.
    var name: String = "this"
    var line: Int = 0

    init(_ work: Work) { self.work = work }

    var isCall: Bool { if case .frame = work { return true }; return false }

    /// Native `async` work, run in a Swift task on the main actor. Cancelling
    /// the app's task cancels that Swift task, so `Task.sleep`, `URLSession`
    /// and the like throw `CancellationError` as they would in compiled code.
    /// `headless` is what `Kiln.validate` gets instead of waiting; nil means
    /// the check stops following the task there.
    static func async(headless: (@MainActor () throws -> KV)? = nil,
                      _ op: @escaping @MainActor () async throws -> KV) -> KSuspension {
        KSuspension(.native { ctx, resume in
            if ctx.interp.headless {
                // A check never does the real thing: it gets the stand-in, or stops here.
                if let headless { resume(Result { try headless() }) }
                return nil
            }
            let work = Task { @MainActor in
                do { resume(.success(try await op())) } catch { resume(.failure(error)) }
            }
            return { work.cancel() }
        })
    }

    /// Callback-style native work: `start` gets `resume` and returns how to
    /// cancel, if it can be.
    static func callback(_ start: @escaping @MainActor (_ ctx: KSuspendContext, _ resume: @escaping Resume) -> Cancel?) -> KSuspension {
        KSuspension(.native(start))
    }

    /// Already done.
    static func done(_ result: Result<KV, Error>) -> KSuspension {
        KSuspension(.native { _, resume in resume(result); return nil })
    }
}

extension KSuspension: Hashable {
    nonisolated static func == (a: KSuspension, b: KSuspension) -> Bool { a === b }
    nonisolated func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }
}

/// Who is waiting.
@MainActor
struct KSuspendContext {
    let interp: KInterpreter
    let task: KTask
}

extension KV {
    /// A value that `await` waits on.
    @MainActor static func suspension(_ s: KSuspension) -> KV { .native(.suspension(s)) }

    var asSuspension: KSuspension? {
        if case .native(.suspension(let s)) = self { return s }
        return nil
    }
}

// MARK: - Async sequences (`for await`)

/// Something `for await` can loop over. Bridges make one from a native
/// `AsyncSequence` with `KAsyncSequence.wrapping`.
@MainActor
final class KAsyncSequence {
    let name: String
    let makeIterator: @MainActor () -> KAsyncIterator
    init(name: String, makeIterator: @escaping @MainActor () -> KAsyncIterator) {
        self.name = name
        self.makeIterator = makeIterator
    }

    /// A native sequence: one Swift task reads it and hands each element,
    /// converted, to the loop. The loop ending or the task being cancelled
    /// cancels the reader.
    static func wrapping<S: AsyncSequence>(_ name: String, _ sequence: S,
                                           _ convert: @escaping @MainActor (S.Element) -> KV) -> KAsyncSequence {
        let box = KUnsafeSendable(sequence)
        return KAsyncSequence(name: name) {
            let channel = KAsyncChannel(interp: nil)
            let reader = Task { @MainActor in
                do {
                    for try await element in box.value { channel.yield(convert(element)) }
                    channel.finish()
                } catch {
                    channel.finish(throwing: error)
                }
            }
            channel.onStop = { reader.cancel() }
            return channel.iterator()
        }
    }
}

/// A native value `for await` loops over itself (`URLSession.AsyncBytes`),
/// which also has members of its own (`.lines`).
@MainActor
protocol KAsyncLoopable: AnyObject {
    func makeAsyncIterator() -> KAsyncIterator
}

/// One loop over a sequence.
@MainActor
final class KAsyncIterator {
    /// Resolves to the next element, or `KAsync.end`.
    let next: @MainActor () -> KSuspension
    /// The loop is over (finished, broke out, threw, or its task stopped).
    let stop: @MainActor () -> Void
    init(next: @escaping @MainActor () -> KSuspension, stop: @escaping @MainActor () -> Void = {}) {
        self.next = next
        self.stop = stop
    }
}

/// A buffer between producers and one consumer: `AsyncStream`, and native
/// sequences read by a Swift task.
@MainActor
final class KAsyncChannel {
    private var buffer: [KV] = []
    private(set) var finished = false
    private var failure: Error?
    private var waiter: KSuspension.Resume?
    weak var interp: KInterpreter?
    /// `continuation.onTermination`, called once with `.finished` or `.cancelled`.
    var onTermination: KFunction?
    /// Native cleanup when the stream ends.
    var onStop: (@MainActor () -> Void)?

    init(interp: KInterpreter?) { self.interp = interp }

    func yield(_ v: KV) {
        guard !finished else { return }
        if let w = waiter { waiter = nil; w(.success(v)) } else { buffer.append(v) }
    }

    func finish(throwing error: Error? = nil) {
        guard !finished else { return }
        finished = true
        failure = error
        if let w = waiter {
            waiter = nil
            if let error { failure = nil; w(.failure(error)) } else { w(.success(KAsync.end)) }
        }
        terminate("finished")
    }

    /// The consumer is gone: drop what's buffered and stop the producer.
    func cancel() {
        guard !finished else { return }
        finished = true
        buffer = []
        if let w = waiter { waiter = nil; w(.success(KAsync.end)) }
        terminate("cancelled")
    }

    private func terminate(_ reason: String) {
        onStop?(); onStop = nil
        if let f = onTermination, let interp {
            onTermination = nil
            interp.perform(f, [.native(.implicit(reason, []))])
        }
    }

    func iterator() -> KAsyncIterator {
        KAsyncIterator(next: { [self] in
            KSuspension.callback { _, resume in
                if !self.buffer.isEmpty { resume(.success(self.buffer.removeFirst())); return nil }
                if self.finished {
                    if let f = self.failure { self.failure = nil; resume(.failure(f)) } else { resume(.success(KAsync.end)) }
                    return nil
                }
                self.waiter = resume
                return { [weak self] in self?.cancel() }
            }
        }, stop: { [weak self] in self?.cancel() })
    }
}

/// Lets a value cross into a `@Sendable` closure. Kiln's values only ever
/// live on the main actor; this is for the hops Swift can't see that in.
struct KUnsafeSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

// MARK: - Tasks

/// A running piece of the app's code that can wait: a `Task {}`, a `.task {}`,
/// an `async let`, a task group's child. Its frames live on the heap.
@MainActor
final class KTask {
    enum State { case ready, running, parked, done }

    let id: Int
    var frames: [KFrame] = []
    var state: State = .ready
    private(set) var isCancelled = false
    /// What the top frame gets when the task next runs (a resumed suspension).
    var pending: KCompletion?
    /// Stops what the task is waiting on.
    var canceller: KSuspension.Cancel?
    var result: KCompletion?
    /// Called with the result when the task ends (`task.value`, `async let`,
    /// a task group, `.task {}`).
    var waiters: [@MainActor (KCompletion) -> Void] = []
    /// Report an error the task ends with (a `Task {}` nobody awaits), as
    /// Kiln always has. Children hand theirs to whoever awaits them.
    var reportsErrors = true
    var children: [KTask] = []
    /// Interpreted calls deep right now.
    var depth = 0
    /// Times resumed in a headless run, to stop an endless loop that waits.
    var headlessResumes = 0

    init(id: Int) { self.id = id }

    func cancel() {
        guard state != .done, !isCancelled else { return }
        isCancelled = true
        if let c = canceller { canceller = nil; c() }
        for child in children { child.cancel() }
    }

    /// Waits for the task from native code (`.task {}`, `.refreshable {}`,
    /// later §1.5's proxies).
    func completion() async -> KCompletion {
        if let result { return result }
        return await withCheckedContinuation { (k: CheckedContinuation<KCompletion, Never>) in
            let box = KUnsafeSendable(k)
            waiters.append { c in box.value.resume(returning: c) }
        }
    }
}

/// How a frame ends, or what it hands its parent.
enum KCompletion {
    case value(KV)
    case flow(KFlow)
    case error(Error)
}

/// What a frame asks for after a step.
@MainActor
enum KStep {
    /// Run this child; its completion comes back as the next input.
    case push(KFrame)
    /// This frame is finished.
    case done(KCompletion)
    /// Wait for this; its result comes back as the next input.
    case wait(KSuspension)
}

/// One activation on a task's heap stack.
@MainActor
class KFrame {
    /// The declared return type of the function this frame is in (`return .red`).
    var returnType: KETypeRef?
    /// A function or closure body: counted for recursion, and where the
    /// return type changes.
    var isFunction: Bool { false }
    /// Gets errors as input instead of being unwound past (`do`/`catch`, `try?`).
    var handlesErrors: Bool { false }
    /// The line errors raised here without one are given.
    var line: Int { 0 }

    /// `input` is nil the first time, then the completion of what the frame
    /// last asked for.
    func step(_ x: KInterpreter, _ input: KCompletion?) throws -> KStep { .done(.flow(.normal)) }
    /// The frame is leaving the stack with `c` (run `defer`s).
    func popped(_ x: KInterpreter, _ c: KCompletion) -> KCompletion { c }
}

enum KAsync {
    /// The end of an async sequence (`next()` returning nil).
    @MainActor static let end: KV = .native(.object("AsyncSequenceEnd", KRef(NSObject())))
    @MainActor static func isEnd(_ v: KV) -> Bool { v == end }

    static let cancellationMessage = "The operation couldn\u{2019}t be completed. (Swift.CancellationError error 1.)"
    @MainActor static var cancellationValue: KV {
        .native(.object("Error", KRef(NSError(domain: "Swift.CancellationError", code: 1,
                                               userInfo: [NSLocalizedDescriptionKey: cancellationMessage]))))
    }
    @MainActor static var cancellationError: Error { KEThrown(value: cancellationValue) }

    @MainActor static func isCancellation(_ e: Error) -> Bool {
        if e is CancellationError { return true }
        if let t = e as? KEThrown, case .native(.object("Error", let ref)) = t.value {
            return (ref.value as? NSError)?.domain == "Swift.CancellationError"
        }
        return false
    }

    /// A native error as the app's code sees it: a thrown `Error` value.
    @MainActor static func appError(_ e: Error) -> Error {
        switch e {
        case is KEThrown, is KERuntimeError: return e
        case is CancellationError: return cancellationError
        case let u as URLError where u.code == .cancelled: return cancellationError
        default: return KEThrown(value: KBuiltins.errorValue((e as NSError).localizedDescription))
        }
    }
}

// MARK: - Which code waits

/// Finds `await` in a body or an expression, stopping at closures (a closure
/// is its own function). For `for await`, the parser wraps the sequence in an
/// `awaitExpr`.
enum KAwaitScan {
    static func stmts(_ s: [KEStmt]) -> Bool { s.contains(where: stmt) }

    static func stmt(_ s: KEStmt) -> Bool {
        switch s {
        case .expr(let e): return expr(e)
        case .variable(let d): return d.isAsyncLet || (d.initial.map(expr) ?? false)
        case .assign(_, let t, let v, _): return expr(t) || expr(v)
        case .ifStmt(let c, let t, let e): return conds(c) || stmts(t) || elseClause(e)
        case .guardStmt(let c, let b): return conds(c) || stmts(b)
        case .switchStmt(let subject, let cases):
            return expr(subject) || cases.contains { c in
                stmts(c.body) || c.patterns.contains { pattern($0.0) || ($0.1.map(expr) ?? false) }
            }
        case .forIn(let p, let seq, let w, let body, _): return pattern(p) || expr(seq) || (w.map(expr) ?? false) || stmts(body)
        case .whileStmt(let c, let b, _): return conds(c) || stmts(b)
        case .repeatWhile(let b, let c, _): return stmts(b) || expr(c)
        case .returnStmt(let e, _): return e.map(expr) ?? false
        case .throwStmt(let e): return expr(e)
        case .doCatch(let b, let cs): return stmts(b) || cs.contains { stmts($0.body) }
        case .deferStmt, .declaration, .breakStmt, .continueStmt, .fallthroughStmt: return false
        }
    }

    static func elseClause(_ e: KEElse?) -> Bool {
        switch e {
        case .block(let b)?: return stmts(b)
        case .elseIf(let s)?: return stmt(s)
        case nil: return false
        }
    }

    static func conds(_ cs: [KECondition]) -> Bool { cs.contains(where: cond) }

    static func cond(_ c: KECondition) -> Bool {
        switch c {
        case .expr(let e), .optionalBinding(_, let e): return expr(e)
        case .casePattern(let p, let e): return pattern(p) || expr(e)
        case .available: return false
        }
    }

    static func pattern(_ p: KEPattern) -> Bool {
        switch p {
        case .expression(let e): return expr(e)
        case .tuple(let ps): return ps.contains(where: pattern)
        case .enumCase(_, _, let ps): return ps.contains(where: pattern)
        case .optional(let q), .cast(let q, _): return pattern(q)
        case .wildcard, .binding, .typeCheck: return false
        }
    }

    static func expr(_ e: KEExpr) -> Bool {
        switch e {
        case .awaitExpr: return true
        case .closure, .int, .double, .bool, .nilLit, .ident, .implicitMember, .keyPath, .selfRef, .typeExpr, .value, .regex:
            return false
        case .string(let segs):
            return segs.contains { if case .interp(let args) = $0 { return args.contains { expr($0.value) } }; return false }
        case .member(let b, _, _), .optionalChain(let b), .prefix(_, let b), .postfix(_, let b), .cast(let b, _, _), .tryExpr(_, let b):
            return expr(b)
        case .call(let c, let args, _), .subscriptAccess(let c, let args, _):
            return expr(c) || args.contains { expr($0.value) }
        case .binary(_, let l, let r, _): return expr(l) || expr(r)
        case .ternary(let a, let b, let c): return expr(a) || expr(b) || expr(c)
        case .array(let xs): return xs.contains(where: expr)
        case .dictionary(let ps): return ps.contains { expr($0.0) || expr($0.1) }
        case .tuple(let xs): return xs.contains { expr($0.1) }
        case .ifExpr(let c, let t, let f): return conds(c) || stmts(t) || stmts(f)
        case .switchExpr(let s, let cases): return expr(s) || cases.contains { stmts($0.body) }
        case .assign(_, let t, let v, _): return expr(t) || expr(v)
        }
    }

    /// The expression with each direct child passed through `f`, in the order
    /// Swift evaluates them. Only for the kinds `KExprFrame` handles generically.
    static func mapChildren(_ e: KEExpr, _ f: (KEExpr) -> KEExpr) -> KEExpr {
        func args(_ a: [KEArg]) -> [KEArg] { a.map { KEArg(label: $0.label, value: f($0.value)) } }
        switch e {
        case .member(let b, let n, let l): return .member(f(b), n, line: l)
        case .optionalChain(let b): return .optionalChain(f(b))
        case .call(let c, let a, let l): let callee = f(c); return .call(callee, args(a), line: l)
        case .subscriptAccess(let b, let a, let l): let base = f(b); return .subscriptAccess(base, args(a), line: l)
        case .prefix(let op, let x): return .prefix(op, f(x))
        case .postfix(let op, let x): return .postfix(op, f(x))
        case .binary(let op, let l, let r, let line): let a = f(l); return .binary(op, a, f(r), line: line)
        case .array(let xs): return .array(xs.map(f))
        case .dictionary(let ps): return .dictionary(ps.map { p in let k = f(p.0); return (k, f(p.1)) })
        case .tuple(let xs): return .tuple(xs.map { ($0.0, f($0.1)) })
        case .string(let segs):
            return .string(segs.map { seg in
                if case .interp(let a) = seg { return .interp(args(a)) }
                return seg
            })
        case .cast(let x, let k, let t): return .cast(f(x), k, t)
        case .assign(let op, let t, let v, let l): return .assign(op, t, f(v), line: l)
        default: return e
        }
    }
}

extension KEFuncDecl {
    /// Its body waits somewhere (not counting closures inside it).
    var awaits: Bool {
        if let cached = awaitsCache { return cached }
        let v = KAwaitScan.stmts(body)
        awaitsCache = v
        return v
    }
}

extension KEClosure {
    var awaits: Bool {
        if let cached = awaitsCache { return cached }
        let v = KAwaitScan.stmts(body)
        awaitsCache = v
        return v
    }
}

extension KEVarDecl {
    /// `async let`.
    var isAsyncLet: Bool { attributes.contains { $0.name == "asyncLet" } }
}

// MARK: - Frames

/// A function or closure body.
final class KBodyFrame: KFrame {
    let env: KEnv
    let stmts: [KEStmt]
    /// A one-expression body whose value is returned.
    let single: KEExpr?
    let declaredReturn: KETypeRef?
    let at: Int
    private var started = false

    init(env: KEnv, stmts: [KEStmt], single: KEExpr?, returns: KETypeRef?, line: Int) {
        self.env = env
        self.stmts = stmts
        self.single = single
        self.declaredReturn = returns
        self.at = line
        super.init()
        returnType = returns
    }

    override var isFunction: Bool { true }

    override func step(_ x: KInterpreter, _ input: KCompletion?) throws -> KStep {
        if !started {
            started = true
            if let e = single { return .push(KExprFrame(e, env, declaredReturn)) }
            return .push(KBlockFrame(stmts, env))
        }
        switch input {
        case .value(let v)?, .flow(.ret(let v))?: return .done(.value(x.coerce(v, to: declaredReturn)))
        case .error?: return .done(input!)
        default: return .done(.value(.void))
        }
    }
}

/// Statements in order, with their `defer`s.
final class KBlockFrame: KFrame {
    let stmts: [KEStmt]
    let env: KEnv
    private var i = 0
    private var defers: [[KEStmt]] = []

    init(_ stmts: [KEStmt], _ env: KEnv) {
        self.stmts = stmts
        self.env = env
    }

    override func step(_ x: KInterpreter, _ input: KCompletion?) throws -> KStep {
        switch input {
        case nil, .flow(.normal)?, .value?: break
        default: return .done(input!)
        }
        while i < stmts.count {
            let s = stmts[i]
            i += 1
            if case .deferStmt(let body) = s { defers.append(body); continue }
            if KAwaitScan.stmt(s) { return .push(try x.statementFrame(s, env)) }
            let f = try x.exec1(s, env)
            if case .normal = f { continue }
            return .done(.flow(f))
        }
        return .done(.flow(.normal))
    }

    override func popped(_ x: KInterpreter, _ c: KCompletion) -> KCompletion {
        for d in defers.reversed() { _ = try? x.exec(d, KEnv(parent: env)) }
        return c
    }
}

/// An expression with an `await` in it. Short-circuiting operators and `try?`
/// get their own handling; anything else evaluates the children that wait,
/// left to right, then the rest of the expression with their values in place.
final class KExprFrame: KFrame {
    enum Mode { case start, awaitOperand, awaited, tryOperand(String), andLeft, orLeft, right, coalesceLeft, ternaryCond, generic }
    let expr: KEExpr
    let env: KEnv
    let expected: KETypeRef?
    private var mode = Mode.start
    private var children: [KEExpr] = []
    private var values: [KV] = []

    init(_ expr: KEExpr, _ env: KEnv, _ expected: KETypeRef?) {
        self.expr = expr
        self.env = env
        self.expected = expected
    }

    override var line: Int { expr.line }
    override var handlesErrors: Bool { if case .tryOperand("try?") = mode { return true }; return false }

    override func step(_ x: KInterpreter, _ input: KCompletion?) throws -> KStep {
        switch mode {
        case .start:
            try x.tick()
            guard KAwaitScan.expr(expr) else { return .done(.value(try x.eval(expr, env, expected))) }
            switch expr {
            case .awaitExpr(let inner):
                mode = .awaitOperand
                return .push(KExprFrame(inner, env, expected))
            case .tryExpr(let kind, let inner):
                mode = .tryOperand(kind)
                return .push(KExprFrame(inner, env, expected))
            case .binary("&&", let l, _, _):
                mode = .andLeft
                return .push(KExprFrame(l, env, nil))
            case .binary("||", let l, _, _):
                mode = .orLeft
                return .push(KExprFrame(l, env, nil))
            case .binary("??", let l, _, _):
                mode = .coalesceLeft
                return .push(KExprFrame(l, env, expected))
            case .ternary(let c, _, _):
                mode = .ternaryCond
                return .push(KExprFrame(c, env, nil))
            case .ifExpr, .switchExpr:
                throw x.fail("'await' inside an if or switch expression isn't supported: use an if or switch statement", expr.line)
            default:
                mode = .generic
                _ = KAwaitScan.mapChildren(expr) { child in
                    if KAwaitScan.expr(child) { children.append(child) }
                    return child
                }
                return try nextChild(x)
            }

        case .awaitOperand:
            guard case .value(let v)? = input else { return .done(input!) }
            mode = .awaited
            return x.awaitStep(v)

        case .awaited, .right, .tryOperand:
            if case .tryOperand("try?") = mode, case .error(let e)? = input {
                if let rt = e as? KERuntimeError, rt.message.hasPrefix("This code ran too long") { return .done(input!) }
                return .done(.value(.nilValue))
            }
            return .done(input!)

        case .andLeft, .orLeft:
            guard case .value(let v)? = input else { return .done(input!) }
            let isAnd: Bool = { if case .andLeft = mode { return true }; return false }()
            if x.truthy(v) != isAnd { return .done(.value(.bool(!isAnd))) }
            guard case .binary(_, _, let r, _) = expr else { return .done(.value(.bool(false))) }
            mode = .right
            return .push(KTruthFrame(KExprFrame(r, env, nil)))

        case .coalesceLeft:
            guard case .value(let a)? = input else { return .done(input!) }
            if !a.isNil { return .done(.value(a)) }
            guard case .binary(_, _, let r, _) = expr else { return .done(.value(.nilValue)) }
            mode = .right
            return .push(KExprFrame(r, env, expected ?? x.typeRef(of: a)))

        case .ternaryCond:
            guard case .value(let c)? = input, case .ternary(_, let t, let f) = expr else { return .done(input!) }
            mode = .right
            return .push(KExprFrame(x.truthy(c) ? t : f, env, expected))

        case .generic:
            guard case .value(let v)? = input else { return .done(input!) }
            values.append(v)
            return try nextChild(x)
        }
    }

    private func nextChild(_ x: KInterpreter) throws -> KStep {
        if values.count < children.count { return .push(KExprFrame(children[values.count], env, nil)) }
        var k = 0
        let rewritten = KAwaitScan.mapChildren(expr) { child in
            guard KAwaitScan.expr(child) else { return child }
            defer { k += 1 }
            return .value(values[k])
        }
        return .done(.value(try x.eval(rewritten, env, expected)))
    }
}

/// `a && (await b)`: the right side as a Bool.
final class KTruthFrame: KFrame {
    let inner: KFrame
    private var started = false
    init(_ inner: KFrame) { self.inner = inner }
    override func step(_ x: KInterpreter, _ input: KCompletion?) throws -> KStep {
        if !started { started = true; return .push(inner) }
        if case .value(let v)? = input { return .done(.value(.bool(x.truthy(v)))) }
        return .done(input!)
    }
}

/// `await (a, b)` or `await [a, b]` over `async let`s: each in turn.
final class KAwaitAllFrame: KFrame {
    var items: [KV]
    let rebuild: ([KV]) -> KV
    private var i = 0
    init(_ items: [KV], _ rebuild: @escaping ([KV]) -> KV) {
        self.items = items
        self.rebuild = rebuild
    }
    override func step(_ x: KInterpreter, _ input: KCompletion?) throws -> KStep {
        if let input {
            guard case .value(let v) = input else { return .done(input) }
            items[i] = v
            i += 1
        }
        while i < items.count {
            if let s = items[i].asSuspension { return .wait(s) }
            i += 1
        }
        return .done(.value(rebuild(items)))
    }
}

/// Waits for one suspension (a task whose whole body is a native wait).
final class KWaitFrame: KFrame {
    let suspension: KSuspension
    private var started = false
    init(_ s: KSuspension) { suspension = s }
    override func step(_ x: KInterpreter, _ input: KCompletion?) throws -> KStep {
        if !started { started = true; return .wait(suspension) }
        return .done(input!)
    }
}

/// Conditions of an `if`, `guard` or `while`, binding into `env`. Ends with a Bool.
final class KCondFrame: KFrame {
    let conds: [KECondition]
    let env: KEnv
    private var i = 0
    private var pending: KECondition?

    init(_ conds: [KECondition], _ env: KEnv) {
        self.conds = conds
        self.env = env
    }

    override func step(_ x: KInterpreter, _ input: KCompletion?) throws -> KStep {
        if let c = pending, let input {
            pending = nil
            guard case .value(let v) = input else { return .done(input) }
            switch c {
            case .expr: if !x.truthy(v) { return .done(.value(.bool(false))) }
            case .optionalBinding(let p, _):
                if v.isNil { return .done(.value(.bool(false))) }
                try x.bindPattern(p, v, in: env, isLet: true, type: nil)
            case .casePattern(let p, _):
                if !(try x.match(p, v, env, binding: false)) { return .done(.value(.bool(false))) }
            case .available: break
            }
        }
        while i < conds.count {
            let c = conds[i]
            i += 1
            guard KAwaitScan.cond(c) else {
                if !(try x.conditions([c], env)) { return .done(.value(.bool(false))) }
                continue
            }
            switch c {
            case .expr(let e), .optionalBinding(_, let e):
                pending = c
                return .push(KExprFrame(e, env, nil))
            case .casePattern(let p, let e):
                if KAwaitScan.pattern(p) { throw x.fail("'await' inside a case pattern isn't supported", e.line) }
                pending = c
                return .push(KExprFrame(e, env, nil))
            case .available: continue
            }
        }
        return .done(.value(.bool(true)))
    }
}

/// `x` statement, `let`/`var`, assignment, `return` and `throw` with a wait in them.
final class KSimpleStmtFrame: KFrame {
    let stmt: KEStmt
    let env: KEnv
    private var started = false

    init(_ stmt: KEStmt, _ env: KEnv) {
        self.stmt = stmt
        self.env = env
    }

    override var line: Int {
        switch stmt {
        case .expr(let e), .throwStmt(let e): return e.line
        case .assign(_, _, _, let l), .returnStmt(_, let l): return l
        case .variable(let d): return d.line
        default: return 0
        }
    }

    override func step(_ x: KInterpreter, _ input: KCompletion?) throws -> KStep {
        if !started {
            started = true
            switch stmt {
            case .expr(let e): return .push(KExprFrame(e, env, nil))
            case .variable(let d):
                if d.isAsyncLet { try x.asyncLet(d, env); return .done(.flow(.normal)) }
                guard let initial = d.initial else { return .done(.flow(.normal)) }
                return .push(KExprFrame(initial, env, d.type))
            case .assign(_, let target, let value, let line):
                if KAwaitScan.expr(target) { throw x.fail("'await' on the left of an assignment isn't supported", line) }
                return .push(KExprFrame(value, env, nil))
            case .returnStmt(let e, _):
                guard let e else { return .done(.flow(.ret(.void))) }
                return .push(KExprFrame(e, env, returnType))
            case .throwStmt(let e): return .push(KExprFrame(e, env, nil))
            default: return .done(.flow(.normal))
            }
        }
        guard case .value(let v)? = input else { return .done(input!) }
        switch stmt {
        case .expr(let e):
            try x.checkAwaited(v, e.line)
            return .done(.flow(.normal))
        case .variable(let d):
            try x.bindPattern(d.pattern, v, in: env, isLet: d.isLet, type: d.type)
            return .done(.flow(.normal))
        case .assign(let op, let target, _, let line):
            try x.assign(op, target, .value(v), env, line)
            return .done(.flow(.normal))
        case .returnStmt: return .done(.flow(.ret(v)))
        case .throwStmt: return .done(.error(KEThrown(value: v)))
        default: return .done(.flow(.normal))
        }
    }
}

final class KIfFrame: KFrame {
    let conds: [KECondition]
    let then: [KEStmt]
    let otherwise: KEElse?
    let env: KEnv
    let scope: KEnv
    private var phase = 0

    init(_ conds: [KECondition], _ then: [KEStmt], _ otherwise: KEElse?, _ env: KEnv) {
        self.conds = conds
        self.then = then
        self.otherwise = otherwise
        self.env = env
        self.scope = KEnv(parent: env)
    }

    override func step(_ x: KInterpreter, _ input: KCompletion?) throws -> KStep {
        switch phase {
        case 0:
            phase = 1
            return .push(KCondFrame(conds, scope))
        case 1:
            guard case .value(let b)? = input else { return .done(input!) }
            phase = 2
            if x.truthy(b) { return .push(KBlockFrame(then, scope)) }
            switch otherwise {
            case .block(let body)?: return .push(KBlockFrame(body, KEnv(parent: env)))
            case .elseIf(let s)?:
                if KAwaitScan.stmt(s) { return .push(try x.statementFrame(s, env)) }
                return .done(.flow(try x.exec1(s, env)))
            case nil: return .done(.flow(.normal))
            }
        default:
            return .done(input!)
        }
    }
}

final class KGuardFrame: KFrame {
    let conds: [KECondition]
    let body: [KEStmt]
    let env: KEnv
    private var phase = 0

    init(_ conds: [KECondition], _ body: [KEStmt], _ env: KEnv) {
        self.conds = conds
        self.body = body
        self.env = env
    }

    override func step(_ x: KInterpreter, _ input: KCompletion?) throws -> KStep {
        switch phase {
        case 0:
            phase = 1
            return .push(KCondFrame(conds, env))
        case 1:
            guard case .value(let b)? = input else { return .done(input!) }
            if x.truthy(b) { return .done(.flow(.normal)) }
            phase = 2
            return .push(KBlockFrame(body, KEnv(parent: env)))
        default:
            return .done(input!)
        }
    }
}

final class KSwitchFrame: KFrame {
    let subject: KEExpr
    let cases: [KESwitchCase]
    let env: KEnv
    private var value: KV?
    private var next = 0
    private var falling = false

    init(_ subject: KEExpr, _ cases: [KESwitchCase], _ env: KEnv) {
        self.subject = subject
        self.cases = cases
        self.env = env
    }

    override func step(_ x: KInterpreter, _ input: KCompletion?) throws -> KStep {
        guard let value else {
            if input == nil { return .push(KExprFrame(subject, env, nil)) }
            guard case .value(let v)? = input else { return .done(input!) }
            self.value = v
            return try nextCase(x, v)
        }
        switch input {
        case .flow(.fall)?:
            falling = true
            return try nextCase(x, value)
        case .flow(.brk(nil))?: return .done(.flow(.normal))
        default: return .done(input!)
        }
    }

    private func nextCase(_ x: KInterpreter, _ value: KV) throws -> KStep {
        while next < cases.count {
            let c = cases[next]
            next += 1
            let scope = KEnv(parent: env)
            var hit = falling || c.isDefault
            if !hit {
                for (pattern, whereClause) in c.patterns {
                    let trial = KEnv(parent: env)
                    if try x.match(pattern, value, trial, binding: false),
                       try whereClause.map({ x.truthy(try x.eval($0, trial)) }) ?? true {
                        scope.vars = trial.vars
                        hit = true
                        break
                    }
                }
            }
            guard hit else { continue }
            falling = false
            return .push(KBlockFrame(c.body, scope))
        }
        return .done(.flow(.normal))
    }
}

/// `for x in items` with a wait in the sequence or the body.
final class KForFrame: KFrame {
    let pattern: KEPattern
    let seq: KEExpr
    let whereClause: KEExpr?
    let body: [KEStmt]
    let label: String?
    let env: KEnv
    private var items: [KV]?
    private var i = 0

    init(_ pattern: KEPattern, _ seq: KEExpr, _ whereClause: KEExpr?, _ body: [KEStmt], _ label: String?, _ env: KEnv) {
        self.pattern = pattern
        self.seq = seq
        self.whereClause = whereClause
        self.body = body
        self.label = label
        self.env = env
    }

    override func step(_ x: KInterpreter, _ input: KCompletion?) throws -> KStep {
        if items == nil {
            if input == nil { return .push(KExprFrame(seq, env, nil)) }
            guard case .value(let v)? = input else { return .done(input!) }
            items = try x.sequence(v)
            return try nextItem(x)
        }
        switch input {
        case .flow(.brk(let l))? where l == nil || l == label: return .done(.flow(.normal))
        case .flow(.cont(let l))? where l == nil || l == label: return try nextItem(x)
        case .flow(.normal)?: return try nextItem(x)
        default: return .done(input!)
        }
    }

    private func nextItem(_ x: KInterpreter) throws -> KStep {
        while let items, i < items.count {
            try x.tick()
            let item = items[i]
            i += 1
            let scope = KEnv(parent: env)
            guard try x.match(pattern, item, scope, binding: true) else { continue }
            if let w = whereClause, !x.truthy(try x.eval(w, scope)) { continue }
            return .push(KBlockFrame(body, scope))
        }
        return .done(.flow(.normal))
    }
}

/// `for await x in sequence` (and `for try await`).
final class KForAwaitFrame: KFrame {
    let pattern: KEPattern
    let seq: KEExpr
    let whereClause: KEExpr?
    let body: [KEStmt]
    let label: String?
    let env: KEnv
    private var iterator: KAsyncIterator?
    private var waiting = false

    init(_ pattern: KEPattern, _ seq: KEExpr, _ whereClause: KEExpr?, _ body: [KEStmt], _ label: String?, _ env: KEnv) {
        self.pattern = pattern
        self.seq = seq
        self.whereClause = whereClause
        self.body = body
        self.label = label
        self.env = env
    }

    override var line: Int { seq.line }

    override func step(_ x: KInterpreter, _ input: KCompletion?) throws -> KStep {
        guard let iterator else {
            if input == nil { return .push(KExprFrame(seq, env, nil)) }
            guard case .value(let v)? = input else { return .done(input!) }
            let it = try x.asyncIterator(v, seq.line)
            iterator = it
            waiting = true
            return .wait(it.next())
        }
        if waiting {
            waiting = false
            guard case .value(let element)? = input else { return .done(input!) }
            if KAsync.isEnd(element) { return .done(.flow(.normal)) }
            try x.tick()
            let scope = KEnv(parent: env)
            guard try x.match(pattern, element, scope, binding: true),
                  try whereClause.map({ x.truthy(try x.eval($0, scope)) }) ?? true else {
                waiting = true
                return .wait(iterator.next())
            }
            return .push(KBlockFrame(body, scope))
        }
        switch input {
        case .flow(.brk(let l))? where l == nil || l == label: return .done(.flow(.normal))
        case .flow(.cont(let l))? where l == nil || l == label: break
        case .flow(.normal)?: break
        default: return .done(input!)
        }
        waiting = true
        return .wait(iterator.next())
    }

    override func popped(_ x: KInterpreter, _ c: KCompletion) -> KCompletion {
        iterator?.stop()
        return c
    }
}

final class KWhileFrame: KFrame {
    let conds: [KECondition]
    let body: [KEStmt]
    let label: String?
    let env: KEnv
    private var inBody = false
    private var scope: KEnv

    init(_ conds: [KECondition], _ body: [KEStmt], _ label: String?, _ env: KEnv) {
        self.conds = conds
        self.body = body
        self.label = label
        self.env = env
        self.scope = env
    }

    override func step(_ x: KInterpreter, _ input: KCompletion?) throws -> KStep {
        if let input {
            if inBody {
                switch input {
                case .flow(.brk(let l)) where l == nil || l == label: return .done(.flow(.normal))
                case .flow(.cont(let l)) where l == nil || l == label: break
                case .flow(.normal): break
                default: return .done(input)
                }
            } else {
                guard case .value(let b) = input else { return .done(input) }
                if !x.truthy(b) { return .done(.flow(.normal)) }
                inBody = true
                return .push(KBlockFrame(body, scope))
            }
        }
        try x.tick()
        inBody = false
        scope = KEnv(parent: env)
        return .push(KCondFrame(conds, scope))
    }
}

final class KRepeatFrame: KFrame {
    let body: [KEStmt]
    let cond: KEExpr
    let label: String?
    let env: KEnv
    private var inBody = false

    init(_ body: [KEStmt], _ cond: KEExpr, _ label: String?, _ env: KEnv) {
        self.body = body
        self.cond = cond
        self.label = label
        self.env = env
    }

    override func step(_ x: KInterpreter, _ input: KCompletion?) throws -> KStep {
        if let input {
            if inBody {
                switch input {
                case .flow(.brk(let l)) where l == nil || l == label: return .done(.flow(.normal))
                case .flow(.cont(let l)) where l == nil || l == label: break
                case .flow(.normal): break
                default: return .done(input)
                }
                inBody = false
                return .push(KExprFrame(cond, env, nil))
            }
            guard case .value(let c) = input else { return .done(input) }
            if !x.truthy(c) { return .done(.flow(.normal)) }
        }
        try x.tick()
        inBody = true
        return .push(KBlockFrame(body, KEnv(parent: env)))
    }
}

final class KDoCatchFrame: KFrame {
    let body: [KEStmt]
    let catches: [KECatch]
    let env: KEnv
    private var phase = 0

    init(_ body: [KEStmt], _ catches: [KECatch], _ env: KEnv) {
        self.body = body
        self.catches = catches
        self.env = env
    }

    override var handlesErrors: Bool { phase == 1 }

    override func step(_ x: KInterpreter, _ input: KCompletion?) throws -> KStep {
        switch phase {
        case 0:
            phase = 1
            return .push(KBlockFrame(body, KEnv(parent: env)))
        case 1:
            phase = 2
            guard case .error(let err)? = input else { return .done(input!) }
            let caught: KV
            if let thrown = err as? KEThrown { caught = thrown.value }
            else if let rt = err as? KERuntimeError, !catches.isEmpty, !rt.message.hasPrefix("This code ran too long") {
                caught = KBuiltins.errorValue(rt.message)
            } else { return .done(input!) }
            guard let c = catches.first else { return .done(input!) }
            let scope = KEnv(parent: env)
            if case .binding(let n, _)? = c.pattern { scope.declare(n, caught) } else { scope.declare("error", caught) }
            return .push(KBlockFrame(c.body, scope))
        default:
            return .done(input!)
        }
    }
}

/// `withTaskGroup { group in … }`: the body, then whatever children are left.
final class KGroupFrame: KFrame {
    let group: KTaskGroup
    let body: KFunction
    private var phase = 0
    private var bodyResult: KCompletion?

    init(_ group: KTaskGroup, _ body: KFunction) {
        self.group = group
        self.body = body
    }

    override var handlesErrors: Bool { phase == 1 }

    override func step(_ x: KInterpreter, _ input: KCompletion?) throws -> KStep {
        switch phase {
        case 0:
            phase = 1
            group.owner = x.currentTask
            return .push(try x.callFrame(body, [.native(.object("TaskGroup", KRef(group)))], [nil]))
        case 1:
            phase = 2
            bodyResult = input
            if case .error? = input { group.cancelAll() }
            return .wait(group.waitForAll(rethrowing: false))
        default:
            if case .value? = bodyResult, group.discarding, let e = group.firstError { return .done(.error(e)) }
            return .done(bodyResult ?? .value(.void))
        }
    }
}

// MARK: - Task groups

@MainActor
final class KTaskGroup {
    let throwing: Bool
    let discarding: Bool
    weak var interp: KInterpreter?
    weak var owner: KTask?
    private var running: [KTask] = []
    private var completed: [KCompletion] = []
    private var waiter: KSuspension.Resume?
    private var allDone: [KSuspension.Resume] = []
    private(set) var firstError: Error?
    private(set) var isCancelled = false

    init(interp: KInterpreter, throwing: Bool, discarding: Bool) {
        self.interp = interp
        self.throwing = throwing
        self.discarding = discarding
    }

    var isEmpty: Bool { running.isEmpty && completed.isEmpty }

    func add(_ f: KFunction) {
        guard let interp else { return }
        let child = interp.startTask(f, [], parent: owner ?? interp.currentTask, reportsErrors: false)
        if isCancelled { child.cancel() }
        running.append(child)
        child.waiters.append { [weak self, weak child] c in
            guard let self, let child else { return }
            self.running.removeAll { $0 === child }
            if case .error(let e) = c, self.firstError == nil, !KAsync.isCancellation(e) || self.throwing {
                self.firstError = e
                if self.discarding && self.throwing { self.cancelAll() }
            }
            if !self.discarding { self.completed.append(c) }
            if let w = self.waiter, !self.completed.isEmpty { self.waiter = nil; w(self.takeNext()) }
            else if let w = self.waiter, self.running.isEmpty { self.waiter = nil; w(.success(KAsync.end)) }
            if self.running.isEmpty {
                let ws = self.allDone
                self.allDone = []
                for w in ws { w(.success(.void)) }
            }
        }
    }

    private func takeNext() -> Result<KV, Error> {
        switch completed.removeFirst() {
        case .value(let v): return .success(v)
        case .error(let e): return throwing ? .failure(e) : .success(.void)
        case .flow: return .success(.void)
        }
    }

    func cancelAll() {
        isCancelled = true
        for t in running { t.cancel() }
    }

    /// The next child's result, in the order they finish; `KAsync.end` when none are left.
    func next() -> KSuspension {
        KSuspension.callback { [self] _, resume in
            if !completed.isEmpty { resume(takeNext()); return nil }
            if running.isEmpty { resume(.success(KAsync.end)); return nil }
            waiter = resume
            return nil
        }
    }

    func waitForAll(rethrowing: Bool) -> KSuspension {
        KSuspension.callback { [self] _, resume in
            let finish: KSuspension.Resume = { [weak self] _ in
                if rethrowing, let e = self?.firstError { resume(.failure(e)) } else { resume(.success(.void)) }
            }
            if running.isEmpty { finish(.success(.void)); return nil }
            allDone.append(finish)
            return nil
        }
    }
}

/// `withCheckedContinuation`'s continuation: resumes the waiting task once.
@MainActor
final class KContinuation {
    private var resume: KSuspension.Resume?
    init(_ resume: @escaping KSuspension.Resume) { self.resume = resume }
    func complete(_ r: Result<KV, Error>) {
        guard let resume else { return }
        self.resume = nil
        resume(r)
    }
}

// MARK: - The driver

extension KInterpreter {
    /// The frame for a statement that waits.
    func statementFrame(_ s: KEStmt, _ env: KEnv) throws -> KFrame {
        switch s {
        case .expr, .variable, .assign, .returnStmt, .throwStmt:
            return KSimpleStmtFrame(s, env)
        case .ifStmt(let c, let t, let e): return KIfFrame(c, t, e, env)
        case .guardStmt(let c, let b): return KGuardFrame(c, b, env)
        case .switchStmt(let subject, let cases): return KSwitchFrame(subject, cases, env)
        case .forIn(let p, let seq, let w, let body, let label):
            if case .awaitExpr(let inner) = seq { return KForAwaitFrame(p, inner, w, body, label, env) }
            return KForFrame(p, seq, w, body, label, env)
        case .whileStmt(let c, let b, let label): return KWhileFrame(c, b, label, env)
        case .repeatWhile(let b, let c, let label): return KRepeatFrame(b, c, label, env)
        case .doCatch(let b, let cs): return KDoCatchFrame(b, cs, env)
        case .deferStmt, .declaration, .breakStmt, .continueStmt, .fallthroughStmt:
            throw fail("Kiln can't wait inside this statement")
        }
    }

    /// The step `await v` takes: wait if it's a suspension, else go on.
    func awaitStep(_ v: KV) -> KStep {
        if let s = v.asSuspension { return .wait(s) }
        switch v {
        case .tuple(let items, let labels) where items.contains(where: { $0.asSuspension != nil }):
            return .push(KAwaitAllFrame(items) { .tuple($0, labels) })
        case .array(let items) where items.contains(where: { $0.asSuspension != nil }):
            return .push(KAwaitAllFrame(items) { .array($0) })
        default:
            return .done(.value(v))
        }
    }

    /// An expression statement's value: a call that needed `await` says so.
    func checkAwaited(_ v: KV, _ line: Int) throws {
        guard let s = v.asSuspension else { return }
        if s.isCall {
            throw fail("'\(s.name)' is async: call it with 'await', inside Task { … }, .task { … } or another async function", line)
        }
        throw fail("This is async: use 'await' inside Task { … }, .task { … } or an async function", line)
    }

    /// The frame a call to `f` runs in, its parameters bound.
    func callFrame(_ f: KFunction, _ args: [KV], _ labels: [String?]) throws -> KFrame {
        switch f.kind {
        case .closure(let c, let captured):
            let env = KEnv(parent: captured)
            bindClosureParams(c, args, env)
            var single: KEExpr?
            if c.body.count == 1, case .expr(let e) = c.body[0] { single = e }
            return KBodyFrame(env: env, stmts: c.body, single: single, returns: nil, line: c.line)
        case .user(let decl, let parent, let ctx):
            return try userFrame(decl, args: args, labels: labels, selfContext: ctx, parent: parent)
        case .native(_, let fn):
            let v = try fn(args, labels)
            if let s = v.asSuspension { return KWaitFrame(s) }
            return KWaitFrame(.done(.success(v)))
        }
    }

    func userFrame(_ decl: KEFuncDecl, args: [KV], labels: [String?], selfContext: KSelfContext?, parent: KEnv) throws -> KFrame {
        let env = KEnv(parent: parent, selfContext: selfContext)
        try bindParameters(decl.params, args: args, labels: labels, into: env, name: decl.name)
        bindGenerics(decl, env)
        var single: KEExpr?
        if decl.body.count == 1, case .expr(let e) = decl.body[0], decl.returnType != nil || decl.isViewBuilder { single = e }
        return KBodyFrame(env: env, stmts: decl.body, single: single, returns: decl.returnType, line: decl.line)
    }

    /// A call to the app's own function that waits: run when awaited.
    func deferredCall(_ decl: KEFuncDecl, args: [KV], labels: [String?], selfContext: KSelfContext?, parent: KEnv) -> KV {
        let s = KSuspension(.frame { [unowned self] in
            try self.userFrame(decl, args: args, labels: labels, selfContext: selfContext, parent: parent)
        })
        s.name = decl.name + "()"
        s.line = decl.line
        return .suspension(s)
    }

    func deferredClosure(_ f: KFunction, _ c: KEClosure, _ args: [KV]) -> KV {
        let s = KSuspension(.frame { [unowned self] in try self.callFrame(f, args, args.map { _ in nil }) })
        s.name = "closure"
        s.line = c.line
        return .suspension(s)
    }

    // MARK: Tasks

    /// Starts `f` as a task. It runs on the main actor once the current code
    /// is done (or at once, inside `validate`'s drain).
    @discardableResult
    func startTask(_ f: KFunction, _ args: [KV], parent: KTask?, reportsErrors: Bool) -> KTask {
        let t = newTask(parent: parent, reportsErrors: reportsErrors)
        do { t.frames = [try callFrame(f, args, args.map { _ in nil })] }
        catch { t.frames = [KWaitFrame(.done(.failure(error)))] }
        enqueue(t)
        return t
    }

    /// Starts a frame as a task: a protocol requirement native code awaits (KEProxies).
    @discardableResult
    func startTask(frame make: () throws -> KFrame, parent: KTask?, reportsErrors: Bool) -> KTask {
        let t = newTask(parent: parent, reportsErrors: reportsErrors)
        do { t.frames = [try make()] }
        catch { t.frames = [KWaitFrame(.done(.failure(error)))] }
        enqueue(t)
        return t
    }

    /// Starts the work a suspension stands for as a task.
    @discardableResult
    func startTask(_ s: KSuspension, parent: KTask?, reportsErrors: Bool) -> KTask {
        let t = newTask(parent: parent, reportsErrors: reportsErrors)
        t.frames = [KWaitFrame(s)]
        enqueue(t)
        return t
    }

    private func newTask(parent: KTask?, reportsErrors: Bool) -> KTask {
        runtime.nextID += 1
        let t = KTask(id: runtime.nextID)
        t.reportsErrors = reportsErrors
        runtime.tasks[ObjectIdentifier(t)] = t
        parent?.children.append(t)
        if parent?.isCancelled == true { t.cancel() }
        return t
    }

    func enqueue(_ t: KTask) {
        guard !runtime.tornDown else { return }
        t.state = .ready
        runtime.ready.append(t)
        if !headless { scheduleDrain() }
    }

    private func scheduleDrain() {
        guard !runtime.drainScheduled else { return }
        runtime.drainScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.runtime.drainScheduled = false
                self?.drain()
            }
        }
    }

    /// Runs every task that's ready until each waits or ends.
    func drain() {
        guard !runtime.draining else { return }
        runtime.draining = true
        defer { runtime.draining = false }
        var turns = 0
        while !runtime.ready.isEmpty, !runtime.tornDown, turns < 100_000 {
            let t = runtime.ready.removeFirst()
            turns += 1
            if headless {
                t.headlessResumes += 1
                // A loop that waits forever (a ticking clock): enough turns to check it.
                if t.headlessResumes > 64 { abandon(t); continue }
            }
            drive(t)
        }
    }

    /// One stretch of a task: from where it is to its next real wait or its end.
    func drive(_ t: KTask) {
        guard t.state == .ready, !runtime.tornDown else { return }
        t.state = .running
        let savedTask = currentTask, savedFuel = fuel, savedReturn = currentReturnType
        currentTask = t
        fuel = budget
        defer {
            currentTask = savedTask
            fuel = max(savedFuel, 0)
            currentReturnType = savedReturn
        }
        var input = t.pending
        t.pending = nil
        while let top = t.frames.last {
            if case .error? = input, !top.handlesErrors {
                input = pop(t, top, input!)
                continue
            }
            currentReturnType = top.returnType
            let step: KStep
            do { step = try top.step(self, input) } catch { step = .done(.error(error)) }
            input = nil
            switch step {
            case .push(let f):
                if let err = push(f, onto: t, from: top) { input = .error(err) }
            case .done(let c):
                input = pop(t, top, c)
            case .wait(let s):
                switch s.work {
                case .frame(let make):
                    do {
                        let f = try make()
                        if let err = push(f, onto: t, from: top) { input = .error(err) }
                    } catch {
                        input = .error(error)
                    }
                case .native(let start):
                    let gate = KResumeGate()
                    t.state = .parked
                    let cancel = start(KSuspendContext(interp: self, task: t)) { [weak self, weak t] result in
                        if gate.starting { gate.result = result; return }
                        guard let self, let t else { return }
                        self.resume(t, result)
                    }
                    gate.starting = false
                    if let r = gate.result {
                        t.state = .running
                        input = completion(r)
                        continue
                    }
                    if t.isCancelled, let cancel { cancel() } else { t.canceller = cancel }
                    return
                }
            }
        }
        finish(t, input ?? .value(.void))
    }

    private func push(_ f: KFrame, onto t: KTask, from top: KFrame) -> Error? {
        if f.isFunction {
            if t.depth >= 400 { return fail("Too much recursion: an async function kept calling itself.", top.line) }
            t.depth += 1
        } else {
            f.returnType = top.returnType
        }
        t.frames.append(f)
        return nil
    }

    private func pop(_ t: KTask, _ f: KFrame, _ c: KCompletion) -> KCompletion {
        t.frames.removeLast()
        if f.isFunction { t.depth -= 1 }
        var out = f.popped(self, c)
        if case .error(var e as KERuntimeError) = out, e.line == 0, f.line > 0 {
            e.line = f.line
            out = .error(e)
        }
        return out
    }

    private func completion(_ r: Result<KV, Error>) -> KCompletion {
        switch r {
        case .success(let v): return .value(v)
        case .failure(let e): return .error(KAsync.appError(e))
        }
    }

    /// A suspension answered later.
    func resume(_ t: KTask, _ result: Result<KV, Error>) {
        guard t.state == .parked, !runtime.tornDown else { return }
        t.canceller = nil
        t.pending = completion(result)
        enqueue(t)
    }

    private func finish(_ t: KTask, _ c: KCompletion) {
        t.state = .done
        t.frames = []
        var c = c
        if case .flow = c { c = .value(.void) }
        t.result = c
        runtime.tasks[ObjectIdentifier(t)] = nil
        let waiters = t.waiters
        t.waiters = []
        for w in waiters { w(c) }
        if case .error(let e) = c, t.reportsErrors, !KAsync.isCancellation(e) { report(e) }
    }

    /// Stops following a task (headless runs): it never resumes.
    private func abandon(_ t: KTask) {
        t.state = .done
        t.frames = []
        runtime.tasks[ObjectIdentifier(t)] = nil
    }

    /// Cancels every task of the run and stops it from running any more of
    /// the app's code: timers, delayed blocks and callbacks are ignored.
    func tearDown() {
        guard !runtime.tornDown else { return }
        let tasks = Array(runtime.tasks.values)
        for t in tasks { t.cancel() }
        runtime.tornDown = true
        for t in tasks { t.frames = []; t.state = .done; t.waiters = [] }
        runtime.tasks = [:]
        runtime.ready = []
        for timer in runtime.timers { timer.invalidate() }
        runtime.timers = []
    }

    var activeTaskCount: Int { runtime.tasks.count }

    // MARK: Entry points

    /// Runs an event's closure (a tap, a timer, `.task {}` in the probe). A
    /// closure that waits becomes a task when `canWait`; otherwise using
    /// `await` there is an error. Headless runs drive the tasks it starts.
    func runAction(_ f: KFunction, _ args: [KV], canWait: Bool) {
        guard !runtime.tornDown else { return }
        do {
            let v = try entry { try call(f, args, args.map { _ in nil }) }
            if let s = v.asSuspension {
                if canWait { startTask(s, parent: nil, reportsErrors: true) }
                else if s.name == "closure" { throw fail("This closure uses 'await', which it can't do here: wrap the code in Task { … }", s.line) }
                else { throw fail("'\(s.name)' is async (it waits): call it with 'await' inside Task { … } or .task { … }", s.line) }
            }
        } catch {
            report(error)
        }
        if headless { drain() }
    }

    /// `.task {}` and `.refreshable {}`: runs `f` as a task SwiftUI waits for,
    /// cancelled when SwiftUI cancels (the view went away, the id changed).
    func runViewTask(_ f: KFunction) async {
        guard !runtime.tornDown else { return }
        let t = startTask(f, [], parent: nil, reportsErrors: true)
        let box = KUnsafeSendable(t)
        await withTaskCancellationHandler {
            _ = await t.completion()
        } onCancel: {
            Task { @MainActor in box.value.cancel() }
        }
    }

    /// `async let name = value`: a child task starts now; reading `name` with
    /// `await` waits for it.
    func asyncLet(_ d: KEVarDecl, _ env: KEnv) throws {
        guard case .binding(let name, _) = d.pattern, let initial = d.initial else {
            throw fail("'async let' needs one name and a value", d.line)
        }
        let child = newTask(parent: currentTask, reportsErrors: false)
        // The value is awaited implicitly: `async let x = load()` waits for `load()`.
        let waited = KEExpr.awaitExpr(initial)
        child.frames = [KBodyFrame(env: env, stmts: [.expr(waited)], single: waited, returns: d.type, line: d.line)]
        enqueue(child)
        env.declare(name, .suspension(taskValue(child)), isLet: true, type: nil)
    }

    /// Waits for a task's result: `task.value`, `async let`.
    func taskValue(_ t: KTask) -> KSuspension {
        KSuspension.callback { _, resume in
            let deliver: @MainActor (KCompletion) -> Void = { c in
                switch c {
                case .value(let v): resume(.success(v))
                case .error(let e): resume(.failure(e))
                case .flow: resume(.success(.void))
                }
            }
            if let r = t.result { deliver(r); return nil }
            t.waiters.append { deliver($0) }
            return nil
        }
    }

    /// What `for await` loops over.
    func asyncIterator(_ v: KV, _ line: Int) throws -> KAsyncIterator {
        switch v {
        case .native(.object("AsyncStream", let ref)):
            guard let ch = ref.value as? KAsyncChannel else { break }
            return ch.iterator()
        case .native(.object("AsyncSequence", let ref)):
            guard let seq = ref.value as? KAsyncSequence else { break }
            return seq.makeIterator()
        case .native(.object("TaskGroup", let ref)):
            guard let g = ref.value as? KTaskGroup else { break }
            return KAsyncIterator(next: { g.next() })
        case .native(.object("AsyncIterator", let ref)):
            guard let it = ref.value as? KAsyncIterator else { break }
            return it
        case .native(.object(_, let ref)) where ref.value is KAsyncLoopable:
            return (ref.value as! KAsyncLoopable).makeAsyncIterator()
        default:
            // A plain collection, as if it were an async sequence.
            var items = try sequence(v)[...]
            return KAsyncIterator(next: {
                .done(.success(items.isEmpty ? KAsync.end : items.removeFirst()))
            })
        }
        throw fail("Can't loop with 'for await' over \(describe(v))", line)
    }
}

/// Catches a resume that happens while the work is still starting.
@MainActor
final class KResumeGate {
    var starting = true
    var result: Result<KV, Error>?
}

/// The task bookkeeping of one run.
@MainActor
final class KRuntime {
    var tasks: [ObjectIdentifier: KTask] = [:]
    var ready: [KTask] = []
    var nextID = 0
    var draining = false
    var drainScheduled = false
    var tornDown = false
    var timers: [KTimerBox] = []
}

// MARK: - Built-ins that wait

extension KBuiltins {
    /// A duration as seconds: `.seconds(2)`, `.milliseconds(500)`, a number.
    static func seconds(_ v: KV?) -> Double? {
        switch v {
        case .int(let i)?: return Double(i)
        case .double(let d)?: return d
        case .native(.implicit(let unit, let a))?:
            let n = a.first?.asDouble ?? 0
            switch unit {
            case "seconds": return n
            case "milliseconds": return n / 1_000
            case "microseconds": return n / 1_000_000
            case "nanoseconds": return n / 1_000_000_000
            case "minutes": return n * 60
            default: return nil
            }
        default: return nil
        }
    }

    static func sleep(_ seconds: Double) -> KV {
        .suspension(KSuspension.callback { ctx, resume in
            if ctx.task.isCancelled { resume(.failure(KAsync.cancellationError)); return nil }
            if ctx.interp.headless { resume(.success(.void)); return nil }
            let work = Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                    resume(.success(.void))
                } catch {
                    resume(.failure(KAsync.cancellationError))
                }
            }
            return { work.cancel() }
        })
    }

    static func yieldNow() -> KV {
        .suspension(KSuspension.callback { ctx, resume in
            if ctx.interp.headless { resume(.success(.void)); return nil }
            Task { @MainActor in resume(.success(.void)) }
            return nil
        })
    }
}
