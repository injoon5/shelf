import XCTest
import SwiftUI
@testable import Kiln

/// Engine 2 checks that run headless. The end-to-end proof is Kiln Lab
/// (Lab/, Tools/iterate.sh), which drives every example natively and in Kiln
/// on a simulator and compares the screens; these pin the fixes it found.
@MainActor
final class KilnEngineTests: XCTestCase {
    private let examples = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../Examples").standardized

    private func files(_ folder: String, _ ext: String) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: examples.appendingPathComponent(folder), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == ext }.sorted { $0.path < $1.path }
    }

    func testExampleAppsAndModelRepliesValidate() throws {
        let apps = try files("Apps", "swift")
        let replies = try files("AppleIntelligence", "md")
        XCTAssertFalse(apps.isEmpty)
        XCTAssertFalse(replies.isEmpty)
        for url in apps {
            let v = Kiln.validate(try String(contentsOf: url, encoding: .utf8))
            XCTAssertEqual(v.errors, [], url.lastPathComponent)
            XCTAssertTrue(v.renderedContent, url.lastPathComponent)
        }
        // Replies that write something SwiftUI doesn't have stop there, with
        // its line (PLAN.md §1.4: unknown names aren't skipped silently).
        let invalid = ["expense.md": ["Line 40: Kiln doesn't support the .stepValue() modifier"]]
        for url in replies {
            let code = Kiln.swiftSource(fromMarkdown: try String(contentsOf: url, encoding: .utf8))
            let v = Kiln.validate(code)
            XCTAssertEqual(v.errors, invalid[url.lastPathComponent] ?? [], url.lastPathComponent)
            XCTAssertTrue(v.renderedContent, url.lastPathComponent)
        }
    }

    /// A computed property read from `body` (directly or through `self.`)
    /// sees the view's @State as it is now, not the struct's initial values.
    func testComputedPropertiesReadTheViewsState() throws {
        let c = try KilnEngine.compile("""
        import SwiftUI
        struct ContentView: View {
            @State private var bill = 80.0
            @State private var people = 2
            private var each: Double { bill / Double(people) }
            var body: some View {
                VStack {
                    Text("each \\(each)")
                    Text("self \\(self.each)")
                }
            }
        }
        """)
        guard case .view(let t) = c.root,
              case .structV(let s) = try c.interp.entry({ try c.interp.instantiate(t, args: [], labels: [], line: 0) }) else {
            return XCTFail("no ContentView")
        }
        let storage = KViewStorage()
        storage.prepare(s, c.interp)
        storage.box("people")?.value = .int(4)
        XCTAssertEqual(try texts(s, storage, c.interp), ["each 20.000000", "self 20.000000"])
    }

    /// `Section("Bill")`, `Stepper("2 people", …)`: a string title as the
    /// first, unlabeled argument reaches the renderer.
    func testUnlabeledFirstArgumentIsATitle() {
        XCTAssertTrue(KArgs(args: [.string("Bill"), .void], labels: [nil, nil]).firstIsUnlabeled)
        XCTAssertFalse(KArgs(args: [.string("x")], labels: ["header"]).firstIsUnlabeled)
    }

    /// `.foregroundStyle(.white.opacity(0.6))`: Color is a View too, so the
    /// opacity arrives as a modifier on a Color view and must still be a color.
    func testColorWithOpacityModifierIsAStyle() throws {
        let c = try KilnEngine.compile("""
        import SwiftUI
        struct ContentView: View {
            var body: some View { Image(systemName: "star.fill").foregroundStyle(.white.opacity(0.6)) }
        }
        """)
        let views = try KilnEngine.rootViews(c.root, c.interp)
        guard case .custom(let s) = views.first?.kind else { return XCTFail("no ContentView") }
        let body = try bodyViews(s, KViewStorage(), c.interp)
        guard case .modified(_, let m) = body.first?.kind, m.name == "foregroundStyle" else { return XCTFail("no foregroundStyle") }
        XCTAssertEqual(KRenderer(interp: c.interp).color(m.first), Color.white.opacity(0.6))
    }

    /// A string literal given to a SwiftUI title is a LocalizedStringKey:
    /// SwiftUI shows `Text("\(1400)")` as "1,400" and `Text("\(3.5)")` as
    /// "3.500000" (checked on a simulator in Lab/KilnLab/LabProbe.swift).
    /// `verbatim:` and plain Strings are left alone.
    func testTitleLiteralsFormatNumbersLikeSwiftUI() throws {
        let c = try KilnEngine.compile("""
        import SwiftUI
        struct ContentView: View {
            let pages = 1400
            var body: some View {
                VStack {
                    Text("\\(pages) pages read")
                    Text("double \\(3.5)")
                    Text("neg \\(-12345)")
                    Text(verbatim: "verbatim \\(pages)")
                    Text("\\(pages)" as String)
                    Text("spec \\(3.14159, specifier: "%.2f")")
                }
            }
        }
        """)
        let views = try KilnEngine.rootViews(c.root, c.interp)
        guard case .custom(let s) = views.first?.kind else { return XCTFail("no ContentView") }
        let locale = Locale.current.groupingSeparator ?? ","
        XCTAssertEqual(try texts(s, KViewStorage(), c.interp),
                       ["1\(locale)400 pages read", "double 3.500000", "neg -12\(locale)345", "verbatim 1400", "1400", "spec 3.14"])
    }

    /// JSONEncoder writes what JSONDecoder reads: stored properties through
    /// CodingKeys, nil optionals left out, raw-value enums, UUIDs and dates.
    /// A property with an inferred type (`var id = UUID()`, `var servings = 2.0`)
    /// comes back as the kind of value its default is.
    func testJSONEncoderRoundTripsDeclaredTypes() throws {
        let c = try KilnEngine.compile(#"""
        import SwiftUI
        enum Level: String, Codable { case easy, hard }
        struct Step: Codable { var text: String }
        struct Recipe: Codable, Identifiable {
            var id = UUID()
            var title: String
            var cookMinutes: Int
            var level: Level = .easy
            var rating: Double?
            var made: Date = Date(timeIntervalSinceReferenceDate: 86400)
            var servings = 2.0
            var steps: [Step] = []
            enum CodingKeys: String, CodingKey { case id, title, cookMinutes = "cook_minutes", level, rating, made, servings, steps }
        }

        func run() -> String {
            let recipes = [Recipe(title: "Soup \"hot\"", cookMinutes: 25, level: .hard, steps: [Step(text: "Boil")]),
                           Recipe(title: "Toast", cookMinutes: 3, rating: 4.5)]
            do {
                let data = try JSONEncoder().encode(recipes)
                let back = try JSONDecoder().decode([Recipe].self, from: data)
                let same = back[0].id == recipes[0].id && back[1].made == recipes[1].made && back[0].servings + 0.5 == 2.5
                return "\(back.count) \(back[0].title) \(back[0].cookMinutes) \(back[0].level.rawValue) \(back[0].rating == nil) \(back[0].steps[0].text) \(back[1].rating ?? 0) \(same)"
            } catch {
                return "failed: " + error.localizedDescription
            }
        }
        struct ContentView: View {
            var body: some View { Text(run()) }
        }
        """#)
        let views = try KilnEngine.rootViews(c.root, c.interp)
        guard case .custom(let s) = views.first?.kind else { return XCTFail("no ContentView") }
        XCTAssertEqual(try texts(s, KViewStorage(), c.interp), [#"2 Soup "hot" 25 hard true Boil 4.5 true"#])
    }

    /// JSONDecoder builds your own Decodable types: CodingKeys, snake_case,
    /// optionals, defaults, nested arrays and raw-value enums; a missing key
    /// throws an Error whose localizedDescription can be shown.
    func testJSONDecoderBuildsDeclaredTypes() throws {
        let c = try KilnEngine.compile(#"""
        import SwiftUI
        enum Level: String, Decodable { case easy, hard }
        struct Step: Decodable { let text: String }
        struct Recipe: Decodable {
            let title: String
            let cookMinutes: Int
            let level: Level
            let rating: Double?
            var favorite = false
            let steps: [Step]
        }
        struct Short: Decodable {
            let name: String
            enum CodingKeys: String, CodingKey { case name = "full_name" }
        }
        struct Needs: Decodable { let missing: Int }

        func run() -> String {
            let json = """
            {"title": "Soup", "cook_minutes": 25, "level": "hard", "steps": [{"text": "Boil"}, {"text": "Stir"}],
             "full_name": "Ada Lovelace"}
            """.data(using: .utf8)!
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            do {
                let r = try decoder.decode(Recipe.self, from: json)
                let n = try JSONDecoder().decode(Short.self, from: json)
                var out = "\(r.title) \(r.cookMinutes) \(r.level.rawValue) \(r.rating == nil) \(r.favorite) \(r.steps.map { $0.text }.joined(separator: ",")) \(n.name)"
                do {
                    _ = try JSONDecoder().decode(Needs.self, from: json)
                } catch {
                    out += " | " + error.localizedDescription
                }
                return out
            } catch {
                return "failed: " + error.localizedDescription
            }
        }
        struct ContentView: View {
            var body: some View { Text(run()) }
        }
        """#)
        let views = try KilnEngine.rootViews(c.root, c.interp)
        guard case .custom(let s) = views.first?.kind else { return XCTFail("no ContentView") }
        XCTAssertEqual(try texts(s, KViewStorage(), c.interp),
                       [#"Soup 25 hard true false Boil,Stir Ada Lovelace | The data couldn't be read because "missing" is missing (decoding Needs)."#])
    }

    /// With a seed, a shuffle in Kiln matches native Swift drawing from
    /// KilnRandom with the same seed (the Lab relies on this).
    func testSeededShuffleMatchesNative() throws {
        Kiln.randomSeed = 7
        defer { Kiln.randomSeed = nil }
        let c = try KilnEngine.compile("""
        import SwiftUI
        let deck = Array(1...12).shuffled()
        struct ContentView: View {
            var body: some View { Text("\\(deck)") }
        }
        """)
        var native = KilnRandom(seed: 7)
        let expected = Array(1...12).shuffled(using: &native)
        XCTAssertEqual(c.interp.describe(c.interp.globalEnv.lookup("deck")?.value ?? .void), "\(expected)")
    }

    // MARK: Helpers

    private func bodyViews(_ s: KStructValue, _ storage: KViewStorage, _ interp: KInterpreter) throws -> [KView] {
        storage.prepare(s, interp)
        let ctx = KSelfContext(type: s.type, location: .box(KBox(.structV(s))), storage: storage)
        let env = KEnv(parent: interp.globalEnv, selfContext: ctx)
        guard let body = s.type.computed["body"] else { return [] }
        let v = try interp.entry { try interp.runAccessor(body.getter ?? [], env: env, returns: body.type) }
        return KBuiltins.asViews(v, interp)
    }

    /// Every Text's string in the body, in order.
    private func texts(_ s: KStructValue, _ storage: KViewStorage, _ interp: KInterpreter) throws -> [String] {
        var out: [String] = []
        func walk(_ v: KView) {
            switch v.kind {
            case .primitive("Text", let args, _, _): out.append(args.first.map { interp.describe($0) } ?? "")
            case .primitive(_, let args, _, _):
                for case .function(let f) in args {
                    (try? interp.entry { try interp.callBuilder(f, []) })?.forEach(walk)
                }
            case .modified(let base, _): walk(base)
            case .group(let vs), .conditional(_, let vs), .switchBranch(_, let vs): vs.forEach(walk)
            default: break
            }
        }
        try bodyViews(s, storage, interp).forEach(walk)
        return out
    }
}
