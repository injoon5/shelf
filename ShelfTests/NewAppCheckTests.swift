import Foundation
import Kiln
import SwiftUI
import Testing
import UIKit
@testable import Shelf

/// The New App sheet checks a pasted reply before it can be installed (plan
/// §1.8, §7): `Kiln.check`'s first error, or `Kiln.validate`'s, takes the
/// preview's place and blocks Install; warnings are listed and don't.
@MainActor
@Suite(.serialized)
struct NewAppCheckTests {
    static func reply(_ body: String, extra: String = "") -> String {
        """
        Here's your app.

        ```swift
        // Name: Tally
        // Icon: number
        // Tint: blue

        import SwiftUI

        struct ContentView: View {
            @State private var count = 0

            var body: some View {
                \(body)
            }
        }
        \(extra)
        ```
        """
    }

    static func library() -> LibraryStore {
        LibraryStore(demo: [], cache: AppCache(root: temporaryFolder()))
    }

    static func pasted(_ text: String) async -> (CreateModel, LibraryStore) {
        let library = library()
        let model = CreateModel(app: nil, source: nil)
        model.paste(text, library: library)
        await model.checked()
        return (model, library)
    }

    @Test func aCleanReplyCanBeInstalled() async {
        let (model, library) = await Self.pasted(Self.reply(#"Button("Count: \(count)") { count += 1 }"#))
        #expect(model.checkError == nil)
        #expect(model.warnings.isEmpty)
        #expect(!model.isChecking)
        #expect(model.canInstall(in: library))
    }

    @Test func anErrorBlocksInstallAndNamesItsLine() async throws {
        let (model, library) = await Self.pasted(Self.reply(#"Text("\(count)").stepValue(0.1)"#))
        let error = try #require(model.checkError)
        #expect(error.line == 11)
        #expect(error.message == "Kiln doesn't support the .stepValue() modifier")
        #expect(error.excerpt.contains { $0.number == 11 && $0.text.contains(".stepValue(0.1)") })
        #expect(!model.canInstall(in: library))
        // Install does nothing while it's blocked.
        await model.installReply(library: library)
        #expect(!model.isFinished)
    }

    @Test func copyErrorCarriesEveryError() async throws {
        let (model, _) = await Self.pasted(Self.reply(#"Text("a").zzz().yyy()"#))
        let error = try #require(model.checkError)
        #expect(error.report.hasPrefix("Line 11: Kiln doesn't support the .zzz() modifier"))
        #expect(error.report.contains("Also:\n- Line 11: Kiln doesn't support the .yyy() modifier"))
    }

    @Test func warningsAreShownAndDontBlock() async {
        let (model, library) = await Self.pasted(Self.reply(#"Button("Zone") { print(TimeZone.current) }"#))
        #expect(model.checkError == nil)
        #expect(model.warnings == ["Line 11: `TimeZone` is accepted but has no effect yet"])
        #expect(model.canInstall(in: library))
    }

    @Test func anErrorValidateFindsBlocksToo() async throws {
        // Checks clean; fails when its action runs.
        let (model, library) = await Self.pasted(Self.reply(#"Button("Go") { let items = [1]; count = items[3] }"#))
        let error = try #require(model.checkError)
        #expect(error.line == 11)
        #expect(error.message.contains("Index out of range"), "\(error.message)")
        #expect(!model.canInstall(in: library))
    }

    @Test func installWaitsForTheCheck() async {
        let library = Self.library()
        let model = CreateModel(app: nil, source: nil)
        model.paste(Self.reply(#"Text("x")"#), library: library)
        // `check` ran at once; `validate` waits for the next turn of the main actor.
        #expect(model.isChecking)
        #expect(!model.canInstall(in: library))
        await model.checked()
        #expect(model.canInstall(in: library))
    }

    @Test func pastingAgainChecksTheNewReply() async {
        let library = Self.library()
        let model = CreateModel(app: nil, source: nil)
        model.paste(Self.reply(#"Text("x").zzz()"#), library: library)
        #expect(model.checkError != nil)
        model.discardReply()
        model.paste(Self.reply(#"Text("x")"#), library: library)
        await model.checked()
        #expect(model.checkError == nil)
    }

    /// The check runs on the phone: it reaches no network, writes no data or
    /// setting the app could keep, and asks for nothing.
    @Test func theCheckTouchesNothing() async throws {
        let server = StubServer { _ in .json("{}") }
        URLProtocol.registerClass(StubProtocol.self)
        defer { URLProtocol.unregisterClass(StubProtocol.self) }
        let key = "kiln-check-probe-\(UUID().uuidString)"
        let source = Self.reply(#"""
            Text("\(count)")
                .task {
                    do {
                        let (data, _) = try await URLSession.shared.data(from: URL(string: "\#(server.origin.absoluteString)/x")!)
                        count = data.count
                    } catch {
                        count = -1
                    }
                    DB.save("counts", Data("[1]".utf8))
                    UserDefaults.standard.set(1, forKey: "\#(key)")
                }
            """#)
        let (model, library) = await Self.pasted(source)
        #expect(model.checkError == nil, "\(String(describing: model.checkError?.report))")
        #expect(server.requests.isEmpty)
        #expect(UserDefaults.standard.object(forKey: key) == nil)
        #expect(await library.host.data.scratch(copying: model.slug).value(for: "counts") == nil)
    }

    /// Fast enough for the sheet: the slowest fixture checks and validates
    /// in well under a second on the simulator.
    @Test func checkAndValidateAreFastEnough() throws {
        var slowest: (String, Duration) = ("", .zero)
        let clock = ContinuousClock()
        for name in FeatureFixtureTests.apps {
            let source = try Fixture.app(name)
            let start = clock.now
            let check = Kiln.check(source)
            let validation = Kiln.validate(source, context: RunContext.check(AppMeta(slug: name, name: name, tint: .blue, version: "1"),
                                                                             session: DBSession(slug: name)))
            let took = clock.now - start
            #expect(check.passed, "\(name): \(check.errors)")
            #expect(validation.errors.isEmpty, "\(name): \(validation.errors)")
            if took > slowest.1 { slowest = (name, took) }
        }
        print("slowest check + validate: \(slowest.0) in \(slowest.1)")
        #expect(slowest.1 < .seconds(1))
    }

    // MARK: The sheet, as a picture

    /// The preview with an error, light and dark, written to
    /// `$SHELF_SCREENSHOTS` when it's set (the design review keeps them).
    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func theSheetShowsTheFirstError(_ style: UIUserInterfaceStyle) async throws {
        let (model, library) = await Self.pasted(Self.reply(#"Text("\(count)").stepValue(0.1)"#))
        let window = try Self.window(NewAppSheet(model: model).environment(library).environment(ShelfSettings()), style: style)
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(500))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        if let folder = ProcessInfo.processInfo.environment["SHELF_SCREENSHOTS"] {
            try image.pngData()?.write(to: URL(fileURLWithPath: folder).appending(path: "new-app-error-\(style == .dark ? "dark" : "light").png"))
        }
        #expect(image.size.width > 0)
    }

    static func window(_ view: some View, style: UIUserInterfaceStyle) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.overrideUserInterfaceStyle = style
        window.rootViewController = UIHostingController(rootView: view)
        window.isHidden = false
        window.rootViewController?.view.layoutIfNeeded()
        return window
    }
}
