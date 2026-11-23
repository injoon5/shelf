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
}
