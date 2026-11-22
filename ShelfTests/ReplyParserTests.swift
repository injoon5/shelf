import Foundation
import Testing
@testable import Shelf

/// The shared reply fixtures (`fixtures/replies/README.md`): the admin's
/// TypeScript parser passes the same cases, so the two can't drift apart.
struct ReplyParserTests {
    struct Expected: Decodable {
        var name: String?
        var icon: String?
        var tint: String
        var slug: String
        var source: String
    }

    static let cases: [String] = {
        let dir = Fixture.root.appending(path: "replies")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasSuffix(".md") && $0 != "README.md" }.map { String($0.dropLast(3)) }.sorted()
    }()

    @Test func allSeventeenCasesAreBundled() {
        #expect(Self.cases.count == 17, "\(Self.cases)")
    }

    @Test(arguments: cases)
    func fixture(_ name: String) throws {
        let dir = Fixture.root.appending(path: "replies")
        // Read as bytes: a String read would already have dropped the byte-order mark.
        let input = try #require(String(data: try Data(contentsOf: dir.appending(path: "\(name).md")), encoding: .utf8))
        let expected = try JSONDecoder().decode(Expected.self, from: Data(contentsOf: dir.appending(path: "\(name).json")))
        let parsed = ReplyParser.parse(input)
        #expect(parsed.name == expected.name)
        #expect(parsed.icon == expected.icon)
        #expect(parsed.tint.rawValue == expected.tint)
        #expect(parsed.slug == expected.slug)
        #expect(parsed.source == expected.source)
    }

    // MARK: Rules the fixtures don't spell out

    @Test func byteOrderMarkAndLoneCarriageReturns() {
        let parsed = ReplyParser.parse("\u{FEFF}// Name: Mac\r// Tint: RED\r\rstruct ContentView: View {}\r")
        #expect(parsed.name == "Mac")
        #expect(parsed.tint == .red)
        #expect(parsed.source == "// Name: Mac\n// Tint: RED\n\nstruct ContentView: View {}\n")
    }

    @Test func emptyReply() {
        let parsed = ReplyParser.parse(" \n\t\n")
        #expect(parsed == ParsedReply(name: nil, icon: nil, tint: .blue, slug: "app", source: ""))
        #expect(ReplyParser.parse("```swift\n```").source == "")
    }

    @Test func fenceLinesAreNeverPartOfABlock() {
        let reply = "````Swift title=App.swift\n// Name: A\n```ignored text\nmiddle\n```swift\nlet b = 2\n"
        #expect(ReplyParser.parse(reply).source == "// Name: A\n\nlet b = 2\n")
    }

    @Test func indentedFencesAndHeaderLines() {
        let reply = "  ```swift  \n   //NAME :  Spaced Out  \n\t// icon:star\n  ```"
        let parsed = ReplyParser.parse(reply)
        #expect(parsed.name == "Spaced Out")
        #expect(parsed.icon == "star")
    }

    @Test func otherCommentsDontEndTheHeader() {
        let parsed = ReplyParser.parse("// A tracker\n\n// by me\n// Tint: mint\nimport SwiftUI\n// Name: Late\n")
        #expect(parsed.tint == .mint)
        #expect(parsed.name == nil)
    }

    @Test func notAHeaderKey() {
        let parsed = ReplyParser.parse("// Names: X\n// Name X\n// Name: Real\n")
        #expect(parsed.name == "Real")
    }

    @Test(arguments: [
        ("Habits", "habits"),
        ("Habit Tracker", "habit-tracker"),
        ("  --Hello,   World!!-- ", "hello-world"),
        ("Ünïcödé Ñame", "unicode-name"),
        ("ﬁle ①", "file-1"),
        ("日記", "app"),
        ("---", "app"),
        ("", "app"),
        ("2048", "2048"),
        (String(repeating: "a", count: 63) + " b", String(repeating: "a", count: 63)),
    ])
    func slug(_ name: String, _ expected: String) {
        #expect(ReplyParser.slug(from: name) == expected)
    }
}
