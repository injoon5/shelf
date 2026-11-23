import Foundation
import Kiln

/// `DB`, the synced store apps keep their data in, as a Kiln host bridge
/// (plan §1.7): native, synchronous, and answered from the run's own
/// `DBSession`, which the run's context carries (`context.provide(session)`).
/// `AppData` saves the session and syncs it, as before.
///
///     DB.load("todos") -> Data?     nil if the key was never saved
///     DB.save("todos", data)        data: JSON Data
///     DB.remove("todos")
///
/// A value the server would refuse (a bad key, over 64 KB, the store full)
/// is an error with the app's line, instead of being lost without a word.
@MainActor
enum DBBridge {
    private static var registered = false

    /// Registers `DB` once; every run then reaches its own session.
    static func register() {
        guard !registered else { return }
        registered = true
        Kiln.registerType("DB", notes: "Synced key-value storage: JSON Data under a string key. Calls return at once.") { t in
            t.staticMethod("load", "_:string", notes: "The Data saved under the key, or nil.") { call in
                let session = try session(call)
                let key = try call.string(0)
                call.context.provided(DBTrace.self)?.calls.append("GET /" + key)
                return session.value(for: key).map { KilnValue(data: $0.json) } ?? .nil
            }
            t.staticMethod("save", "_:string _:any", notes: "Saves JSON Data under the key.") { call in
                let session = try session(call)
                let key = try call.string(0)
                call.context.provided(DBTrace.self)?.calls.append("PUT /" + key)
                guard let data = call.value(1)?.data else { throw call.error("needs Data: encode the value with JSONEncoder") }
                guard let value = JSONValue(json: data) else { throw call.error("the data isn't JSON: encode the value with JSONEncoder") }
                do {
                    try session.write(value, for: key)
                } catch let refusal as DBSession.Refusal {
                    throw call.error(message(for: refusal, key: key))
                }
                return .void
            }
            t.staticMethod("remove", "_:string", notes: "Removes the key.") { call in
                let key = try call.string(0)
                call.context.provided(DBTrace.self)?.calls.append("DELETE /" + key)
                try session(call).remove(key)
                return .void
            }
        }
    }

    private static func session(_ call: KilnCall) throws -> DBSession {
        guard let session = call.context.provided(DBSession.self) else {
            throw call.error("DB isn't available here")
        }
        return session
    }

    static func message(for refusal: DBSession.Refusal, key: String) -> String {
        switch refusal {
        case .invalidKey: "\"\(key)\" isn't a key DB can keep: keys are 1–128 characters, with no \"/\""
        case .valueTooLarge: "the value is over 64 KB, the most DB keeps under one key"
        case .tooManyKeys: "DB keeps at most \(DBSession.maxKeys) keys per app: store a collection under one key"
        case .storeFull: "DB keeps at most 5 MB per app"
        }
    }
}

/// Every `DB` call of a run, as "GET /key", "PUT /key", "DELETE /key", when
/// the run's context is given one (`context.provide(DBTrace())`): for tests
/// and for looking into what an app does.
@MainActor
final class DBTrace {
    var calls: [String] = []
}
