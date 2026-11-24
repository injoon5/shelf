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

    /// The prompt's hand-written sections each have a fixture, and so does
    /// every family "What works" lists (built from Kiln's manifest): a
    /// fixture names it in its `// Covers:` line and uses one of its symbols.
    /// When a round's first bridge puts a family in the prompt, this fails
    /// until a fixture covers it.
    @Test func everyPromptSectionHasAFixture() throws {
        for name in ["swift-language", "swift-protocols", "swift-builders", "swift-codable", "async", "saving-data"] {
            #expect(Self.apps.contains(name), "missing fixtures/apps/\(name).swift")
        }
        let manifest = try #require(PromptCatalog.manifest)
        var covering: [String: [String]] = [:]
        for name in Self.apps {
            let source = try Self.source(name)
            guard let line = source.split(separator: "\n").first(where: { $0.hasPrefix("// Covers: ") }) else { continue }
            for family in line.dropFirst("// Covers: ".count).split(separator: ",") {
                covering[family.trimmingCharacters(in: .whitespaces), default: []].append(source)
            }
        }
        for family in PromptCatalog.listedFamilies(manifest) {
            let sources = covering[family.name] ?? []
            #expect(!sources.isEmpty, "no fixture covers \(family.name): add `// Covers: \(family.name)` to one in fixtures/apps/")
            let names = manifest.symbols.filter { $0.family == family.name && $0.support != "stub" }.map(\.name)
            let uses = sources.contains { source in
                names.contains { n in
                    ["." + n + "(", "." + n + " ", "." + n + "\n", n + "(", n + " {", "@" + n + " ", n + "."].contains { source.contains($0) }
                }
            }
            #expect(uses, "the fixtures covering \(family.name) use none of its symbols")
        }
    }

    @Test(arguments: apps)
    func fixtureRunsValidatesAndRenders(_ name: String) throws {
        let source = try Self.source(name)
        #expect(source.hasPrefix("// Name: "), "\(name) needs the three header lines")
        #expect(ReplyParser.parse(source).name != nil)
        #expect(source.contains("struct ContentView: View"))

        let result = Kiln.run(source, context: Self.check(name))
        defer { result.tearDown() }
        #expect(result.errors.isEmpty, "\(name): \(result.errors)")
        #expect(result.hasView, "\(name) produced no view")

        let validation = Kiln.validate(source, context: Self.check(name))
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
        let (seen, session) = try Self.validateSavingData(stored: [:])
        #expect(seen.contains("GET /books"))
        #expect(seen.contains("GET /notes"))
        // `Clear Notes` calls `DB.remove`.
        #expect(seen.contains("DELETE /notes"))
        let books = try Self.savedBooks(session)
        #expect(books.map { $0["title"] as? String } == ["Untitled"])
        #expect(books.first?["tags"] as? [String] == ["new"])
        // `var id = UUID()` and `var added = Date()` are written as a UUID string and a number.
        #expect((books.first?["id"] as? String).flatMap(UUID.init(uuidString:)) != nil)
        #expect(books.first?["added"] is Double)
    }

    @Test func oldDataGainsNewFieldsFromTheirDefaults() throws {
        // Saved by an earlier version that had only `id`, `title` and `added`.
        let old = #"[{"id":"8F1E2D3C-1111-2222-3333-444455556666","title":"Dune","added":700000000}]"#
        let (_, session) = try Self.validateSavingData(stored: ["books": Data(old.utf8)])
        let book = try #require(try Self.savedBooks(session).first)
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
        let (_, session) = try Self.validateSavingData(stored: ["books": Data(saved.utf8)])
        let book = try #require(try Self.savedBooks(session).first)
        #expect(book["author"] as? String == "Austen")
        #expect(book["rating"] as? Int == 4)
        #expect(book["shelf"] as? String == "finished")
        #expect((book["progress"] as? [String: Int]) == ["page": 3, "total": 9])
    }

    @Test func unreadableDataIsNeverOverwritten() throws {
        let (seen, _) = try Self.validateSavingData(stored: ["books": Data(#"[{"title":42}]"#.utf8)])
        #expect(seen.contains("GET /books"))
        #expect(!seen.contains("PUT /books"), "\(seen)")
    }

    // MARK: What doesn't work

    /// Each snippet is something a model would plausibly write, and the
    /// prompt's "What doesn't work" section warns against it. If one starts
    /// passing, Kiln has improved and the prompt can say so.
    @Test(arguments: [
        ("enum with a payload as Codable", #"Text("x").onAppear { print("decoded", (try? JSONDecoder().decode([Payload].self, from: JSONEncoder().encode([Payload.some(1)])))?.count ?? 0) }"#, "decoded 1"),
    ])
    func doesntWork(_ claim: String, _ body: String, _ printedIfItWorked: String) {
        let (errors, console, _) = Self.probe(Self.claimSource(body))
        #expect(!errors.isEmpty || !console.contains(printedIfItWorked), "\(claim) now works? \(console)")
    }

    /// PLAN.md §1.6: what the prompt used to warn against, now working.
    @Test(arguments: [
        ("protocol extension", #"Text(Person().greeting()).onAppear { print(Person().greeting()) }"#, "Hi Ann"),
        ("method on allCases", #"Text("x").onAppear { print(Size.allCases.map { "\($0)" }.joined(separator: "+")) }"#, "small+large"),
        ("binding animation", #"Toggle("On", isOn: $on.animation()).onAppear { print("animated", on) }"#, "animated false"),
        ("one-sided range in case", #"Text("x").onAppear { print(grade(95), grade(3)) }"#, "A B"),
        ("Data from a UTF-8 view", #"Text("x").onAppear { print("bytes", Data("abc".utf8).count) }"#, "bytes 3"),
        ("tuple labels from the type", #"Text("x").onAppear { print("max", bounds().max) }"#, "max 9"),
        ("custom init(from:)", #"Text("x").onAppear { print("custom", (try? JSONDecoder().decode(Custom.self, from: Data("{\"name\":\"x\"}".utf8)))?.count ?? -1) }"#, "custom 99"),
    ])
    func nowWorks(_ claim: String, _ body: String, _ printed: String) {
        let (errors, console, _) = Self.probe(Self.claimSource(body))
        #expect(errors.isEmpty, "\(claim): \(errors)")
        #expect(console.contains(printed), "\(claim): \(console)")
    }

    /// PLAN.md §2: what the prompt used to warn against, now drawn.
    @Test(arguments: [
        ("gesture", #"Text("x").gesture(DragGesture().onChanged { value in print(value.translation.width) })"#),
        ("Canvas", #"Canvas { context, size in context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.blue)) }"#),
        ("glassEffect", #"Text("x").glassEffect()"#),
        ("matchedGeometryEffect", #"Text("x").matchedGeometryEffect(id: "x", in: space)"#),
    ])
    func nowDraws(_ claim: String, _ body: String) throws {
        let rendered = try Self.render(Self.claimSource(body))
        #expect(rendered.errors.isEmpty && rendered.warnings.isEmpty, "\(claim): \(rendered)")
    }

    /// "What works": a `Path` drawn directly, as a shape (PLAN.md §1.4 made `Path` a value).
    @Test func pathDrawsAsAView() throws {
        let rendered = try Self.render(Self.claimSource(#"Path { p in p.addRect(CGRect(x: 0, y: 0, width: 9, height: 9)) }.stroke(.blue)"#))
        #expect(rendered.errors.isEmpty && rendered.warnings.isEmpty, "\(rendered)")
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

    @Test func payloadEnumsNeedTheirOwnCodable() {
        // An enum with associated values is saved by its own `init(from:)` and `encode(to:)` (as
        // `Custom` is read by its own); without them it can't be.
        let (errors, console, _) = Self.probe(Self.claimSource(#"""
            Text("x").onAppear {
                do { _ = try JSONEncoder().encode([Payload.some(1)]) } catch { print("payload", error.localizedDescription) }
            }
            """#))
        #expect(errors.isEmpty, "\(errors)")
        #expect(console.contains("has associated values"), "\(console)")
    }

    // MARK: Native code calling the app's code (PLAN.md §1.5)

    /// A representable's controller is UIKit's, its coordinator is the app's
    /// class, and a delegate message from UIKit reaches the app's method,
    /// which writes through its `@Binding`.
    @Test func imagePickerDelegateReachesTheAppsCoordinator() async throws {
        let compiled = try KilnEngine.compile(#"""
            import SwiftUI
            import UIKit

            struct ImagePicker: UIViewControllerRepresentable {
                @Binding var picked: String
                func makeUIViewController(context: Context) -> UIImagePickerController {
                    let picker = UIImagePickerController()
                    picker.sourceType = .photoLibrary
                    picker.delegate = context.coordinator
                    return picker
                }
                func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}
                func makeCoordinator() -> Coordinator { Coordinator(self) }

                class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
                    let parent: ImagePicker
                    init(_ parent: ImagePicker) { self.parent = parent }
                    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
                        if let image = info[.originalImage] as? UIImage {
                            parent.picked = "\(Int(image.size.width))x\(Int(image.size.height))"
                            print("picked", parent.picked)
                        }
                    }
                }
            }

            struct ContentView: View {
                @State private var picked = "none"
                var body: some View {
                    VStack {
                        Text(picked)
                        ImagePicker(picked: $picked)
                    }
                }
            }
            """#, context: Self.check())
        defer { compiled.interp.tearDown(); compiled.interp.context.tearDown() }
        let window = try Self.show(compiled)
        defer { window.isHidden = true }
        var picker: UIImagePickerController?
        for _ in 0..<50 where picker == nil {
            try await Task.sleep(for: .milliseconds(20))
            picker = Self.find(UIImagePickerController.self, in: window.rootViewController)
        }
        let p = try #require(picker, "the app's representable didn't show a UIImagePickerController")
        #expect(p.sourceType == .photoLibrary)
        let delegate = try #require(p.delegate)
        // Only what the app implements.
        #expect(delegate.responds(to: #selector(UIImagePickerControllerDelegate.imagePickerController(_:didFinishPickingMediaWithInfo:))))
        #expect(!delegate.responds(to: #selector(UIImagePickerControllerDelegate.imagePickerControllerDidCancel(_:))))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 7)).image { _ in }
        delegate.imagePickerController?(p, didFinishPickingMediaWithInfo: [.originalImage: image])
        #expect(compiled.interp.console.contains("picked 12x7"), "\(compiled.interp.console) \(compiled.interp.errors)")
        #expect(compiled.interp.errors.isEmpty, "\(compiled.interp.errors)")
    }

    /// A representable may only return a controller Kiln allows.
    @Test func representableOutsideTheAllowlistIsAnError() throws {
        let rendered = try Self.render(#"""
            import SwiftUI
            import UIKit
            struct Wrong: UIViewControllerRepresentable {
                func makeUIViewController(context: Context) -> UIViewController { UIImage(systemName: "star") }
                func updateUIViewController(_ vc: UIViewController, context: Context) {}
            }
            struct ContentView: View {
                var body: some View { Wrong() }
            }
            """#)
        #expect(rendered.errors.contains { $0.contains("must return a controller Kiln allows (UIImagePickerController)") }, "\(rendered.errors)")
    }

    static func find<T: UIViewController>(_ type: T.Type, in vc: UIViewController?) -> T? {
        guard let vc else { return nil }
        if let t = vc as? T { return t }
        for child in vc.children { if let t = find(type, in: child) { return t } }
        return find(type, in: vc.presentedViewController)
    }

    // MARK: Helpers

    /// The fixture as Shelf runs it: as written (plan §1.7 left nothing to rewrite).
    static func source(_ name: String) throws -> String {
        try Fixture.app(name)
    }

    /// A check's context for a fixture, as Shelf's `validate` would give it:
    /// Kiln's stub, a `DB` session, and permissions that answer at once.
    static func check(_ name: String = "fixture", session: DBSession = DBSession(slug: "fixture"), trace: DBTrace? = nil) -> KilnContext {
        let context = RunContext.check(AppMeta(slug: name, name: name, tint: .blue, version: "1"), session: session)
        if let trace { context.provide(trace) }
        return context
    }

    /// The saving-data fixture checked over a store holding `stored`: every
    /// `DB` call it made, and the store after.
    static func validateSavingData(stored: [String: Data]) throws -> ([String], DBSession) {
        let source = try self.source("saving-data")
        let session = DBSession(slug: "saving-data", entries: stored.compactMapValues(JSONValue.init(json:)))
        let trace = DBTrace()
        let validation = Kiln.validate(source, context: check("saving-data", session: session, trace: trace))
        #expect(validation.errors.isEmpty, "\(validation.errors)")
        return (trace.calls, session)
    }

    static func savedBooks(_ session: DBSession) throws -> [[String: Any]] {
        let books = try #require(session.value(for: "books"), "books were never saved")
        return try #require(try JSONSerialization.jsonObject(with: books.json) as? [[String: Any]])
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

        func grade(_ score: Int) -> String {
            switch score {
            case 90...: return "A"
            default: return "B"
            }
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
            let compiled = try KilnEngine.compile(source, context: check())
            defer { compiled.interp.context.tearDown() }
            KProbe(interp: compiled.interp, ticks: 1).run(compiled.root)
            return (compiled.interp.errors, compiled.interp.console, compiled.interp.warnings)
        } catch {
            return (["\(error)"], "", [])
        }
    }

    /// Shows the app in a window, as Shelf does, and returns what Kiln's
    /// renderer reported while drawing it.
    static func render(_ source: String) throws -> (errors: [String], warnings: [String]) {
        let compiled = try KilnEngine.compile(source, context: check())
        // What the app started (`.task`) stops with the window, as when Shelf closes it.
        defer { compiled.interp.tearDown(); compiled.interp.context.tearDown() }
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
