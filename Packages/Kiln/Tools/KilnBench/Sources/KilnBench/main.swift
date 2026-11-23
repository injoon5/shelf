import Foundation
import Kiln

// KilnBench: runs Kiln over example apps, Shelf's fixtures and model replies,
// and prints one JSON line per input.
//
//   KilnBench [--runs N] [--prelude FILE] input.swift|reply.md …
//
// Two things are timed for each input, in this process:
//   - `run`:      Kiln.run, which parses, sets up the interpreter and wraps the
//                 root view (no body is evaluated yet).
//   - `validate`: Kiln.validate, which does the same, then evaluates every body
//                 and fires every action once (timers `ticks` times).
// The first call is reported on its own (`*ColdMs`). After it, `--runs`
// samples are taken (default 1); a sample repeats the call enough times to
// last about 20 ms, so a 1 ms app isn't lost in the clock's and the
// scheduler's noise. `*MedianMs` and `*MinMs` are per call, over the samples.
// The minimum is the steadiest number to compare two builds by.
//
// The network is never touched: every http(s) request fails at once with
// "not connected", as in Shelf's fixture tests, and `db://` requests are
// answered from an in-memory store keyed by the `DB-Key` header, as Shelf's
// `ShelfDBProtocol` does. `--prelude FILE` appends FILE to every source that
// uses `DB.`, the way Shelf's `SourceRewriter` appends its `DB` helper.

/// The Swift source to run from a file: a .swift file as is, or a model reply
/// (.md) merged the way Haplo AI runs it (Kiln.swiftSource(fromMarkdown:)).
@MainActor func source(of path: String, prelude: String?) -> String {
    let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    var code = path.hasSuffix(".md") ? Kiln.swiftSource(fromMarkdown: text) : text
    if let prelude, code.contains("DB.") { code += "\n\n" + prelude + "\n" }
    return code
}

/// Answers every request without the network (see the header).
final class OfflineProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var store: [String: Data] = [:]

    static func reset() { lock.withLock { store = [:] } }

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
        var status = 200
        var reply: Data?
        Self.lock.withLock {
            switch request.httpMethod ?? "GET" {
            case "GET": if let value = Self.store[key] { reply = value } else { status = 404 }
            case "PUT": Self.store[key] = body
            case "DELETE": Self.store[key] = nil
            default: status = 405
            }
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        if let reply { client?.urlProtocol(self, didLoad: reply) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct Timing {
    var cold = 0.0
    var repeats = 1
    var samples: [Double] = []
    var median: Double {
        let s = samples.sorted()
        guard !s.isEmpty else { return cold }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
    var min: Double { samples.min() ?? cold }

    /// Times `body` once cold, then `runs` samples of enough calls to last ~20 ms.
    @MainActor static func measure(runs: Int, _ body: () -> Void) -> Timing {
        let clock = ContinuousClock()
        var t = Timing()
        OfflineProtocol.reset()
        t.cold = ms(clock.measure(body))
        t.repeats = Swift.max(1, Int((20 / Swift.max(t.cold, 0.01)).rounded(.up)))
        for _ in 0..<runs {
            var total = 0.0
            for _ in 0..<t.repeats {
                OfflineProtocol.reset()
                total += ms(clock.measure(body))
            }
            t.samples.append(total / Double(t.repeats))
        }
        return t
    }
}

func ms(_ d: Duration) -> Double {
    Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
}

func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }

@MainActor func main() {
    var args = Array(CommandLine.arguments.dropFirst())
    var runs = 1
    var prelude: String?
    while let flag = args.first, flag.hasPrefix("--") {
        args.removeFirst()
        guard let value = args.first else { break }
        args.removeFirst()
        switch flag {
        case "--runs": runs = max(1, Int(value) ?? 1)
        case "--prelude": prelude = try? String(contentsOfFile: value, encoding: .utf8)
        default: FileHandle.standardError.write(Data("unknown flag \(flag)\n".utf8))
        }
    }
    URLProtocol.registerClass(OfflineProtocol.self)
    Kiln.randomSeed = 1

    var rows: [[String: Any]] = []
    for path in args {
        let code = source(of: path, prelude: prelude)
        var last: KilnValidation?
        let run = Timing.measure(runs: runs) { _ = Kiln.run(code) }
        let validate = Timing.measure(runs: runs) { last = Kiln.validate(code) }
        let v = last!
        rows.append([
            "file": (path as NSString).lastPathComponent,
            "valid": v.isValid,
            "hasView": v.hasView,
            "rendered": v.renderedContent,
            "errors": v.errors.map { String($0.prefix(240)) },
            "warnings": v.warnings.prefix(6).map { String($0.prefix(200)) },
            "runs": runs, "runRepeats": run.repeats, "validateRepeats": validate.repeats,
            // `ms` is kept for Lab/report.py: the cold validate, as before.
            "ms": Int(validate.cold.rounded()),
            "runColdMs": round2(run.cold), "runMedianMs": round2(run.median), "runMinMs": round2(run.min),
            "validateColdMs": round2(validate.cold), "validateMedianMs": round2(validate.median), "validateMinMs": round2(validate.min),
        ])
    }
    // One marked line per input: Kiln's own debug prints share stdout.
    for row in rows {
        let data = try! JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        print("@@KILNBENCH@@" + String(data: data, encoding: .utf8)!)
    }
}
MainActor.assumeIsolated { main() }
