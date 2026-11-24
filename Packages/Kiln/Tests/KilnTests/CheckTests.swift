//
//  CheckTests.swift
//  KilnTests
//
//  `Kiln.check` (PLAN.md §1.8): one test per error class, the warning for a
//  stub, what an issue carries (line, column, suggestion), and apps written
//  the way models write them, which must check clean when they run.
//

import XCTest
@testable import Kiln

@MainActor
final class CheckTests: XCTestCase {

    /// A view whose body is `body`, with `extra` declarations after it.
    func app(_ body: String, state: String = "", extra: String = "") -> String {
        """
        import SwiftUI

        struct ContentView: View {
            @State private var on = false
            @State private var count = 0
            @State private var name = ""
            \(state)

            var body: some View {
                \(body)
            }
        }
        \(extra)
        """
    }

    func errors(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> [KilnIssue] {
        Kiln.check(source).errors
    }

    func only(_ kind: KilnIssue.Kind, in source: String, file: StaticString = #filePath, line: UInt = #line) -> KilnIssue? {
        let check = Kiln.check(source)
        XCTAssertEqual(check.errors.count, 1, "\(check.issues)", file: file, line: line)
        let issue = check.errors.first
        XCTAssertEqual(issue?.kind, kind, "\(check.issues)", file: file, line: line)
        return issue
    }

    // MARK: Clean

    func testAPlainAppIsClean() {
        let check = Kiln.check(app(#"""
            NavigationStack {
                List {
                    Toggle("On", isOn: $on)
                    Stepper("Count: \(count)", value: $count)
                    TextField("Name", text: $name)
                }
                .navigationTitle("Settings")
            }
            """#))
        XCTAssertTrue(check.passed, "\(check.issues)")
        XCTAssertTrue(check.issues.isEmpty, "\(check.issues)")
    }

    // MARK: Syntax and the root

    func testSyntaxErrorHasItsLine() {
        let issue = only(.syntax, in: "import SwiftUI\nstruct ContentView: View {\n    var body: some View { Text(\"x\" }\n}\n")
        XCTAssertEqual(issue?.line, 3)
    }

    func testNoViewIsAnError() {
        let issue = only(.noView, in: "struct Habit { var name = \"\" }\n")
        XCTAssertEqual(issue?.suggestion?.contains("ContentView"), true)
    }

    // MARK: Unknown names

    func testUnknownModifierHasLineColumnAndSuggestion() throws {
        let source = app(#"Text("Hi").paddng(8)"#)
        let issue = try XCTUnwrap(only(.unknownModifier, in: source))
        XCTAssertEqual(issue.line, 10)
        XCTAssertEqual(issue.column, source.components(separatedBy: "\n")[9].distance(of: "paddng").map { $0 + 1 })
        XCTAssertEqual(issue.message, "Kiln doesn't support the .paddng() modifier")
        XCTAssertEqual(issue.suggestion, "Did you mean `.padding`?")
        XCTAssertEqual(issue.description, "Line 10: Kiln doesn't support the .paddng() modifier. Did you mean `.padding`?")
    }

    func testAModifierAfterAModifierIsChecked() {
        let issue = only(.unknownModifier, in: app(#"Text("Hi").padding().stepValue(0.1)"#))
        XCTAssertEqual(issue?.message.contains(".stepValue"), true)
    }

    func testUnknownTypeIsAnError() {
        let issue = only(.unknownName, in: app(#"Button("Play") { let scene = SKScene(size: .zero); print(scene) }"#))
        XCTAssertEqual(issue?.message, "Kiln doesn't have 'SKScene'")
    }

    func testUnknownTypesStaticMemberIsAnError() {
        let issue = only(.unknownName, in: app(#"Button("Name") { print(UIDevice.current.name) }"#))
        XCTAssertEqual(issue?.message, "Kiln doesn't have 'UIDevice'")
    }

    func testUnknownViewIsAnError() {
        let issue = only(.unknownName, in: app(#"Map()"#))
        XCTAssertEqual(issue?.message, "Kiln doesn't have 'Map'")
    }

    func testUndeclaredNameIsAnError() {
        let issue = only(.unknownName, in: app(#"Toggle("On", isOn: $on).onTapGesture { cuont += 1 }"#))
        XCTAssertEqual(issue?.message, "Cannot find 'cuont' in scope")
        XCTAssertEqual(issue?.suggestion, "Did you mean `count`?")
    }

    func testMemberOfTheAppsTypeIsChecked() {
        let source = app(#"Text(Habit().nmae)"#, extra: "struct Habit { var name = \"Run\" }")
        let issue = only(.unknownMember, in: source)
        XCTAssertEqual(issue?.message, "Value of type 'Habit' has no member 'nmae'")
        XCTAssertEqual(issue?.suggestion, "Did you mean `name`?")
    }

    func testEnumCaseIsChecked() {
        let issue = only(.unknownMember, in: app(#"Text(Mood.happpy.rawValue)"#, extra: "enum Mood: String { case happy, sad }"))
        XCTAssertEqual(issue?.message, "Type 'Mood' has no member 'happpy'")
    }

    func testMemberOfANativeValueIsChecked() {
        let issue = only(.unknownMember, in: app(#"Text(name.uppercasedd())"#))
        XCTAssertEqual(issue?.message, "Value of type 'String' has no method 'uppercasedd'")
    }

    func testStaticMemberOfANativeTypeIsChecked() {
        let issue = only(.unknownMember, in: app(#"Text(Date.nwo.formatted())"#))
        XCTAssertEqual(issue?.message, "Kiln's Date has no member 'nwo'")
        XCTAssertEqual(issue?.suggestion, "Did you mean `now`?")
    }

    // MARK: Arguments

    func testWrongLabelsListTheOverloads() throws {
        let issue = try XCTUnwrap(only(.arguments, in: app(#"Text("x").blur(10)"#)))
        XCTAssertEqual(issue.message, "Kiln has no .blur(_:)")
        XCTAssertEqual(issue.suggestion?.hasPrefix("It has .blur(radius:"), true, issue.suggestion ?? "")
    }

    func testViewLabelsAreChecked() {
        let issue = only(.arguments, in: app(#"Toggle("On", value: $on)"#))
        XCTAssertEqual(issue?.message, "Kiln has no Toggle(_:value:)")
    }

    func testAValueWhereABindingGoes() {
        let issue = only(.argumentType, in: app(#"Toggle("On", isOn: on)"#))
        XCTAssertEqual(issue?.message, "Toggle(_:isOn:): 'isOn' needs a binding such as $on, not the value")
    }

    // MARK: Waiting

    func testAwaitInBodyIsAnError() {
        let issue = only(.awaitNotAllowed, in: app(#"Text(await load())"#, extra: "func load() async -> String { \"x\" }"))
        XCTAssertEqual(issue?.message, "'await' can't be used in a view's `body`")
    }

    func testAwaitInAComputedPropertyIsAnError() {
        let issue = only(.awaitNotAllowed, in: app(#"Text(title)"#, state: "var title: String { await load() }",
                                                  extra: "func load() async -> String { \"x\" }"))
        XCTAssertEqual(issue?.message, "'await' can't be used in a computed property")
    }

    func testAwaitInAnInitIsAnError() {
        let issue = only(.awaitNotAllowed, in: app(#"Text("x")"#, extra: """
            struct Loader {
                var text = ""
                init() { text = await load() }
            }
            func load() async -> String { "x" }
            """))
        XCTAssertEqual(issue?.message, "'await' can't be used in an `init`")
    }

    func testAwaitInAFunctionThatIsntAsyncIsAnError() {
        let issue = only(.awaitNotAllowed, in: app(#"Text("x").task { await refresh() }"#, extra: """
            func refresh() async { fetch() }
            func fetch() { try? await Task.sleep(for: .seconds(1)) }
            """))
        XCTAssertEqual(issue?.message, "'await' can't be used in `fetch()`, which isn't `async`")
    }

    func testAwaitInAnActionClosureIsAnError() {
        let issue = only(.awaitNotAllowed, in: app(#"Button("Go") { await load() }"#, extra: "func load() async {}"))
        XCTAssertEqual(issue?.message, "This closure uses 'await', which it can't do here")
        XCTAssertEqual(issue?.suggestion, "Wrap the code in Task { … }")
    }

    func testAwaitWhereItCanWaitIsFine() {
        let check = Kiln.check(app(#"""
            Button("Go") { Task { await load() } }
                .task { await load() }
                .task(id: count) { try? await Task.sleep(for: .seconds(1)) }
                .refreshable { await load() }
            """#, extra: """
            func load() async {
                async let a = other()
                _ = await a
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await other() }
                }
            }
            func other() async {}
            """))
        XCTAssertTrue(check.passed, "\(check.issues)")
    }

    func testAsyncCallWithoutAwaitIsAnError() {
        let issue = only(.missingAwait, in: app(#"Text("x").task { load() }"#, extra: "func load() async {}"))
        XCTAssertEqual(issue?.message, "'load()' is async: call it with 'await'")
    }

    func testBridgedAsyncCallWithoutAwaitIsAnError() {
        let issue = only(.missingAwait, in: app(#"Text("x").task { try? Task.sleep(for: .seconds(1)) }"#))
        XCTAssertEqual(issue?.message, "'Task.sleep' is async: call it with 'await'")
    }

    func testAsyncMethodWithoutAwaitIsAnError() {
        let issue = only(.missingAwait, in: app(#"Text("x").task { model.load() }"#, state: "@State private var model = Model()", extra: """
            @Observable class Model {
                var items: [String] = []
                func load() async { items = ["a"] }
            }
            """))
        XCTAssertEqual(issue?.message, "'load()' is async: call it with 'await'")
    }

    // MARK: Protocols

    func testViewWithoutBodyIsAnError() {
        let issue = only(.missingRequirement, in: app(#"Row()"#, extra: "struct Row: View { var title = \"x\" }"))
        XCTAssertEqual(issue?.message, "'Row' adopts View but has no `body`")
        XCTAssertEqual(issue?.suggestion, "Add `var body: some View { … }`")
    }

    func testIdentifiableWithoutIdIsAnError() {
        let issue = only(.missingRequirement, in: app(#"List(items) { Text($0.name) }"#, state: "@State private var items: [Item] = []",
                                                     extra: "struct Item: Identifiable { var name = \"\" }"))
        XCTAssertEqual(issue?.message, "'Item' adopts Identifiable but has no `id`")
    }

    func testShapeWithoutPathIsAnError() {
        let issue = only(.missingRequirement, in: app(#"Triangle().fill(.red)"#, extra: "struct Triangle: Shape { }"))
        XCTAssertEqual(issue?.message, "'Triangle' adopts Shape but has no `path(in:)`")
    }

    func testRequirementsFromExtensionsAndSynthesisCount() {
        let check = Kiln.check(app(#"Text("x")"#, extra: """
            final class Store: Identifiable, ObservableObject {}
            enum Kind: CaseIterable, Comparable { case a, b }
            struct Late: View {}
            extension Late { var body: some View { Text("late") } }
            struct Failure: LocalizedError {}
            """))
        XCTAssertTrue(check.passed, "\(check.issues)")
    }

    // MARK: Stubs

    func testStubIsAWarningNotAnError() throws {
        let check = Kiln.check(app(#"Button("Zone") { print(TimeZone.current) }"#))
        XCTAssertTrue(check.passed, "\(check.issues)")
        let warning = try XCTUnwrap(check.warnings.first)
        XCTAssertEqual(warning.kind, .stub)
        XCTAssertEqual(warning.message, "`TimeZone` is accepted but has no effect yet")
    }

    func testStubViewAndTypeAreWarnings() {
        let check = Kiln.check(app(#"""
            VStack {
                Button("Open") { UIApplication.shared.open(URL(string: "https://apple.com")!) }
            }
            """#))
        XCTAssertTrue(check.passed, "\(check.issues)")
        XCTAssertEqual(Set(check.warnings.map(\.kind)), [.stub])
        XCTAssertEqual(check.warnings.map(\.message), ["`UIApplication` is accepted but has no effect yet"])
    }

    // MARK: Results

    func testErrorsComeFirstInLineOrder() {
        let check = Kiln.check(app(#"""
            VStack {
                Button("a") { print(TimeZone.current) }
                Text("b").zzz()
                Text("c").yyy()
            }
            """#))
        XCTAssertEqual(check.issues.map(\.kind), [.unknownModifier, .unknownModifier, .stub])
        XCTAssertLessThan(check.issues[0].line, check.issues[1].line)
        XCTAssertEqual(check.firstError?.message.contains(".zzz"), true)
    }

    /// Static and fast: a long app checks in a few milliseconds.
    func testCheckIsFast() throws {
        let url = CheckCorpusTests.kilnRoot.appendingPathComponent("Examples/LibraryApp.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        _ = Kiln.check(source)
        let start = Date()
        for _ in 0..<10 { _ = Kiln.check(source) }
        let each = Date().timeIntervalSince(start) / 10
        XCTAssertLessThan(each, 0.1, "check took \(each)s")
    }

    // MARK: The manifest's language gaps

    /// The probes behind "What doesn't work" tell a feature that works from one that doesn't.
    func testGapProbesTellWorkingFromFailing() {
        XCTAssertTrue(KLanguageGaps.works(KLanguageGap(id: "works", what: "", check: #"print("ok")"#)))
        XCTAssertFalse(KLanguageGaps.works(KLanguageGap(id: "fails", what: "", check: #"print("no")"#)))
        XCTAssertFalse(KLanguageGaps.works(KLanguageGap(id: "throws", what: "", check: #"let a = [1]; print(a[3] == 1 ? "ok" : "no")"#)))
        XCTAssertFalse(KLanguageGaps.works(KLanguageGap(id: "syntax", what: "", check: #"print("ok"#)))
        XCTAssertEqual(Set(KLanguageGaps.all.map(\.id)).count, KLanguageGaps.all.count)
    }

    // MARK: Apps as models write them

    /// Idioms models reach for, each app run and checked: one that runs must check clean.
    func testModelWrittenAppsCheckClean() {
        for (name, source) in CheckSamples.apps {
            let validation = Kiln.validate(source)
            let check = Kiln.check(source)
            if validation.errors.isEmpty {
                XCTAssertTrue(check.passed, "\(name) runs but check says: \(check.errors)")
            } else {
                print("sample \(name) doesn't run: \(validation.errors)")
            }
        }
    }
}

private extension StringProtocol {
    func distance(of needle: String) -> Int? {
        guard let r = range(of: needle) else { return nil }
        return self.distance(from: startIndex, to: r.lowerBound)
    }
}
