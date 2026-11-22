import Foundation
import Kiln
import Testing
@testable import Shelf

struct SourceRewriterTests {
    private func scoped(_ source: String) -> String {
        SourceRewriter.scopingAppStorage(in: source, to: "habits")
    }

    @Test func thePlainForm() {
        #expect(scoped(#"@AppStorage("count") private var count = 0"#) == #"@AppStorage("habits.count") private var count = 0"#)
    }

    @Test func aStoreArgumentIsKept() {
        #expect(scoped(#"@AppStorage("k", store: .standard) var k = """#) == #"@AppStorage("habits.k", store: .standard) var k = """#)
    }

    @Test func spacingAndNewlinesBeforeTheKey() {
        #expect(scoped("@AppStorage (\n    \"theme\"\n) var theme = 0") == "@AppStorage (\n    \"habits.theme\"\n) var theme = 0")
    }

    @Test func everyAttributeInAFile() {
        let source = """
        struct ContentView: View {
            @AppStorage("a") var a = 1
            @AppStorage("b") var b = true
        }
        """
        let out = scoped(source)
        #expect(out.contains(#"@AppStorage("habits.a")"#))
        #expect(out.contains(#"@AppStorage("habits.b")"#))
    }

    @Test func commentsAreLeftAlone() {
        let source = """
        // @AppStorage("count") is how the count is kept
        /* @AppStorage("old") /* nested @AppStorage("older") */ still a comment @AppStorage("x") */
        @AppStorage("count") var count = 0
        """
        let out = scoped(source)
        #expect(out.contains(#"// @AppStorage("count") is"#))
        #expect(out.contains(#"@AppStorage("old")"#))
        #expect(out.contains(#"@AppStorage("older")"#))
        #expect(out.contains(#"@AppStorage("x") */"#))
        #expect(out.hasSuffix(#"@AppStorage("habits.count") var count = 0"#))
    }

    @Test func stringsAreLeftAlone() {
        let source = ##"""
        let help = "Use @AppStorage(\"count\") for the count"
        let raw = #"@AppStorage("raw")"#
        let block = """
            @AppStorage("block")
            """
        @AppStorage("real") var real = 0
        """##
        let out = scoped(source)
        #expect(out.contains(#"@AppStorage(\"count\") for"#))
        #expect(out.contains(##"#"@AppStorage("raw")"#"##))
        #expect(out.contains(#"    @AppStorage("block")"#))
        #expect(out.contains(#"@AppStorage("habits.real")"#))
    }

    @Test func codeInsideAnInterpolationIsStillCode() {
        // A quote inside `\\( … )` doesn't end the string, so what follows the string is read correctly.
        let source = #"""
        let label = "Total: \(items["a"] ?? 0) items"
        @AppStorage("after") var after = 0
        """#
        let out = scoped(source)
        #expect(out.contains(#"items["a"]"#))
        #expect(out.contains(#"@AppStorage("habits.after")"#))
    }

    @Test func aStringLaterOnTheAttributesLineIsStillAString() {
        let source = #"""
        @AppStorage("note") var note = """
            @AppStorage("inside")
            """
        """#
        let out = scoped(source)
        #expect(out.contains(#"@AppStorage("habits.note")"#))
        #expect(out.contains(#"    @AppStorage("inside")"#))
    }

    @Test func similarNamesAndOtherFormsAreNotTouched() {
        #expect(scoped(#"@AppStorageBacked("k") var k = 0"#) == #"@AppStorageBacked("k") var k = 0"#)
        #expect(scoped("@AppStorage(key) var k = 0") == "@AppStorage(key) var k = 0")
        #expect(scoped("@AppStorage") == "@AppStorage")
    }

    @Test func lineNumbersNeverMove() {
        let source = "a\n@AppStorage(\"k\") var k = 0\n\"unterminated\nb\n/* open"
        #expect(scoped(source).components(separatedBy: "\n").count == source.components(separatedBy: "\n").count)
        #expect(SourceRewriter.prepare("DB.load(\"x\")\nline two", slug: "s").hasPrefix("DB.load(\"x\")\nline two\n"))
    }

    @Test func thePreludeIsAddedOnlyWhenNeeded() {
        #expect(SourceRewriter.prepare("let x = DB.load(\"k\")", slug: "s").contains("enum DB {"))
        #expect(!SourceRewriter.prepare("let x = 1", slug: "s").contains("enum DB {"))
        let own = "enum DB { static func load(_ k: String) -> Int { 1 } }\nlet x = DB.load(\"k\")"
        #expect(SourceRewriter.prepare(own, slug: "s") == own)
    }

    @Test @MainActor func twoAppsWithTheSameKeyKeepTheirOwnValues() {
        // What the rewrite is for: Kiln stores `@AppStorage` under `kiln.app.<key>`,
        // in the `UserDefaults.standard` every test shares, so these slugs are this run's own.
        let one = "one-\(UUID().uuidString)"
        let two = "two-\(UUID().uuidString)"
        let source = """
        import SwiftUI
        struct ContentView: View {
            @AppStorage("count") private var count = 0
            var body: some View { Text("\\(count)").onAppear { count += 1 } }
        }
        """
        let keys = AppStorageKeys(.standard)
        defer { [one, two].forEach { keys.remove(slug: $0) } }
        _ = Kiln.validate(SourceRewriter.prepare(source, slug: one))
        _ = Kiln.validate(SourceRewriter.prepare(source, slug: one))
        _ = Kiln.validate(SourceRewriter.prepare(source, slug: two))
        #expect(keys.defaults.integer(forKey: "kiln.app.\(one).count") == 2)
        #expect(keys.defaults.integer(forKey: "kiln.app.\(two).count") == 1)
    }
}

struct CompileErrorTests {
    private let source = (1...9).map { "line \($0)" }.joined(separator: "\n")

    @Test func theFailingLineAndItsNeighbours() {
        let error = CompileError(errors: ["Line 5: expected ')'\n  5 | line 5"], source: source)
        #expect(error.line == 5)
        #expect(error.message == "expected ')'")
        #expect(error.excerpt.map(\.number) == [3, 4, 5, 6, 7])
        #expect(error.excerpt[2].text == "line 5")
        #expect(error.report.contains("> 5 | line 5"))
    }

    @Test func theExcerptStopsAtTheFilesEdges() {
        #expect(CompileError(errors: ["Line 1: bad"], source: source).excerpt.map(\.number) == [1, 2, 3])
        #expect(CompileError(errors: ["Line 9: bad"], source: source).excerpt.map(\.number) == [7, 8, 9])
        #expect(CompileError(errors: ["Line 40: bad"], source: source).excerpt.isEmpty)
    }

    @Test func noLineNumberMeansJustTheMessage() {
        let error = CompileError(errors: ["No SwiftUI view found."], source: source)
        #expect(error.line == nil)
        #expect(error.excerpt.isEmpty)
        #expect(error.report == "No SwiftUI view found.")
    }
}
