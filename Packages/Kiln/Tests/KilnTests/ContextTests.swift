//
//  ContextTests.swift
//  KilnTests
//
//  The run context (PLAN.md §1.7): each run's own defaults and folder, the
//  host's bridges reaching the host's values through it, the capability
//  gate and its stub, teardown, and errors reaching the host.
//

import XCTest
import SwiftUI
@testable import Kiln

@MainActor
final class ContextTests: XCTestCase {
    private var folders: [URL] = []
    private var suites: [String] = []

    override func tearDown() async throws {
        await MainActor.run {
            for f in folders { try? FileManager.default.removeItem(at: f) }
            for s in suites { UserDefaults.standard.removePersistentDomain(forName: s) }
        }
    }

    /// A real (not stub) context with a fresh suite and folder.
    private func context(_ slug: String, capabilities: (any KilnCapabilityGate)? = nil) -> KilnContext {
        let suite = "kiln.test.\(slug).\(UUID().uuidString)"
        suites.append(suite)
        let folder = FileManager.default.temporaryDirectory.appending(path: "kiln-test-\(UUID().uuidString)/\(slug)")
        folders.append(folder.deletingLastPathComponent())
        return KilnContext(slug: slug, name: slug.capitalized, defaults: UserDefaults(suiteName: suite)!,
                           files: KilnFiles(root: folder), capabilities: capabilities)
    }

    /// Runs `source` headless with `context`, firing its actions, and returns
    /// what it printed and its errors. The context is left up.
    private func probe(_ source: String, _ context: KilnContext) throws -> (console: String, errors: [String]) {
        let c = try KilnEngine.compile(source, headless: true, context: context)
        KProbe(interp: c.interp, ticks: 1).run(c.root)
        c.interp.tearDown()
        return (c.interp.console, c.interp.errors)
    }

    private func app(_ body: String, state: String = "") -> String {
        """
        import SwiftUI
        struct ContentView: View {
            \(state)
            var body: some View {
                \(body)
            }
        }
        """
    }

    // MARK: Defaults

    func testTwoRunsKeepTheirDefaultsApart() throws {
        let one = context("one"), two = context("two")
        let source = app(#"""
        Text("\(count)").onAppear {
                    print("was", count, UserDefaults.standard.integer(forKey: "count"))
                    count += 1
                    UserDefaults.standard.set("hi", forKey: "greeting")
                }
        """#, state: #"@AppStorage("count") private var count = 0"#)

        XCTAssertEqual(try probe(source, one).console, "was 0 0\n")
        XCTAssertEqual(try probe(source, one).console, "was 1 1\n", "@AppStorage and UserDefaults.standard are the same key")
        XCTAssertEqual(try probe(source, two).console, "was 0 0\n", "the second app saw the first one's value")

        XCTAssertEqual(one.defaults.integer(forKey: "count"), 2)
        XCTAssertEqual(two.defaults.integer(forKey: "count"), 1)
        XCTAssertEqual(one.defaults.string(forKey: "greeting"), "hi")
        XCTAssertNil(UserDefaults.standard.object(forKey: "count"))
        XCTAssertNil(UserDefaults.standard.object(forKey: "kiln.app.count"))
    }

    func testDefaultsKeepCollectionsAndData() throws {
        let one = context("lists")
        let (console, errors) = try probe(app(#"""
        Text("x").onAppear {
                    UserDefaults.standard.set(["a", "b"], forKey: "tags")
                    UserDefaults.standard.set("abc".data(using: .utf8)!, forKey: "blob")
                    let tags = UserDefaults.standard.stringArray(forKey: "tags") ?? []
                    let blob = UserDefaults.standard.data(forKey: "blob")
                    print(tags.count, blob?.count ?? -1)
                    UserDefaults.standard.removeObject(forKey: "tags")
                    print(UserDefaults.standard.object(forKey: "tags") == nil)
                }
        """#), one)
        XCTAssertEqual(errors, [])
        XCTAssertEqual(console, "2 3\ntrue\n")
    }

    // MARK: Files

    func testFilesAreWrittenAndReadInTheAppsFolder() throws {
        let one = context("notes")
        let (console, errors) = try probe(app(#"""
        Text("x").onAppear {
                    let url = URL.documentsDirectory.appendingPathComponent("note.txt")
                    try? "hello".write(to: url, atomically: true, encoding: .utf8)
                    let text = (try? String(contentsOf: url, encoding: .utf8)) ?? "missing"
                    let data = try? Data(contentsOf: url)
                    print(text, data?.count ?? -1)
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    print(try! FileManager.default.contentsOfDirectory(atPath: docs.path).joined(separator: ","))
                    let cache = URL.cachesDirectory.appending(path: "c.json")
                    try? "{}".data(using: .utf8)!.write(to: cache)
                    print(FileManager.default.fileExists(atPath: cache.path))
                    try? FileManager.default.removeItem(at: cache)
                    print(FileManager.default.fileExists(atPath: cache.path))
                    do { _ = try Data(contentsOf: URL.documentsDirectory.appendingPathComponent("nope")) } catch { print("caught") }
                }
        """#), one)
        XCTAssertEqual(errors, [])
        XCTAssertEqual(console, "hello 5\nnote.txt\ntrue\nfalse\ncaught\n")
        let written = one.files.root.appending(path: "Documents/note.txt")
        XCTAssertEqual(try String(contentsOf: written, encoding: .utf8), "hello")
        XCTAssertGreaterThan(one.files.usage(), 0)
    }

    func testAPathThatLeavesTheFolderIsAnError() throws {
        let one = context("escape")
        let outside = FileManager.default.temporaryDirectory.appending(path: "kiln-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        folders.append(outside)
        try "secret".write(to: outside.appending(path: "secret.txt"), atomically: true, encoding: .utf8)
        // A link inside the folder that points out of it.
        try FileManager.default.createDirectory(at: one.files.documents, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: one.files.documents.appending(path: "link"), withDestinationURL: outside)

        let attempts = [
            #"_ = try Data(contentsOf: URL(fileURLWithPath: "\#(outside.path)/secret.txt"))"#,
            #"try "x".write(to: URL.documentsDirectory.appendingPathComponent("../../../x.txt"), atomically: true, encoding: .utf8)"#,
            #"_ = try String(contentsOf: URL.documentsDirectory.appendingPathComponent("link/secret.txt"), encoding: .utf8)"#,
            #"try FileManager.default.removeItem(atPath: "\#(outside.path)/secret.txt")"#,
            #"_ = FileManager.default.fileExists(atPath: "/etc/hosts")"#,
            #"_ = try Data(contentsOf: URL(string: "https://example.com")!)"#,
        ]
        for (i, attempt) in attempts.enumerated() {
            let source = """
            import SwiftUI
            struct ContentView: View {
                var body: some View {
                    Text("x").onAppear {
                        \(attempt)
                    }
                }
            }
            """
            let errors = try probe(source, one).errors
            XCTAssertEqual(errors.count, 1, "attempt \(i) wasn't refused: \(attempt)")
            XCTAssertTrue(errors.first?.hasPrefix("Line 5: ") == true, "\(errors)")
            XCTAssertTrue(errors.first.map { $0.contains("outside the app's folder") || $0.contains("isn't a file") } == true, "\(errors)")
        }
        XCTAssertEqual(try String(contentsOf: outside.appending(path: "secret.txt"), encoding: .utf8), "secret")
        XCTAssertFalse(FileManager.default.fileExists(atPath: one.files.root.deletingLastPathComponent().appending(path: "x.txt").path))
    }

    func testTheResolverKeepsInsideAndRefusesOutside() throws {
        let files = KilnFiles(root: FileManager.default.temporaryDirectory.appending(path: "kiln-resolve-\(UUID().uuidString)/app"))
        folders.append(files.root.deletingLastPathComponent())
        XCTAssertNoThrow(try files.resolve(files.documents.appending(path: "a/../b.txt")))
        XCTAssertNoThrow(try files.resolve(path: "Documents/new/deeper.txt"))
        XCTAssertThrowsError(try files.resolve(files.root.appending(path: "../app2/x")))
        XCTAssertThrowsError(try files.resolve(path: "/"))
        XCTAssertThrowsError(try files.resolve(URL(string: "https://example.com/x")!))
    }

    // MARK: Host bridges

    final class Store { var values: [String: String] = [:] }

    func testAHostBridgeReachesItsRunsValue() throws {
        Kiln.registerType("KilnTestContextStore") { t in
            t.staticMethod("save", "_:string _:string") { call in
                guard let store = call.context.provided(Store.self) else { throw call.error("no store") }
                store.values[try call.string(0)] = try call.string(1)
                return .void
            }
            t.staticMethod("load", "_:string") { call in
                call.context.provided(Store.self)?.values[try call.string(0)].map { KilnValue(string: $0) } ?? .nil
            }
            t.staticProperty("app") { call in KilnValue(string: call.context.name) }
        }
        let one = context("first"), two = context("second")
        let a = Store(), b = Store()
        one.provide(a)
        two.provide(b)
        let source = app(#"""
        Text("x").onAppear {
                    print(KilnTestContextStore.app, KilnTestContextStore.load("k") ?? "none")
                    KilnTestContextStore.save("k", KilnTestContextStore.app)
                }
        """#)
        XCTAssertEqual(try probe(source, one).console, "First none\n")
        XCTAssertEqual(try probe(source, two).console, "Second none\n")
        XCTAssertEqual(try probe(source, one).console, "First First\n")
        XCTAssertEqual(a.values, ["k": "First"])
        XCTAssertEqual(b.values, ["k": "Second"])

        let none = context("bare")
        let errors = try probe(source, none).errors
        XCTAssertEqual(errors, ["Line 7: KilnTestContextStore.save(_:_:): no store"])
    }

    // MARK: Capabilities

    func testTheStubGateAnswersAtOnceAndRecords() throws {
        Kiln.registerFunction("kilnTestAskLocation", signature: "") { call in
            call.context.capabilities.request(.location)
        }
        Kiln.registerFunction("kilnTestCameraStatus", signature: "") { call in
            KilnValue(string: call.context.capabilities.status(.camera).rawValue)
        }
        let stub = KilnStubCapabilities([.location: .denied])
        let source = app(#"""
        Text("x").task {
                    let allowed = await kilnTestAskLocation()
                    print("location", allowed, kilnTestCameraStatus())
                }
        """#)
        let (console, errors) = try probe(source, KilnContext.stub(capabilities: stub))
        XCTAssertEqual(errors, [])
        XCTAssertEqual(console, "location false notAsked\n")
        XCTAssertEqual(stub.requested, [.location])

        let allowing = KilnStubCapabilities()
        XCTAssertEqual(try probe(source, KilnContext.stub(capabilities: allowing)).console, "location true allowed\n")
    }

    /// A real run waits for the host's answer; tearing the run down
    /// withdraws a request still waiting.
    func testARealRequestWaitsAndTeardownWithdrawsIt() async throws {
        final class Gate: KilnCapabilityGate {
            var continuation: CheckedContinuation<Bool, Never>?
            var cancelled = 0
            func request(_ capability: KilnCapability) async -> Bool {
                await withCheckedContinuation { continuation = $0 }
            }
            func status(_ capability: KilnCapability) -> KilnPermissionStatus { .notAsked }
            func cancelRequests() {
                cancelled += 1
                continuation?.resume(returning: false)
                continuation = nil
            }
        }
        Kiln.registerFunction("kilnTestAskCamera", signature: "") { call in
            call.context.capabilities.request(.camera)
        }
        let gate = Gate()
        let ctx = context("camera", capabilities: gate)
        let c = try KilnEngine.compile(app(#"""
        Text("x").onAppear {
                    Task {
                        let ok = await kilnTestAskCamera()
                        print("camera", ok)
                    }
                }
        """#), context: ctx)
        ctx.onTearDown { [weak interp = c.interp] in interp?.tearDown() }
        KProbe(interp: c.interp, ticks: 1).run(c.root)
        for _ in 0..<20 where gate.continuation == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(gate.continuation, "the gate was never asked")
        XCTAssertEqual(c.interp.activeTaskCount, 1)
        gate.continuation?.resume(returning: true)
        gate.continuation = nil
        for _ in 0..<20 where !c.interp.console.contains("camera") { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(c.interp.console, "camera true\n")

        // Asked again, then the card closes.
        KProbe(interp: c.interp, ticks: 1).run(c.root)
        for _ in 0..<20 where gate.continuation == nil { try await Task.sleep(for: .milliseconds(10)) }
        ctx.tearDown()
        XCTAssertEqual(gate.cancelled, 1)
        XCTAssertEqual(c.interp.activeTaskCount, 0)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(c.interp.console, "camera true\n", "the app ran after teardown")
    }

    // MARK: Teardown

    func testTeardownStopsWhatBridgesRegistered() throws {
        var stopped: [String] = []
        Kiln.registerFunction("kilnTestStart", signature: "_:string") { call in
            let name = try call.string(0)
            let token = call.context.onTearDown { stopped.append(name) }
            if name == "self-stopping" { token.cancel() }
            return .void
        }
        let ctx = context("sensors")
        let result = Kiln.run("""
        import SwiftUI
        let a: Void = kilnTestStart("motion")
        let b: Void = kilnTestStart("self-stopping")
        let c: Void = kilnTestStart("location")
        struct ContentView: View {
            var body: some View { Text("x") }
        }
        """, context: ctx)
        XCTAssertEqual(result.errors, [])
        // Nothing stops until the screen closes.
        _ = try XCTUnwrap(result.view)
        XCTAssertEqual(stopped, [])
        result.tearDown()
        XCTAssertEqual(stopped, ["location", "motion"], "last registered first, and the cancelled one not at all")
        XCTAssertTrue(ctx.isTornDown)
        result.tearDown()
        XCTAssertEqual(stopped, ["location", "motion"], "twice")
        // Registered after teardown: stopped at once.
        ctx.onTearDown { stopped.append("late") }
        XCTAssertEqual(stopped.last, "late")
    }

    func testTeardownCancelsTheRunsTasks() throws {
        let ctx = context("timer")
        let c = try KilnEngine.compile(app(#"""
        Text("x").onAppear {
                    Task { try? await Task.sleep(for: .seconds(30)); print("late") }
                }
        """#), context: ctx)
        ctx.onTearDown { [weak interp = c.interp] in interp?.tearDown() }
        KProbe(interp: c.interp, ticks: 1).run(c.root)
        XCTAssertEqual(c.interp.activeTaskCount, 1)
        ctx.tearDown()
        XCTAssertEqual(c.interp.activeTaskCount, 0)
    }

    func testAStubContextLeavesNothingBehind() throws {
        let stub = KilnContext.stub()
        let v = Kiln.validate(app(#"""
        Text("x").onAppear {
                    UserDefaults.standard.set(1, forKey: "k")
                    try? "x".write(to: URL.documentsDirectory.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
                }
        """#), context: stub)
        XCTAssertEqual(v.errors, [])
        XCTAssertTrue(stub.isTornDown)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stub.files.root.path))
        XCTAssertNil(stub.defaults.object(forKey: "k"))
    }

    // MARK: Errors

    func testACheckErrorReachesTheHostWithItsLine() async throws {
        let ctx = context("broken")
        var heard: [KilnError] = []
        ctx.onError = { heard.append($0) }
        let result = Kiln.run("import SwiftUI\nstruct ContentView: View {\n  var body: some View { Text(\"x\" }\n}", context: ctx)
        XCTAssertNil(result.view)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(heard.count, 1)
        XCTAssertEqual(heard.first?.phase, .check)
        XCTAssertEqual(heard.first?.line, 3)
    }

    func testABodyErrorReachesTheHost() async throws {
        let ctx = context("body")
        var heard: [KilnError] = []
        let result = Kiln.run(app(#"""
        VStack {
                    Text("Total")
                    Text(String(totals[3]))
                }
        """#, state: "let totals = [1, 2]"), context: ctx)
        ctx.onError = { heard.append($0) }
        let view = try XCTUnwrap(result.view)
        try show(view)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(heard.map(\.phase), [.body], "\(heard)")
        XCTAssertEqual(heard.first?.line, 7)
        XCTAssertTrue(heard.first?.message.contains("out of range") == true, "\(heard)")
        result.tearDown()
    }

    func testAnActionsErrorReachesTheHostAsARuntimeError() async throws {
        let ctx = context("action")
        var heard: [KilnError] = []
        ctx.onError = { heard.append($0) }
        _ = try probe(app(#"""
        Text("x").onAppear {
                    let xs: [Int] = []
                    print(xs[0])
                }
        """#), ctx)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(heard.map(\.phase), [.runtime])
        XCTAssertEqual(heard.first?.line, 7)
    }

    // MARK: Parsing off the main thread

    func testSourceParsedOffTheMainThreadRuns() async throws {
        let source = app(#"Text("Parsed \(1 + 1)")"#)
        let parsed = await Task.detached { Kiln.parse(source) }.value
        XCTAssertTrue(parsed.parsed)
        let result = Kiln.run(parsed, context: context("parsed"))
        XCTAssertEqual(result.errors, [])
        XCTAssertNotNil(result.view)

        let broken = await Task.detached { Kiln.parse("struct {") }.value
        XCTAssertFalse(broken.parsed)
        XCTAssertEqual(Kiln.run(broken, context: context("broken")).errors.count, 1)
    }

    private func show(_ view: AnyView) throws {
        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        let host = NSHostingView(rootView: view.frame(width: 200, height: 100))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        #else
        let host = UIHostingController(rootView: view.frame(width: 200, height: 100))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        window.rootViewController = host
        window.isHidden = false
        for _ in 0..<5 {
            host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        #endif
    }
}
