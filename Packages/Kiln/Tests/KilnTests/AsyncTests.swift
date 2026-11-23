import XCTest
@testable import Kiln

/// Code that can wait (PLAN.md §1.3): the frames that run it, and what an app
/// gets — real sleeps, cancellation, task groups, `async let`, `for await`,
/// `MainActor.run`, the per-stretch budget, and teardown.
@MainActor
final class AsyncTests: XCTestCase {

    // MARK: Helpers

    /// Compiles `source` (plus a trivial ContentView) and runs its global
    /// `main()` as a task, live (really waiting) or headless.
    func run(_ source: String, headless: Bool = false, budget: Int? = nil,
             _ body: ((KInterpreter, KTask) async -> Void)? = nil) async throws -> (interp: KInterpreter, result: KCompletion) {
        let c = try KilnEngine.compile(source + "\nstruct ContentView: View { var body: some View { Text(\"x\") } }", headless: headless)
        if let budget { c.interp.budget = budget }
        let main = try XCTUnwrap(c.interp.functions["main"]?.first, "no main()")
        let t = c.interp.startTask(KFunction(.user(main, c.interp.globalEnv, nil)), [], parent: nil, reportsErrors: true)
        if headless { c.interp.drain() }
        await body?(c.interp, t)
        let r = await t.completion()
        return (c.interp, r)
    }

    func value(_ c: KCompletion) -> KV? { if case .value(let v) = c { return v }; return nil }

    func elapsed(_ work: () async throws -> Void) async rethrows -> Double {
        let start = Date()
        try await work()
        return Date().timeIntervalSince(start)
    }

    // MARK: Which code waits

    func testScanFindsAwaitButNotInsideClosures() throws {
        let p = try KEParser.parse("""
        func a() async { await b() }
        func b() async { let f = { await c() }; _ = f }
        func c() async {}
        func d() { for await x in s { print(x) } }
        func e() async { async let x = c(); _ = x }
        """)
        let byName = Dictionary(uniqueKeysWithValues: p.functions.map { ($0.name, $0) })
        XCTAssertTrue(byName["a"]!.awaits)
        XCTAssertFalse(byName["b"]!.awaits, "an await inside a closure belongs to the closure")
        XCTAssertFalse(byName["c"]!.awaits)
        XCTAssertTrue(byName["d"]!.awaits, "for await waits")
        XCTAssertTrue(byName["e"]!.awaits, "async let starts a child task")
    }

    func testSubstitutionKeepsTheRestOfTheExpression() throws {
        let p = try KEParser.parse("let x = f(1, await g(), h: 2 + (await k()))")
        guard case .variable(let d) = p.globals[0], let e = d.initial else { return XCTFail() }
        var seen = 0
        _ = KAwaitScan.mapChildren(e) { child in if KAwaitScan.expr(child) { seen += 1 }; return child }
        XCTAssertEqual(seen, 2, "both awaiting arguments, left to right")
    }

    // MARK: The frames: control flow across waits

    func testControlFlowAcrossWaits() async throws {
        let (interp, r) = try await run("""
        func step(_ n: Int) async -> Int { await Task.yield(); return n }
        func maybe(_ n: Int) async -> Int? { await Task.yield(); return n }
        func main() async -> String {
            var log: [String] = []
            defer { print("deferred") }
            outer: for i in 0..<4 {
                if await step(i) == 1 { continue }
                var j = 0
                while j < 3 {
                    j += await step(1)
                    if j == 2 && i == 3 { break outer }
                }
                log.append("\\(i):\\(j)")
            }
            var k = 0
            repeat { k = await step(k + 1) } while k < 3
            switch await step(k) {
            case 3: log.append("three")
                fallthrough
            case 4: log.append("after")
            default: log.append("no")
            }
            guard let first = await maybe(7) else { return "none" }
            let total = await step(first) + (await step(1)) * 2
            log.append("\\(total)")
            log.append(k > 2 && (await step(1)) == 1 ? "and" : "nope")
            return log.joined(separator: ",")
        }
        """, headless: true)
        XCTAssertEqual(interp.errors, [])
        XCTAssertEqual(value(r)?.asString, "0:3,2:3,three,after,9,and")
        XCTAssertEqual(interp.console, "deferred\n")
    }

    func testErrorsAcrossWaits() async throws {
        let (interp, r) = try await run("""
        enum Oops: Error { case bad(Int) }
        func fail(_ n: Int) async throws -> Int { await Task.yield(); throw Oops.bad(n) }
        func main() async -> [String] {
            var out: [String] = []
            do {
                _ = try await fail(1)
                out.append("not here")
            } catch {
                out.append("caught \\(error)")
            }
            let maybe = try? await fail(2)
            out.append(maybe == nil ? "nil" : "value")
            do {
                defer { out.append("cleanup") }
                _ = try await fail(3)
            } catch {
                out.append("then \\(error)")
            }
            return out
        }
        """, headless: true)
        XCTAssertEqual(interp.errors, [])
        XCTAssertEqual(value(r).map { interp.describe($0) }, #"["caught bad(1)", "nil", "cleanup", "then bad(3)"]"#)
    }

    func testAsyncMethodsAndRecursion() async throws {
        let (interp, r) = try await run("""
        struct Counter {
            var n = 0
            mutating func bump() async { await Task.yield(); n += 1 }
        }
        final class Store {
            var items: [Int] = []
            func load(_ k: Int) async { await Task.yield(); items.append(k) }
            static func make() async -> Store { let s = Store(); await s.load(9); return s }
        }
        func countdown(_ n: Int) async -> Int { n == 0 ? 0 : await countdown(n - 1) + 1 }
        func main() async -> String {
            var c = Counter()
            await c.bump()
            await c.bump()
            let s = await Store.make()
            await s.load(4)
            var captured = 1
            let add: () async -> Void = { await Task.yield(); captured += 10 }
            await add()
            return "\\(c.n) \\(s.items) \\(await countdown(50)) \\(captured)"
        }
        """, headless: true)
        XCTAssertEqual(interp.errors, [])
        XCTAssertEqual(value(r)?.asString, "2 [9, 4] 50 11")
    }

    func testRunawayAsyncRecursionIsStopped() async throws {
        let (interp, r) = try await run("""
        func forever(_ n: Int) async -> Int { await forever(n + 1) }
        func main() async { _ = await forever(0) }
        """, headless: true)
        guard case .error = r else { return XCTFail("\(r)") }
        XCTAssertTrue(interp.errors.contains { $0.contains("Too much recursion") }, "\(interp.errors)")
    }

    // MARK: Sleeping really waits, and doesn't block

    func testSleepReallyWaitsWithoutBlockingTheMainThread() async throws {
        var mainRan = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { mainRan = true }
        let seconds = try await elapsed {
            let (interp, _) = try await run("""
            func main() async {
                print("before")
                try? await Task.sleep(nanoseconds: 300_000_000)
                print("middle")
                try? await Task.sleep(for: .milliseconds(200))
                print("after")
            }
            """)
            XCTAssertEqual(interp.console, "before\nmiddle\nafter\n")
        }
        XCTAssertGreaterThanOrEqual(seconds, 0.5)
        XCTAssertLessThan(seconds, 2)
        XCTAssertTrue(mainRan, "the main thread ran other work while the task slept")
    }

    // MARK: Cancellation

    func testCancellingATaskWakesItsSleep() async throws {
        let seconds = try await elapsed {
            let (interp, _) = try await run("""
            func main() async {
                let t = Task {
                    do {
                        try await Task.sleep(for: .seconds(10))
                        print("woke")
                    } catch {
                        print("cancelled", Task.isCancelled, error is CancellationError)
                    }
                }
                try? await Task.sleep(for: .milliseconds(50))
                t.cancel()
                await t.value
                print("done", t.isCancelled)
            }
            """)
            XCTAssertEqual(interp.console, "cancelled true true\ndone true\n")
            XCTAssertEqual(interp.errors, [])
        }
        XCTAssertLessThan(seconds, 2)
    }

    func testCheckCancellation() async throws {
        let (interp, _) = try await run("""
        func main() async {
            let t = Task {
                var i = 0
                do {
                    while true {
                        try Task.checkCancellation()
                        i += 1
                        await Task.yield()
                    }
                } catch {
                    print("stopped", i > 0)
                }
            }
            try? await Task.sleep(for: .milliseconds(30))
            t.cancel()
            _ = await t.value
        }
        """)
        XCTAssertEqual(interp.console, "stopped true\n")
    }

    func testViewTaskIsCancelledWithSwiftUIsTask() async throws {
        let c = try KilnEngine.compile("""
        func work() async {
            do { try await Task.sleep(for: .seconds(10)); print("finished") }
            catch { print("cancelled") }
        }
        struct ContentView: View { var body: some View { Text("x").task { await work() } } }
        """)
        let work = try XCTUnwrap(c.interp.functions["work"]?.first)
        let closure = KFunction(.user(work, c.interp.globalEnv, nil))
        // SwiftUI runs `.task`'s action in a Swift task and cancels it when the view goes away.
        let swiftUITask = Task { @MainActor in await c.interp.runViewTask(closure) }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(c.interp.activeTaskCount, 1)
        swiftUITask.cancel()
        await swiftUITask.value
        XCTAssertEqual(c.interp.console, "cancelled\n")
        XCTAssertEqual(c.interp.activeTaskCount, 0)
    }

    // MARK: Structured concurrency

    func testAsyncLetRunsAtTheSameTime() async throws {
        let seconds = try await elapsed {
            let (interp, r) = try await run("""
            func slow(_ n: Int) async -> Int {
                try? await Task.sleep(for: .milliseconds(300))
                return n * 10
            }
            func main() async -> Int {
                async let a = slow(1)
                async let b = slow(2)
                let (x, y) = await (a, b)
                let again = await a
                return x + y + again
            }
            """)
            XCTAssertEqual(interp.errors, [])
            XCTAssertEqual(value(r)?.asInt, 40)
        }
        XCTAssertLessThan(seconds, 0.55, "the two waits overlap")
    }

    func testTaskGroups() async throws {
        let (interp, r) = try await run("""
        enum E: Error { case odd }
        func sleepy(_ ms: Int) async -> Int {
            try? await Task.sleep(for: .milliseconds(ms))
            return ms
        }
        func check(_ n: Int) async throws -> Int {
            await Task.yield()
            if n % 2 == 1 { throw E.odd }
            return n
        }
        func main() async -> String {
            let order = await withTaskGroup(of: Int.self) { group in
                for ms in [120, 20, 70] { group.addTask { await sleepy(ms) } }
                var seen: [Int] = []
                for await ms in group { seen.append(ms) }
                return seen
            }
            let sum = await withTaskGroup(of: Int.self, returning: Int.self) { group in
                for i in 1...4 { group.addTask { i * i } }
                var total = 0
                while let v = await group.next() { total += v }
                return total
            }
            var failed = "no"
            do {
                _ = try await withThrowingTaskGroup(of: Int.self) { group in
                    for i in [2, 3] { group.addTask { try await check(i) } }
                    var total = 0
                    for try await v in group { total += v }
                    return total
                }
            } catch {
                failed = "yes"
            }
            return "\\(order) \\(sum) \\(failed)"
        }
        """)
        XCTAssertEqual(interp.errors, [])
        XCTAssertEqual(value(r)?.asString, "[20, 70, 120] 30 yes")
    }

    // MARK: Streams

    func testForAwaitOverAnAsyncStream() async throws {
        let (interp, r) = try await run("""
        func ticks(_ n: Int) -> AsyncStream<Int> {
            AsyncStream { continuation in
                Task {
                    for i in 1...n {
                        try? await Task.sleep(for: .milliseconds(10))
                        continuation.yield(i)
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in print("terminated") }
            }
        }
        func main() async -> Int {
            var total = 0
            for await i in ticks(5) { total += i }
            let (stream, continuation) = AsyncStream.makeStream(of: String.self)
            continuation.yield("a")
            continuation.yield("b")
            continuation.finish()
            var joined = ""
            for await s in stream { joined += s }
            print(joined)
            return total
        }
        """)
        XCTAssertEqual(interp.errors, [])
        XCTAssertEqual(value(r)?.asInt, 15)
        XCTAssertEqual(interp.console, "terminated\nab\n")
    }

    func testNativeAsyncSequence() async throws {
        let c = try KilnEngine.compile("""
        func main(_ numbers: Any) async -> Int {
            var sum = 0
            for await n in numbers { sum += n }
            return sum
        }
        struct ContentView: View { var body: some View { Text("x") } }
        """)
        let native = AsyncStream<Int> { k in for i in 1...4 { k.yield(i) }; k.finish() }
        let seq = KAsyncSequence.wrapping("Numbers", native) { .int($0) }
        let main = try XCTUnwrap(c.interp.functions["main"]?.first)
        let t = c.interp.startTask(KFunction(.user(main, c.interp.globalEnv, nil)), [.native(.object("AsyncSequence", KRef(seq)))],
                                   parent: nil, reportsErrors: true)
        let r = await t.completion()
        XCTAssertEqual(value(r)?.asInt, 10)
    }

    // MARK: MainActor, continuations, the network

    func testMainActorRunAndContinuations() async throws {
        let (interp, r) = try await run("""
        func later() async -> String {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    continuation.resume(returning: "resumed")
                }
            }
        }
        func main() async -> String {
            let x = await MainActor.run { 21 * 2 }
            return "\\(x) \\(await later())"
        }
        """)
        XCTAssertEqual(interp.errors, [])
        XCTAssertEqual(value(r)?.asString, "42 resumed")
    }

    func testURLSessionDataWaitsWithoutBlocking() async throws {
        URLProtocol.registerClass(AsyncTestsProtocol.self)
        defer { URLProtocol.unregisterClass(AsyncTestsProtocol.self) }
        var mainRan = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { mainRan = true }
        let (interp, r) = try await run("""
        struct Reply: Codable { let name: String }
        func main() async -> String {
            do {
                let (data, response) = try await URLSession.shared.data(from: URL(string: "https://kiln-async.test/slow")!)
                let reply = try JSONDecoder().decode(Reply.self, from: data)
                return "\\(reply.name) \\((response as? HTTPURLResponse)?.statusCode ?? 0)"
            } catch {
                return "failed: \\(error.localizedDescription)"
            }
        }
        """)
        XCTAssertEqual(interp.errors, [])
        XCTAssertEqual(value(r)?.asString, "Kiln 200")
        XCTAssertTrue(mainRan, "the main thread wasn't held while the request was in flight")
    }

    func testHostAnswersARequestWithoutWaiting() throws {
        Kiln.hostRequestHandler = { request in
            request.url?.scheme == "db" ? KilnHostResponse(statusCode: 200, body: Data("[1,2]".utf8)) : nil
        }
        defer { Kiln.hostRequestHandler = nil }
        let v = Kiln.validate("""
        struct ContentView: View {
            @State private var n = 0
            var body: some View {
                Text("\\(n)").onAppear {
                    let r = try? URLSession.shared.data(for: URLRequest(url: URL(string: "db://data/")!))
                    if let (data, _) = r, let xs = try? JSONDecoder().decode([Int].self, from: data) { n = xs.count; print(n) }
                }
            }
        }
        """)
        XCTAssertEqual(v.errors, [])
    }

    // MARK: Code that can't wait

    func testAwaitInBodyIsAnErrorWithItsLine() {
        let v = Kiln.validate("""
        func name() async -> String { "x" }
        struct ContentView: View {
            var body: some View {
                Text(await name())
            }
        }
        """)
        XCTAssertTrue(v.errors.contains { $0.hasPrefix("Line 4: 'await' can't be used here") }, "\(v.errors)")
    }

    func testAwaitInComputedPropertyAndInitAreErrors() {
        let computed = Kiln.validate("""
        func name() async -> String { "x" }
        struct ContentView: View {
            var label: String { await name() }
            var body: some View { Text(label) }
        }
        """)
        XCTAssertTrue(computed.errors.contains { $0.hasPrefix("Line 3: 'await' can't be used here") }, "\(computed.errors)")
        let initializer = Kiln.validate("""
        func name() async -> String { "x" }
        struct Model {
            var title: String
            init() { title = await name() }
        }
        struct ContentView: View {
            var body: some View {
                Text("x").onAppear { _ = Model() }
            }
        }
        """)
        XCTAssertTrue(initializer.errors.contains { $0.hasPrefix("Line 4: 'await' can't be used here") }, "\(initializer.errors)")
    }

    func testCallingAnAsyncFunctionWithoutAwaitIsAnError() {
        let v = Kiln.validate("""
        func load() async { await Task.yield() }
        struct ContentView: View {
            var body: some View {
                Button("Go") { load() }
            }
        }
        """)
        XCTAssertTrue(v.errors.contains { $0.contains("'load()' is async") }, "\(v.errors)")
    }

    // MARK: The budget is per stretch

    func testBudgetIsPerStretchBetweenWaits() async throws {
        // Each stretch is ~1,500 steps; the whole run is far over the 4,000 budget.
        let (interp, _) = try await run("""
        func main() async {
            var total = 0
            for _ in 0..<20 {
                for i in 0..<300 { total += i % 3 }
                await Task.yield()
            }
            print(total)
        }
        """, budget: 4_000)
        XCTAssertEqual(interp.errors, [])
        XCTAssertEqual(interp.console, "6000\n")
    }

    func testARunawayLoopInATaskStopsWithItsLine() async throws {
        let (interp, _) = try await run("""
        func main() async {
            await Task.yield()
            var x = 0
            while true {
                x += 1
            }
        }
        """, budget: 10_000)
        XCTAssertTrue(interp.errors.contains { $0.hasPrefix("Line 5: This code ran too long") }, "\(interp.errors)")
    }

    func testARunawayLoopInAnActionStopsWithItsLine() {
        let v = Kiln.validate("""
        struct ContentView: View {
            @State private var x = 0
            var body: some View {
                Text("\\(x)").onAppear {
                    while true {
                        x += 1
                    }
                }
            }
        }
        """, fuel: 50_000)
        XCTAssertTrue(v.errors.contains { $0.hasPrefix("Line 6: This code ran too long") }, "\(v.errors)")
    }

    // MARK: Headless (validate)

    func testValidateRunsTasksWithoutWaiting() {
        let start = Date()
        let v = Kiln.validate("""
        struct ContentView: View {
            @State private var value = 0
            var body: some View {
                Text("\\(value)")
                    .task {
                        try? await Task.sleep(for: .seconds(30))
                        value = missing()
                    }
            }
        }
        """)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        XCTAssertTrue(v.errors.contains { $0.contains("Cannot find 'missing' in scope") }, "the code after the sleep was checked: \(v.errors)")
    }

    func testValidateNeverTouchesTheNetwork() {
        let v = Kiln.validate("""
        struct ContentView: View {
            @State private var status = "…"
            var body: some View {
                Text(status).task {
                    do {
                        _ = try await URLSession.shared.data(from: URL(string: "https://example.com")!)
                        status = "online"
                    } catch {
                        status = "offline"
                    }
                }
            }
        }
        """)
        XCTAssertEqual(v.errors, [])
    }

    // MARK: Teardown

    func testTearDownCancelsEveryTask() async throws {
        let result = Kiln.run("""
        let started = Date()
        struct ContentView: View {
            var body: some View {
                Text("x")
            }
        }
        func spin(_ name: String) async {
            while true { try? await Task.sleep(for: .milliseconds(20)) ; print(name) }
        }
        """)
        let interp = try XCTUnwrap(result.interp)
        let spin = try XCTUnwrap(interp.functions["spin"]?.first)
        for name in ["a", "b", "c"] {
            interp.startTask(KFunction(.user(spin, interp.globalEnv, nil)), [.string(name)], parent: nil, reportsErrors: true)
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(result.activeTaskCount, 3)
        XCTAssertFalse(interp.console.isEmpty)
        result.tearDown()
        XCTAssertEqual(result.activeTaskCount, 0)
        let printed = interp.console
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(interp.console, printed, "nothing runs after teardown")
    }
}

/// Answers https://kiln-async.test/ after a short delay, off the main thread.
final class AsyncTestsProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "kiln-async.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [self] in
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                                cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(#"{"name":"Kiln"}"#.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
