import Foundation
@testable import Shelf

/// Answers `db://` the way Shelf does, from a session that starts with the
/// stored values, and every web request with a failure, so no fixture
/// depends on the internet. Records every request.
final class FakeServer: URLProtocol, @unchecked Sendable {
    /// `path` is "/" and the key `ShelfDBProtocol` answered for.
    struct Seen: Sendable { var method: String; var path: String; var body: Data }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _seen: [Seen] = []
    nonisolated(unsafe) private static var session = DBSession(slug: "fixture")

    static var seen: [Seen] { lock.withLock { _seen } }

    static func start(stored: [String: Data] = [:]) {
        lock.withLock {
            _seen = []
            session = DBSession(slug: "fixture", entries: stored.compactMapValues(JSONValue.init(json:)))
        }
        URLProtocol.registerClass(FakeServer.self)
    }

    static func stop() {
        URLProtocol.unregisterClass(FakeServer.self)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        return ["db", "http", "https"].contains(url.scheme ?? "")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let method = request.httpMethod ?? "GET"
        let body = request.httpBody ?? request.httpBodyStream.map(ShelfDBProtocol.drain) ?? Data()
        if url.scheme != "db" {
            // The fixtures handle a failed request; that is the path worth pinning.
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let key = ShelfDBProtocol.key(for: request)
        let session = Self.lock.withLock {
            Self._seen.append(Seen(method: method, path: "/" + key, body: body))
            return Self.session
        }
        let reply = ShelfDBProtocol.answer(method: method, key: key, body: { body }, session: session)
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data = reply.body { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
