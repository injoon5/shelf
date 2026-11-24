//
//  StreamsBridgeTests.swift
//  KilnTests
//
//  PLAN.md §3.8: streamed responses (`bytes(from:)`, `.lines`) and
//  WebSockets, against a URLProtocol and a WebSocket echo server on this
//  Mac; the socket closes with the card, and a check never opens one.
//

import XCTest
import Network
@testable import Kiln

@MainActor
final class StreamsBridgeTests: XCTestCase {
    private var contexts: [KilnContext] = []

    override func tearDown() async throws {
        for c in contexts { c.tearDown() }
        contexts = []
    }

    private func context() -> KilnContext {
        let folder = FileManager.default.temporaryDirectory.appending(path: "kiln-streams-\(UUID().uuidString)")
        let c = KilnContext(slug: "streams", name: "Streams", defaults: KilnMemoryDefaults(), files: KilnFiles(root: folder))
        contexts.append(c)
        return c
    }

    /// Runs the app's `async` `main()` for real, and returns what it returned.
    private func run(_ source: String, _ context: KilnContext) async throws -> (KInterpreter, KV?) {
        let c = try KilnEngine.compile(source + "\nstruct ContentView: View { var body: some View { Text(\"x\") } }",
                                       headless: false, context: context)
        let main = try XCTUnwrap(c.interp.functions["main"]?.first)
        let t = c.interp.startTask(KFunction(.user(main, c.interp.globalEnv, nil)), [], parent: nil, reportsErrors: true)
        if case .value(let v) = await t.completion() { return (c.interp, v) }
        return (c.interp, nil)
    }

    // MARK: Streamed responses

    func testBytesStreamLinesAsTheyArrive() async throws {
        URLProtocol.registerClass(StreamsTestsProtocol.self)
        defer { URLProtocol.unregisterClass(StreamsTestsProtocol.self) }
        let (interp, v) = try await run("""
        func main() async -> String {
            do {
                let (bytes, response) = try await URLSession.shared.bytes(from: URL(string: "https://kiln-streams.test/feed")!)
                var lines: [String] = []
                for try await line in bytes.lines {
                    lines.append(line)
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                return "\\(status) " + lines.joined(separator: "|")
            } catch {
                return "failed: \\(error.localizedDescription)"
            }
        }
        """, context())
        XCTAssertEqual(interp.errors, [])
        XCTAssertEqual(v?.asString, "200 first|second|third")
    }

    func testBytesCanBeReadOneByOne() async throws {
        URLProtocol.registerClass(StreamsTestsProtocol.self)
        defer { URLProtocol.unregisterClass(StreamsTestsProtocol.self) }
        let (interp, v) = try await run("""
        func main() async throws -> Int {
            var request = URLRequest(url: URL(string: "https://kiln-streams.test/feed")!)
            request.httpMethod = "GET"
            let (bytes, _) = try await URLSession.shared.bytes(for: request)
            var newlines = 0
            for try await byte in bytes where byte == 10 {
                newlines += 1
            }
            return newlines
        }
        """, context())
        XCTAssertEqual(interp.errors, [])
        XCTAssertEqual(v?.asInt, 3)
    }

    // MARK: WebSockets

    func testWebSocketSendsAndReceivesTextAndData() async throws {
        let server = try await EchoServer.start()
        defer { server.stop() }
        let (interp, v) = try await run(server.substitute("""
        func main() async -> String {
            let socket = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:PORT")!)
            socket.resume()
            var out: [String] = []
            do {
                try await socket.send(.string("hello"))
                switch try await socket.receive() {
                case .string(let text): out.append(text)
                case .data: out.append("data?")
                @unknown default: out.append("?")
                }
                try await socket.send(URLSessionWebSocketTask.Message.data(Data([1, 2, 3])))
                let reply = try await socket.receive()
                if case .data(let data) = reply { out.append("\\(data.count) bytes") }
                out.append(socket.state == .running ? "running" : "not running")
                socket.cancel(with: .normalClosure, reason: nil)
            } catch {
                out.append("failed: \\(error.localizedDescription)")
            }
            return out.joined(separator: ", ")
        }
        """), context())
        XCTAssertEqual(interp.errors, [])
        XCTAssertEqual(v?.asString, "echo: hello, 3 bytes, running")
        try await server.waitForClose()
        XCTAssertEqual(server.closeCodes, [.protocolCode(.normalClosure)])
    }

    func testSendPingAndCallbackForms() async throws {
        let server = try await EchoServer.start()
        defer { server.stop() }
        let c = try KilnEngine.compile(server.substitute("""
        var log: [String] = []
        func main() {
            let socket = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:PORT")!)
            socket.resume()
            socket.sendPing { error in
                log.append(error == nil ? "pong" : "no pong")
                socket.send(.string("hi")) { error in
                    log.append(error == nil ? "sent" : "not sent")
                    socket.receive { result in
                        switch result {
                        case .success(.string(let text)): log.append(text)
                        case .success: log.append("data")
                        case .failure(let error): log.append(error.localizedDescription)
                        }
                    }
                }
            }
        }
        struct ContentView: View { var body: some View { Text("x") } }
        """), headless: false, context: context())
        c.interp.perform(KFunction(.user(try XCTUnwrap(c.interp.functions["main"]?.first), c.interp.globalEnv, nil)))
        let deadline = Date().addingTimeInterval(5)
        while (c.interp.globalEnv.lookup("log")?.value.asArray?.count ?? 0) < 3, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(c.interp.errors, [])
        XCTAssertEqual(c.interp.globalEnv.lookup("log")?.value.asArray?.compactMap(\.asString), ["pong", "sent", "echo: hi"])
    }

    /// The card closes: the app's socket says it's going away.
    func testClosingTheCardClosesTheSocket() async throws {
        let server = try await EchoServer.start()
        defer { server.stop() }
        let ctx = context()
        let c = try KilnEngine.compile(server.substitute("""
        var received: [String] = []
        func listen() async {
            let socket = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:PORT")!)
            socket.resume()
            try? await socket.send(.string("open"))
            while true {
                guard let message = try? await socket.receive() else { break }
                if case .string(let text) = message { received.append(text) }
            }
        }
        struct ContentView: View { var body: some View { Text("x") } }
        """), headless: false, context: ctx)
        _ = c.interp.startTask(KFunction(.user(try XCTUnwrap(c.interp.functions["listen"]?.first), c.interp.globalEnv, nil)),
                               [], parent: nil, reportsErrors: true)
        let deadline = Date().addingTimeInterval(5)
        while (c.interp.globalEnv.lookup("received")?.value.asArray?.count ?? 0) < 1, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(c.interp.globalEnv.lookup("received")?.value.asArray?.first?.asString, "echo: open")
        ctx.tearDown()
        try await server.waitForClose()
        XCTAssertEqual(server.closeCodes, [.protocolCode(.goingAway)])
        XCTAssertEqual(c.interp.errors, [])
    }

    /// A check never touches the network: a stream and a socket fail at
    /// once, as offline, and the app's `catch` runs.
    func testAStubContextNeverOpensAStreamOrASocket() throws {
        let c = try KilnEngine.compile("""
        struct ContentView: View {
            var body: some View {
                Text("x")
                    .task {
                        do { _ = try await URLSession.shared.bytes(from: URL(string: "https://example.com")!); print("streamed") }
                        catch { print("stream offline") }
                    }
                    .task {
                        let socket = URLSession.shared.webSocketTask(with: URL(string: "wss://example.com")!)
                        socket.resume()
                        do { try await socket.send(.string("x")); print("sent") } catch { print("send offline") }
                        do { _ = try await socket.receive(); print("received") } catch { print("receive offline") }
                    }
            }
        }
        """, headless: true, context: .stub())
        KProbe(interp: c.interp, ticks: 1).run(c.root)
        c.interp.tearDown()
        XCTAssertEqual(c.interp.errors, [])
        for line in ["stream offline", "send offline", "receive offline"] {
            XCTAssertTrue(c.interp.console.contains(line + "\n"), c.interp.console)
        }
    }

    func testTheCheckerKnowsTheStreamingAPI() {
        let check = Kiln.check("""
        import SwiftUI

        struct ContentView: View {
            @State private var lines: [String] = []
            @State private var socket: URLSessionWebSocketTask?

            var body: some View {
                List(lines, id: \\.self) { Text($0) }
                    .task {
                        guard let (bytes, _) = try? await URLSession.shared.bytes(from: URL(string: "https://example.com")!) else { return }
                        do {
                            for try await line in bytes.lines { lines.append(line) }
                        } catch {}
                    }
                    .task {
                        let s = URLSession.shared.webSocketTask(with: URL(string: "wss://example.com")!)
                        socket = s
                        s.resume()
                        while let message = try? await s.receive() {
                            switch message {
                            case .string(let text): lines.append(text)
                            case .data(let data): lines.append("\\(data.count) bytes")
                            @unknown default: break
                            }
                        }
                    }
                    .onDisappear { socket?.cancel(with: .goingAway, reason: nil) }
            }
        }
        """)
        XCTAssertEqual(check.errors.map(\.description), [])
        XCTAssertEqual(check.warnings.map(\.description), [])
    }
}

/// `https://kiln-streams.test/feed`: three lines, sent in two pieces.
final class StreamsTestsProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "kiln-streams.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("first\nsec".utf8))
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { [self] in
            client?.urlProtocol(self, didLoad: Data("ond\nthird\n".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

/// A WebSocket server on 127.0.0.1 that echoes text as "echo: …" and data as
/// is, answers pings, and records the close codes clients send.
final class EchoServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "kiln.echo")
    private let lock = NSLock()
    private var codes: [NWProtocolWebSocket.CloseCode] = []
    private(set) var port: UInt16 = 0

    var closeCodes: [NWProtocolWebSocket.CloseCode] { lock.withLock { codes } }

    private init() throws {
        let params = NWParameters.tcp
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        listener = try NWListener(using: params, on: .any)
    }

    static func start() async throws -> EchoServer {
        let server = try EchoServer()
        server.listener.newConnectionHandler = { [weak server] conn in server?.serve(conn) }
        try await withCheckedThrowingContinuation { (k: CheckedContinuation<Void, Error>) in
            var resumed = false
            server.listener.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready: resumed = true; k.resume()
                case .failed(let e): resumed = true; k.resume(throwing: e)
                default: break
                }
            }
            server.listener.start(queue: server.queue)
        }
        server.port = server.listener.port?.rawValue ?? 0
        return server
    }

    func stop() { listener.cancel() }

    /// An app's source with `PORT` replaced by this server's port.
    func substitute(_ source: String) -> String { source.replacingOccurrences(of: "PORT", with: "\(port)") }

    /// Waits up to 5 s for a client's close frame.
    func waitForClose() async throws {
        let deadline = Date().addingTimeInterval(5)
        while closeCodes.isEmpty, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
    }

    private func serve(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn)
    }

    private func receive(_ conn: NWConnection) {
        conn.receiveMessage { [weak self] data, context, _, error in
            guard let self, error == nil, let context,
                  let meta = context.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata else { return }
            switch meta.opcode {
            case .close:
                self.lock.withLock { self.codes.append(meta.closeCode) }
                conn.cancel()
            case .text, .binary:
                var out = data ?? Data()
                if meta.opcode == .text { out = Data(("echo: " + String(decoding: out, as: UTF8.self)).utf8) }
                let reply = NWConnection.ContentContext(identifier: "echo", metadata: [NWProtocolWebSocket.Metadata(opcode: meta.opcode)])
                conn.send(content: out, contentContext: reply, isComplete: true, completion: .contentProcessed { _ in self.receive(conn) })
            default:
                self.receive(conn)
            }
        }
    }
}
