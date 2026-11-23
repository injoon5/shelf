import Foundation
import Kiln
@testable import Shelf

/// Answers `db://` the way Shelf does, from a session that starts with the
/// stored values, and every web request with a failure, so no fixture
/// depends on the internet. Records every request. Kiln asks it for `db://`
/// first (`Kiln.hostRequestHandler`), as it asks `ShelfDBProtocol`.
final class FakeServer: URLProtocol, @unchecked Sendable {
    /// `path` is "/" and the key `ShelfDBProtocol` answered for.
    struct Seen: Sendable { var method: String; var path: String; var body: Data }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _seen: [Seen] = []
    nonisolated(unsafe) private static var session = DBSession(slug: "fixture")

    static var seen: [Seen] { lock.withLock { _seen } }

    @MainActor static func start(stored: [String: Data] = [:]) {
        lock.withLock {
            _seen = []
            session = DBSession(slug: "fixture", entries: stored.compactMapValues(JSONValue.init(json:)))
        }
        URLProtocol.registerClass(FakeServer.self)
        Kiln.hostRequestHandler = { request in
            guard request.url?.scheme == "db" else { return nil }
            let reply = answer(request)
            return KilnHostResponse(statusCode: reply.status, body: reply.body)
        }
    }

    @MainActor static func stop() {
        URLProtocol.unregisterClass(FakeServer.self)
        Kiln.hostRequestHandler = nil
    }

    /// Records a `db://` request and answers it from the session.
    static func answer(_ request: URLRequest) -> ShelfDBProtocol.Reply {
        let method = request.httpMethod ?? "GET"
        let body = request.httpBody ?? request.httpBodyStream.map(ShelfDBProtocol.drain) ?? Data()
        let key = ShelfDBProtocol.key(for: request)
        let session = lock.withLock {
            _seen.append(Seen(method: method, path: "/" + key, body: body))
            return Self.session
        }
        return ShelfDBProtocol.answer(method: method, key: key, body: { body }, session: session)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        return ["db", "http", "https"].contains(url.scheme ?? "")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        if url.scheme != "db" {
            // The fixtures handle a failed request; that is the path worth pinning.
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let reply = Self.answer(request)
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data = reply.body { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
