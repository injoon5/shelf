import XCTest
import SwiftUI
@_spi(KilnTesting) @testable import Kiln

/// Round 2C (PLAN.md §3): Foundation and the standard library. Values are the
/// corpus's job (`CorpusTests`); these pin what a value can't show: errors
/// instead of placeholders, `Kiln.run`'s errors, the checker, views, and the
/// manifest's forms.
@MainActor
final class Round2CTests: XCTestCase {
    func run(_ code: String) -> KilnResult {
        Kiln.run("import SwiftUI\nstruct ContentView: View { var body: some View { Text(\"x\") } }\n" + code, context: .stub())
    }

    // MARK: Silent wrong values are errors now

    func testAnUnknownStaticMemberIsAnErrorNotAPlaceholder() {
        let r = run("let id = HKHealthStore.isHealthDataAvailable()\nprint(id)")
        XCTAssertEqual(r.errors.first, "Line 3: Cannot find 'HKHealthStore' in scope: Kiln doesn't have it")
        XCTAssertEqual(r.consoleOutput, "")
        // A known type's unknown member, too.
        XCTAssertEqual(run("print(Calendar.nonsense)").errors, ["Line 3: Type 'Calendar' has no member 'nonsense' in Kiln"])
        // SwiftUI's symbolic types stay symbolic.
        XCTAssertEqual(run("let e = Edge.Set.all\nprint(e)").errors, [])
    }

    func testRunReportsErrorsFromTopLevelCode() {
        let r = run("let xs = [1]\nprint(xs[3])")
        XCTAssertEqual(r.errors, ["Line 4: Index out of range: 3 (the array has 1 item)"])
        XCTAssertNotNil(r.view, "the app still shows")
    }

    func testAFormatStyleKilnDoesntHaveIsAnError() {
        let r = run("print(5.formatted(.number.nonsense()))")
        XCTAssertEqual(r.errors, ["Kiln doesn't have .nonsense on a number style"])
    }

    func testIntegerOverflowTrapsAsSwiftDoes() {
        XCTAssertEqual(run("print(Int.max + 1)").errors, ["Line 3: Arithmetic overflow: 9223372036854775807 + 1 doesn't fit in an Int (use &+ to wrap around)"])
        XCTAssertEqual(run("let b: UInt8 = 200\nprint(b + 100)").errors.first?.contains("Arithmetic overflow"), true)
    }

    // MARK: The checker

    func testTheCheckerKnowsRound2CsTypes() {
        let source = """
            import SwiftUI
            import Combine
            struct ContentView: View {
                @State private var text = ""
                let subject = PassthroughSubject<String, Never>()
                var body: some View {
                    Text(text)
                        .onReceive(subject) { text = $0 }
                        .onAppear {
                            let cal = Calendar(identifier: .gregorian)
                            let d = cal.date(bySettingHour: 9, minute: 0, second: 0, of: .now)
                            let comps = DateComponents(year: 2026, month: 1)
                            let n: UInt8 = 7
                            let v = SIMD2<Double>(1, 2)
                            print(d as Any, comps.month ?? 0, n &+ 1, v.x, Bundle.main.bundleIdentifier ?? "", Duration.seconds(2))
                        }
                }
            }
            """
        XCTAssertEqual(Kiln.check(source).errors.map(\.message), [])
    }

    func testCalendarsUnbridgedFormIsAnError() {
        let check = Kiln.check(BridgeTest.app(#"Button("x") { _ = Calendar.current.date(from: DateComponents(), in: .current) }"#))
        XCTAssertEqual(check.errors.count, 1)
        XCTAssertEqual(check.errors.first?.message.contains("Kiln has no date(from:in:)"), true, "\(check.errors.map(\.message))")
    }

    // MARK: Views

    func testOnReceiveTakesACombinePublisher() {
        let src = BridgeTest.app(#"""
            Text("\(count)")
                .onReceive(subject) { count = $0 }
            """#, state: "@State private var count = 0\n    let subject = CurrentValueSubject<Int, Never>(4)")
        XCTAssertEqual(BridgeTest.problems(src), [])
        XCTAssertEqual(Kiln.check(src).warnings.map(\.message), [])
    }

    func testImageRendererRendersAView() {
        let r = run("""
            let renderer = ImageRenderer(content: Color.blue.frame(width: 4, height: 6))
            print(renderer.cgImage?.height ?? 0)
            """)
        XCTAssertEqual(r.errors, [])
        XCTAssertEqual(r.consoleOutput, "6\n")
    }

    // MARK: Closures with `$0`

    func testGestureCallbacksTake$0() {
        let src = BridgeTest.app(#"""
            Rectangle()
                .frame(width: 200, height: 200)
                .gesture(
                    DragGesture()
                        .onChanged { offset = $0.translation; points.append($0.location) }
                        .onEnded { _ in offset = .zero }
                        .simultaneously(with: RotateGesture().onChanged { angle = $0.rotation })
                )
            """#, state: "@State private var offset = CGSize.zero\n    @State private var points: [CGPoint] = []\n    @State private var angle = Angle.zero")
        XCTAssertEqual(Kiln.check(src).errors.map(\.message), [])
        XCTAssertEqual(Kiln.validate(src).errors, [])
    }

    // MARK: The manifest's forms

    func testTheManifestListsEachFormOfAMember() throws {
        let symbols = KRegistry.shared.manifest(includeHost: false).symbols
        let date = try XCTUnwrap(symbols.first { $0.id == "member:Calendar.date" })
        let forms = try XCTUnwrap(date.overloads)
        XCTAssertTrue(forms.contains { $0.labels == ["byAdding", "value", "to", "wrappingComponents"] && $0.member == "method" })
        XCTAssertTrue(forms.contains { $0.labels == ["bySetting", "value", "of"] })
        let setHour = try XCTUnwrap(forms.first { $0.labels.first == "bySettingHour" })
        XCTAssertEqual(setHour.signature, "bySettingHour:number minute:number second:number of:any matchingPolicy:any? repeatedTimePolicy:any? direction:any?")
        XCTAssertNil(date.anyLabels, "every form of Calendar.date is listed")
        // A loose bridge says so: other label sets may work.
        XCTAssertEqual(symbols.first { $0.id == "member:Sequence.map" }?.anyLabels, true)
        // An async form.
        XCTAssertEqual(symbols.first { $0.id == "member:Task.sleep" }?.anyLabels, true)
    }
}
