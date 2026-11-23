//
//  KilnValidateTests.swift
//  KilnTests
//
//  Tests for the `Kiln.validate` probe — the deep native-app validation that
//  eagerly renders + exercises generated apps instead of trusting the vacuous
//  "parsed and produced a view wrapper" check.
//

import XCTest
@testable import Kiln

@MainActor
final class KilnValidateTests: XCTestCase {

    // A complete, working app validates clean.
    func testGoodTodoAppIsValid() {
        let src = """
        import SwiftUI
        struct ContentView: View {
            @State private var items = ["Buy groceries", "Walk the dog"]
            @State private var newItem = ""
            var body: some View {
                VStack {
                    Text("To-Do").font(.largeTitle)
                    ForEach(items, id: \\.self) { item in
                        Text(item)
                    }
                    Button("Add") { items.append("task") }
                }
            }
        }
        """
        let v = Kiln.validate(src)
        XCTAssertTrue(v.hasView)
        XCTAssertTrue(v.renderedContent, "expected visible content")
        XCTAssertTrue(v.errors.isEmpty, "unexpected errors: \(v.errors)")
        XCTAssertTrue(v.isValid)
    }

    // A body that returns nothing visible is caught as a blank screen — the exact
    // failure the old errors+hasView check missed.
    func testBlankBodyIsCaught() {
        let src = """
        import SwiftUI
        struct ContentView: View {
            var body: some View {
                VStack {
                    EmptyView()
                }
            }
        }
        """
        let v = Kiln.validate(src)
        XCTAssertFalse(v.renderedContent, "a body with no visible content must not read as rendered")
        XCTAssertFalse(v.isValid)
    }

    // An infinite recursion must terminate via the call-depth / fuel guard, not
    // hang the test, and must be reported.
    func testInfiniteRecursionIsBounded() {
        let src = """
        import SwiftUI
        struct ContentView: View {
            var body: some View {
                Text(spin())
            }
            func spin() -> String {
                return spin()
            }
        }
        """
        let v = Kiln.validate(src, fuel: 100_000)
        XCTAssertFalse(v.errors.isEmpty, "runaway recursion should be reported")
    }

    // An unsupported container view (List/Form/TabView/…) parses to a dropped
    // no-op and renders blank — the probe must call it out with a fix-it, even
    // when a sibling view draws something (so it wouldn't read as blank).
    func testUnsupportedContainerReported() {
        let src = """
        import SwiftUI
        struct ContentView: View {
            @State private var items = ["a", "b", "c"]
            var body: some View {
                VStack {
                    Text("My List")
                    List {
                        ForEach(items, id: \\.self) { item in Text(item) }
                    }
                }
            }
        }
        """
        // The modern engine renders List with real SwiftUI (it used to be flagged).
        let v = Kiln.validate(src)
        XCTAssertTrue(v.isValid, "List should validate cleanly now; errors=\(v.errors)")
    }

    // Parse-level failure still reports (no view produced).
    func testNoContentViewReported() {
        let src = "import SwiftUI\nlet x = 5"
        let v = Kiln.validate(src)
        XCTAssertFalse(v.hasView)
        XCTAssertFalse(v.errors.isEmpty)
    }

    // The original interpreter's dialect is gone: it no longer switches engines,
    // it fails on the one engine with its line.
    func testOldDialectFailsWithItsLine() {
        let src = """
        import SwiftUI
        struct ContentView: View {
            @State private var x = 0.0
            var body: some View {
                GameCanvas([["type": "circle", "x": x, "y": 200.0, "r": 20.0]])
                    .onTick(0.1) { x += 1 }
            }
        }
        """
        XCTAssertEqual(Kiln.validate(src).errors.first, "Line 5: Cannot find 'GameCanvas' in scope")
        // A comment or a string that merely mentions it changes nothing.
        let mention = "import SwiftUI\n// GameCanvas( .onTick( Storage.save\nstruct ContentView: View {\n    var body: some View { Text(\"BarChart(\") }\n}"
        XCTAssertTrue(Kiln.validate(mention).isValid, "\(Kiln.validate(mention).errors)")
    }
}
