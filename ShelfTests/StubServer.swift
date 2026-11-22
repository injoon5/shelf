import Foundation
import Synchronization
@testable import Shelf

/// One request as the stub saw it.
struct StubRequest: Sendable {
    var method: String
    /// Percent-encoded, as sent.
    var path: String
    var query: [String: String]
    var headers: [String: String]
    var body: Data

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
    var json: JSONValue? { JSONValue(json: body) }
}

struct StubResponse: Sendable {
    var status = 200
    var body = Data()
    var headers: [String: String] = [:]
    var delay: Duration = .zero
    var offline = false

    static let offline = StubResponse(offline: true)

    static func json(_ text: String, status: Int = 200, headers: [String: String] = [:]) -> StubResponse {
        StubResponse(status: status, body: Data(text.utf8), headers: headers)
    }

    static func json(_ value: JSONValue, status: Int = 200, headers: [String: String] = [:]) -> StubResponse {
        StubResponse(status: status, body: value.json, headers: headers)
    }

    static func fixture(_ name: String, status: Int = 200, headers: [String: String] = [:]) -> StubResponse {
        StubResponse(status: status, body: Fixture.api(name), headers: headers)
    }

    func delayed(_ delay: Duration) -> StubResponse {
        var copy = self
        copy.delay = delay
        return copy
    }
}

extension Fixture {
    static func api(_ name: String) -> Data {
        (try? Data(contentsOf: root.appending(path: "api/\(name).json"))) ?? Data()
    }
}

/// A fake server behind its own host, reached through its own `URLSession`.
/// Each test makes its own, so suites can run side by side.
final class StubServer: Sendable {
    typealias Handler = @Sendable (StubRequest) -> StubResponse

    let host = "stub-\(UUID().uuidString.lowercased()).test"
    var origin: URL { URL(string: "https://\(host)")! }
    let session: URLSession

    private struct State {
        var handler: Handler
        var requests: [StubRequest] = []
        var inFlight = 0
        var maxInFlight = 0
    }
    private let state: Mutex<State>

    init(_ handler: @escaping Handler = { _ in StubResponse(status: 404) }) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        config.timeoutIntervalForRequest = 10
        session = URLSession(configuration: config)
        state = Mutex(State(handler: handler))
        StubProtocol.servers.withLock { $0[host] = self }
    }

    func api(token: String = "test-token") -> API {
        API(origin: origin, token: token, session: session)
    }

    func handle(_ handler: @escaping Handler) {
        state.withLock { $0.handler = handler }
    }

    var requests: [StubRequest] { state.withLock { $0.requests } }
    var maxInFlight: Int { state.withLock { $0.maxInFlight } }

    func requests(_ method: String, _ path: String) -> [StubRequest] {
        requests.filter { $0.method == method && $0.path == path }
    }

    fileprivate func begin(_ request: StubRequest) -> StubResponse {
        let handler = state.withLock { state in
            state.requests.append(request)
            state.inFlight += 1
            state.maxInFlight = max(state.maxInFlight, state.inFlight)
            return state.handler
        }
        return handler(request)
    }

    fileprivate func end() {
        state.withLock { $0.inFlight -= 1 }
    }
}

final class StubProtocol: URLProtocol, @unchecked Sendable {
    static let servers = Mutex<[String: StubServer]>([:])
    private let stopped = Mutex(false)

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host() else { return false }
        return servers.withLock { $0[host] != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host(),
              let server = Self.servers.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let seen = StubRequest(
            method: request.httpMethod ?? "GET",
            path: url.path(percentEncoded: true),
            query: Dictionary((components?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a }),
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody ?? request.httpBodyStream.map(FakeServer.drain) ?? Data())
        let response = server.begin(seen)

        let deliver: @Sendable () -> Void = { [self] in
            defer { server.end() }
            guard !stopped.withLock({ $0 }) else { return }
            if response.offline {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                return
            }
            let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: response.headers)!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.body)
            client?.urlProtocolDidFinishLoading(self)
        }
        if response.delay > .zero {
            let (seconds, attoseconds) = response.delay.components
            let interval = Double(seconds) + Double(attoseconds) / 1e18
            DispatchQueue.global().asyncAfter(deadline: .now() + interval, execute: deliver)
        } else {
            deliver()
        }
    }

    override func stopLoading() {
        stopped.withLock { $0 = true }
    }
}

/// A folder of its own under the temporary directory.
func temporaryFolder() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "shelf-tests-\(UUID().uuidString)")
}

/// Polls `condition` until it holds or `timeout` passes.
func eventually(timeout: Duration = .seconds(3), _ condition: @Sendable () async -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await condition()
}

/// Every file in `folder` (not its subfolders), name → bytes.
func snapshot(of folder: URL) -> [String: Data] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
    var files: [String: Data] = [:]
    for name in names {
        files[name] = try? Data(contentsOf: folder.appending(path: name))
    }
    return files
}

/// A value behind a lock, shareable between tasks and closures.
final class Locked<Value: Sendable>: Sendable {
    private let mutex: Mutex<Value>
    init(_ value: Value) { mutex = Mutex(value) }
    var value: Value { mutex.withLock { $0 } }
    func withLock<T: Sendable>(_ body: (inout Value) -> T) -> T { mutex.withLock { body(&$0) } }
}
