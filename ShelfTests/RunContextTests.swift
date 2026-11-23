import Foundation
@testable import Kiln
import SwiftUI
import Testing
import UIKit
@testable import Shelf

/// Each run's Kiln context, as Shelf builds it (plan §1.7): `DB` as a host
/// bridge over the run's own session, each app's settings suite and the
/// move into it, the error screen for a `body` that fails, and teardown.
@MainActor
@Suite(.serialized)
struct RunContextTests {
    static let meta = AppMeta(slug: "todos-db", name: "Todos", tint: .blue, version: "1")

    // MARK: DB

    /// The whole path: an app run by Kiln, `DB` as a host bridge, and a real session.
    @Test func dbRoundTripsThroughTheRunsSession() throws {
        let session = DBSession(slug: "todos", entries: [
            "todos": .array([.object(["title": .string("Milk")])]),
        ])
        // The probe fires onAppear, which loads the list; the change saves it back.
        let validation = Kiln.validate(try Fixture.app("todos-db"), context: RunContext.check(Self.meta, session: session))
        #expect(validation.errors.isEmpty, "\(validation.errors)")

        let stored = try #require(session.value(for: "todos"))
        guard case .array(let items) = stored, case .object(let first)? = items.first else {
            Issue.record("\(stored)")
            return
        }
        #expect(items.count == 1)
        #expect(first["title"] == .string("Milk"))
        #expect(first["done"] == .bool(false))
        guard case .string(let id)? = first["id"] else { Issue.record("\(first)"); return }
        #expect(UUID(uuidString: id) != nil)
    }

    /// Two runs, two sessions: a `DB` call reaches only its own run's.
    @Test func eachRunReachesItsOwnSession() {
        let one = DBSession(slug: "one"), two = DBSession(slug: "two")
        let source = Self.app(#"""
            Text("x").onAppear {
                        DB.save("k", "\(DB.load("k") == nil ? 1 : 2)".data(using: .utf8)!)
                    }
            """#)
        #expect(Kiln.validate(source, context: RunContext.check(Self.meta, session: one)).errors.isEmpty)
        #expect(Kiln.validate(source, context: RunContext.check(Self.meta, session: one)).errors.isEmpty)
        #expect(Kiln.validate(source, context: RunContext.check(Self.meta, session: two)).errors.isEmpty)
        #expect(one.value(for: "k") == .int(2))
        #expect(two.value(for: "k") == .int(1))
    }

    /// Every key the server accepts comes back as itself, including the
    /// ones a URL would have cut short, decoded or collapsed.
    @Test func dbKeepsEveryValidKeyWhole() {
        let keys = ["a?b", "a#b", "a b", "100%", "q=1&r=2", "한글", "..", ".", "a%2Fb", " padded ", "a"]
        let session = DBSession(slug: "keys")
        let list = keys.map { "\"\($0)\"" }.joined(separator: ", ")
        let (errors, console) = Self.probe(Self.app(#"""
            Text("x").onAppear {
                        let keys = [\#(list)]
                        for i in 0..<keys.count {
                            DB.save(keys[i], "\(i)".data(using: .utf8)!)
                        }
                        for i in 0..<keys.count {
                            if let data = DB.load(keys[i]), let n = try? JSONDecoder().decode(Int.self, from: data) {
                                print("load", i, n)
                            } else {
                                print("load", i, "missing")
                            }
                        }
                        DB.remove("a?b")
                        print("removed", DB.load("a?b") == nil, DB.load("a") != nil)
                    }
            """#), session: session)
        #expect(errors.isEmpty, "\(errors)")
        var expected: [String: JSONValue] = [:]
        for (i, key) in keys.enumerated() where key != "a?b" { expected[key] = .int(i) }
        #expect(session.all() == expected)
        for i in keys.indices {
            #expect(console.contains("load \(i) \(i)\n"), "\(keys[i]): \(console)")
        }
        #expect(console.contains("removed true true"), "\(console)")
    }

    /// What the server would refuse is an error with the app's line, not lost.
    @Test(arguments: [
        (#"DB.save("a/b", "1".data(using: .utf8)!)"#, "isn't a key DB can keep"),
        (#"DB.save("k", "not json".data(using: .utf8)!)"#, "isn't JSON"),
        (#"DB.save("k", 5)"#, "needs Data"),
        (#"DB.save("k", ("\"" + String(repeating: "x", count: 70_000) + "\"").data(using: .utf8)!)"#, "over 64 KB"),
    ])
    func dbRefusalsAreErrorsWithTheirLine(_ call: String, _ message: String) {
        let session = DBSession(slug: "refusals")
        let (errors, _) = Self.probe(Self.app("""
            Text("x").onAppear {
                        \(call)
                    }
            """), session: session)
        #expect(errors.count == 1, "\(errors)")
        #expect(errors.first?.hasPrefix("Line 6: DB.save(_:_:): ") == true, "\(errors)")
        #expect(errors.first?.contains(message) == true, "\(errors)")
        #expect(session.all().isEmpty)
    }

    // MARK: The stage

    /// The runner opens an app's data from the library's own store, so a
    /// library with no server (the demo) never writes to the real one; and
    /// the New App preview copies from that same store.
    @Test func theStageUsesTheLibrarysStore() async throws {
        let folder = temporaryFolder()
        let library = LibraryStore(demo: [], cache: AppCache(root: folder))
        let slug = "stage-\(UUID().uuidString.lowercased())"
        let stored = await library.data.open(slug)
        try stored.write(.int(1), for: "k")
        let meta = AppMeta(slug: slug, name: "Stage", tint: .blue, version: "1")
        let source = "import SwiftUI\nstruct ContentView: View { var body: some View { Text(\"x\") } }"

        // Opened for real: the very session the library's store holds.
        let synced = try await Self.showing(AppStage(app: meta, source: source, store: .synced, host: library.host,
                                                     permissions: StubAppPermissions(), onRun: { _ in }))
        #expect(synced.context.provided(DBSession.self) === stored)
        #expect(synced.context.slug == slug)
        #expect(synced.isTornDown, "closing the stage didn't stop the run")

        // The preview: a copy of what that store holds, not the store itself.
        let scratch = try await Self.showing(AppStage(app: meta, source: source, store: .scratch(copying: slug),
                                                      host: library.host, permissions: StubAppPermissions()))
        let copy = try #require(scratch.context.provided(DBSession.self))
        #expect(copy !== stored)
        #expect(copy.value(for: "k") == .int(1))
        await library.data.reset()
    }

    /// A `body` that fails while the app runs: Shelf hears of it, with its
    /// line, and shows its error screen instead of Kiln's red label.
    @Test func aBodyErrorShowsTheErrorScreen() async throws {
        let library = LibraryStore(demo: [], cache: AppCache(root: temporaryFolder()))
        let meta = AppMeta(slug: "broken-\(UUID().uuidString.lowercased())", name: "Broken", tint: .red, version: "1")
        let source = Self.app(#"""
            VStack {
                        Text("Total")
                        Text(String(totals[3]))
                    }
            """#, state: "let totals = [1, 2]")
        let heard = Locked<[CompileError]>([])
        let window = try Self.window(AppStage(app: meta, source: source, store: .scratch(copying: nil), host: library.host,
                                              permissions: StubAppPermissions(), onError: { e in heard.withLock { $0.append(e) } }))
        defer { window.isHidden = true }
        let deadline = ContinuousClock.now + .seconds(5)
        while heard.value.isEmpty, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let error = try #require(heard.value.first)
        #expect(error.line == 7)
        #expect(error.message.contains("out of range"), "\(error.message)")
        #expect(error.excerpt.contains { $0.number == 7 && $0.text.contains("totals[3]") })

        // The error screen is what shows: the app's own text is gone.
        // Polled, not a fixed wait: the screen's crossfade runs late on a busy machine.
        let shown = ContinuousClock.now + .seconds(5)
        var labels = Self.texts(in: window)
        while !labels.contains(where: { $0.contains("Broken couldn’t open") }), ContinuousClock.now < shown {
            try await Task.sleep(for: .milliseconds(20))
            labels = Self.texts(in: window)
        }
        #expect(labels.contains { $0.contains("Broken couldn’t open") }, "\(labels)")
        #expect(!labels.contains("Total"), "\(labels)")
    }

    // MARK: Teardown

    /// Closing a card stops the app: its tasks, what its bridges started,
    /// and a permission request still waiting.
    @Test func tearingARunDownStopsItAndWithdrawsItsRequests() throws {
        final class Counting: AppPermissions {
            var cancelled = 0
            func request(_ capability: Capability) async -> Bool { true }
            func status(_ capability: Capability) -> PermissionStatus { .allowed }
            func cancelRequests() { cancelled += 1 }
        }
        let permissions = Counting()
        let host = AppHost(data: AppData(root: temporaryFolder(), api: { nil }),
                           defaults: AppDefaults(legacy: .standard, prefix: "shelf-tests.\(UUID().uuidString)."),
                           files: AppFiles(root: temporaryFolder()))
        defer { host.defaults.removeAll() }
        let context = RunContext.installed(Self.meta, session: DBSession(slug: "t"), permissions: permissions, host: host)
        var stopped = false
        context.onTearDown { stopped = true }
        let run = AppRun(context: context, permissions: permissions)
        run.result = Kiln.run(Self.app(#"Text("x").task { try? await Task.sleep(for: .seconds(30)) }"#), context: context)
        run.tearDown()
        #expect(stopped)
        #expect(run.isTornDown)
        #expect(permissions.cancelled >= 1)
        #expect(run.result?.activeTaskCount == 0)
    }

    /// The gate a run gets is the app's: Kiln's capabilities are Shelf's.
    @Test func theRunsGateIsTheAppsPermissions() async {
        let stub = StubAppPermissions([.location: .denied, .camera: .allowed], answerWhenAsked: false)
        let gate = PermissionsGate(stub)
        #expect(gate.status(.location) == .denied)
        #expect(gate.status(.camera) == .allowed)
        #expect(gate.status(.microphone) == .notAsked)
        #expect(gate.answerWithoutAsking(.camera))
        #expect(!gate.answerWithoutAsking(.microphone))
        #expect(await gate.request(.location) == false)
        #expect(stub.requested == [.camera, .microphone, .location])
        for capability in KilnCapability.allCases { #expect(Capability(capability) != nil, "\(capability)") }
    }

    // MARK: Settings

    @Test func legacyAppStorageMovesIntoTheAppsSuiteOnce() throws {
        let legacyName = "shelf-tests-legacy-\(UUID().uuidString)"
        let legacy = try #require(UserDefaults(suiteName: legacyName))
        defer { legacy.removePersistentDomain(forName: legacyName) }
        let defaults = AppDefaults(legacy: legacy, prefix: legacyName + ".app.")
        defer { defaults.removeAll() }
        legacy.set(3, forKey: "kiln.app.tip-jar.count")
        legacy.set("Ann", forKey: "kiln.app.tip-jar.name")
        legacy.set(9, forKey: "kiln.app.tip-jar-2.count")
        legacy.set(true, forKey: "unrelated")

        let suite = defaults.suite(for: "tip-jar")
        #expect(suite.integer(forKey: "count") == 3)
        #expect(suite.string(forKey: "name") == "Ann")
        #expect(suite.object(forKey: "unrelated") == nil, "another domain's key leaked in")
        #expect(legacy.object(forKey: "kiln.app.tip-jar.count") == nil, "moved, not copied")
        #expect(legacy.integer(forKey: "kiln.app.tip-jar-2.count") == 9, "another app's key moved")

        // Once: what the app sets since stays, even if an old key turns up.
        suite.set(4, forKey: "count")
        legacy.set(1, forKey: "kiln.app.tip-jar.count")
        #expect(defaults.suite(for: "tip-jar").integer(forKey: "count") == 4)

        // And the app reads it as its own `@AppStorage`.
        let (errors, console) = Self.probe(Self.app(#"""
            Text("\(count)").onAppear { print("count", count, name) }
            """#, state: #"""
            @AppStorage("count") private var count = 0
                @AppStorage("name") private var name = ""
            """#), defaults: defaults.suite(for: "tip-jar"))
        #expect(errors.isEmpty, "\(errors)")
        #expect(console == "count 4 Ann\n")
    }

    // MARK: Helpers

    static func app(_ body: String, state: String = "") -> String {
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

    /// Runs `source` headless with the actions fired, over `session`, with
    /// `defaults` as its settings: its errors and what it printed.
    static func probe(_ source: String, session: DBSession = DBSession(slug: "probe"),
                      defaults: UserDefaults? = nil) -> (errors: [String], console: String) {
        DBBridge.register()
        let context: KilnContext
        if let defaults {
            context = KilnContext(slug: "probe", name: "Probe", defaults: defaults,
                                  files: KilnFiles(root: temporaryFolder()))
        } else {
            context = RunContext.check(meta, session: session)
        }
        context.provide(session)
        defer { context.tearDown() }
        do {
            let compiled = try KilnEngine.compile(source, headless: true, context: context)
            KProbe(interp: compiled.interp, ticks: 1).run(compiled.root)
            compiled.interp.tearDown()
            return (compiled.interp.errors, compiled.interp.console)
        } catch {
            return (["\(error)"], "")
        }
    }

    static func window(_ stage: AppStage) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = UIHostingController(rootView: stage)
        window.isHidden = false
        return window
    }

    /// Shows `stage` until its app has been built, then closes it, and
    /// returns the run it had.
    static func showing(_ stage: AppStage) async throws -> AppRun {
        let runs = Locked<[AppRun]>([])
        var stage = stage
        let earlier = stage.onRun
        stage.onRun = { run in earlier(run); runs.withLock { $0.append(run) } }
        let window = try window(stage)
        let deadline = ContinuousClock.now + .seconds(5)
        while runs.value.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let run = try #require(runs.value.first)
        window.rootViewController = nil
        window.isHidden = true
        try await Task.sleep(for: .milliseconds(50))
        return run
    }

    static func texts(in window: UIWindow) -> [String] {
        func walk(_ element: NSObject) -> [String] {
            var out: [String] = []
            if let label = element.accessibilityLabel, !label.isEmpty { out.append(label) }
            for child in (element.accessibilityElements as? [NSObject]) ?? [] { out += walk(child) }
            if let view = element as? UIView { for sub in view.subviews { out += walk(sub) } }
            return out
        }
        return walk(window)
    }
}
