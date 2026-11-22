import Foundation

/// Answers `db://data/{key}` from a dictionary, and the made-up web hosts the
/// fixtures use with canned replies, so no fixture depends on the internet.
final class FakeServer: URLProtocol, @unchecked Sendable {
    struct Seen: Sendable { var method: String; var path: String; var body: Data }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _seen: [Seen] = []
    nonisolated(unsafe) private static var _stored: [String: Data] = [:]
    static let webHosts: Set<String> = ["api.example.com", "picsum.photos"]

    static var seen: [Seen] { lock.withLock { _seen } }

    static func start(stored: [String: Data] = [:]) {
        lock.withLock { _seen = []; _stored = stored }
        URLProtocol.registerClass(FakeServer.self)
    }

    static func stop() {
        URLProtocol.unregisterClass(FakeServer.self)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        return url.scheme == "db" || webHosts.contains(url.host() ?? "")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let method = request.httpMethod ?? "GET"
        let body = request.httpBody ?? request.httpBodyStream.map(Self.drain) ?? Data()
        if url.scheme != "db" {
            // The fixtures handle a failed request; that is the path worth pinning.
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let key = String(url.path.dropFirst())
        let found: Data? = Self.lock.withLock {
            Self._seen.append(Seen(method: method, path: url.path, body: body))
            if method == "PUT" { Self._stored[key] = body }
            if method == "DELETE" { Self._stored[key] = nil }
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
