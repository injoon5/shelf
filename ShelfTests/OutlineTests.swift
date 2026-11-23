import Foundation
import Testing
@testable import Shelf

/// `Outline.make` (plan §9.2): what the change prompt shows of an app when
/// its source is left out.
struct OutlineTests {
    // MARK: Every fixture app

    @Test(arguments: FeatureFixtureTests.apps)
    func keepsSavedTypesAndKeys(_ name: String) throws {
        let source = try Fixture.app(name)
        let outline = Outline.make(from: source)

        for line in Outline.header(of: source) {
            #expect(outline.hasPrefix(line) || outline.contains("\n" + line + "\n"), "\(name): header \(line)")
        }
        for block in Self.codableDeclarations(in: source) {
            #expect(outline.contains(block), "\(name): saved type not kept in full:\n\(block)")
        }
        for key in Self.keyLiterals(in: source) {
            #expect(outline.contains("\"\(key)\""), "\(name): key \(key)")
        }
    }

    @Test(arguments: FeatureFixtureTests.apps)
    func leavesOutEveryOtherBody(_ name: String) throws {
        let source = try Fixture.app(name)
        var rest = Outline.make(from: source)
        for block in Self.codableDeclarations(in: source) {
            rest = rest.replacingOccurrences(of: block, with: "")
        }
        for line in rest.components(separatedBy: "\n") where line.contains("{") {
            // A protocol's `var title: String { get }` is a requirement, not a body.
            let requirement = line.hasSuffix("{ get }") || line.hasSuffix("{ get set }")
            #expect(line.hasSuffix("{ … }") || Self.isTypeHeader(line) || requirement, "\(name): a body is left in: \(line)")
        }
        for statement in ["return ", "NavigationStack {", ".onAppear", "DB.save(", "withAnimation", "print("] {
            #expect(!rest.contains(statement), "\(name): \(statement)")
        }
        let lines = source.components(separatedBy: "\n").count
        if lines > 40 {
            #expect(Outline.make(from: source).count < source.count * 3 / 4, "\(name): the outline isn't much shorter")
        }
    }

    // MARK: Saved types

    @Test func savedTypesPullInWhatTheyHold() {
        let source = """
            // Name: Plants
            import SwiftUI

            struct Plant: Codable, Identifiable {
                var id = UUID()
                var name: String
                var schedule: Schedule
                var photos: [Photo] = []
                var kind = Kind.fern
            }

            struct Schedule {
                var every: Int
                var last: Date? = nil
                var tag: Tag?
            }

            struct Photo { var caption: String }

            enum Kind: String { case fern, cactus }

            enum Tag: String { case home, office }

            struct Unrelated {
                var value: Int
                func compute() -> Int { value * 2 }
            }
            """
        let outline = Outline.make(from: source)
        #expect(outline.contains("""
            struct Schedule {
                var every: Int
                var last: Date? = nil
                var tag: Tag?
            }
            """))
        #expect(outline.contains("struct Photo { var caption: String }"))
        #expect(outline.contains("enum Kind: String { case fern, cactus }"))
        #expect(outline.contains("enum Tag: String { case home, office }"))
        #expect(outline.contains("    func compute() -> Int { … }"))
    }

    @Test func conformanceFromAnExtensionAndNestedTypes() {
        let source = """
            struct Settings {
                var theme: Theme = .light
                var units = Units()
                enum Theme: String { case light, dark }
                struct Units { var metric = true }
                func describe() -> String { theme.rawValue }
            }
            extension Settings: Codable {}

            struct Screen: View {
                struct Row: Codable { var label: String }
                var rows: [Row] = []
                var body: some View { Text("\\(rows.count)") }
            }
            """
        let outline = Outline.make(from: source)
        #expect(outline.contains("    func describe() -> String { theme.rawValue }"), "saved types are kept whole, methods too")
        #expect(outline.contains("extension Settings: Codable {"))
        #expect(outline.contains("    struct Row: Codable { var label: String }"))
        #expect(outline.contains("    var body: some View { … }"))
    }

    @Test func codingKeysInAnExtensionStay() {
        let source = """
            struct Item: Codable { var userName: String }
            extension Item {
                enum CodingKeys: String, CodingKey { case userName = "user_name" }
                var shout: String { userName.uppercased() }
            }
            """
        let outline = Outline.make(from: source)
        #expect(outline.contains(#"    enum CodingKeys: String, CodingKey { case userName = "user_name" }"#))
        #expect(outline.contains("    var shout: String { … }"))
    }

    @Test func generics() {
        let source = """
            struct Box<Value: Codable>: Codable { var value: Value }
            struct Stack<Element> where Element: Equatable {
                var items: [Element] = []
                mutating func push(_ e: Element) { items.append(e) }
                func map<U>(_ f: (Element) -> U) -> [U] where U: Hashable { items.map(f) }
            }
            """
        let outline = Outline.make(from: source)
        #expect(outline.contains("struct Box<Value: Codable>: Codable { var value: Value }"))
        #expect(outline.contains("struct Stack<Element> where Element: Equatable {"))
        #expect(outline.contains("    mutating func push(_ e: Element) { … }"))
        #expect(outline.contains("    func map<U>(_ f: (Element) -> U) -> [U] where U: Hashable { … }"))
    }

    // MARK: Keys

    @Test func keysFromStringLiteralsOnly() {
        let source = """
            struct ContentView: View {
                @AppStorage("darkMode") private var darkMode = false
                @AppStorage( "count" ) var count = 0
                var body: some View { Text("x") }
                func load() {
                    if let data = DB.load("items") { print(data) }
                    DB.save("items", Data())
                    DB.remove("old-items")
                    DB.save(dynamicKey, Data())
                    // DB.save("commented", Data())
                    print("DB.save(\\"inString\\", x)")
                }
            }
            """
        let outline = Outline.make(from: source)
        #expect(outline.contains(#"// Saved with DB: "items", "old-items""#), "\(outline)")
        #expect(outline.contains(#"// Saved with @AppStorage: "darkMode", "count""#))
        #expect(!outline.contains("commented"))
        #expect(!outline.contains("inString"))
    }

    // MARK: Reading Swift

    @Test func bracesInStringsAndComments() {
        let source = #####"""
            struct ContentView: View {
                let open = "{"
                let close = "}\"}"
                let raw = #"a "quoted" } brace"#
                let rawer = ##"also "# } here"##
                let multi = """
                    }}} "{" \(items.map { "\($0) }" }.joined())
                    """
                let rawMulti = #"""
                    } \#(1 + 1) "}" \( not interpolation }
                    """#
                /* a { block /* nested } */ comment { */
                var body: some View { Text("}") } // }
                func after() { }
            }
            """#####
        let outline = Outline.make(from: source)
        #expect(outline.contains(#"    let close = "}\"}""#))
        #expect(outline.contains(##"    let raw = #"a "quoted" } brace"#"##))
        #expect(outline.contains("    let multi = \"\"\"\n        }}} \"{\""))
        #expect(outline.contains("    var body: some View { … }"))
        #expect(outline.contains("    func after() { … }"))
        #expect(outline.hasSuffix("}\n"))
        #expect(!outline.contains("nested"))
    }

    @Test func attributesModifiersAndAccessors() {
        let source = """
            @MainActor
            @Observable
            final class Store {
                @ObservationIgnored private(set) var count = 0
                static let shared = Store()
                var doubled: Int {
                    get { count * 2 }
                    set { count = newValue / 2 }
                }
                var name = "" {
                    didSet { print(name) }
                }
                @discardableResult
                func bump() -> Int { count += 1; return count }
                init() {}
                deinit { print("bye") }
                subscript(i: Int) -> Int { i }
            }
            protocol Named {
                var name: String { get set }
                func greet() -> String
            }
            #Preview {
                ContentView()
            }
            """
        let outline = Outline.make(from: source)
        #expect(outline.contains("@MainActor\n@Observable\nfinal class Store {"))
        #expect(outline.contains("    @ObservationIgnored private(set) var count = 0"))
        #expect(outline.contains("    static let shared = Store()"))
        #expect(outline.contains("    var doubled: Int { … }"))
        #expect(outline.contains("    var name = \"\" { … }"))
        #expect(outline.contains("    @discardableResult\n    func bump() -> Int { … }"))
        #expect(outline.contains("    init() { … }"))
        #expect(outline.contains("    deinit { … }"))
        #expect(outline.contains("    subscript(i: Int) -> Int { … }"))
        #expect(outline.contains("    var name: String { get set }"))
        #expect(outline.contains("    func greet() -> String\n"))
        #expect(outline.contains("#Preview { … }"))
    }

    @Test func multiLineDeclarations() {
        let source = """
            struct ContentView: View {
                let timer = Timer.publish(every: 1, on: .main, in: .common)
                    .autoconnect()
                @State private var items = [
                    "a",
                    "b",
                ]
                let formatter: DateFormatter = {
                    let f = DateFormatter()
                    return f
                }()
                func long(
                    a: Int,
                    b: Int
                ) -> Int {
                    a + b
                }
                var body: some View { Text("x") }
            }
            """
        let outline = Outline.make(from: source)
        #expect(outline.contains("    let timer = Timer.publish(every: 1, on: .main, in: .common)\n        .autoconnect()\n"))
        #expect(outline.contains("    @State private var items = [\n        \"a\",\n        \"b\",\n    ]"))
        #expect(outline.contains("    let formatter: DateFormatter = {\n        let f = DateFormatter()\n        return f\n    }()"))
        #expect(outline.contains("    func long(\n        a: Int,\n        b: Int\n    ) -> Int { … }"))
    }

    @Test func oneLineTypesGetOneMemberPerLine() {
        let outline = Outline.make(from: "struct Row: View { let title: String; var body: some View { Text(title) } }")
        #expect(outline == "struct Row: View {\n    let title: String\n    var body: some View { … }\n}\n")
    }

    // MARK: Never crashes

    @Test func truncatedFileKeepsTheRestAsItIs() throws {
        let source = try Fixture.app("saving-data")
        let cut = String(source[..<source.range(of: "func load() {")!.upperBound]) + "\n        if let data = DB.load(\"books\") {\n"
        let outline = Outline.make(from: cut)
        #expect(outline.contains("struct Book: Codable"))
        #expect(outline.contains("if let data = DB.load(\"books\") {"), "the cut-off type is left as it is")
        #expect(outline.contains(#"// Saved with DB: "notes", "books""#))
    }

    @Test func malformedInputNeverCrashesOrHangs() throws {
        let inputs = [
            "", "\n\n", "}", "}}}{{{", "{", "\"", "\"\"\"", "#\"", "/*", "/* /* */", "struct", "struct {", "func (",
            "var x = \"\\(", "let s = \"\\(\"\\(\"\\(", "@", "@MainActor", "@Attr(", "#Preview {", "extension", "enum E { case",
            String(repeating: "\"\\(", count: 500), String(repeating: "{", count: 2000), String(repeating: "/*", count: 300),
            "struct A { var b: Int {", "\u{FEFF}// Name: X\r\nstruct A {}\r\n", "\"\u{301}{\"", "#\"\"\"\n}\n\"\"\"#",
        ]
        for input in inputs {
            _ = Outline.make(from: input)
        }
        // Every prefix of a real app, in steps.
        for name in FeatureFixtureTests.apps {
            let scalars = Array(try Fixture.app(name).unicodeScalars)
            for end in stride(from: 0, to: scalars.count, by: 53) {
                var view = String.UnicodeScalarView()
                view.append(contentsOf: scalars[..<end])
                _ = Outline.make(from: String(view))
            }
        }
    }

    // MARK: Helpers

    /// The full text of each type declared `Codable`, `Encodable` or
    /// `Decodable` in a fixture, found by indentation (fixtures are formatted).
    static func codableDeclarations(in source: String) -> [String] {
        let lines = source.components(separatedBy: "\n")
        var blocks: [String] = []
        for (i, line) in lines.enumerated() where isTypeHeader(line)
            && ["Codable", "Encodable", "Decodable"].contains(where: { line.contains($0) }) {
            let indent = String(line.prefix { $0 == " " })
            if line.hasSuffix("}") { blocks.append(line); continue }
            guard let end = lines[(i + 1)...].firstIndex(where: { $0 == indent + "}" }) else { continue }
            blocks.append(lines[i...end].joined(separator: "\n"))
        }
        // A nested saved type is inside its parent's block already.
        return blocks.filter { block in !blocks.contains { $0 != block && $0.contains(block) } }
    }

    static func keyLiterals(in source: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"(?:DB\.(?:load|save|remove)|@AppStorage)\("([^"]+)""#)
        let ns = source as NSString
        return regex.matches(in: source, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    static func isTypeHeader(_ line: String) -> Bool {
        let words = line.split(separator: " ").map(String.init)
        return words.contains { ["struct", "class", "enum", "extension", "actor", "protocol"].contains($0) }
    }
}
