import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Kiln
@testable import Shelf

/// The feature fixtures (plan §9.4): every claim under "What works" and
/// "Saving data" in `Resources/Prompts/new.md` has an app in `fixtures/apps/`
/// that must run, validate and render in this Kiln without a single error or
/// warning. The cheap "What doesn't work" claims are pinned too, so a Kiln
/// update that changes them shows up here and the prompt can follow.
@MainActor
@Suite(.serialized)
struct FeatureFixtureTests {
    nonisolated static let apps: [String] = {
        let dir = Fixture.root.appending(path: "apps")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasSuffix(".swift") }.map { String($0.dropLast(6)) }.sorted()
    }()

    @Test func everyPromptSectionHasAFixture() {
        for name in ["swift-language", "state", "views-navigation", "views-lists-controls", "views-layout-drawing",
                     "time", "async", "network", "images", "saving-data"] {
            #expect(Self.apps.contains(name), "missing fixtures/apps/\(name).swift")
        }
    }

    @Test(arguments: apps)
    func fixtureRunsValidatesAndRenders(_ name: String) throws {
        let source = try Self.source(name)
        #expect(source.hasPrefix("// Name: "), "\(name) needs the three header lines")
        #expect(ReplyParser.parse(source).name != nil)
        #expect(source.contains("struct ContentView: View"))

        FakeServer.start()
        defer { FakeServer.stop() }

        let result = Kiln.run(source)
        #expect(result.errors.isEmpty, "\(name): \(result.errors)")
        #expect(result.hasView, "\(name) produced no view")

        let validation = Kiln.validate(source)
        #expect(validation.errors.isEmpty, "\(name): \(validation.errors)")
        #expect(validation.warnings.isEmpty, "\(name): \(validation.warnings)")
        #expect(validation.renderedContent, "\(name) rendered nothing")

        // `validate` never mounts the view, so Kiln's renderer (unknown views and
        // modifiers, a Shape's `path(in:)`) only speaks up when the view is shown.
        let rendered = try Self.render(source)
        #expect(rendered.errors.isEmpty, "\(name): \(rendered.errors)")
        #expect(rendered.warnings.isEmpty, "\(name): \(rendered.warnings)")
    }

    // MARK: Saving data, end to end

    @Test func savingDataStartsEmptyAndSaves() throws {
        let seen = try Self.validateSavingData(stored: [:])
        #expect(seen.contains("GET /books"))
        #expect(seen.contains("GET /notes"))
        // `Clear Notes` calls `DB.remove`.
        #expect(seen.contains("DELETE /notes"))
        let books = try Self.savedBooks()
        #expect(books.map { $0["title"] as? String } == ["Untitled"])
        #expect(books.first?["tags"] as? [String] == ["new"])
        // `var id = UUID()` and `var added = Date()` are written as a UUID string and a number.
        #expect((books.first?["id"] as? String).flatMap(UUID.init(uuidString:)) != nil)
        #expect(books.first?["added"] is Double)
    }

    @Test func oldDataGainsNewFieldsFromTheirDefaults() throws {
        // Saved by an earlier version that had only `id`, `title` and `added`.
        let old = #"[{"id":"8F1E2D3C-1111-2222-3333-444455556666","title":"Dune","added":700000000}]"#
        _ = try Self.validateSavingData(stored: ["books": Data(old.utf8)])
        let book = try #require(try Self.savedBooks().first)
        #expect(book["id"] as? String == "8F1E2D3C-1111-2222-3333-444455556666")
        #expect(book["title"] as? String == "Dune")
        #expect(book["added"] as? Double == 700000000)
        #expect(book["shelf"] as? String == "reading")
        #expect(book["tags"] as? [String] == [])
        #expect((book["progress"] as? [String: Int]) == ["page": 0, "total": 0])
        // Nil optionals are left out, and read back as nil.
        #expect(book["author"] == nil)
        #expect(book["rating"] == nil)
    }

    @Test func optionalsAndEnumsRoundTrip() throws {
        let saved = #"[{"id":"8F1E2D3C-1111-2222-3333-444455556666","title":"Emma","author":"Austen","rating":4,"shelf":"finished","added":1,"progress":{"page":3,"total":9},"tags":["x"]}]"#
        _ = try Self.validateSavingData(stored: ["books": Data(saved.utf8)])
        let book = try #require(try Self.savedBooks().first)
        #expect(book["author"] as? String == "Austen")
        #expect(book["rating"] as? Int == 4)
        #expect(book["shelf"] as? String == "finished")
        #expect((book["progress"] as? [String: Int]) == ["page": 3, "total": 9])
    }

    @Test func unreadableDataIsNeverOverwritten() throws {
        let seen = try Self.validateSavingData(stored: ["books": Data(#"[{"title":42}]"#.utf8)])
        #expect(seen.contains("GET /books"))
        #expect(!seen.contains("PUT /books"), "\(seen)")
    }

    // MARK: What doesn't work

    /// Each snippet is something a model would plausibly write, and the
    /// prompt's "What doesn't work" section warns against it. If one starts
    /// passing, Kiln has improved and the prompt can say so.
    @Test(arguments: [
        ("gesture", #"Text("x").gesture(DragGesture().onChanged { _ in })"#, "DragGesture"),
        ("protocol extension", #"Text(Person().greeting())"#, "greeting"),
        ("tuple labels from the type", #"Text("\(bounds().max)")"#, "max"),
        ("method on allCases", #"Text(Size.allCases.map { "\($0)" }.joined())"#, "allCases"),
        ("binding animation", #"Toggle("On", isOn: $on.animation())"#, "animation"),
    ])
    func doesntWork(_ claim: String, _ body: String, _ mentioned: String) {
        let source = Self.claimSource(body)
        let errors = Kiln.validate(source).errors
        #expect(errors.contains { $0.contains(mentioned) }, "\(claim) now works? errors: \(errors)")
    }

    @Test func oneSidedRangeInCaseIsASyntaxError() {
        let source = Self.claimSource(#"Text("x")"#) + """

            func grade(_ score: Int) -> String {
                switch score {
                case 90...: return "A"
                default: return "B"
                }
            }
            """
        let errors = Kiln.run(source).errors
        #expect(errors.contains { $0.contains("case 90...:") }, "one-sided ranges in case patterns now work? \(errors)")
        // The closed range a model should write instead.
        #expect(Kiln.run(source.replacingOccurrences(of: "case 90...:", with: "case 90...100:")).errors.isEmpty)
    }

    @Test(arguments: [
        ("Canvas", #"Canvas { context, size in }"#, "Canvas isn't supported"),
        ("Path as a view", #"Path { p in p.addRect(CGRect(x: 0, y: 0, width: 9, height: 9)) }"#, "Path isn't supported"),
        ("glassEffect", #"Text("x").glassEffect()"#, ".glassEffect()"),
        ("matchedGeometryEffect", #"Text("x").matchedGeometryEffect(id: "x", in: space)"#, ".matchedGeometryEffect()"),
    ])
    func doesntDraw(_ claim: String, _ body: String, _ warning: String) throws {
        let rendered = try Self.render(Self.claimSource(body))
        let all = rendered.warnings + rendered.errors
        #expect(all.contains { $0.contains(warning) }, "\(claim) now works? \(all)")
    }

    // MARK: Waiting (PLAN.md §1.3, §1.11's "real async works")

    /// The async fixture, shown as Shelf shows it: it sleeps, fetches with
    /// `try await` from a stub server, and counts down with `for await` over an
    /// `AsyncStream`, all really waiting, without holding the main thread.
    @Test func asyncFixtureSleepsFetchesAndStreams() async throws {
        let server = StubServer { request in
            request.path == "/today"
                ? .json(#"{"text":"Stay hungry, stay foolish.","author":"Stewart Brand"}"#).delayed(.milliseconds(100))
                : StubResponse(status: 404)
        }
        URLProtocol.registerClass(StubProtocol.self)
        defer { URLProtocol.unregisterClass(StubProtocol.self) }
        let source = try Self.source("async")
            .replacingOccurrences(of: "https://quotes.example.com", with: server.origin.absoluteString)
        let compiled = try KilnEngine.compile(source)
        defer { compiled.interp.tearDown() }

        let clock = ContinuousClock()
        let start = clock.now
        let window = try Self.show(compiled)
        defer { window.isHidden = true }
        var mainRuns = 0
        let deadline = start + .seconds(5)
        while clock.now < deadline {
            let console = compiled.interp.console
            if console.contains("counted [3, 2, 1]"), console.contains("loaded Stewart Brand"), compiled.interp.activeTaskCount == 0 { break }
            mainRuns += 1
            try await Task.sleep(for: .milliseconds(20))
        }
        let console = compiled.interp.console
        // The countdown runs while the quote loads, so their lines interleave.
        #expect(console.contains("slept\n"), "\(console) \(compiled.interp.errors)")
        #expect(console.contains("loaded Stewart Brand"), "\(console) \(compiled.interp.errors)")
        #expect(console.range(of: "slept")!.lowerBound < console.range(of: "loaded")!.lowerBound)
        #expect(console.contains("counted [3, 2, 1]"), "\(console)")
        #expect(compiled.interp.errors.isEmpty, "\(compiled.interp.errors)")
        #expect(compiled.interp.warnings.isEmpty, "\(compiled.interp.warnings)")
        #expect(server.requests("GET", "/today").count == 1)
        // The 300 ms sleep and the 100 ms response were really waited for…
        #expect(clock.now - start >= .milliseconds(400))
        // …while the main thread kept running other work.
        #expect(mainRuns >= 10)
    }

    @Test func asyncTasksStopWithTheRun() async throws {
        let compiled = try KilnEngine.compile(Self.claimSource(#"""
            Text("x").task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(10))
                    print("tick")
                }
            }
            """#))
        let window = try Self.show(compiled)
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(150))
        #expect(compiled.interp.activeTaskCount == 1)
        compiled.interp.tearDown()
        #expect(compiled.interp.activeTaskCount == 0)
        let printed = compiled.interp.console
        #expect(printed.contains("tick"))
        try await Task.sleep(for: .milliseconds(100))
        #expect(compiled.interp.console == printed)
    }

    @Test func dataFromUTF8ViewIsEmpty() {
        // `Data(text.utf8)` comes out empty in Kiln; `text.data(using: .utf8)` works.
        let (errors, console, _) = Self.probe(Self.claimSource(#"""
            Text("x").onAppear {
                print("view", Data("abc".utf8).count)
                print("using", "abc".data(using: .utf8)!.count)
            }
            """#))
        #expect(errors.isEmpty, "\(errors)")
        #expect(console.contains("view 0"), "\(console)")
        #expect(console.contains("using 3"), "\(console)")
    }

    @Test func customCodableAndPayloadEnumsAreNotSupported() {
        let (errors, console, _) = Self.probe(Self.claimSource(#"""
            Text("x").onAppear {
                let custom = try? JSONDecoder().decode(Custom.self, from: "{\"name\":\"x\"}".data(using: .utf8)!)
                print("custom", custom?.count ?? -1)
                do { _ = try JSONEncoder().encode([Payload.some(1)]) } catch { print("payload", error.localizedDescription) }
            }
            """#))
        #expect(errors.isEmpty, "\(errors)")
        // Kiln ignores `init(from:)`, so the missing `count` fails the decode instead of becoming 99.
        #expect(console.contains("custom -1"), "\(console)")
        #expect(console.contains("has associated values"), "\(console)")
    }

    // MARK: Helpers

    /// The fixture as Shelf runs it.
    static func source(_ name: String) throws -> String {
        SourceRewriter.prepare(try Fixture.app(name), slug: name)
    }

    static func validateSavingData(stored: [String: Data]) throws -> [String] {
        let source = try self.source("saving-data")
        FakeServer.start(stored: stored)
        defer { FakeServer.stop() }
        let validation = Kiln.validate(source)
        #expect(validation.errors.isEmpty, "\(validation.errors)")
        return FakeServer.seen.map { "\($0.method) \($0.path)" }
    }

    static func savedBooks() throws -> [[String: Any]] {
        let put = try #require(FakeServer.seen.last { $0.method == "PUT" && $0.path == "/books" }, "books were never saved")
        return try #require(try JSONSerialization.jsonObject(with: put.body) as? [[String: Any]])
    }

    static func claimSource(_ body: String) -> String {
        """
        import SwiftUI

        protocol Greeter { var name: String { get } }
        extension Greeter { func greeting() -> String { "Hi " + name } }
        struct Person: Greeter { var name = "Ann" }

        enum Size: CaseIterable { case small, large }
        enum Payload: Codable { case some(Int) }

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

        func bounds() -> (min: Int, max: Int) {
            return (1, 9)
        }

        struct ContentView: View {
            @State private var on = false
            @Namespace private var space

            var body: some View {
                \(body)
            }
        }
        """
    }

    /// What `Kiln.validate` does, keeping what the code printed.
    static func probe(_ source: String) -> (errors: [String], console: String, warnings: [String]) {
        do {
            let compiled = try KilnEngine.compile(source)
            KProbe(interp: compiled.interp, ticks: 1).run(compiled.root)
            return (compiled.interp.errors, compiled.interp.console, compiled.interp.warnings)
        } catch {
            return (["\(error)"], "", [])
        }
    }

    /// Shows the app in a window, as Shelf does, and returns what Kiln's
    /// renderer reported while drawing it.
    static func render(_ source: String) throws -> (errors: [String], warnings: [String]) {
        let compiled = try KilnEngine.compile(source)
        // What the app started (`.task`) stops with the window, as when Shelf closes it.
        defer { compiled.interp.tearDown() }
        let window = try show(compiled)
        for _ in 0..<5 {
            window.rootViewController?.view.setNeedsLayout()
            window.rootViewController?.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        window.isHidden = true
        return (compiled.interp.errors, compiled.interp.warnings)
    }

    /// The app in a window of its own, laid out once.
    static func show(_ compiled: KilnEngine.Compiled) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let host = UIHostingController(rootView: KRootView(compiled: compiled))
        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        return window
    }
}
