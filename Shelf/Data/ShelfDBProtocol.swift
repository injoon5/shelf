import Foundation
import Kiln
import Synchronization

/// Answers the private `db://` scheme from the open app's `DBSession`, without
/// touching the network (plan §8.4).
///
/// | Request                       | Answer                                  |
/// |-------------------------------|-----------------------------------------|
/// | `GET db://data/{key}`         | `200` with the JSON value, or `404`     |
/// | `PUT db://data/{key}` + JSON  | `204`; `400` not JSON or a bad key, `413` over a limit |
/// | `DELETE db://data/{key}`      | `204`                                   |
/// | `GET db://data/`              | `200` with `{ key: value }`             |
///
/// The key is the `DB-Key` header when there is one, which is how the `DB`
/// helper sends it (`Prelude`), and otherwise the URL's path after its first
/// "/", percent-decoded.
///
/// Kiln asks first: `activate` installs `answerForKiln` as
/// `Kiln.hostRequestHandler`, so the app's `DB` calls are answered on the main
/// actor, at once, without waiting (Kiln no longer blocks the main thread on
/// a request). Requests that come through `URLSession` itself are answered on
/// the loading thread, as before. PLAN.md §1.7 replaces both with a `DB` host
/// bridge.
final class ShelfDBProtocol: URLProtocol, @unchecked Sendable {
    private struct Registration {
        var session: DBSession?
        var registered = false
    }

    private static let registration = Mutex(Registration())

    /// Where `DB` puts the key. A key in a URL is cut short at "?" or "#" and
    /// has its "%" escapes decoded, and Kiln can't percent-encode one; a
    /// header carries every valid key as it is. It never leaves the phone.
    static let keyHeader = "DB-Key"

    /// The session `db://` requests go to now, if any.
    static var current: DBSession? { registration.withLock { $0.session } }

    /// Routes `db://` requests on `URLSession.shared` to `session` until
    /// `deactivate`. Shelf runs one app at a time, so the slug is never in the URL.
    @MainActor static func activate(_ session: DBSession) {
        Kiln.hostRequestHandler = answerForKiln
        registration.withLock { registration in
            registration.session = session
            if !registration.registered {
                URLProtocol.registerClass(ShelfDBProtocol.self)
                registration.registered = true
            }
        }
    }

    /// Stops answering for `session`. A newer session that has since been
    /// activated is left alone.
    @MainActor static func deactivate(_ session: DBSession) {
        registration.withLock { registration in
            guard registration.session === session else { return }
            registration.session = nil
            if registration.registered {
                URLProtocol.unregisterClass(ShelfDBProtocol.self)
                registration.registered = false
            }
        }
    }

    /// The table above for a request from the app's code (`Kiln.hostRequestHandler`):
    /// nil for anything but `db://`, which goes to the network as usual.
    @MainActor static func answerForKiln(_ request: URLRequest) -> KilnHostResponse? {
        guard request.url?.scheme?.lowercased() == "db" else { return nil }
        guard let session = current else { return KilnHostResponse(statusCode: 503) }
        let reply = answer(
            method: (request.httpMethod ?? "GET").uppercased(),
            key: key(for: request),
            body: { request.httpBody ?? request.httpBodyStream.map(drain) },
            session: session)
        return KilnHostResponse(statusCode: reply.status, body: reply.body)
    }

    // MARK: URLProtocol

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme?.lowercased() == "db"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard request.url != nil else { return finish(400) }
        guard let session = Self.current else { return finish(503) }
        let reply = Self.answer(
            method: (request.httpMethod ?? "GET").uppercased(),
            key: Self.key(for: request),
            body: { [request] in request.httpBody ?? request.httpBodyStream.map(Self.drain) },
            session: session)
        finish(reply.status, body: reply.body)
    }

    override func stopLoading() {}

    // MARK: Answers

    struct Reply: Equatable {
        var status: Int
        var body: Data?
    }

    /// The table above, as a pure function of the request and the session.
    static func answer(method: String, key: String, body: () -> Data?, session: DBSession) -> Reply {
        switch method {
        case "GET":
            if key.isEmpty { return Reply(status: 200, body: JSONValue.object(session.all()).json) }
            guard let value = session.value(for: key) else { return Reply(status: 404) }
            return Reply(status: 200, body: value.json)
        case "PUT":
            guard let data = body(), let value = JSONValue(json: data) else { return Reply(status: 400) }
            do {
                try session.write(value, for: key)
                return Reply(status: 204)
            } catch .invalidKey {
                return Reply(status: 400)
            } catch {
                return Reply(status: 413)
            }
        case "DELETE":
            guard DBSession.isValidKey(key) else { return Reply(status: 400) }
            session.remove(key)
            return Reply(status: 204)
        default:
            return Reply(status: 405)
        }
    }

    /// The `DB-Key` header, or else the key in the URL. Either way the open
    /// app's session answers, so no key names another app's data.
    static func key(for request: URLRequest) -> String {
        request.value(forHTTPHeaderField: keyHeader) ?? request.url.map(key(in:)) ?? ""
    }

    /// Everything after the path's first "/", percent-decoded. `db://data/`
    /// and `db://data` both name the whole store.
    static func key(in url: URL) -> String {
        let path = url.path(percentEncoded: false)
        return path.hasPrefix("/") ? String(path.dropFirst()) : path
    }

    private func finish(_ status: Int, body: Data? = nil) {
        let url = request.url ?? URL(string: "db://data/")!
        let headers = body == nil ? [:] : ["Content-Type": "application/json"]
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let body { client?.urlProtocol(self, didLoad: body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    static func drain(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
