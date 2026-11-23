// Copied into the engine before §1.3 when Tools/diff.sh builds it, so
// KETranscript.swift and KilnDiff compile against it unchanged. That engine
// has no tasks to drain and no host hook: its `await` blocks on URLSession,
// which KilnDiff's URLProtocol answers.
import Foundation

public struct KilnHostResponse {
    public var statusCode: Int
    public var body: Data?
    public init(statusCode: Int, body: Data? = nil) { self.statusCode = statusCode; self.body = body }
}

extension Kiln {
    @MainActor public static var hostRequestHandler: ((URLRequest) -> KilnHostResponse?)? {
        get { nil }
        set { _ = newValue }
    }
}

extension KInterpreter {
    func _transcriptFire(_ f: KFunction, _ args: [KV], canWait: Bool) {
        do { _ = try entry { try call(f, args, args.map { _ in nil }) } } catch { report(error) }
    }
    func _transcriptDrain() {}
}
