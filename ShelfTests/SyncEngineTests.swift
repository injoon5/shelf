import Foundation
import Synchronization
import Testing
@testable import Shelf

/// A fake `/api/apps` with an ETag, per-app sources, and switches for failure.
final class FakeLibrary: Sendable {
    struct State {
        var apps: [AppMeta] = []
        var sources: [String: String] = [:]
        var failing: Set<String> = []
        var offline = false
        var unauthorized = false
        var listDelay: Duration = .zero
        var sourceDelay: Duration = .zero
    }
    let state = Locked(State())
    let server = StubServer()

    init() {
        server.handle { [state] request in state.withLock { Self.respond(to: request, in: $0) } }
    }

    func put(_ slug: String, version: String, name: String? = nil) {
        state.withLock { state in
            let meta = AppMeta(slug: slug, name: name ?? slug.capitalized, tint: .teal, version: version, updatedAt: 1)
            if let i = state.apps.firstIndex(where: { $0.slug == slug }) { state.apps[i] = meta } else { state.apps.append(meta) }
            state.sources[slug] = "// Name: \(meta.name)\n// \(version)\n"
        }
    }

    func remove(_ slug: String) {
        state.withLock { state in
            state.apps.removeAll { $0.slug == slug }
            state.sources[slug] = nil
        }
    }

    func update(_ change: (inout State) -> Void) { state.withLock { change(&$0) } }

    var listRequests: [StubRequest] { server.requests("GET", "/api/apps") }
    func sourceRequests(_ slug: String) -> [StubRequest] { server.requests("GET", "/api/apps/\(slug)") }

    private static func respond(to request: StubRequest, in state: State) -> StubResponse {
        if state.offline { return .offline }
        if state.unauthorized { return .fixture("error-401", status: 401) }
        if request.path == "/api/apps" {
            let etag = "\"" + state.apps.map(\.version).joined(separator: "-") + "\""
            if request.header("If-None-Match") == etag { return StubResponse(status: 304).delayed(state.listDelay) }
            let apps = (try? JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(state.apps))) ?? .array([])
            return StubResponse.json(.object(["apps": apps]), headers: ["ETag": etag]).delayed(state.listDelay)
        }
        let slug = String(request.path.dropFirst("/api/apps/".count))
        guard let meta = state.apps.first(where: { $0.slug == slug }), let source = state.sources[slug] else {
            return .fixture("error-404", status: 404)
        }
        if state.failing.contains(slug) { return StubResponse(status: 500).delayed(state.sourceDelay) }
        guard case .object(var body)? = try? JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(meta)) else {
            return StubResponse(status: 500)
        }
        body["source"] = .string(source)
        return StubResponse.json(.object(body)).delayed(state.sourceDelay)
    }
}

/// Collects a sync's events.
final class EventLog: Sendable {
    private let events = Locked<[SyncEngine.Event]>([])
    func record(_ event: SyncEngine.Event) { events.withLock { $0.append(event) } }
    var all: [SyncEngine.Event] { events.withLock { $0 } }
    var listed: [CachedApp]? {
        for case .listed(let apps) in all { return apps }
        return nil
    }
    var summary: [String] {
        all.map { event in
            switch event {
            case .listed(let apps): "listed \(apps.map(\.slug).joined(separator: ","))"
            case .downloading(let slug): "downloading \(slug)"
            case .finished(let slug, let ok): "finished \(slug) \(ok)"
            }
        }
    }
}

struct SyncHarness {
    let library = FakeLibrary()
    let cache = AppCache(root: temporaryFolder())
    let suite = "shelf-tests-\(UUID().uuidString)"
    let defaults: UserDefaults
    let engine: SyncEngine
    let signedIn = Locked(true)

    init() {
        defaults = UserDefaults(suiteName: suite)!
        let api = library.server.api()
        engine = SyncEngine(cache: cache, api: { [signedIn] in signedIn.value ? api : nil },
                            appStorage: AppStorageKeys(defaults))
    }

    func sync(_ log: EventLog = EventLog()) async throws -> LibraryIndex {
        try await engine.sync { log.record($0) }
    }

    func app(_ slug: String, in index: LibraryIndex) -> CachedApp? {
        index.apps.first { $0.slug == slug }
    }

    func cleanUp() {
        cache.removeAll()
        defaults.removePersistentDomain(forName: suite)
    }
}

@Suite struct SyncEngineTests {
    @Test func firstSync() async throws {
        let h = SyncHarness()
        defer { h.cleanUp() }
        h.library.put("habits", version: "v1")
        h.library.put("tip-jar", version: "t1")

        let log = EventLog()
        let index = try await h.sync(log)

        #expect(index.apps.map(\.slug) == ["habits", "tip-jar"])
        #expect(index.apps.allSatisfy { $0.isCurrent && !$0.isNew })
        #expect(index.etag == "\"v1-t1\"")
        #expect(index.syncedAt != nil)
        #expect(h.cache.readIndex() == index)
        #expect(h.cache.source(for: "habits") == "// Name: Habits\n// v1\n")
        #expect(h.cache.source(for: "tip-jar") != nil)

        // The list comes first, with nothing on disk yet.
        #expect(log.summary.first == "listed habits,tip-jar")
        #expect(log.listed?.allSatisfy { $0.cachedVersion == nil && !$0.isNew } == true)
        #expect(Set(log.summary.dropFirst()) == ["downloading habits", "finished habits true", "downloading tip-jar", "finished tip-jar true"])
    }

    @Test func notModified() async throws {
        let h = SyncHarness()
        defer { h.cleanUp() }
        h.library.put("habits", version: "v1")
        let first = try await h.sync()

        let index = try await h.sync()
        #expect(h.library.listRequests.last?.header("If-None-Match") == "\"v1\"")
        #expect(h.library.sourceRequests("habits").count == 1)
        #expect(index.apps == first.apps)
        #expect(index.etag == first.etag)
        #expect(try #require(index.syncedAt) >= #require(first.syncedAt))
        #expect(h.cache.readIndex() == index)
    }

    @Test func update() async throws {
        let h = SyncHarness()
        defer { h.cleanUp() }
        h.library.put("habits", version: "v1")
        h.library.put("tip-jar", version: "t1")
        _ = try await h.sync()

        h.library.put("habits", version: "v2", name: "Habits 2")
        let log = EventLog()
        let index = try await h.sync(log)

        // Listed with the new meta and the old version on disk.
        let listed = try #require(log.listed?.first { $0.slug == "habits" })
        #expect(listed.meta.version == "v2")
        #expect(listed.meta.name == "Habits 2")
        #expect(listed.cachedVersion == "v1")
        #expect(!log.summary.contains("downloading tip-jar"))

        let habits = try #require(h.app("habits", in: index))
        #expect(habits.cachedVersion == "v2")
        #expect(habits.isNew)
        #expect(h.app("tip-jar", in: index)?.isNew == false)
        #expect(h.cache.source(for: "habits") == "// Name: Habits 2\n// v2\n")
        #expect(index.etag == "\"v2-t1\"")
    }

    @Test func partialFailure() async throws {
        let h = SyncHarness()
        defer { h.cleanUp() }
        h.library.put("habits", version: "v1")
        h.library.put("tip-jar", version: "t1")
        _ = try await h.sync()

        h.library.put("habits", version: "v2")
        h.library.put("tip-jar", version: "t2")
        h.library.put("notes", version: "n1")
        h.library.update { $0.failing = ["habits", "notes"] }
        let log = EventLog()
        let index = try await h.sync(log)

        let habits = try #require(h.app("habits", in: index))
        #expect(habits.meta.version == "v2")
        #expect(habits.cachedVersion == "v1")
        #expect(habits.isRunnable && !habits.isCurrent && !habits.isNew)
        #expect(h.cache.source(for: "habits") == "// Name: Habits\n// v1\n")
        let notes = try #require(h.app("notes", in: index))
        #expect(notes.cachedVersion == nil && !notes.isNew)
        #expect(h.app("tip-jar", in: index)?.cachedVersion == "t2")
        #expect(h.app("tip-jar", in: index)?.isNew == true)
        #expect(index.etag == nil)
        #expect(log.summary.contains("finished habits false"))
        #expect(log.summary.contains("finished notes false"))

        // The next sync can't get a 304, so it retries.
        h.library.update { $0.failing = [] }
        let retried = try await h.sync()
        #expect(h.library.listRequests.last?.header("If-None-Match") == nil)
        #expect(h.app("habits", in: retried)?.cachedVersion == "v2")
        #expect(h.app("habits", in: retried)?.isNew == true)
        #expect(h.app("notes", in: retried)?.cachedVersion == "n1")
        #expect(h.app("notes", in: retried)?.isNew == true)
        #expect(h.library.sourceRequests("tip-jar").count == 2)
        #expect(retried.etag == "\"v2-t2-n1\"")
        #expect(h.cache.source(for: "habits") == "// Name: Habits\n// v2\n")
    }

    @Test func deletedApp() async throws {
        let h = SyncHarness()
        defer { h.cleanUp() }
        h.library.put("habits", version: "v1")
        h.library.put("tip-jar", version: "t1")
        _ = try await h.sync()
        h.defaults.set(3, forKey: "kiln.app.tip-jar.count")
        h.defaults.set("x", forKey: "kiln.app.tip-jar.name")
        h.defaults.set(1, forKey: "kiln.app.tip-jar-2.count")
        h.defaults.set(2, forKey: "kiln.app.habits.count")
        h.defaults.set(true, forKey: "unrelated")

        h.library.remove("tip-jar")
        let index = try await h.sync()

        #expect(index.apps.map(\.slug) == ["habits"])
        #expect(h.cache.source(for: "tip-jar") == nil)
        #expect(!FileManager.default.fileExists(atPath: h.cache.root.appending(path: "tip-jar.swift").path(percentEncoded: false)))
        #expect(h.defaults.object(forKey: "kiln.app.tip-jar.count") == nil)
        #expect(h.defaults.object(forKey: "kiln.app.tip-jar.name") == nil)
        #expect(h.defaults.integer(forKey: "kiln.app.tip-jar-2.count") == 1)
        #expect(h.defaults.integer(forKey: "kiln.app.habits.count") == 2)
        #expect(h.defaults.bool(forKey: "unrelated"))
        #expect(h.cache.source(for: "habits") != nil)
    }

    @Test(arguments: ["unauthorized", "offline", "signedOut", "serverError"])
    func listFailureLeavesTheCacheUntouched(failure: String) async throws {
        let h = SyncHarness()
        defer { h.cleanUp() }
        h.library.put("habits", version: "v1")
        h.library.put("tip-jar", version: "t1")
        _ = try await h.sync()
        h.library.put("habits", version: "v2")
        h.library.remove("tip-jar")
        h.defaults.set(1, forKey: "kiln.app.tip-jar.count")
        let before = snapshot(of: h.cache.root)
        #expect(before.count == 3)

        let expected: API.Failure
        switch failure {
        case "unauthorized":
            h.library.update { $0.unauthorized = true }
            expected = .unauthorized
        case "offline":
            h.library.update { $0.offline = true }
            expected = .offline
        case "signedOut":
            h.signedIn.withLock { $0 = false }
            expected = .unauthorized
        default:
            h.library.server.handle { _ in StubResponse(status: 503) }
            expected = .rejected(status: 503, message: "The server had a problem. Try again later.")
        }
        await #expect(throws: expected) { try await h.sync() }
        #expect(snapshot(of: h.cache.root) == before)
        #expect(h.defaults.integer(forKey: "kiln.app.tip-jar.count") == 1)
    }

    @Test func blueDots() async throws {
        let h = SyncHarness()
        defer { h.cleanUp() }
        h.library.put("habits", version: "v1")
        _ = try await h.sync()

        // An app added after the first sync gets a dot.
        h.library.put("notes", version: "n1")
        var index = try await h.sync()
        #expect(h.app("notes", in: index)?.isNew == true)
        #expect(h.app("habits", in: index)?.isNew == false)

        // It stays through syncs that change nothing, and through other changes.
        h.library.put("habits", version: "v2")
        index = try await h.sync()
        #expect(h.app("notes", in: index)?.isNew == true)
        #expect(h.app("habits", in: index)?.isNew == true)

        // Opening clears it, on disk too.
        index = await h.engine.markOpened("notes")
        #expect(h.app("notes", in: index)?.isNew == false)
        #expect(h.app("notes", in: h.cache.readIndex())?.isNew == false)
        #expect(h.app("habits", in: h.cache.readIndex())?.isNew == true)
        index = try await h.sync()
        #expect(h.app("notes", in: index)?.isNew == false)
    }

    @Test func firstSyncAfterSignInMarksNothing() async throws {
        let h = SyncHarness()
        defer { h.cleanUp() }
        for i in 0..<3 { h.library.put("app\(i)", version: "1") }
        let index = try await h.sync()
        #expect(index.apps.count == 3)
        #expect(index.apps.allSatisfy { !$0.isNew })
    }

    @Test func atMostFourDownloadsAtOnce() async throws {
        let h = SyncHarness()
        defer { h.cleanUp() }
        for i in 0..<10 { h.library.put("app\(i)", version: "1") }
        h.library.update { $0.sourceDelay = .milliseconds(150) }

        let index = try await h.sync()
        #expect(index.apps.count == 10)
        #expect(index.apps.allSatisfy { $0.isCurrent })
        #expect(h.library.server.maxInFlight == 4)
    }

    @Test func overlappingSyncsShareOneRun() async throws {
        let h = SyncHarness()
        defer { h.cleanUp() }
        h.library.put("habits", version: "v1")
        h.library.update { $0.listDelay = .milliseconds(200) }

        let engine = h.engine
        async let a = engine.sync()
        async let b = engine.sync()
        let (first, second) = try await (a, b)
        #expect(first == second)
        #expect(h.library.listRequests.count == 1)
        #expect(h.library.sourceRequests("habits").count == 1)
    }

    @Test func fetchesOneApp() async throws {
        let h = SyncHarness()
        defer { h.cleanUp() }
        h.library.put("habits", version: "v1")
        h.library.put("notes", version: "n1")
        h.library.update { $0.failing = ["notes"] }
        _ = try await h.sync()
        h.library.update { $0.failing = [] }

        // A first download, as from a tap on the install pie: no dot.
        var index = try await h.engine.fetch("notes")
        #expect(h.app("notes", in: index)?.cachedVersion == "n1")
        #expect(h.app("notes", in: index)?.isNew == false)
        #expect(h.cache.source(for: "notes") != nil)
        #expect(h.cache.readIndex() == index)

        // An update to source already here: a dot, and no stale etag.
        h.library.put("habits", version: "v2")
        index = try await h.engine.fetch("habits")
        #expect(h.app("habits", in: index)?.cachedVersion == "v2")
        #expect(h.app("habits", in: index)?.isNew == true)
        #expect(index.etag == nil)

        h.library.update { $0.offline = true }
        await #expect(throws: API.Failure.offline) { try await h.engine.fetch("habits") }
    }

    @Test func missingSourceIsDownloadedAgain() async throws {
        let h = SyncHarness()
        defer { h.cleanUp() }
        h.library.put("habits", version: "v1")
        _ = try await h.sync()
        h.cache.removeSource(for: "habits")

        let index = try await h.sync()
        #expect(h.library.listRequests.last?.header("If-None-Match") == nil)
        #expect(h.app("habits", in: index)?.isCurrent == true)
        #expect(h.cache.source(for: "habits") != nil)
    }

    @Test func reset() async throws {
        let h = SyncHarness()
        defer { h.cleanUp() }
        h.library.put("habits", version: "v1")
        _ = try await h.sync()
        h.defaults.set(1, forKey: "kiln.app.habits.count")
        h.defaults.set(1, forKey: "kiln.other")

        await h.engine.reset()
        #expect(h.cache.readIndex() == LibraryIndex())
        #expect(!FileManager.default.fileExists(atPath: h.cache.root.path(percentEncoded: false)))
        #expect(h.defaults.object(forKey: "kiln.app.habits.count") == nil)
        #expect(h.defaults.integer(forKey: "kiln.other") == 1)
    }
}

@Suite struct AppCacheTests {
    @Test func roundTrips() throws {
        let cache = AppCache(root: temporaryFolder())
        defer { cache.removeAll() }
        #expect(cache.readIndex() == LibraryIndex())
        #expect(cache.source(for: "a") == nil)

        let index = LibraryIndex(etag: "\"e\"", apps: [CachedApp(meta: AppMeta(slug: "a", name: "A", version: "1"), cachedVersion: "1", isNew: true)], syncedAt: Date(timeIntervalSince1970: 1000))
        try cache.writeIndex(index)
        try cache.writeSource("hello", for: "a")
        #expect(cache.readIndex() == index)
        #expect(cache.source(for: "a") == "hello")
        #expect(cache.sourceSlugs() == ["a"])

        let protection = try FileManager.default.attributesOfItem(atPath: cache.root.appending(path: "a.swift").path(percentEncoded: false))[.protectionKey] as? FileProtectionType
        #expect(protection == nil || protection == .completeUntilFirstUserAuthentication)

        cache.removeSource(for: "a")
        #expect(cache.source(for: "a") == nil)
        #expect(throws: AppCache.Failure.self) { try cache.writeSource("x", for: "../evil") }
    }

    @Test func unreadableIndexIsEmpty() throws {
        let cache = AppCache(root: temporaryFolder())
        defer { cache.removeAll() }
        try FileManager.default.createDirectory(at: cache.root, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: cache.root.appending(path: "index.json"))
        #expect(cache.readIndex() == LibraryIndex())
    }
}
