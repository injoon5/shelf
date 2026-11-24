//
//  CallFormsFixesTests.swift
//  KilnTests
//
//  What the call-forms audit (CallFormsAuditTests) found, fixed: calls Swift
//  takes that Kiln rejected or bound to the wrong parameter, run end to end.
//

import XCTest
@testable import Kiln

@MainActor
final class CallFormsFixesTests: XCTestCase {

    // MARK: The binder

    /// A closure goes to an overload whose closure parameter takes it, before
    /// one where an `any` parameter would: `.chartXAxisLabel { Text("Day") }`
    /// is `content:`'s, not the title's.
    func testAClosurePrefersAClosureParameter() throws {
        let interp = try KInterpreter(program: try KEParser.parse("let x = 1"), headless: true)
        let title = KOverload(params: KSignature.parse("_:any position:any?"))
        let content = KOverload(params: KSignature.parse("position:any? content:content"))
        let (i, b) = try interp.pick([title, content], "chartXAxisLabel", labels: [nil], syntax: [.closureLiteral], line: 0)
        XCTAssertEqual(i, 1)
        XCTAssertEqual(b, [1])
        // A value still takes the first.
        XCTAssertEqual(try interp.pick([title, content], "chartXAxisLabel", labels: [nil], syntax: [.stringLiteral], line: 0).0, 0)
        // With nothing better, the closure goes where it fits.
        XCTAssertEqual(try interp.pick([title], "chartXAxisLabel", labels: [nil], syntax: [.closureLiteral], line: 0).0, 0)
    }

    /// A closure passes over an unlabeled parameter with a default that isn't
    /// for closures: `.accessibilityAction { … }` is the handler.
    func testAClosurePassesOverAnOptionalValue() {
        let action = KOverload(params: KSignature.parse("_:any? _:action"))
        XCTAssertEqual(action.bind([nil], [.closureLiteral]), [1])
        XCTAssertEqual(action.bind([nil, nil], [.other, .closureLiteral]), [0, 1])
    }

    /// Swift's forward scan looks only as far as the parameter the next
    /// argument is for, and counts any parameter that needs an argument.
    func testTheForwardScanStopsAtTheNextLabel() {
        let o = KOverload(params: KSignature.parse("a:closure? b:closure c:closure?"))
        XCTAssertEqual(o.bind([nil, "b"], [.closureLiteral, .closureLiteral]), [0, 1])
        XCTAssertEqual(o.bind([nil, "c"], [.closureLiteral, .closureLiteral]), [1, 2])
        XCTAssertEqual(o.bind([nil], [.closureLiteral]), [1])
    }

    // MARK: Registrations, end to end

    func testFormsTheAuditFound() throws {
        let src = BridgeTest.app(#"""
            NavigationStack {
                List(selection: $picked) {
                    Picker(selection: $choice) {
                        Text("One").tag(1)
                        Text("Two").tag(2)
                    } label: {
                        Text("Choice")
                    }
                    Picker("Menu", selection: $choice) {
                        Text("One").tag(1)
                    } currentValueLabel: {
                        Text("\(choice)")
                    }
                    NavigationLink {
                        Text("Detail")
                    } label: {
                        Text("Open")
                    }
                    Slider(value: $volume, in: 0...1) { Text("Volume") }
                    Slider(value: $volume, in: 0...1, label: { Text("Volume") }) { editing in print(editing) }
                    Stepper(value: $count, in: 0...10, onEditingChanged: { _ in }) { Text("Count") }
                    Stepper { Text("Manual") } onIncrement: { count += 1 } onDecrement: { count -= 1 }
                    TextField("Name", text: $name) { print("committed") }
                    Text("Hello", comment: "A greeting")
                    Text(Date(), formatter: formatter)
                    ShareLink("Share", items: ["a", "b"]) { item in SharePreview(item) }
                    AnyView(erasing: Text("Erased"))
                    UnevenRoundedRectangle(cornerRadii: .init(topLeading: 8, bottomTrailing: 8)).frame(height: 10)
                    LinearGradient(stops: [.init(color: .red, location: 0), .init(color: .blue, location: 1)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 10)
                    AngularGradient(stops: [.init(color: .red, location: 0), .init(color: .blue, location: 1)], center: .center)
                        .frame(height: 10)
                    EllipticalGradient(stops: [.init(color: .red, location: 0), .init(color: .blue, location: 0.5)])
                        .frame(height: 10)
                    Text("Masked").mask { Circle() }
                    Text("Pill").padding().background(in: Capsule())
                    Text("Action").accessibilityAction { count += 1 }
                    Text("Tap").onTapGesture(count: 1, coordinateSpace: .local, inputKinds: .all) { count += 1 }
                }
                .contextMenu(forSelectionType: Int.self) { ids in
                    Button("Delete \(ids.count)") {}
                }
                .toolbar {
                    ToolbarItem(id: "add", placement: .automatic, showsByDefault: true) { Button("Add") {} }
                }
                .task(name: "Load") { count = 1 }
                .alert("Delete?", item: $selected) { item in
                    Button("Delete \(item)", role: .destructive) {}
                } message: { item in
                    Text(item)
                }
            }
            """#, state: """
            @State private var picked: Set<Int> = []
            @State private var choice = 1
            @State private var volume = 0.5
            @State private var count = 0
            @State private var name = ""
            @State private var selected: String? = nil
            let formatter = DateFormatter()
            """)
        XCTAssertEqual(BridgeTest.problems(src), [])
        let bound = try BridgeTest.bound(src)
        for form in ["Picker(selection:content:label:)", "Picker(_:selection:content:currentValueLabel:)", "NavigationLink(destination:label:)",
                     "Stepper(value:in:step:onEditingChanged:label:)", "Stepper(label:onIncrement:onDecrement:onEditingChanged:)",
                     "Text(_:tableName:bundle:comment:)", "Text(_:formatter:)", "ShareLink(_:items:subject:message:preview:)",
                     "AnyView(erasing:)", ".mask(alignment:_:)", ".background(in:fillStyle:)", ".accessibilityAction(_:_:)",
                     ".contextMenu(forSelectionType:menu:primaryAction:)", ".task(name:priority:_:)",
                     ".alert(_:item:actions:message:)"] {
            XCTAssertTrue(bound.contains(form), "\(form) in \(bound)")
        }
    }

    func testChartFormsTheAuditFound() throws {
        let src = BridgeTest.app(#"""
            Chart {
                BarMark(x: .value("Day", "Mon"), y: .value("Count", 3))
                RuleMark(xStart: 10, xEnd: 200, y: .value("Goal", 2))
            }
            .chartXAxisLabel { Text("Day") }
            .chartLegend(position: .bottom) { Text("Legend") }
            .chartForegroundStyleScale(domain: ["Mon", "Tue"]) { day in day == "Mon" ? Color.red : Color.blue }
            .frame(height: 200)
            """#)
        XCTAssertEqual(BridgeTest.problems(src), [])
        let bound = try BridgeTest.bound(src)
        XCTAssertTrue(bound.contains(".chartXAxisLabel(position:alignment:spacing:content:)"), "\(bound)")
        XCTAssertTrue(bound.contains(".chartForegroundStyleScale(domain:mapping:)"), "\(bound)")
        XCTAssertTrue(bound.contains("RuleMark(xStart:xEnd:y:)"), "\(bound)")
    }
}
