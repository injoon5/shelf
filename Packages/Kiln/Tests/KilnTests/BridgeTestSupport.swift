import XCTest
import SwiftUI
@testable import Kiln

/// Round 1's bridge tests: an app's code is checked (`Kiln.check`), validated
/// (its body evaluated and its actions fired), and shown in a real window so
/// every bridge's SwiftUI view is built.
@MainActor
enum BridgeTest {
    static func app(_ body: String, state: String = "", extra: String = "") -> String {
        """
        import SwiftUI
        \(extra)
        struct ContentView: View {
            \(state)
            var body: some View {
                \(body)
            }
        }
        """
    }

    /// Errors from checking, validating and showing the app, in that order.
    static func problems(_ source: String, host: Bool = true, file: StaticString = #filePath, line: UInt = #line) -> [String] {
        var out: [String] = []
        out += Kiln.check(source).errors.map { "check: \($0)" }
        out += Kiln.validate(source).errors.map { "validate: \($0)" }
        if host { out += shown(source).map { "shown: \($0)" } }
        return out
    }

    /// Errors reported while the app is shown in a window for a moment.
    static func shown(_ source: String, size: CGSize = CGSize(width: 390, height: 844)) -> [String] {
        var errors: [String] = []
        let context = KilnContext.stub()
        context.onError = { errors.append($0.message) }
        let result = Kiln.run(source, context: context)
        errors += result.errors
        guard let view = result.view else { return errors + ["no view"] }
        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        for _ in 0..<6 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        window.contentView = nil
        #else
        let host = UIHostingController(rootView: view.frame(width: size.width, height: size.height))
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.isHidden = false
        for _ in 0..<6 { host.view.layoutIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        window.isHidden = true
        #endif
        result.tearDown()
        return errors
    }

    /// The overloads the code's views and modifiers picked, as `Name(labels:)`.
    static func bound(_ source: String) throws -> [String] {
        let c = try KilnEngine.compile(source, headless: true)
        var out: [String] = []
        func walk(_ v: KView) {
            switch v.kind {
            case .primitive(let n, let args, _, _):
                if let b = v.bound { out.append(b.overload.display(n)) }
                for a in args { if case .function(let f) = a, let views = try? c.interp.callBuilder(f) { views.forEach(walk) } }
            case .modified(let base, let m):
                walk(base)
                if let b = m.bound { out.append(b.overload.display("." + m.name)) }
                for a in m.args { if case .function(let f) = a, let views = try? c.interp.callBuilder(f) { views.forEach(walk) } }
            case .group(let vs), .conditional(_, let vs), .switchBranch(_, let vs): vs.forEach(walk)
            case .custom(let s):
                if let b = s.type.computed["body"] {
                    let env = KEnv(parent: c.interp.globalEnv, selfContext: KSelfContext(type: s.type, location: .box(KBox(.structV(s))), storage: nil))
                    if let v = try? c.interp.entry({ try c.interp.runAccessor(b.getter ?? [], env: env, returns: b.type) }) {
                        KBuiltins.asViews(v, c.interp).forEach(walk)
                    }
                }
            default: break
            }
        }
        try KilnEngine.rootViews(c.root, c.interp).forEach(walk)
        return out
    }
}
