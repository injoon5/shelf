import XCTest
import SwiftUI
@testable import Kiln

/// Round 1, Controls: every bridge's forms resolve, its arguments decode,
/// its view builds, and a wrong call's error reads correctly.
@MainActor
final class ControlsBridgeTests: XCTestCase {
    private func assertClean(_ body: String, state: String = "", extra: String = "", file: StaticString = #filePath, line: UInt = #line) {
        let p = BridgeTest.problems(BridgeTest.app(body, state: state, extra: extra))
        XCTAssertEqual(p, [], file: file, line: line)
    }

    func testCustomButtonAndToggleStylesRunTheAppsMakeBody() {
        let extra = """
        struct PressStyle: ButtonStyle {
            var scale: CGFloat = 0.9
            func makeBody(configuration: Configuration) -> some View {
                configuration.label
                    .padding()
                    .scaleEffect(configuration.isPressed ? scale : 1)
                    .background(configuration.role == .destructive ? Color.red : Color.blue)
            }
        }
        struct TapStyle: PrimitiveButtonStyle {
            func makeBody(configuration: Configuration) -> some View {
                configuration.label.onTapGesture { configuration.trigger() }
            }
        }
        struct CheckboxStyle: ToggleStyle {
            func makeBody(configuration: Configuration) -> some View {
                Button { configuration.isOn.toggle() } label: {
                    HStack {
                        Image(systemName: configuration.isOn ? "checkmark.square" : "square")
                        configuration.label
                    }
                }
            }
        }
        struct Stacked: LabelStyle {
            func makeBody(configuration: Configuration) -> some View {
                VStack { configuration.icon; configuration.title }
            }
        }
        struct Card: GroupBoxStyle {
            func makeBody(configuration: Configuration) -> some View {
                VStack(alignment: .leading) { configuration.label.font(.headline); configuration.content }
            }
        }
        struct Bar: ProgressViewStyle {
            func makeBody(configuration: Configuration) -> some View {
                Capsule().frame(width: 200 * (configuration.fractionCompleted ?? 0), height: 6)
            }
        }
        struct Native: ToggleStyle {
            func makeBody(configuration: Configuration) -> some View { Toggle(configuration).tint(.green) }
        }
        """
        assertClean("""
        VStack {
            Button("Press") { }.buttonStyle(PressStyle())
            Button("Delete", role: .destructive) { }.buttonStyle(PressStyle(scale: 0.8))
            Button("Tap") { }.buttonStyle(TapStyle())
            Toggle("Agree", isOn: $on).toggleStyle(CheckboxStyle())
            Toggle("Native", isOn: $on).toggleStyle(Native())
            Label("Star", systemImage: "star").labelStyle(Stacked())
            GroupBox("Card") { Text("Body") }.groupBoxStyle(Card())
            ProgressView(value: 0.4).progressViewStyle(Bar())
        }
        """, state: "@State private var on = false", extra: extra)
    }

    func testAStyleThatLeavesOutMakeBodyIsACheckError() {
        let source = BridgeTest.app(#"Button("x") { }.buttonStyle(Plain())"#, extra: "struct Plain: ButtonStyle { }")
        XCTAssertTrue(Kiln.check(source).errors.contains { $0.message.contains("makeBody(configuration:)") }, "\(Kiln.check(source).errors)")
    }

    func testBuiltInStylesIncludingGlass() {
        assertClean("""
        VStack {
            Button("Glass") { }.buttonStyle(.glass)
            Button("Clear") { }.buttonStyle(.glass(.clear))
            Button("Prominent") { }.buttonStyle(.glassProminent).buttonBorderShape(.roundedRectangle(radius: 6))
            Menu("Menu") { Button("A") { } }.menuStyle(.button).menuIndicator(.hidden).menuOrder(.fixed)
            ControlGroup { Button("A") { }; Button("B") { } }.controlGroupStyle(.navigation)
            Form { Text("x") }.formStyle(.grouped)
            Gauge(value: 0.5) { Text("Fuel") }.gaugeStyle(.linearCapacity)
            TextField("Name", text: $text).textFieldStyle(.roundedBorder)
            TextEditor(text: $text).textEditorStyle(.plain)
            Picker("P", selection: $text) { Text("a").tag("a") }.pickerStyle(.palette).paletteSelectionEffect(.custom)
            LabeledContent("Key", value: "Value").labeledContentStyle(.automatic)
            DisclosureGroup("More") { Text("x") }.disclosureGroupStyle(.automatic)
            GroupBox { Text("x") }.groupBoxStyle(.automatic)
        }
        """, state: #"@State private var text = "a""#)
    }

    func testSliderWithTicksLabelsAndNeutralValue() throws {
        let body = """
        VStack {
            Slider(value: $v, in: 0...10, step: 1) { Text("Volume") } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("10") }
            Slider(value: $v, in: 0...10, neutralValue: 5) { Text("Balance") } ticks: {
                SliderTick(0)
                SliderTick("Mid", 5)
                SliderTickContentForEach([2.0, 8.0], id: \\.self) { SliderTick($0) }
            }
            Slider(value: $v, in: 0...10, onEditingChanged: { editing in print(editing) })
        }
        """
        assertClean(body, state: "@State private var v = 3.0")
        let picked = try BridgeTest.bound(BridgeTest.app(body, state: "@State private var v = 3.0"))
        XCTAssertTrue(picked.contains("Slider(value:in:step:label:minimumValueLabel:maximumValueLabel:onEditingChanged:)"), "\(picked)")
        XCTAssertTrue(picked.contains("Slider(value:in:step:neutralValue:enabledBounds:label:currentValueLabel:minimumValueLabel:maximumValueLabel:ticks:onEditingChanged:)"), "\(picked)")
    }

    func testPickersAndDates() {
        assertClean("""
        Form {
            DatePicker("When", selection: $date, in: Date()..., displayedComponents: .date).datePickerStyle(.graphical)
            DatePicker("Until", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
            MultiDatePicker("Days", selection: $days)
            ColorPicker("Color", selection: $color, supportsOpacity: false)
            ColorPicker(selection: $color) { Text("Tint") }
        }
        """, state: "@State private var date = Date()\n@State private var days: Set<DateComponents> = []\n@State private var color = Color.red")
    }

    func testMenuPrimaryActionTextInputsAndRename() {
        assertClean("""
        VStack {
            Menu("Add", systemImage: "plus") { Button("Photo") { } } primaryAction: { count += 1 }
            Menu { Button("A") { } } label: { Label("More", systemImage: "ellipsis") } primaryAction: { count += 1 }
            TextField("Notes", text: $text, prompt: Text("Write…"), axis: .vertical).lineLimit(3...6)
            TextField(text: $text, prompt: Text("Name")) { Text("Name") }
            SecureField("Password", text: $text)
            TextField("Age", value: $count, format: .number)
            TextEditor(text: $rich)
            Text(rich)
            Text(timerInterval: Date()...Date().addingTimeInterval(60), countsDown: true)
            ProgressView(timerInterval: Date()...Date().addingTimeInterval(60))
            RenameButton()
            Stepper("Count", value: $count, in: 0...10, step: 2)
            LabeledContent("Total") { Text("3") }
            Button("Repeat") { count += 1 }.buttonRepeatBehavior(.enabled).help("Adds one")
            Toggle("Hidden label", isOn: .constant(true)).labelsHidden()
        }
        .controlSize(.small)
        """, state: #"""
        @State private var text = ""
        @State private var count = 0
        @State private var rich = try! AttributedString(markdown: "**Bold** and _italic_")
        """#)
    }

    func testEnvironmentValuesAreReadWhereTheViewIsShown() {
        let extra = """
        struct Probe: View {
            @Environment(\\.isEnabled) private var isEnabled
            @Environment(\\.controlSize) private var size
            var body: some View { Text(isEnabled ? "on" : "off").foregroundStyle(size == .small ? .red : .blue) }
        }
        """
        assertClean("VStack { Probe().disabled(true); Probe().controlSize(.small); Probe().environment(\\.isEnabled, false) }", extra: extra)
    }

    func testAWrongCallSaysWhichFormsThereAre() {
        let v = Kiln.validate(BridgeTest.app(#"Slider(value: $v, from: 0)"#, state: "@State private var v = 0.0"))
        XCTAssertEqual(v.errors.count, 1)
        XCTAssertTrue(v.errors.first?.hasPrefix("Line 6: Kiln has no Slider(value:from:); it has Slider(value:in:step:onEditingChanged:)") == true, "\(v.errors)")
    }
}
