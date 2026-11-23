import Foundation
@_spi(KilnTesting) import Kiln

// KilnDiff: one transcript per input (see Kiln's KETranscript.swift), printed
// as one marked JSON line each, for Tools/diff.sh to compare across builds.
//
//   KilnDiff [--prelude FILE] input.swift|reply.md …
//
// Nothing touches the network: http(s) fails at once with "not connected",
// and `db://` is answered from memory (by URLProtocol for an engine that
// blocks on URLSession, by Kiln.hostRequestHandler for one that doesn't).

@MainActor func source(of path: String, prelude: String?) -> String {
    let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    var code = path.hasSuffix(".md") ? Kiln.swiftSource(fromMarkdown: text) : text
    if let prelude, code.contains("DB."), code.range(of: #"\b(enum|struct|class)\s+DB\b"#, options: .regularExpression) == nil {
        code += "\n\n" + prelude + "\n"
    }
    return code
}

/// The `db://` store, shared by both ways in.
enum Store {
    nonisolated(unsafe) static var values: [String: Data] = [:]
    static let lock = NSLock()
    static func answer(_ request: URLRequest) -> (Int, Data?) {
        let key = request.value(forHTTPHeaderField: "DB-Key") ?? ""
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                body.append(buffer, count: n)
            }
            stream.close()
        }
        return lock.withLock {
            switch request.httpMethod ?? "GET" {
            case "GET": return values[key].map { (200, $0) } ?? (404, nil)
            case "PUT": values[key] = body; return (204, nil)
            case "DELETE": values[key] = nil; return (204, nil)
            default: return (405, nil)
            }
        }
    }
}

final class OfflineProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        ["db", "http", "https"].contains(request.url?.scheme ?? "")
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        guard url.scheme == "db" else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let (status, reply) = Store.answer(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        if let reply { client?.urlProtocol(self, didLoad: reply) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor func main() {
    var args = Array(CommandLine.arguments.dropFirst())
    var prelude: String?
    if args.first == "--prelude", args.count > 1 {
        prelude = try? String(contentsOfFile: args[1], encoding: .utf8)
        args.removeFirst(2)
    }
    URLProtocol.registerClass(OfflineProtocol.self)
    Kiln.hostRequestHandler = { request in
        guard request.url?.scheme == "db" else { return nil }
        let (status, body) = Store.answer(request)
        return KilnHostResponse(statusCode: status, body: body)
    }
    for path in args {
        Store.lock.withLock { Store.values = [:] }
        Kiln.randomSeed = 1
        let transcript = Kiln.transcript(source(of: path, prelude: prelude))
        let row: [String: Any] = ["file": path, "transcript": transcript]
        let data = try! JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        print("@@KILNDIFF@@" + String(data: data, encoding: .utf8)!)
    }
}
MainActor.assumeIsolated { main() }
