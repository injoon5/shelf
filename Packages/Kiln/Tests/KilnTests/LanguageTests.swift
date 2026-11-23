import XCTest
import SwiftUI
@_spi(KilnTesting) @testable import Kiln

/// PLAN.md §1.6: Swift that should work in Kiln, one test per item.
/// Each program runs headless; `print` is what it shows.
@MainActor
final class LanguageTests: XCTestCase {

    /// Runs top-level code: what it printed, and its errors.
    func run(_ source: String) -> (console: String, errors: [String]) {
        do {
            let interp = try KInterpreter(program: try KEParser.parse(source), headless: true)
            return (interp.console, interp.errors)
        } catch {
            return ("", ["\(error)"])
        }
    }

    func expect(_ source: String, prints expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let r = run(source)
        XCTAssertEqual(r.errors, [], file: file, line: line)
        XCTAssertEqual(r.console, expected, file: file, line: line)
    }

    func expect(_ source: String, fails expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let r = run(source)
        XCTAssertTrue(r.errors.contains { $0.contains(expected) }, "\(r.errors)", file: file, line: line)
    }

    // MARK: Protocols

    func testProtocolExtensionDefaults() {
        expect("""
        protocol Greeter { var name: String { get } }
        extension Greeter {
            func greeting() -> String { "Hi " + name }
            var shout: String { greeting().uppercased() }
        }
        struct Person: Greeter { var name = "Ann" }
        struct Robot: Greeter {
            var name = "R2"
            func greeting() -> String { "Beep, " + name }
        }
        print(Person().greeting())
        print(Person().shout)
        print(Robot().greeting())
        print(Robot().shout)
        """, prints: "Hi Ann\nHI ANN\nBeep, R2\nBEEP, R2\n")
    }

    func testConstrainedExtensionsAndInheritance() {
        expect("""
        protocol Named { var name: String { get } }
        protocol Titled: Named {}
        extension Named { func label() -> String { "plain " + name } }
        extension Named where Self: Equatable { func label() -> String { "equatable " + name } }
        struct A: Titled { var name = "a" }
        struct B: Titled, Equatable { var name = "b" }
        print(A().label())
        print(B().label())
        print(A() is Named, B() is Titled)
        """, prints: "plain a\nequatable b\ntrue true\n")
    }

    func testExistentialsAndSomeP() {
        expect("""
        protocol Shape2D { func area() -> Double }
        extension Shape2D { func describe() -> String { "area \\(area())" } }
        struct Square: Shape2D { var side: Double; func area() -> Double { side * side } }
        struct Circle2: Shape2D { var r: Double; func area() -> Double { 3 * r * r } }
        let shapes: [any Shape2D] = [Square(side: 2), Circle2(r: 1)]
        for s in shapes { print(s.describe()) }
        func biggest(_ items: [any Shape2D]) -> some Shape2D { items.max { $0.area() < $1.area() }! }
        print(biggest(shapes).area())
        let total = shapes.map { $0.area() }.reduce(0, +)
        print(total)
        if let sq = shapes[0] as? Square { print("square", sq.side) }
        print(shapes.filter { $0 is Circle2 }.count)
        """, prints: "area 4.0\narea 3.0\n4.0\n7.0\nsquare 2.0\n1\n")
    }

    func testStaticMemberOnProtocolType() {
        expect("""
        protocol Theme { var color: String { get } }
        struct Ocean: Theme { var color = "blue" }
        extension Theme where Self == Ocean { static var ocean: Ocean { Ocean() } }
        func paint(_ t: any Theme) -> String { t.color }
        print(paint(.ocean))
        """, prints: "blue\n")
    }

    func testProtocolOnNativeType() {
        expect("""
        protocol Describable { func describe() -> String }
        extension Describable { func twice() -> String { describe() + describe() } }
        extension Int: Describable { func describe() -> String { "#\\(self)" } }
        let items: [any Describable] = [3, 4]
        print(items.map { $0.twice() })
        print(5 is Describable)
        """, prints: "[\"#3#3\", \"#4#4\"]\ntrue\n")
    }

    func testExtensionsOnSwiftsProtocols() {
        expect("""
        extension Collection { var second: Element? { count > 1 ? self[index(after: startIndex)] : nil } }
        extension Sequence where Element: Numeric { func total() -> Element { reduce(0, +) } }
        extension Comparable { func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) } }
        struct Expense { var amount: Double }
        struct Income { var amount: Double }
        extension Array where Element == Expense { var sum: Double { reduce(0) { $0 + $1.amount } } }
        extension Array where Element == Income { var sum: Double { -reduce(0) { $0 + $1.amount } } }
        print([1, 2, 3].total())
        print(15.clamped(0, 10))
        print([Expense(amount: 2), Expense(amount: 3)].sum, [Income(amount: 1)].sum)
        """, prints: "6\n10\n5.0 -1.0\n")
    }

    func testGenericParametersNameTheirTypes() {
        expect("""
        protocol Animal { init(); var sound: String { get } }
        struct Dog: Animal { var sound = "woof" }
        func make<T: Animal>(_ type: T.Type) -> T { T() }
        func echo<T>(_ x: T) -> String { "\\(T.self)" }
        print(make(Dog.self).sound)
        print(echo(Dog()))
        """, prints: "woof\nDog\n")
    }

    func testCustomEquatableAndHashable() {
        expect("""
        struct Item: Hashable {
            var id: Int
            var name: String
            static func == (a: Item, b: Item) -> Bool { a.id == b.id }
            func hash(into hasher: inout Hasher) { hasher.combine(id) }
        }
        let a = Item(id: 1, name: "a"), b = Item(id: 1, name: "renamed")
        print(a == b, a != b)
        print(Set([a, b]).count)
        print([a].contains(b), [a].firstIndex(of: b) ?? -1)
        var counts: [Item: Int] = [:]
        counts[a, default: 0] += 1
        counts[b, default: 0] += 1
        print(counts[a] ?? 0)
        """, prints: "true false\n1\ntrue 0\n2\n")
    }

    func testComparableAndCustomStringConvertible() {
        expect("""
        struct Version: Comparable, CustomStringConvertible {
            var major: Int, minor: Int
            static func < (a: Version, b: Version) -> Bool { (a.major, a.minor) < (b.major, b.minor) }
            var description: String { "v\\(major).\\(minor)" }
        }
        let vs = [Version(major: 2, minor: 0), Version(major: 1, minor: 5), Version(major: 1, minor: 9)]
        print(vs.sorted())
        print(vs.max()!, vs.min()!)
        print(Version(major: 1, minor: 0) >= Version(major: 1, minor: 0))
        print("now \\(vs[0])")
        """, prints: "[v1.5, v1.9, v2.0]\nv2.0 v1.5\ntrue\nnow v2.0\n")
    }

    func testMissingRequirementIsAnError() {
        expect("""
        protocol Greeter { var name: String { get }; func greet() -> String }
        struct Mute: Greeter { var name = "x" }
        """, fails: "'Mute' doesn't conform to 'Greeter': it has no greet()")
    }

    func testClassInheritance() {
        expect("""
        class Animal { var name: String; init(name: String) { self.name = name }; func speak() -> String { name + " makes a sound" } }
        class Dog: Animal { override func speak() -> String { name + " barks" } }
        class Puppy: Dog {}
        let pets: [Animal] = [Animal(name: "a"), Dog(name: "d"), Puppy(name: "p")]
        for p in pets { print(p.speak()) }
        print(pets.filter { $0 is Dog }.count)
        """, prints: "a makes a sound\nd barks\np barks\n2\n")
    }

    func testConformanceDecidesWhatWorks() {
        expect("""
        struct Point { var x = 0 }
        print(Point() == Point())
        """, fails: "Binary operator '==' can't compare two 'Point' values: 'Point' isn't Equatable")
        expect("""
        enum Size { case s, m }
        print(Size.allCases)
        """, fails: "Type 'Size' has no member 'allCases': add `: CaseIterable`")
        expect("""
        struct Box { var w = 1 }
        print([Box(), Box()].sorted())
        """, fails: "'Box' isn't Comparable")
        // Synthesized where Swift synthesizes them, and inherited through protocols.
        expect("""
        enum Size: CaseIterable { case s, m }
        protocol Keyed: Hashable {}
        struct Tag: Keyed { var name = "a" }
        enum Load { case idle, busy(Int) }
        print(Size.allCases.map { "\\($0)" }.joined(separator: ","), Size.s == .s, Tag() == Tag(), Set([Tag(), Tag()]).count)
        let p: Load? = nil
        print(p == nil)
        """, prints: "s,m true true 1\ntrue\n")
    }

    // MARK: Result builders

    func testUserResultBuilder() {
        expect("""
        @resultBuilder
        struct ListBuilder {
            static func buildBlock(_ parts: [String]...) -> [String] { parts.flatMap { $0 } }
            static func buildExpression(_ s: String) -> [String] { [s] }
            static func buildExpression(_ n: Int) -> [String] { ["#\\(n)"] }
            static func buildOptional(_ p: [String]?) -> [String] { p ?? [] }
            static func buildEither(first p: [String]) -> [String] { p }
            static func buildEither(second p: [String]) -> [String] { p }
            static func buildArray(_ ps: [[String]]) -> [String] { ps.flatMap { $0 } }
            static func buildFinalResult(_ p: [String]) -> String { p.joined(separator: ",") }
        }
        @ListBuilder func make(_ vip: Bool, _ n: Int) -> String {
            "a"
            7
            if vip { "vip" }
            if n > 1 { "many" } else if n == 1 { "one" } else { "none" }
            for i in 0..<n { "i\\(i)" }
            switch n { case 0: "zero"; case 1: "uno"; default: "lots" }
            let tail = "z"
            tail
        }
        struct Menu {
            var vip = false
            @ListBuilder var items: String {
                "soup"
                if vip { "caviar" }
            }
        }
        func render(@ListBuilder _ content: () -> String) -> String { "[" + content() + "]" }
        print(make(true, 2))
        print(make(false, 0))
        print(Menu().items, Menu(vip: true).items)
        print(render { "x"; if true { "y" } })
        """, prints: "a,#7,vip,many,i0,i1,lots,z\na,#7,none,zero,z\nsoup soup,caviar\n[x,y]\n")
    }

    func testBuildPartialBlockAndEitherTree() {
        expect("""
        @resultBuilder enum Sum {
            static func buildPartialBlock(first: Int) -> Int { first }
            static func buildPartialBlock(accumulated: Int, next: Int) -> Int { accumulated + next }
            static func buildEither(first: Int) -> Int { first * 10 }
            static func buildEither(second: Int) -> Int { second * 100 }
        }
        @Sum func pick(_ k: Int) -> Int {
            1
            switch k { case 0: 2; case 1: 3; default: 4 }
        }
        print(pick(0), pick(1), pick(2))
        """, prints: "201 3001 401\n")
    }

    /// A builder a bridge registers (RegexBuilder's, §3.3) works the same way.
    func testNativeResultBuilder() {
        KRegistry.shared.resultBuilder("JoinBuilder", .language) { b in
            b.method("buildBlock") { parts, _, interp in .string(parts.map { interp.describe($0) }.joined(separator: "+")) }
            b.method("buildOptional") { args, _, _ in args.first.flatMap { $0.isNil ? nil : $0 } ?? .string("-") }
        }
        expect("""
        func join(@JoinBuilder _ f: () -> String) -> String { f() }
        print(join { "a"; 1; if true { "c" }; if false { "d" } })
        """, prints: "a+1+c+-\n")
    }

    func testViewBuilderFunctionsPropertiesAndParameters() throws {
        let code = """
        import SwiftUI
        struct Card<Content: View>: View {
            @ViewBuilder let content: Content
            var body: some View { VStack { content } }
        }
        struct Panel<Content: View>: View {
            let title: String
            let content: () -> Content
            init(_ title: String, @ViewBuilder content: @escaping () -> Content) { self.title = title; self.content = content }
            var body: some View { VStack { Text(title); content() } }
        }
        struct ContentView: View {
            @State private var n = 2
            var body: some View {
                VStack {
                    header(n > 1)
                    rows
                    Card { Text("in card"); Text("twice") }
                    Panel("P") { Text("p1"); if n == 2 { Text("p2") } }
                    labelled { Text("L") }
                }
            }
            @ViewBuilder func header(_ big: Bool) -> some View {
                if big { Text("big") } else { Text("small") }
            }
            @ViewBuilder var rows: some View {
                ForEach(0..<n, id: \\.self) { i in Text("row \\(i)") }
                switch n { case 2: Text("two"); default: Text("other") }
            }
            func labelled(@ViewBuilder _ content: () -> some View) -> some View { HStack { Text("label:"); content() } }
        }
        """
        let t = Kiln.transcript(code, steps: 0)
        for s in ["big", "row 1", "two", "in card", "twice", "p1", "p2", "label:", "\"L\""] {
            XCTAssertTrue(t.contains(s), "missing \(s) in\n\(t)")
        }
        XCTAssertFalse(t.lowercased().contains("error"), t)
    }

    // MARK: Property wrappers

    func testCustomPropertyWrappers() {
        expect("""
        @propertyWrapper
        struct Clamped {
            private var value: Int
            let range: ClosedRange<Int>
            init(wrappedValue: Int, _ range: ClosedRange<Int>) { self.range = range; value = min(max(wrappedValue, range.lowerBound), range.upperBound) }
            var wrappedValue: Int {
                get { value }
                set { value = min(max(newValue, range.lowerBound), range.upperBound) }
            }
            var projectedValue: String { "\\(value) in \\(range.lowerBound)...\\(range.upperBound)" }
        }
        @propertyWrapper
        struct Trimmed {
            private var text = ""
            var wrappedValue: String {
                get { text }
                set { text = newValue.trimmingCharacters(in: .whitespaces) }
            }
            init(wrappedValue: String) { self.wrappedValue = wrappedValue }
        }
        struct Speaker {
            @Clamped(0...10) var volume = 5
            @Trimmed var name: String
            var plays = 0 { didSet { print("played", plays) } }
            mutating func louder() { volume += 4 }
        }
        var s = Speaker(name: "  Hi  ")
        print(s.volume, s.name)
        s.louder(); s.louder()
        print(s.volume, s.$volume)
        s.name = "  Bye "
        print("[" + s.name + "]")
        s.volume = -3
        print(s.volume)
        final class Mixer {
            @Clamped(1...3) var level = 9
            @Trimmed var label = " a "
        }
        let m = Mixer()
        m.level = 2
        print(m.level, m.$level, m.label)
        func local() {
            @Clamped(0...1) var x = 7
            x = 5
            print(x, $x)
        }
        local()
        """, prints: "5 Hi\n10 10 in 0...10\n[Bye]\n0\n2 2 in 1...3 a\n1 1 in 0...1\n")
    }

    func testPropertyWrapperInInitAndWithArguments() {
        expect("""
        @propertyWrapper
        struct Scaled {
            var raw: Double
            var factor: Double
            init(wrappedValue: Double, factor: Double = 2) { raw = wrappedValue; self.factor = factor }
            var wrappedValue: Double { get { raw * factor } set { raw = newValue / factor } }
        }
        @propertyWrapper
        struct Counted { var wrappedValue: Int; var projectedValue: Int { wrappedValue * 100 } }
        struct Model {
            @Scaled(factor: 10) var size: Double
            @Counted var hits: Int
            init(size: Double) { self.size = size; self.hits = 3 }
        }
        let m = Model(size: 1.5)
        print(m.size, m.hits, m.$hits)
        """, prints: "15.0 3 300\n")
    }

    // MARK: Codable

    func testCustomInitFromAndEncodeTo() {
        expect("""
        struct Custom: Codable {
            var name: String
            var count: Int
            var tags: [String]
            enum CodingKeys: String, CodingKey { case name = "full_name", count, tags }
            init(name: String, count: Int) { self.name = name; self.count = count; tags = [] }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                name = try c.decode(String.self, forKey: .name)
                count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 99
                tags = c.contains(.tags) ? try c.decode([String].self, forKey: .tags) : ["none"]
            }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(name.uppercased(), forKey: .name)
                try c.encode(count * 2, forKey: .count)
            }
        }
        struct Other: Codable { var name = "o"; enum CodingKeys: String, CodingKey { case name = "other_name" } }
        let d = try! JSONDecoder().decode(Custom.self, from: Data(#"{"full_name":"ann"}"#.utf8))
        print(d.name, d.count, d.tags)
        let out = try! JSONEncoder().encode(Custom(name: "bo", count: 2))
        print(String(data: out, encoding: .utf8)!)
        print(String(data: try! JSONEncoder().encode(Other()), encoding: .utf8)!)
        """, prints: "ann 99 [\"none\"]\n{\"count\":4,\"full_name\":\"BO\"}\n{\"other_name\":\"o\"}\n")
    }

    func testUnkeyedSingleValueAndNestedContainers() {
        expect("""
        struct Point: Codable {
            var x: Int, y: Int
            init(x: Int, y: Int) { self.x = x; self.y = y }
            init(from decoder: Decoder) throws {
                var c = try decoder.unkeyedContainer()
                x = try c.decode(Int.self)
                y = try c.decode(Int.self)
            }
            func encode(to encoder: Encoder) throws {
                var c = encoder.unkeyedContainer()
                try c.encode(x)
                try c.encode(y)
            }
        }
        struct Celsius: Codable {
            var value: Double
            init(_ v: Double) { value = v }
            init(from decoder: Decoder) throws { value = try decoder.singleValueContainer().decode(Double.self) }
            func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(value) }
        }
        enum Shape: Codable {
            case circle(Double), square(Double)
            enum CodingKeys: String, CodingKey { case kind, size }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                let size = try c.decode(Double.self, forKey: .size)
                switch try c.decode(String.self, forKey: .kind) {
                case "circle": self = .circle(size)
                case "square": self = .square(size)
                default: throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "bad kind")
                }
            }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .circle(let s): try c.encode("circle", forKey: .kind); try c.encode(s, forKey: .size)
                case .square(let s): try c.encode("square", forKey: .kind); try c.encode(s, forKey: .size)
                }
            }
        }
        struct Plot: Codable {
            var points: [Point]
            var temp: Celsius
            var shapes: [Shape]
            var meta: [String: String]
            enum CodingKeys: String, CodingKey { case points, temp, shapes, meta }
            enum MetaKeys: String, CodingKey { case author }
            init(points: [Point], temp: Celsius, shapes: [Shape]) { self.points = points; self.temp = temp; self.shapes = shapes; meta = [:] }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                points = try c.decode([Point].self, forKey: .points)
                temp = try c.decode(Celsius.self, forKey: .temp)
                shapes = try c.decode([Shape].self, forKey: .shapes)
                let m = try c.nestedContainer(keyedBy: MetaKeys.self, forKey: .meta)
                meta = ["author": try m.decode(String.self, forKey: .author)]
            }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(points, forKey: .points)
                try c.encode(temp, forKey: .temp)
                try c.encode(shapes, forKey: .shapes)
                var m = c.nestedContainer(keyedBy: MetaKeys.self, forKey: .meta)
                try m.encode("kiln", forKey: .author)
            }
        }
        let p = Plot(points: [Point(x: 1, y: 2)], temp: Celsius(21.5), shapes: [.circle(1), .square(2)])
        let data = try! JSONEncoder().encode(p)
        let text = String(data: data, encoding: .utf8)!
        print(text)
        let back = try! JSONDecoder().decode(Plot.self, from: data)
        print(back.points[0].y, back.temp.value, back.shapes.count, back.meta["author"]!)
        if case .square(let s) = back.shapes[1] { print("square", s) }
        do {
            _ = try JSONDecoder().decode(Shape.self, from: Data(#"{"kind":"blob","size":1}"#.utf8))
        } catch {
            print(error.localizedDescription)
        }
        """, prints: "{\"meta\":{\"author\":\"kiln\"},\"points\":[[1,2]],\"shapes\":[{\"kind\":\"circle\",\"size\":1},{\"kind\":\"square\",\"size\":2}],\"temp\":21.5}\n2 21.5 2 kiln\nsquare 2.0\nThe data couldn't be read because it isn't in the correct format. (bad kind)\n")
    }

    /// Kiln 0.2.1's patch: `JSONEncoder().encode`, `[T].self`, and a decoded `UUID` stays a `UUID`.
    /// And a `Set` comes back a set; `Data(text.utf8)` has the bytes.
    func testCodablePatchFixesSetsAndData() {
        expect("""
        struct Todo: Codable, Identifiable, Hashable {
            var id = UUID()
            var title: String
            var tags: Set<String> = []
        }
        let todos = [Todo(title: "a", tags: ["x", "y"])]
        let data = try! JSONEncoder().encode(todos)
        let back = try! JSONDecoder().decode([Todo].self, from: data)
        print(back[0].id == todos[0].id, back[0].id is UUID, back[0].tags == ["y", "x"], back[0].tags is Set<String>)
        print(try! JSONDecoder().decode(Set<Int>.self, from: Data("[3,1,3]".utf8)).count)
        print(Data("héllo".utf8).count, String(data: Data([72, 105]), encoding: .utf8)!)
        """, prints: "true true true true\n2\n6 Hi\n")
    }

    func testCodingNeedsCodable() {
        expect("""
        struct Plain { var a = 1 }
        let d = try? JSONEncoder().encode(Plain())
        """, fails: "'Plain' isn't Encodable, so it can't be written as JSON: add `: Codable`")
    }

    // MARK: Regex literals

    func testRegexLiterals() {
        expect(#"""
        let text = "Order 66 shipped on 2024-03-09"
        if let m = text.firstMatch(of: /(\d{4})-(\d{2})-(\d{2})/) {
            print(m.0, m.1, m.output.3)
        }
        let named = #/(?<word>[a-z]+)-(?<num>\d+)/#
        if let m = "id: abc-42".firstMatch(of: named) { print(m.word, m.num) }
        print(text.contains(/\d+/), "nope".contains(/\d/))
        print(text.replacing(/\d/, with: "#"))
        print("a1b22".replacing(/\d+/) { m in "<\(m.0)>" })
        print("1 22 333".matches(of: /\d+/).map { $0.0 })
        print("2024".wholeMatch(of: /\d+/) != nil, "20x4".wholeMatch(of: /\d+/) == nil)
        let half = 10 / 2 / 5
        print(half)
        let r = try Regex("[A-Z]+")
        print("abcDEFgh".firstMatch(of: r)!.0)
        let path = #/a/b/#
        print("xa/by".contains(path))
        let spaced = #/
          (\d+)   # digits
          \s*
          (kg|g)  # unit
        /#
        if let m = "12 kg".wholeMatch(of: spaced) { print(m.1, m.2) }
        func kind(_ s: String) -> String {
            switch s {
            case /\d+/: return "number"
            case /[a-z]+/: return "word"
            default: return "other"
            }
        }
        print(kind("123"), kind("abc"), kind("a1"))
        """#, prints: "2024-03-09 2024 09\nabc 42\ntrue false\nOrder ## shipped on ####-##-##\na<1>b<22>\n[\"1\", \"22\", \"333\"]\ntrue true\n1\nDEF\ntrue\n12 kg\nnumber word other\n")
    }

    func testBadRegexIsAnErrorWithItsLine() {
        expect("""
        let a = 1
        let r = /(unclosed/
        """, fails: "Line 2: Invalid regex /(unclosed/")
    }

    // MARK: Small items

    func testOneSidedRangesInCase() {
        expect("""
        func grade(_ score: Int) -> String {
            switch score {
            case 90...: return "A"
            case 80..<90: return "B"
            case ..<50: return "F"
            default: return "C"
            }
        }
        func half(_ c: String) -> String {
            switch c { case "n"...: return "late"; default: return "early" }
        }
        print(grade(95), grade(85), grade(10), grade(60), half("q"), half("b"))
        print([1, 2, 3, 4][2...], (5...).contains(7))
        """, prints: "A B F C late early\n[3, 4] true\n")
    }

    func testBindingAnimationAndAllCasesMethods() throws {
        let code = """
        import SwiftUI
        enum Size: String, CaseIterable { case small, large }
        struct ContentView: View {
            @State private var on = false
            var body: some View {
                VStack {
                    Toggle("On", isOn: $on.animation())
                    Toggle("Spring", isOn: $on.animation(.spring()))
                    Text(Size.allCases.map { $0.rawValue }.joined(separator: "/"))
                    Text("\\(Size.allCases.count) sizes, first \\(Size.allCases.first!.rawValue)")
                }
            }
        }
        """
        let t = Kiln.transcript(code, steps: 0)
        XCTAssertTrue(t.contains("small/large"), t)
        XCTAssertTrue(t.contains("2 sizes, first small"), t)
        XCTAssertFalse(t.lowercased().contains("error"), t)
        XCTAssertEqual(Kiln.validate(code).errors, [])
    }
}
