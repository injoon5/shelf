import Foundation
import Kiln
import Synchronization
import Testing
@testable import Shelf

/// `db://` through the real `URLSession.shared`, the way Kiln reaches it.
///
/// Every test runs synchronously on the main actor, blocking it while each
/// request loads, exactly as Kiln does. That also keeps these tests from
/// interleaving with the fixture tests, whose `FakeServer` also answers `db`.
@MainActor
@Suite(.serialized)
struct ShelfDBProtocolTests {
    struct Answer {
        var status: Int
        var body: Data
        var json: JSONValue? { JSONValue(json: body) }
    }

    /// Loads `url` on `URLSession.shared`, holding the calling thread until it ends.
    func load(_ url: String, method: String = "GET", body: Data? = nil) -> Answer? {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        request.httpBody = body
        let result = Locked<Answer?>(nil)
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse {
                result.withLock { $0 = Answer(status: http.statusCode, body: data ?? Data()) }
            }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 5)
        return result.value
    }

    @Test func theFourRoutes() {
        let session = DBSession(slug: "todos", entries: ["a": .int(1)])
        ShelfDBProtocol.activate(session)
        defer { ShelfDBProtocol.deactivate(session) }

        #expect(load("db://data/missing")?.status == 404)
        #expect(load("db://data/a")?.status == 200)
        #expect(load("db://data/a")?.json == .int(1))

        #expect(load("db://data/list", method: "PUT", body: Data(#"[{"title":"Milk"}]"#.utf8))?.status == 204)
        #expect(session.value(for: "list") == .array([.object(["title": .string("Milk")])]))
        #expect(load("db://data/list")?.json == .array([.object(["title": .string("Milk")])]))

        let all = load("db://data/")
        #expect(all?.status == 200)
        #expect(all?.json == .object(["a": .int(1), "list": .array([.object(["title": .string("Milk")])])]))

        #expect(load("db://data/a", method: "DELETE")?.status == 204)
        #expect(load("db://data/a")?.status == 404)
        #expect(session.value(for: "a") == nil)
    }

    @Test func refusals() {
        let session = DBSession(slug: "todos")
        ShelfDBProtocol.activate(session)
        defer { ShelfDBProtocol.deactivate(session) }

        #expect(load("db://data/k", method: "PUT", body: Data("not json".utf8))?.status == 400)
        #expect(load("db://data/k", method: "PUT")?.status == 400)
        #expect(load("db://data/a%2Fb", method: "PUT", body: Data("1".utf8))?.status == 400)
        #expect(load("db://data/", method: "PUT", body: Data("1".utf8))?.status == 400)
        let big = Data(("\"" + String(repeating: "x", count: 70_000) + "\"").utf8)
        #expect(load("db://data/big", method: "PUT", body: big)?.status == 413)
        #expect(session.all().isEmpty)
    }

    @Test func keysArePercentDecoded() {
        let session = DBSession(slug: "todos")
        ShelfDBProtocol.activate(session)
        defer { ShelfDBProtocol.deactivate(session) }

        #expect(load("db://data/my%20key", method: "PUT", body: Data("true".utf8))?.status == 204)
        #expect(session.value(for: "my key") == .bool(true))
        #expect(load("db://data/caf%C3%A9", method: "PUT", body: Data("1".utf8))?.status == 204)
        #expect(session.value(for: "café") == .int(1))
    }

    @Test func deactivateLeavesANewerSessionAlone() {
        let old = DBSession(slug: "old", entries: ["k": .string("old")])
        let new = DBSession(slug: "new", entries: ["k": .string("new")])
        ShelfDBProtocol.activate(old)
        ShelfDBProtocol.activate(new)
        ShelfDBProtocol.deactivate(old)
        #expect(ShelfDBProtocol.current === new)
        #expect(load("db://data/k")?.json == .string("new"))

        ShelfDBProtocol.deactivate(new)
        #expect(ShelfDBProtocol.current == nil)
        // No longer registered: nothing answers.
        #expect(load("db://data/k") == nil)
    }

    @Test func answersWithoutASession() {
        #expect(ShelfDBProtocol.answer(method: "GET", key: "k", body: { nil }, session: DBSession(slug: "x")).status == 404)
        #expect(ShelfDBProtocol.answer(method: "POST", key: "k", body: { nil }, session: DBSession(slug: "x")).status == 405)
        #expect(ShelfDBProtocol.key(in: URL(string: "db://data")!) == "")
        #expect(ShelfDBProtocol.key(in: URL(string: "db://data/a%2Fb")!) == "a/b")
    }

    /// The whole path: an app run by Kiln, the appended prelude, this protocol
    /// and a real session.
    @Test func kilnRoundTripsThroughARealSession() throws {
        let session = DBSession(slug: "todos", entries: [
            "todos": .array([.object(["title": .string("Milk")])]),
        ])
        ShelfDBProtocol.activate(session)
        defer { ShelfDBProtocol.deactivate(session) }

        // The probe fires onAppear, which loads the list; the change saves it back.
        let source = SourceRewriter.prepare(try Fixture.app("todos-db"), slug: "todos-db")
        let validation = Kiln.validate(source)
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
}
