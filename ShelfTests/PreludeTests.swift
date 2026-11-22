import Foundation
import Kiln
import Testing
@testable import Shelf

/// The gate from the plan (§8.4): before anything depends on the `DB` prelude,
/// prove that Kiln's engine accepts it and that a `db://` request made by
/// interpreted code really reaches a `URLProtocol` on `URLSession.shared`.
@MainActor
@Suite(.serialized)
struct PreludeTests {
    @Test func kilnAcceptsThePreludeAndExample() throws {
        let source = try Fixture.app("todos-db") + "\n" + Prelude.db
        let result = Kiln.run(source)
        #expect(result.errors.isEmpty, "\(result.errors)")
        #expect(result.hasView)
    }

    @Test func interpretedCodeReachesTheDBScheme() throws {
        SpyProtocol.reset(stored: ["todos": Data(#"[{"title":"Milk"}]"#.utf8)])
        URLProtocol.registerClass(SpyProtocol.self)
        defer { URLProtocol.unregisterClass(SpyProtocol.self) }

        // The probe fires onAppear, which loads the stored list; that change saves it back.
        let source = try Fixture.app("todos-db") + "\n" + Prelude.db
        let validation = Kiln.validate(source)
        #expect(validation.errors.isEmpty, "\(validation.errors)")
        #expect(validation.hasView)

        let seen = SpyProtocol.seen
        #expect(seen.first.map { "\($0.method) \($0.path)" } == "GET /todos")
        let put = try #require(seen.first { $0.method == "PUT" && $0.path == "/todos" }, "\(seen.map { "\($0.method) \($0.path)" })")
        let saved = try #require(try JSONSerialization.jsonObject(with: put.body) as? [[String: Any]])
        // The stored item had only a title: the rest comes from the type's defaults.
        #expect(saved.first?["title"] as? String == "Milk")
        #expect(saved.first?["done"] as? Bool == false)
        #expect((saved.first?["id"] as? String).flatMap(UUID.init(uuidString:)) != nil)
    }
}

enum Fixture {
    static var root: URL {
        Bundle(for: Anchor.self).resourceURL!.appending(path: "fixtures")
    }
    static func app(_ name: String) throws -> String {
        try String(contentsOf: root.appending(path: "apps/\(name).swift"), encoding: .utf8)
    }
    private final class Anchor {}
}

/// Answers `db://data/{key}` from a dictionary and records what it was asked.
final class SpyProtocol: URLProtocol, @unchecked Sendable {
    struct Seen: Sendable { var method: String; var path: String; var body: Data }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _seen: [Seen] = []
    nonisolated(unsafe) private static var _stored: [String: Data] = [:]

    static var seen: [Seen] { lock.withLock { _seen } }
    static func reset(stored: [String: Data]) { lock.withLock { _seen = []; _stored = stored } }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.scheme == "db" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let method = request.httpMethod ?? "GET"
        let body = request.httpBody ?? request.httpBodyStream.map(Self.drain) ?? Data()
        let key = String(url.path.dropFirst())
        let found: Data? = Self.lock.withLock {
            Self._seen.append(Seen(method: method, path: url.path, body: body))
            if method == "PUT" { Self._stored[key] = body }
            return Self._stored[key]
        }
        let status = method == "GET" ? (found == nil ? 404 : 200) : 204
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if method == "GET", let found { client?.urlProtocol(self, didLoad: found) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func drain(_ stream: InputStream) -> Data {
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}
