//
//  CheckCorpusTests.swift
//  KilnTests
//
//  The false-positive guard for `Kiln.check` (PLAN.md §1.8): every app Kiln
//  has (the example apps Lab runs, the Apple Intelligence replies, Shelf's
//  feature fixtures, the benchmark workloads, and every app written inline
//  in these tests) is checked. Any input that runs (`Kiln.validate` finds no
//  error) must check with no error either, except the one known case:
//  `expense.md` writes `.stepValue(0.1)`, which SwiftUI doesn't have.
//

import XCTest
@testable import Kiln

@MainActor
final class CheckCorpusTests: XCTestCase {

    /// Inputs that run but that `check` may reject, and why.
    static let knownErrors: [String: String] = [
        "Examples/AppleIntelligence/expense.md": ".stepValue",
    ]

    struct Input {
        let name: String
        let source: String
    }

    static var kilnRoot: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    static var repoRoot: URL { kilnRoot.deletingLastPathComponent().deletingLastPathComponent() }

    static func files(_ dir: URL, _ ext: String) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == ext }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Every app Kiln has.
    static func corpus() -> [Input] {
        var out: [Input] = []
        func add(_ url: URL, _ prefix: String) {
            guard var text = try? String(contentsOf: url, encoding: .utf8) else { return }
            if url.pathExtension == "md" { text = Kiln.swiftSource(fromMarkdown: text) }
            out.append(Input(name: prefix + url.lastPathComponent, source: text))
        }
        for f in files(kilnRoot.appendingPathComponent("Examples/Apps"), "swift") { add(f, "Examples/Apps/") }
        for f in files(kilnRoot.appendingPathComponent("Examples/AppleIntelligence"), "md") { add(f, "Examples/AppleIntelligence/") }
        for f in files(kilnRoot.appendingPathComponent("Examples/Networking"), "swift") { add(f, "Examples/Networking/") }
        add(kilnRoot.appendingPathComponent("Examples/LibraryApp.swift"), "Examples/")
        for f in files(kilnRoot.appendingPathComponent("Benchmarks/Workloads"), "swift") { add(f, "Benchmarks/Workloads/") }
        for f in files(repoRoot.appendingPathComponent("fixtures/apps"), "swift") { add(f, "fixtures/apps/") }
        out += testSources()
        return out
    }

    /// Every multi-line string literal in these tests that holds an app (as `Tools/diff.py` extracts them).
    static func testSources() -> [Input] {
        var out: [Input] = []
        let dir = kilnRoot.appendingPathComponent("Tests/KilnTests")
        guard let re = try? NSRegularExpression(pattern: #"(#*)"""\n(.*?)\n([ \t]*)"""\1"#, options: [.dotMatchesLineSeparators]) else { return [] }
        for f in files(dir, "swift") where f.lastPathComponent != "CheckTests.swift" && f.lastPathComponent != "CheckCorpusTests.swift" {
            guard let text = try? String(contentsOf: f, encoding: .utf8) else { continue }
            let ns = text as NSString
            for (i, m) in re.matches(in: text, range: NSRange(location: 0, length: ns.length)).enumerated() {
                let raw = ns.substring(with: m.range(at: 1))
                let body = ns.substring(with: m.range(at: 2))
                let indent = ns.substring(with: m.range(at: 3))
                guard body.contains("View"), body.contains("body") else { continue }
                var src = body.components(separatedBy: "\n").map { $0.hasPrefix(indent) ? String($0.dropFirst(indent.count)) : $0 }.joined(separator: "\n")
                if raw.isEmpty { src = src.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\") }
                // Interpolated test parameters can't be checked as written.
                if raw.isEmpty && src.contains("\\(") && !src.contains("\"\\(") { }
                out.append(Input(name: "tests/\(f.deletingPathExtension().lastPathComponent)-\(i)", source: src))
            }
        }
        return out
    }

    /// Shelf's `DB`, so the fixtures that save data run here too.
    static func registerDB() {
        Kiln.registerType("DB", notes: "Test stand-in") { t in
            t.staticMethod("load", "_:string") { _ in .nil }
            t.staticMethod("save", "_:string _:any") { _ in .void }
            t.staticMethod("remove", "_:string") { _ in .void }
        }
    }

    func testCheckHasNoFalseErrors() {
        Self.registerDB()
        var ran = 0, clean = 0, flagged: [String] = [], report: [String] = []
        var warnings = 0
        for input in Self.corpus() {
            let validation = Kiln.validate(input.source)
            let check = Kiln.check(input.source)
            warnings += check.warnings.count
            for w in check.warnings { report.append("  warning \(input.name): \(w)") }
            guard validation.errors.isEmpty else {
                for e in check.errors { report.append("  (doesn't run) \(input.name): \(e)") }
                continue
            }
            ran += 1
            let errors = check.errors.filter { e in Self.knownErrors[input.name].map { !e.message.contains($0) } ?? true }
            if errors.isEmpty { clean += 1 } else {
                flagged.append(input.name)
                for e in errors { report.append("  FALSE ERROR \(input.name): \(e)") }
            }
        }
        print("Kiln.check corpus: \(ran) inputs run; \(clean) check clean; \(flagged.count) with false errors; \(warnings) warnings")
        for r in report { print(r) }
        XCTAssertGreaterThan(ran, 40)
        XCTAssertTrue(flagged.isEmpty, "false errors in \(flagged)")
    }

    /// The known case is still caught.
    func testExpenseReplyStepValueIsCaught() throws {
        let input = try XCTUnwrap(Self.corpus().first { $0.name == "Examples/AppleIntelligence/expense.md" })
        let check = Kiln.check(input.source)
        XCTAssertTrue(check.errors.contains { $0.kind == .unknownModifier && $0.message.contains(".stepValue") }, "\(check.issues)")
    }
}
