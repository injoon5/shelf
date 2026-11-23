//
//  KETranscriptShim.swift
//  Kiln's engine
//
//  The calls KETranscript.swift and Tools/KilnDiff make that differ between
//  engines. Tools/KilnDiff/BaselineShim.swift is the copy the engine before
//  §1.3 is built with; this one starts as the same.
//
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
