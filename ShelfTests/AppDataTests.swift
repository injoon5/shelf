import Foundation
import Synchronization
import Testing
@testable import Shelf

/// A fake `/api/apps/{slug}/data` with one global rev, like the server's.
final class FakeDataServer: Sendable {
    struct Row: Equatable { var value: JSONValue?; var rev: Int }
    struct State {
        var rows: [String: [String: Row]] = [:]
        var rev = 0
        var offline = false
        var pullDelay: Duration = .zero
        var pushDelay: Duration = .zero
        var pushes: [JSONValue] = []
    }
    let state = Locked(State())
    let server = StubServer()

    init() {
        server.handle { [state] request in state.withLock { Self.respond(to: request, in: &$0) } }
    }

    /// Another device writes (or deletes, with nil).
    func write(_ slug: String, _ key: String, _ value: JSONValue?) {
        state.withLock { state in
            state.rev += 1
            state.rows[slug, default: [:]][key] = Row(value: value, rev: state.rev)
        }
    }

    func value(_ slug: String, _ key: String) -> JSONValue? {
        state.withLock { $0.rows[slug]?[key]?.value }
    }
    func row(_ slug: String, _ key: String) -> Row? { state.withLock { $0.rows[slug]?[key] } }
    var pushes: [JSONValue] { state.withLock { $0.pushes } }
    func update(_ change: (inout State) -> Void) { state.withLock { change(&$0) } }

    private static func respond(to request: StubRequest, in state: inout State) -> StubResponse {
        if state.offline { return .offline }
        let parts = request.path.split(separator: "/").map(String.init)  // api apps {slug} data
        guard parts.count == 4, parts[3] == "data" else { return StubResponse(status: 404) }
        let slug = parts[2].removingPercentEncoding ?? parts[2]
        switch request.method {
        case "GET":
            let since = Int(request.query["since"] ?? "0") ?? 0
            let rows = state.rows[slug] ?? [:]
            let changes = rows.filter { $0.value.rev > since }.sorted { $0.value.rev < $1.value.rev }
                .map { JSONValue.object(["key": .string($0.key), "value": $0.value.value ?? .null, "rev": .int($0.value.rev)]) }
            let newest = rows.values.map(\.rev).max() ?? 0
            return StubResponse.json(.object(["changes": .array(changes), "rev": .int(max(since, newest))])).delayed(state.pullDelay)
        case "POST":
            guard let body = request.json, case .object(let fields) = body else { return StubResponse(status: 400) }
            state.pushes.append(body)
            state.rev += 1
            if case .object(let set)? = fields["set"] {
                for (key, value) in set { state.rows[slug, default: [:]][key] = Row(value: value, rev: state.rev) }
            }
            if case .array(let keys)? = fields["delete"] {
                for case .string(let key) in keys { state.rows[slug, default: [:]][key] = Row(value: nil, rev: state.rev) }
            }
            return StubResponse.json(.object(["rev": .int(state.rev)])).delayed(state.pushDelay)
        default:
            return StubResponse(status: 405)
        }
    }
}

struct DataHarness {
    let remote = FakeDataServer()
    let root = temporaryFolder()
    let signedIn = Locked(true)

    func store(pushDelay: Duration = .milliseconds(50), saveDelay: Duration = .milliseconds(20)) -> AppData {
        let api = remote.server.api()
        return AppData(root: root, api: { [signedIn] in signedIn.value ? api : nil },
                       pushDelay: pushDelay, saveDelay: saveDelay)
    }

    func file(_ slug: String) -> DBSession.File? {
        guard let data = try? Data(contentsOf: root.appending(path: "\(slug).json")) else { return nil }
        return try? JSONDecoder().decode(DBSession.File.self, from: data)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

@Suite struct AppDataTests {
    @Test func offlineWriteIsPushedLater() async throws {
        let h = DataHarness()
        defer { h.cleanUp() }
        h.remote.update { $0.offline = true }
        let store = h.store()

        let session = await store.open("todos")
        try session.write(.array([.string("Milk")]), for: "list")
        #expect(session.value(for: "list") == .array([.string("Milk")]))
        await store.close(session)
        #expect(h.file("todos")?.dirty == ["list"])
        #expect(h.file("todos")?.entries["list"]?.value == .array([.string("Milk")]))

        // Back online, in a later launch.
        h.remote.update { $0.offline = false }
        let later = h.store()
        await later.pushAll()
        #expect(h.remote.value("todos", "list") == .array([.string("Milk")]))
        #expect(h.file("todos")?.dirty == [])
    }

    @Test func pushesOnceWritesHaveSettled() async throws {
        let h = DataHarness()
        defer { h.cleanUp() }
        // Each write restarts the wait: the sleeps add to more than one
        // delay, but no gap is one, with room for a slow machine.
        let store = h.store(pushDelay: .seconds(1))
        let session = await store.open("todos")
        try session.write(.int(1), for: "a")
        try await Task.sleep(for: .milliseconds(600))
        try session.write(.int(2), for: "a")
        try await Task.sleep(for: .milliseconds(600))
        #expect(h.remote.pushes.isEmpty)
        #expect(await eventually { h.remote.value("todos", "a") == .int(2) })
        #expect(h.remote.pushes.count == 1)
        // Saved to disk long before the push.
        #expect(h.file("todos")?.entries["a"]?.value == .int(2))
    }

    @Test func dirtyKeySurvivesAPull() async throws {
        let h = DataHarness()
        defer { h.cleanUp() }
        h.remote.update { $0.offline = true }
        let store = h.store(pushDelay: .seconds(60))
        let session = await store.open("todos")
        try session.write(.string("phone"), for: "k")

        h.remote.update { $0.offline = false }
        h.remote.write("todos", "k", .string("web"))
        h.remote.write("todos", "other", .string("web"))
        await store.pull(["todos"])
        #expect(session.value(for: "k") == .string("phone"))
        #expect(session.value(for: "other") == .string("web"))

        await store.pushAll()
        #expect(h.remote.value("todos", "k") == .string("phone"))
    }

    @Test func tombstoneRemovesACleanKey() async throws {
        let h = DataHarness()
        defer { h.cleanUp() }
        h.remote.write("todos", "k", .int(1))
        let store = h.store()
        let session = await store.open("todos")
        #expect(session.value(for: "k") == .int(1))

        h.remote.write("todos", "k", nil)
        await store.pull(["todos"])
        #expect(session.value(for: "k") == nil)
        #expect(h.file("todos")?.entries["k"] == nil)
        #expect(h.file("todos")?.rev == 2)
    }

    @Test func localDeleteIsPushedAsADelete() async throws {
        let h = DataHarness()
        defer { h.cleanUp() }
        h.remote.write("todos", "k", .int(1))
        h.remote.write("todos", "keep", .int(2))
        let store = h.store(pushDelay: .seconds(60))
        let session = await store.open("todos")
        session.remove("k")
        #expect(session.value(for: "k") == nil)
        await store.close(session)

        #expect(h.remote.pushes == [.object(["set": .object([:]), "delete": .array([.string("k")])])])
        #expect(h.remote.row("todos", "k")?.value == nil)
        #expect(h.remote.value("todos", "keep") == .int(2))
        #expect(h.file("todos")?.dirty == [])
    }

    @Test func pushDoesNotMoveTheCursor() async throws {
        let h = DataHarness()
        defer { h.cleanUp() }
        let store = h.store(pushDelay: .seconds(60))
        let session = await store.open("todos")
        #expect(h.file("todos")?.rev ?? 0 == 0)

        // Another device writes; this one pushes before it pulls.
        h.remote.write("todos", "theirs", .int(1))
        try session.write(.int(2), for: "mine")
        await store.pushAll()
        #expect(h.remote.row("todos", "mine")?.rev == 2)
        #expect(h.file("todos")?.rev == 0)

        await store.pull(["todos"])
        #expect(session.value(for: "theirs") == .int(1))
        #expect(session.value(for: "mine") == .int(2))
        #expect(h.file("todos")?.rev == 2)
    }

    @Test func keyWrittenDuringAPushStaysDirty() async throws {
        let h = DataHarness()
        defer { h.cleanUp() }
        h.remote.update { $0.pushDelay = .milliseconds(300) }
        let store = h.store(pushDelay: .seconds(60))
        let session = await store.open("todos")
        try session.write(.int(1), for: "k")

        let push = Task { await store.pushAll() }
        #expect(await eventually { !h.remote.pushes.isEmpty })
        try session.write(.int(2), for: "k")
        await push.value
        #expect(h.remote.value("todos", "k") == .int(1))
        #expect(await eventually { h.file("todos")?.dirty == ["k"] })

        h.remote.update { $0.pushDelay = .zero }
        await store.pushAll()
        #expect(h.remote.value("todos", "k") == .int(2))
        #expect(h.file("todos")?.dirty == [])
    }

    @Test func openWaitsForThePullAtMostTheTimeout() async throws {
        let h = DataHarness()
        defer { h.cleanUp() }
        h.remote.write("todos", "k", .int(1))
        h.remote.update { $0.pullDelay = .milliseconds(800) }
        let store = h.store()

        let clock = ContinuousClock()
        let start = clock.now
        let session = await store.open("todos", pullTimeout: .milliseconds(100))
        #expect(clock.now - start < .milliseconds(600))
        #expect(session.value(for: "k") == nil)

        // The late pull still lands.
        #expect(await eventually { session.value(for: "k") == .int(1) })
    }

    @Test func openWithAQuickServerHasItsData() async throws {
        let h = DataHarness()
        defer { h.cleanUp() }
        h.remote.write("todos", "k", .int(1))
        let session = await h.store().open("todos")
        #expect(session.value(for: "k") == .int(1))
        #expect(session.all() == ["k": .int(1)])
    }

    @Test func signedOutSkipsQuietly() async throws {
        let h = DataHarness()
        defer { h.cleanUp() }
        h.signedIn.withLock { $0 = false }
        let store = h.store()
        let session = await store.open("todos")
        try session.write(.int(1), for: "k")
        await store.close(session)
        #expect(h.remote.server.requests.isEmpty)
        #expect(h.file("todos")?.dirty == ["k"])
    }

    @Test func scratchNeverTouchesDisk() async throws {
        let h = DataHarness()
        defer { h.cleanUp() }
        let store = h.store()
        let real = await store.open("todos")
        try real.write(.int(1), for: "k")
        await store.close(real)
        let before = snapshot(of: h.root)
        let pushes = h.remote.pushes.count

        let scratch = await store.scratch(copying: "todos")
        #expect(scratch.value(for: "k") == .int(1))
        try scratch.write(.int(99), for: "k")
        try scratch.write(.int(5), for: "new")
        await store.close(scratch)
        await store.pushAll()
        try await Task.sleep(for: .milliseconds(150))

        #expect(snapshot(of: h.root) == before)
        #expect(h.remote.pushes.count == pushes)
        #expect(real.value(for: "k") == .int(1))
        #expect(await store.scratch(copying: nil).all().isEmpty)
    }

    @Test func usageAndDeleteAllAndReset() async throws {
        let h = DataHarness()
        defer { h.cleanUp() }
        h.remote.write("todos", "unseen", .int(7))
        let store = h.store(pushDelay: .seconds(60))
        let todos = await store.open("todos")
        try todos.write(.string(String(repeating: "x", count: 1000)), for: "big")
        let notes = await store.open("notes")
        try notes.write(.int(1), for: "n")
        await store.close(notes)

        let usage = await store.usage()
        #expect(Set(usage.keys) == ["todos", "notes"])
        #expect(try #require(usage["todos"]) > 1000)
        #expect(try #require(usage["notes"]) > 0)

        // Delete Data: every key, including one this phone never pulled since open.
        h.remote.write("todos", "later", .int(8))
        await store.deleteAll(for: "todos")
        #expect(todos.all().isEmpty)
        #expect(h.remote.value("todos", "unseen") == nil)
        #expect(h.remote.value("todos", "later") == nil)
        #expect(h.remote.value("todos", "big") == nil)
        #expect(h.remote.value("notes", "n") == .int(1))

        let pushes = h.remote.pushes.count
        try notes.write(.int(2), for: "n")
        await store.reset()
        #expect(!FileManager.default.fileExists(atPath: h.root.path(percentEncoded: false)))
        await store.pushAll()
        try await Task.sleep(for: .milliseconds(100))
        #expect(h.remote.pushes.count == pushes)
        #expect(!FileManager.default.fileExists(atPath: h.root.path(percentEncoded: false)))
    }

    /// Delete App: the store goes with its pending writes, nothing is pushed,
    /// and a session the app still holds writes nowhere.
    @Test func removeDropsTheStoreAndItsPendingWrites() async throws {
        let h = DataHarness()
        defer { h.cleanUp() }
        let store = h.store(pushDelay: .milliseconds(100))
        let todos = await store.open("todos")
        try todos.write(.int(1), for: "saved")
        await store.close(todos)
        #expect(h.remote.value("todos", "saved") == .int(1))
        h.remote.update { $0.offline = true }
        try todos.write(.int(2), for: "pending")
        let notes = await store.open("notes")
        try notes.write(.int(1), for: "n")
        await store.close(notes)
        #expect(await eventually { h.file("todos")?.dirty == ["pending"] })

        await store.remove("todos")
        try todos.write(.int(3), for: "after")
        h.remote.update { $0.offline = false }

        try await Task.sleep(for: .milliseconds(300))
        await store.pushAll()
        #expect(h.remote.row("todos", "pending") == nil)
        #expect(h.remote.row("todos", "after") == nil)
        #expect(h.file("todos") == nil)
        #expect(await store.usage()["todos"] == nil)
        // The other app's pending write still goes.
        #expect(h.remote.value("notes", "n") == .int(1))
        // Made again under the same slug, it starts empty.
        let again = await store.open("todos", pullTimeout: .zero)
        #expect(again.value(for: "pending") == nil)
        #expect(again !== todos)
    }

    @Test func reloadsWhatWasSaved() async throws {
        let h = DataHarness()
        defer { h.cleanUp() }
        h.remote.update { $0.offline = true }
        let store = h.store(pushDelay: .seconds(60))
        let session = await store.open("todos")
        try session.write(.object(["a": .bool(true)]), for: "settings")
        #expect(await eventually { h.file("todos")?.entries["settings"] != nil })

        let reopened = await h.store().open("todos")
        #expect(reopened.value(for: "settings") == .object(["a": .bool(true)]))
    }
}

@Suite struct DBSessionLimitTests {
    @Test func keys() {
        let session = DBSession(slug: "t")
        for bad in ["", "a/b", "tab\there", "bell\u{7}", "del\u{7F}", "c1\u{85}", String(repeating: "k", count: 129)] {
            #expect(throws: DBSession.Refusal.invalidKey) { try session.write(.int(1), for: bad) }
        }
        for good in ["a", "with space", "ümlaut", "🙂", String(repeating: "k", count: 128), String(repeating: "🙂", count: 128)] {
            #expect(throws: Never.self) { try session.write(.int(1), for: good) }
        }
    }

    /// A string value whose JSON is exactly `bytes` long (its two quotes included).
    static func value(bytes: Int) -> JSONValue { .string(String(repeating: "x", count: bytes - 2)) }

    @Test func valueSize() {
        let session = DBSession(slug: "t")
        #expect(Self.value(bytes: 65536).json.count == 65536)
        #expect(throws: Never.self) { try session.write(Self.value(bytes: 65536), for: "fits") }
        #expect(throws: DBSession.Refusal.valueTooLarge) { try session.write(Self.value(bytes: 65537), for: "big") }
        #expect(session.value(for: "big") == nil)
    }

    @Test func keyCount() throws {
        let session = DBSession(slug: "t")
        for i in 0..<1000 { try session.write(.int(i), for: "k\(i)") }
        #expect(throws: DBSession.Refusal.tooManyKeys) { try session.write(.int(0), for: "one-more") }
        #expect(throws: Never.self) { try session.write(.int(-1), for: "k5") }
        session.remove("k0")
        #expect(throws: Never.self) { try session.write(.int(0), for: "one-more") }
    }

    @Test func storeSize() throws {
        let session = DBSession(slug: "t")
        for i in 0..<80 { try session.write(Self.value(bytes: 65536), for: "k\(i)") }
        #expect(throws: DBSession.Refusal.storeFull) { try session.write(.int(1), for: "x") }
        // Replacing a value with a smaller one is always allowed.
        #expect(throws: Never.self) { try session.write(.int(1), for: "k0") }
        #expect(throws: Never.self) { try session.write(.int(2), for: "x") }
    }

    @Test func nullDeletes() throws {
        let session = DBSession(slug: "t", entries: ["k": .int(1)])
        try session.write(.null, for: "k")
        #expect(session.value(for: "k") == nil)
    }
}
