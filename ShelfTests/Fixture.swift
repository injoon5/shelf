import Foundation

/// The shared fixtures, bundled into the test target.
enum Fixture {
    static var root: URL {
        Bundle(for: Anchor.self).resourceURL!.appending(path: "fixtures")
    }
    static func app(_ name: String) throws -> String {
        try String(contentsOf: root.appending(path: "apps/\(name).swift"), encoding: .utf8)
    }
    private final class Anchor {}
}
