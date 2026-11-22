import Foundation
import Testing
@testable import Shelf

/// The API client against the real response bodies in `fixtures/api`.
struct APITests {
    static let token = "secret-token-7f3a9c"

    // MARK: Every fixture decodes

    @Test func everyFixtureIsJSON() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: Fixture.root.appending(path: "api").path(percentEncoded: false))
            .filter { $0.hasSuffix(".json") }
        #expect(names.count >= 26)
        for name in names {
            #expect(JSONValue(json: Fixture.api(String(name.dropLast(5)))) != nil, "\(name)")
        }
    }

    @Test func listsApps() async throws {
        let server = StubServer { _ in .fixture("apps", headers: ["ETag": #""abc123""#]) }
        let listing = try await server.api(token: Self.token).apps(ifNoneMatch: nil)
        guard case .apps(let apps, let etag) = listing else { Issue.record("\(listing)"); return }
        #expect(etag == #""abc123""#)
        #expect(apps.map(\.slug) == ["habits", "tip-jar"])
        #expect(apps[0] == AppMeta(slug: "habits", name: "Habits", icon: "checkmark.circle.fill", tint: .green,
                                   version: "Sq2UK0Jsbo62g16z", updatedAt: 1795350589603, revertible: true))
        #expect(apps[1].icon == nil)
        #expect(apps[1].tint == .mint)

        let request = try #require(server.requests.first)
        #expect(request.method == "GET")
        #expect(request.path == "/api/apps")
        #expect(request.header("Authorization") == "Bearer \(Self.token)")
        #expect(request.header("If-None-Match") == nil)
    }

    @Test func notModified() async throws {
        let server = StubServer { request in
            request.header("If-None-Match") == #"W/"abc""# ? StubResponse(status: 304) : .fixture("apps")
        }
        let listing = try await server.api().apps(ifNoneMatch: #"W/"abc""#)
        #expect(listing == .unchanged)
        #expect(server.requests.first?.header("If-None-Match") == #"W/"abc""#)
    }

    @Test func listingWithoutETag() async throws {
        let server = StubServer { _ in .fixture("apps") }
        guard case .apps(_, let etag) = try await server.api().apps(ifNoneMatch: nil) else { Issue.record(); return }
        #expect(etag == nil)
    }

    @Test func fetchesOneApp() async throws {
        let server = StubServer { _ in .fixture("app") }
        let app = try await server.api().app("habits")
        #expect(app.meta.slug == "habits")
        #expect(app.meta.version == "Sq2UK0Jsbo62g16z")
        #expect(app.source.hasPrefix("// Name: Habits\n"))
        #expect(server.requests.first?.path == "/api/apps/habits")
    }

    @Test func installs() async throws {
        let server = StubServer { _ in .fixture("app-put", status: 201) }
        let meta = try await server.api().install(slug: "habits", name: "Habits", icon: nil, tint: .green, source: "// Name: Habits\n")
        #expect(meta.version == "5XQdzfAmgEiss7e7")
        #expect(meta.revertible == false)
        let request = try #require(server.requests.first)
        #expect(request.method == "PUT")
        #expect(request.path == "/api/apps/habits")
        #expect(request.header("Content-Type") == "application/json")
        #expect(request.json == .object([
            "name": .string("Habits"), "icon": .null, "tint": .string("green"), "source": .string("// Name: Habits\n"),
        ]))
    }

    @Test func reverts() async throws {
        let server = StubServer { _ in .fixture("app-revert") }
        let meta = try await server.api().revert("habits")
        #expect(meta.revertible)
        #expect(server.requests.first.map { "\($0.method) \($0.path)" } == "POST /api/apps/habits/revert")
    }

    @Test func readsDataChanges() async throws {
        let server = StubServer { _ in .fixture("data-since") }
        let changes = try await server.api().changes(for: "habits", since: 1)
        #expect(changes.rev == 4)
        #expect(changes.changes == [
            .init(key: "streak", value: nil, rev: 3),
            .init(key: "settings", value: .object(["theme": .string("dark")]), rev: 4),
        ])
        let request = try #require(server.requests.first)
        #expect(request.path == "/api/apps/habits/data")
        #expect(request.query == ["since": "1"])
    }

    @Test func pushesABatch() async throws {
        let server = StubServer { _ in .fixture("data-batch") }
        let rev = try await server.api().push(to: "habits", set: ["a": .int(1)], delete: ["b"])
        #expect(rev == 4)
        let request = try #require(server.requests.first)
        #expect("\(request.method) \(request.path)" == "POST /api/apps/habits/data")
        #expect(request.json == .object(["set": .object(["a": .int(1)]), "delete": .array([.string("b")])]))
    }

    @Test func mintsKeys() async throws {
        let server = StubServer { _ in .fixture("install-key", status: 201) }
        let key = try await server.api().mintKey(for: "habits")
        #expect(key.id == "vVFOoGTDhjQ")
        #expect(key.key.hasPrefix("shelf_ik_vVFOoGTDhjQ_"))
        #expect(key.expiresAt == 1795352389610)
        _ = try await server.api().mintKey(for: nil)
        #expect(server.requests.map(\.json) == [.object(["slug": .string("habits")]), .object([:])])
        #expect(server.requests.allSatisfy { $0.method == "POST" && $0.path == "/api/install-keys" })
    }

    @Test func keyStatuses() async throws {
        let server = StubServer { request in
            switch request.path {
            case "/api/install-keys/w": .fixture("install-key-status-waiting")
            case "/api/install-keys/u": .fixture("install-key-status-used")
            default: .fixture("error-404", status: 404)
            }
        }
        let api = server.api()
        #expect(try await api.keyStatus("w") == .waiting)
        #expect(try await api.keyStatus("u") == .used(slug: "counter"))
        #expect(try await api.keyStatus("gone") == .expired)
    }

    @Test func revokesKeys() async throws {
        let server = StubServer { request in
            request.path == "/api/install-keys/7TDZRwWE8Hc" ? .fixture("install-key-revoke") : .fixture("error-404", status: 404)
        }
        try await server.api().revokeKey("7TDZRwWE8Hc")
        try await server.api().revokeKey("unknown")
        #expect(server.requests.map(\.method) == ["DELETE", "DELETE"])
    }

    // MARK: URLs

    @Test func encodesPathSegments() async throws {
        let server = StubServer { _ in .fixture("app") }
        _ = try? await server.api().app("a b/c?d#e%")
        #expect(server.requests.first?.path == "/api/apps/a%20b%2Fc%3Fd%23e%25")
    }

    @Test func keepsTheOriginsPath() {
        let api = API(origin: URL(string: "http://192.168.1.2:5173/base/")!, token: "t")
        #expect(api.url(["apps", "x"])?.absoluteString == "http://192.168.1.2:5173/base/api/apps/x")
        let plain = API(origin: URL(string: "https://ij5.dev")!, token: "t")
        #expect(plain.url(["apps"], query: [URLQueryItem(name: "since", value: "3")])?.absoluteString == "https://ij5.dev/api/apps?since=3")
    }

    @Test func aSiteIsTheSameHoweverItIsTyped() {
        let site = URL(string: "https://ij5.dev")!
        #expect(Account.isSameSite(site, URL(string: "https://IJ5.dev/")!))
        #expect(Account.isSameSite(URL(string: "http://192.168.1.2:5173/base/")!, URL(string: "http://192.168.1.2:5173/base")!))
        #expect(!Account.isSameSite(site, URL(string: "http://ij5.dev")!))
        #expect(!Account.isSameSite(site, URL(string: "https://ij5.dev:8443")!))
        #expect(!Account.isSameSite(site, URL(string: "https://ij5.dev/other")!))
    }

    // MARK: Errors

    @Test(arguments: [
        ("error-401", 401, API.Failure.unauthorized),
        ("error-401-missing", 401, .unauthorized),
        ("error-409", 409, .rejected(status: 409, message: "That slug is taken. Pick another.")),
        ("error-413", 413, .rejected(status: 413, message: "An app can be at most 256 KB.")),
        ("error-413-data", 413, .rejected(status: 413, message: "A value can be at most 64 KB.")),
        ("error-422", 422, .rejected(status: 422, message: "That app is not valid.")),
        ("error-404-revert", 404, .rejected(status: 404, message: "Nothing to revert to.")),
        ("error-400", 400, .rejected(status: 400, message: "Body must be JSON.")),
    ])
    func mapsErrors(fixture: String, status: Int, expected: API.Failure) async {
        let server = StubServer { _ in .fixture(fixture, status: status) }
        await #expect(throws: expected) { try await server.api().install(slug: "x", name: "X", icon: nil, tint: .blue, source: "") }
    }

    @Test func offline() async {
        let server = StubServer { _ in .offline }
        await #expect(throws: API.Failure.offline) { try await server.api().apps(ifNoneMatch: nil) }
    }

    @Test func serverErrorWithoutJSON() async {
        let server = StubServer { _ in StubResponse(status: 502, body: Data("<html>Bad Gateway</html>".utf8)) }
        await #expect(throws: API.Failure.rejected(status: 502, message: "The server had a problem. Try again later.")) {
            try await server.api().app("x")
        }
    }

    @Test func unreadableSuccess() async {
        let server = StubServer { _ in .json(#"{"unexpected": true}"#) }
        await #expect(throws: API.Failure.rejected(status: 200, message: "The server's answer couldn't be read.")) {
            try await server.api().app("x")
        }
    }

    @Test func errorsNeverCarryTheToken() async {
        let responses: [StubResponse] = [
            .offline, .fixture("error-401", status: 401), .fixture("error-409", status: 409),
            StubResponse(status: 500), .json("not json"),
            .json(#"{"error": "x"}"#, status: 418),
        ]
        for response in responses {
            let server = StubServer { _ in response }
            do {
                _ = try await server.api(token: Self.token).app("x")
                Issue.record("expected a failure")
            } catch {
                for text in [String(describing: error), String(reflecting: error), error.localizedDescription] {
                    #expect(!text.contains(Self.token), "\(text)")
                }
            }
        }
    }
}
