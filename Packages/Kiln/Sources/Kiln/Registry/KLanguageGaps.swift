//
//  KLanguageGaps.swift
//  Kiln's bridge registry
//
//  Swift that models write and Kiln doesn't run yet (PLAN.md §1.6), each
//  with a probe: a small app that prints "ok" only when the feature works.
//  The manifest lists the gaps whose probe fails (`kiln-manifest.json`'s
//  `gaps`, written by `Tools/manifest.sh`), and Shelf's prompt builds its
//  "What doesn't work" from that list. So the prompt never warns about
//  something Kiln has fixed: when §1.6 (or anyone) makes a probe pass, the
//  next manifest drops the gap, and `testManifestIsCurrent` fails until
//  it's regenerated.
//
//  To add one: a gap models hit, its sentence for authors (what fails, and
//  what to write instead), and a probe whose `check` prints "ok" when it works.
//

import Foundation

struct KLanguageGap {
    let id: String
    /// For app authors, in the prompt: what fails and what to write instead. Markdown.
    let what: String
    /// Declarations the probe needs, outside `ContentView`.
    var decls = ""
    /// The probe's body (a view expression).
    var body = #"Text("probe")"#
    /// Statements run on appear: they print "ok" when the feature works.
    let check: String

    var source: String {
        """
        import SwiftUI

        \(decls)

        struct ContentView: View {
            @State private var on = false
            var body: some View {
                \(body)
                    .onAppear {
                        \(check)
                    }
            }
        }
        """
    }
}

@MainActor
enum KLanguageGaps {
    static let all: [KLanguageGap] = [
        KLanguageGap(id: "one-sided-case-range",
                     what: "A one-sided range in a `case` (`case 90...:`) stops the whole file from running. Write `case 90...100:`.",
                     decls: """
                     func grade(_ score: Int) -> String {
                         switch score {
                         case 90...: return "A"
                         default: return "B"
                         }
                     }
                     """,
                     check: #"print(grade(95) == "A" ? "ok" : "no")"#),
        KLanguageGap(id: "allcases-method",
                     what: "Calling a method straight on `allCases` (`Kind.allCases.map { … }`) fails. Store it first: `let kinds = Kind.allCases`. `ForEach(Kind.allCases)` works.",
                     decls: "enum Size: CaseIterable { case small, large }",
                     check: #"print(Size.allCases.map { "\($0)" }.joined() == "smalllarge" ? "ok" : "no")"#),
        KLanguageGap(id: "binding-animation",
                     what: "`$value.animation()` on a binding. Use `.animation(_:value:)` on the view.",
                     body: #"Toggle("On", isOn: $on.animation())"#,
                     check: #"print("ok")"#),
        KLanguageGap(id: "protocol-extensions",
                     what: "Methods from a protocol extension (default implementations) don't exist. Put the method on each type, or in a function that takes the value.",
                     decls: """
                     protocol Greeter { var name: String { get } }
                     extension Greeter { func greeting() -> String { "Hi " + name } }
                     struct Person: Greeter { var name = "Ann" }
                     """,
                     check: #"print(Person().greeting() == "Hi Ann" ? "ok" : "no")"#),
        KLanguageGap(id: "property-wrappers",
                     what: "Custom property wrappers (`@propertyWrapper`) are ignored: the property is a plain stored value. Use `didSet` or a computed property.",
                     decls: """
                     @propertyWrapper struct Clamped {
                         private var value: Int
                         var wrappedValue: Int {
                             get { value }
                             set { value = min(max(newValue, 0), 10) }
                         }
                         init(wrappedValue: Int) { value = min(max(wrappedValue, 0), 10) }
                     }
                     struct Level { @Clamped var value: Int = 5 }
                     """,
                     check: """
                     var level = Level()
                     level.value = 50
                     print(level.value == 10 ? "ok" : "no")
                     """),
        KLanguageGap(id: "result-builders",
                     what: "Result builders (`@resultBuilder`) of your own. SwiftUI's `@ViewBuilder` works.",
                     decls: """
                     @resultBuilder struct Joined {
                         static func buildBlock(_ parts: String...) -> String { parts.joined(separator: ",") }
                     }
                     @Joined func letters() -> String {
                         "a"
                         "b"
                     }
                     """,
                     check: #"print(letters() == "a,b" ? "ok" : "no")"#),
        KLanguageGap(id: "custom-codable",
                     what: "Kiln reads and writes JSON by a type's stored properties and its `CodingKeys`, and ignores `init(from:)` and `encode(to:)`.",
                     decls: """
                     struct Custom: Codable {
                         var name: String
                         var count: Int
                         enum CodingKeys: String, CodingKey { case name, count }
                         init(from decoder: Decoder) throws {
                             let c = try decoder.container(keyedBy: CodingKeys.self)
                             name = try c.decode(String.self, forKey: .name)
                             count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 99
                         }
                     }
                     """,
                     check: """
                     let custom = try? JSONDecoder().decode(Custom.self, from: "{\\"name\\":\\"x\\"}".data(using: .utf8)!)
                     print(custom?.count == 99 ? "ok" : "no")
                     """),
        KLanguageGap(id: "payload-enum-codable",
                     what: "An enum with associated values isn't `Codable` by itself: give a saved enum raw values (`enum Priority: String, Codable`), or write its `init(from:)` and `encode(to:)`.",
                     decls: "enum Payload: Codable { case some(Int) }",
                     check: """
                     do {
                         let data = try JSONEncoder().encode([Payload.some(1)])
                         let back = try JSONDecoder().decode([Payload].self, from: data)
                         print(back.count == 1 ? "ok" : "no")
                     } catch { print("no") }
                     """),
        KLanguageGap(id: "set-round-trip",
                     what: "A `Set` encoded as JSON decodes as an array: save arrays and dictionaries, not `Set`s.",
                     check: """
                     do {
                         let data = try JSONEncoder().encode(Set([1, 2]))
                         var back = try JSONDecoder().decode(Set<Int>.self, from: data)
                         back.insert(1)
                         print(back.count == 2 ? "ok" : "no")
                     } catch { print("no") }
                     """),
        KLanguageGap(id: "data-utf8",
                     what: "`Data(text.utf8)` comes out empty: use `text.data(using: .utf8)`.",
                     check: #"print(Data("abc".utf8).count == 3 ? "ok" : "no")"#),
        KLanguageGap(id: "tuple-labels",
                     what: "A tuple doesn't take its labels from the declared type: write them in the literal (`return (min: a, max: b)`).",
                     decls: "func bounds() -> (min: Int, max: Int) { return (1, 9) }",
                     check: #"print(bounds().max == 9 ? "ok" : "no")"#),
        KLanguageGap(id: "regex-literals",
                     what: "Regex literals (`/\\d+/`) don't parse. Check text with `String` methods instead.",
                     check: #"print("a1".contains(/\d/) ? "ok" : "no")"#),
    ]

    /// Whether the probe runs and prints "ok".
    static func works(_ gap: KLanguageGap) -> Bool {
        let context = KilnContext.stub()
        context.begin()
        defer { context.tearDown() }
        guard let compiled = try? KilnEngine.compile(gap.source, headless: true, context: context) else { return false }
        defer { compiled.interp.tearDown() }
        KProbe(interp: compiled.interp, ticks: 1).run(compiled.root)
        return compiled.interp.errors.isEmpty && compiled.interp.console.contains("ok")
    }

    /// The gaps Kiln has today, for the manifest.
    static func current() -> [KManifest.Gap] {
        all.filter { !works($0) }.map { KManifest.Gap(id: $0.id, what: $0.what) }
    }
}
