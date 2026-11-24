//
//  Streams.swift
//  Bridges: streamed responses and WebSockets (PLAN.md §3.8)
//
//  `let (bytes, response) = try await URLSession.shared.bytes(from: url)`,
//  then `for try await line in bytes.lines` (or each byte, or
//  `.characters`): the body is read as it arrives.
//
//  `URLSession.shared.webSocketTask(with: url)`, `resume()`, `try await
//  send(.string(text))` or `.data(data)`, `try await receive()` in a loop,
//  `sendPing`, and `cancel(with:reason:)`. A message is `.string(text)` or
//  `.data(data)`, matched with `switch` as in compiled code.
//
//  Closing the card ends both: every socket the app opened is cancelled
//  (`.goingAway`), and a stream's loop stops with the app's tasks, which
//  stops the read. A check (`validate`, a stub context) never touches the
//  network: a stream, a send or a receive fails at once, as offline.
//

import Foundation

enum KStreams {
    @MainActor static var offlineError: Error {
        KEThrown(value: KBuiltins.errorValue(URLError(.notConnectedToInternet).localizedDescription))
    }

    /// The run never touches the network.
    @MainActor static func isOffline(_ interp: KInterpreter) -> Bool { interp.headless || interp.context.isStub }

    /// A suspension that fails as offline.
    @MainActor static func offline() -> KV { .suspension(.done(.failure(offlineError))) }

    // MARK: URLSession

    @MainActor static func sessionMethods(_ t: KTypeBuilder) {
        for (sig, label) in [("from:any delegate:any?", "from"), ("for:any delegate:any?", "for")] {
            t.method("bytes", sig, async: true) { c in
                guard let req = KBuiltins.request(c.arg(label)) else { throw c.fail("needs a URL") }
                return bytes(req, c.interp)
            }
        }
        for sig in ["with:any", "with:any protocols:any"] {
            t.method("webSocketTask", sig) { c in
                guard let req = KBuiltins.request(c.arg("with")) else { throw c.fail("needs a URL") }
                let protocols = ((try? c.interp.sequence(c.arg("protocols") ?? .array([]))) ?? []).compactMap(\.asString)
                return .native(.object("URLSessionWebSocketTask",
                                       KRef(KWebSocket(request: req, protocols: protocols, context: c.context, live: !isOffline(c.interp)))))
            }
        }
    }

    /// `try await URLSession.shared.bytes(for:)`: the response once its
    /// headers arrive, and the body as a sequence.
    @MainActor static func bytes(_ request: URLRequest, _ interp: KInterpreter) -> KV {
        if interp.context.isStub { return offline() }
        let req = KUnsafeSendable(request)
        return .suspension(KSuspension.async(headless: { throw offlineError }) {
            let (bytes, response) = try await URLSession.shared.bytes(for: req.value)
            return .tuple([.native(.object("URLSession.AsyncBytes", KRef(KAsyncBytes(bytes)))),
                           .native(.object("HTTPURLResponse", KRef(response)))], [nil, nil])
        })
    }

    // MARK: Messages

    /// `data` of `.data`, or of `URLSessionWebSocketTask.Message.data`, which
    /// arrives qualified (`Message.data`).
    static func member(_ name: String) -> String { name.split(separator: ".").last.map(String.init) ?? name }

    /// `.string(text)`, `.data(data)`, or `URLSessionWebSocketTask.Message.string(text)`.
    @MainActor static func message(_ v: KV?, _ interp: KInterpreter) -> URLSessionWebSocketTask.Message? {
        guard case .native(.implicit(let name, let args))? = v, let payload = args.first else { return nil }
        switch member(name) {
        case "string": return .string(payload.asString ?? interp.describe(payload))
        case "data": return KBuiltins.dataValue(payload).map { .data($0) }
        default: return nil
        }
    }

    @MainActor static func value(_ m: URLSessionWebSocketTask.Message) -> KV {
        switch m {
        case .string(let s): return .native(.implicit("string", [.string(s)]))
        case .data(let d): return .native(.implicit("data", [KBuiltins.data(d)]))
        @unknown default: return .native(.implicit("data", [KBuiltins.data(Data())]))
        }
    }

    static let closeCodes: [(String, URLSessionWebSocketTask.CloseCode)] = [
        ("invalid", .invalid), ("normalClosure", .normalClosure), ("goingAway", .goingAway), ("protocolError", .protocolError),
        ("unsupportedData", .unsupportedData), ("noStatusReceived", .noStatusReceived), ("abnormalClosure", .abnormalClosure),
        ("invalidFramePayloadData", .invalidFramePayloadData), ("policyViolation", .policyViolation),
        ("messageTooBig", .messageTooBig), ("mandatoryExtensionMissing", .mandatoryExtensionMissing),
        ("internalServerError", .internalServerError), ("tlsHandshakeFailure", .tlsHandshakeFailure),
    ]

    @MainActor static func closeCode(_ v: KV?) -> URLSessionWebSocketTask.CloseCode {
        if case .native(.implicit(let name, _))? = v, let code = closeCodes.first(where: { $0.0 == member(name) }) { return code.1 }
        if let raw = v?.asInt, let code = URLSessionWebSocketTask.CloseCode(rawValue: raw) { return code }
        return .normalClosure
    }

    static func name(_ code: URLSessionWebSocketTask.CloseCode) -> String {
        closeCodes.first { $0.1 == code }?.0 ?? "invalid"
    }

    static func name(_ state: URLSessionTask.State) -> String {
        switch state {
        case .running: return "running"
        case .suspended: return "suspended"
        case .canceling: return "canceling"
        case .completed: return "completed"
        @unknown default: return "completed"
        }
    }
}

/// `URLSession.AsyncBytes`: a response's body, read as it arrives. Each loop
/// over it, or its `lines`, reads it in a Swift task that stops with the loop.
@MainActor
final class KAsyncBytes: KAsyncLoopable {
    let bytes: URLSession.AsyncBytes
    init(_ bytes: URLSession.AsyncBytes) { self.bytes = bytes }

    func makeAsyncIterator() -> KAsyncIterator {
        KAsyncSequence.wrapping("URLSession.AsyncBytes", bytes) { .int(Int($0)) }.makeIterator()
    }

    var lines: KV {
        .native(.object("AsyncSequence", KRef(KAsyncSequence.wrapping("AsyncLineSequence", bytes.lines) { .string($0) })))
    }

    var characters: KV {
        .native(.object("AsyncSequence", KRef(KAsyncSequence.wrapping("AsyncCharacterSequence", bytes.characters) { .string(String($0)) })))
    }
}

/// `URLSession.shared.webSocketTask(with:)`. Offline (a check), it has no
/// native task, and every send and receive fails at once.
@MainActor
final class KWebSocket {
    let task: URLSessionWebSocketTask?

    init(request: URLRequest, protocols: [String], context: KilnContext, live: Bool) {
        guard live else { task = nil; return }
        let t: URLSessionWebSocketTask
        if protocols.isEmpty || request.url == nil {
            t = URLSession.shared.webSocketTask(with: request)
        } else {
            var r = request
            r.setValue(protocols.joined(separator: ", "), forHTTPHeaderField: "Sec-WebSocket-Protocol")
            t = URLSession.shared.webSocketTask(with: r)
        }
        task = t
        // The card closes: so does the socket, as an app going away.
        context.onTearDown { [weak t] in t?.cancel(with: .goingAway, reason: nil) }
    }
}

extension NetworkingBridges {
    @MainActor static func streams(_ r: KRegistry) {
        r.type("URLSession.AsyncBytes", .networking, support: .full, notes: "`for try await` over its bytes, `.lines` or `.characters`.") { t in
            t.property("lines") { c in c.object(KAsyncBytes.self)?.lines ?? .array([]) }
            t.property("characters") { c in c.object(KAsyncBytes.self)?.characters ?? .array([]) }
        }

        r.type("URLSessionWebSocketTask", .networking, support: .full, notes: "Closed (`.goingAway`) when the app closes.") { t in
            t.method("resume", "") { c in c.object(KWebSocket.self)?.task?.resume(); return .void }

            t.method("send", "_:any", async: true) { c in
                guard let socket = c.object(KWebSocket.self) else { return .void }
                guard let m = KStreams.message(c.first, c.interp) else { throw c.fail("sends `.string(text)` or `.data(data)`") }
                guard let task = socket.task else { return KStreams.offline() }
                let message = KUnsafeSendable(m)
                return .suspension(KSuspension.async(headless: { throw KStreams.offlineError }) {
                    try await task.send(message.value)
                    return .void
                })
            }
            t.method("send", "_:any completionHandler:closure") { c in
                guard let socket = c.object(KWebSocket.self) else { return .void }
                guard let m = KStreams.message(c.first, c.interp) else { throw c.fail("sends `.string(text)` or `.data(data)`") }
                let handler = c.function("completionHandler")
                let interp = c.interp
                let callback = KUnsafeSendable((interp, handler))
                guard let task = socket.task else {
                    interp.perform(handler, [KBuiltins.errorValue(URLError(.notConnectedToInternet).localizedDescription)])
                    return .void
                }
                task.send(m) { error in
                    let e = error.map { ($0 as NSError).localizedDescription }
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { callback.value.0.perform(callback.value.1, [e.map(KBuiltins.errorValue) ?? .nilValue]) }
                    }
                }
                return .void
            }

            t.method("receive", "", async: true) { c in
                guard let task = c.object(KWebSocket.self)?.task else { return KStreams.offline() }
                return .suspension(KSuspension.async(headless: { throw KStreams.offlineError }) {
                    KStreams.value(try await task.receive())
                })
            }
            t.method("receive", "completionHandler:closure") { c in
                let handler = c.function("completionHandler")
                let interp = c.interp
                let callback = KUnsafeSendable((interp, handler))
                guard let task = c.object(KWebSocket.self)?.task else {
                    interp.perform(handler, [.native(.implicit("failure", [KBuiltins.errorValue(URLError(.notConnectedToInternet).localizedDescription)]))])
                    return .void
                }
                task.receive { result in
                    let r = KUnsafeSendable(result)
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            let (interp, handler) = callback.value
                            switch r.value {
                            case .success(let m): interp.perform(handler, [.native(.implicit("success", [KStreams.value(m)]))])
                            case .failure(let e):
                                interp.perform(handler, [.native(.implicit("failure", [KBuiltins.errorValue((e as NSError).localizedDescription)]))])
                            }
                        }
                    }
                }
                return .void
            }

            t.method("sendPing", "pongReceiveHandler:closure") { c in
                let handler = c.function("pongReceiveHandler")
                let interp = c.interp
                let callback = KUnsafeSendable((interp, handler))
                guard let task = c.object(KWebSocket.self)?.task else {
                    interp.perform(handler, [KBuiltins.errorValue(URLError(.notConnectedToInternet).localizedDescription)])
                    return .void
                }
                task.sendPing { error in
                    let e = error.map { ($0 as NSError).localizedDescription }
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { callback.value.0.perform(callback.value.1, [e.map(KBuiltins.errorValue) ?? .nilValue]) }
                    }
                }
                return .void
            }

            t.method("cancel", "with:any reason:any?") { c in
                c.object(KWebSocket.self)?.task?.cancel(with: KStreams.closeCode(c.arg("with")), reason: KBuiltins.dataValue(c.arg("reason")))
                return .void
            }
            t.method("cancel", "") { c in c.object(KWebSocket.self)?.task?.cancel(); return .void }

            t.property("state") { c in
                .native(.implicit(c.object(KWebSocket.self)?.task.map { KStreams.name($0.state) } ?? "suspended", []))
            }
            t.property("closeCode") { c in
                .native(.implicit(c.object(KWebSocket.self)?.task.map { KStreams.name($0.closeCode) } ?? "invalid", []))
            }
            t.property("closeReason") { c in
                c.object(KWebSocket.self)?.task?.closeReason.map { KBuiltins.data($0) } ?? .nilValue
            }
            t.property("maximumMessageSize", { c in .int(c.object(KWebSocket.self)?.task?.maximumMessageSize ?? 1_048_576) },
                       set: { c in if let n = c.first?.asInt { c.object(KWebSocket.self)?.task?.maximumMessageSize = n } })
        }

        r.type("URLSessionWebSocketTask.Message", .networking, support: .full) { t in
            t.staticMethod("string", "_:string") { c in .native(.implicit("string", [c.first ?? .string("")])) }
            t.staticMethod("data", "_:any") { c in .native(.implicit("data", [c.first ?? KBuiltins.data(Data())])) }
            t.implicit { name, args, _ in ["string", "data"].contains(name) ? .native(.implicit(name, args)) : nil }
        }
        r.type("URLSessionWebSocketTask.CloseCode", .networking, support: .full) { t in
            t.anyStatic { _, name in KStreams.closeCodes.contains { $0.0 == name } ? .native(.implicit(name, [])) : nil }
            t.implicit { name, _, _ in KStreams.closeCodes.contains { $0.0 == name } ? .native(.implicit(name, [])) : nil }
        }
    }
}
