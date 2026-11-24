//
//  Networking.swift
//  Bridges: URLSession and requests
//
//  `try await URLSession.shared.data(from:)` (or `for:` a request) waits
//  without blocking, and `bytes(from:)` streams the body (Streams.swift, with
//  WebSockets); `dataTask(with:) { data, response, error in }.resume()`, for
//  older code, calls back on the main thread. All of it is cancelled when the
//  app's screen closes. `validate` (and any stub context) never touches the network: a
//  request fails at once, as offline.
//

import SwiftUI

@objc(KilnBridges_Networking)
final class NetworkingBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        streams(r)
        r.type("URLSession", .networking, notes: "`shared` only.") { t in
            t.staticProperty("shared") { _ in .native(.object("URLSession", KRef(URLSession.shared))) }
            t.method("data", notes: "`try await`: waits without blocking.", async: true) { c in
                guard let req = KBuiltins.request(c.arg("from") ?? c.arg("for") ?? c.first) else { throw c.interp.fail("URLSession.data needs a URL", c.line) }
                return try KBuiltins.fetch(req, c.interp, c.line)
            }
            t.method("dataTask") { c in
                guard let req = KBuiltins.request(c.arg("with") ?? c.first) else { throw c.interp.fail("URLSession.dataTask needs a URL", c.line) }
                var completion: KFunction?
                if case .function(let f)? = c.last { completion = f }
                return .native(.object("URLSessionDataTask", KRef(KDataTask(request: req, completion: completion))))
            }
            // Streamed responses and WebSockets (Streams.swift).
            KStreams.sessionMethods(t)
        }

        r.type("URLSessionDataTask", .networking) { t in
            t.method("resume") { c in
                guard let box = c.object(KDataTask.self), box.task == nil, !box.started else { return .void }
                box.started = true
                let completion = box.completion
                let interp = c.interp
                if interp.headless || interp.context.isStub {
                    // A check: the request fails at once, as offline.
                    interp.perform(completion, [.nilValue, .nilValue,
                                                KBuiltins.errorValue(URLError(.notConnectedToInternet).localizedDescription)])
                    return .void
                }
                c.context.onTearDown { [weak box] in box?.task?.cancel() }
                box.task = URLSession.shared.dataTask(with: box.request) { data, response, error in
                    let d = data, resp = response, e = error?.localizedDescription
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            interp.perform(completion, [d.map { KBuiltins.data($0) } ?? .nilValue,
                                                        resp.map { .native(.object("HTTPURLResponse", KRef($0))) } ?? .nilValue,
                                                        e.map { KBuiltins.errorValue($0) } ?? .nilValue])
                        }
                    }
                }
                box.task?.resume()
                return .void
            }
            t.method("cancel") { c in c.object(KDataTask.self)?.task?.cancel(); return .void }
        }

        r.type("URLRequest", .networking) { t in
            t.initializer { c in
                guard let req = KBuiltins.request(c.arg("url") ?? c.first) else { return .nilValue }
                return .native(.object("URLRequest", KRef(NSMutableURLRequest(url: req.url!))))
            }
            t.property("url") { c in c.object(NSURLRequest.self)?.url.map { .native(.url($0)) } ?? .nilValue }
            t.property("httpMethod", { c in .string(c.object(NSURLRequest.self)?.httpMethod ?? "GET") },
                       set: { c in c.object(NSMutableURLRequest.self)?.httpMethod = c.first?.asString ?? "GET" })
            t.property("httpBody", { c in c.object(NSURLRequest.self)?.httpBody.map { KBuiltins.data($0) } ?? .nilValue },
                       set: { c in c.object(NSMutableURLRequest.self)?.httpBody = KBuiltins.dataValue(c.first) })
            t.anySetter { _, _ in true }
            t.method("setValue") { c in
                if let req = c.object(NSMutableURLRequest.self), let field = c.arg("forHTTPHeaderField")?.asString {
                    req.setValue(c.first.map { c.interp.describe($0) }, forHTTPHeaderField: field)
                }
                return .void
            }
        }

        r.type("URLComponents", .networking) { t in
            t.initializer { c in
                let fromString = c.arg("string")?.asString.flatMap { NSURLComponents(string: $0) }
                if c.arg("string") != nil, fromString == nil { return .nilValue }
                var fromURL: NSURLComponents?
                if case .native(.url(let u))? = c.arg("url") { fromURL = NSURLComponents(url: u, resolvingAgainstBaseURL: false) }
                return .native(.object("URLComponents", KRef(fromString ?? fromURL ?? NSURLComponents())))
            }
            t.property("url") { c in c.object(NSURLComponents.self)?.url.map { .native(.url($0)) } ?? .nilValue }
            t.property("string") { c in c.object(NSURLComponents.self)?.string.map { .string($0) } ?? .nilValue }
            t.property("queryItems", { c in
                c.object(NSURLComponents.self)?.queryItems.map { .array($0.map { .native(.object("URLQueryItem", KRef($0 as NSURLQueryItem))) }) } ?? .nilValue
            }, set: { c in
                guard case .array(let items)? = c.first else { return }
                c.object(NSURLComponents.self)?.queryItems = items.compactMap {
                    if case .native(.object("URLQueryItem", let ref)) = $0 { return (ref.value as? NSURLQueryItem).map { $0 as URLQueryItem } }
                    return nil
                }
            })
            t.property("path", { c in .string(c.object(NSURLComponents.self)?.path ?? "") },
                       set: { c in c.object(NSURLComponents.self)?.path = c.first?.asString })
            t.anySetter { _, _ in true }
        }

        r.type("URLQueryItem", .networking) { t in
            t.initializer { c in
                .native(.object("URLQueryItem", KRef(NSURLQueryItem(name: c.arg("name")?.asString ?? "",
                                                                    value: c.arg("value").flatMap { $0.isNil ? nil : c.interp.describe($0) }))))
            }
            t.property("name") { c in .string(c.object(NSURLQueryItem.self)?.name ?? "") }
            t.property("value") { c in c.object(NSURLQueryItem.self)?.value.map { .string($0) } ?? .nilValue }
        }

        r.type("HTTPURLResponse", .networking) { t in
            t.property("statusCode") { c in .int(c.object(HTTPURLResponse.self)?.statusCode ?? 200) }
            t.property("url") { c in c.object(URLResponse.self)?.url.map { .native(.url($0)) } ?? .nilValue }
        }
    }
}
