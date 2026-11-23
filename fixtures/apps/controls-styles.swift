// Name: Coffee Order
// Icon: cup.and.saucer.fill
// Tint: brown
// Covers: Controls

import SwiftUI

struct PressableStyle: ButtonStyle {
    var color: Color = .brown
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct CheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}

struct ContentView: View {
    @State private var size = 2.0
    @State private var shots = 1
    @State private var oatMilk = false
    @State private var extraHot = false
    @State private var pickup = Date()
    @State private var days: Set<DateComponents> = []
    @State private var tint = Color.brown
    @State private var note = ""
    @State private var orders = 0
    @State private var roast = "Medium"

    var body: some View {
        NavigationStack {
            Form {
                Section("Drink") {
                    Picker("Roast", selection: $roast) {
                        ForEach(["Light", "Medium", "Dark"], id: \.self) { Text($0) }
                    }
                    .pickerStyle(.segmented)
                    Slider(value: $size, in: 1...3, step: 1) {
                        Text("Size")
                    } minimumValueLabel: {
                        Text("S")
                    } maximumValueLabel: {
                        Text("L")
                    }
                    Stepper("Shots: \(shots)", value: $shots, in: 1...4)
                    Toggle("Oat milk", isOn: $oatMilk).toggleStyle(CheckboxStyle())
                    Toggle("Extra hot", isOn: $extraHot)
                    Gauge(value: Double(shots), in: 0...4) {
                        Text("Caffeine")
                    } currentValueLabel: {
                        Text("\(shots)")
                    }
                    .gaugeStyle(.accessoryLinearCapacity)
                }
                Section("Pickup") {
                    DatePicker("Time", selection: $pickup, in: Date()..., displayedComponents: .hourAndMinute)
                    MultiDatePicker("Weekly", selection: $days)
                    ColorPicker("Cup", selection: $tint, supportsOpacity: false)
                    TextField("Note for the barista", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                    LabeledContent("Orders today", value: "\(orders)")
                }
                Section {
                    ControlGroup {
                        Button("Reset", systemImage: "arrow.counterclockwise") { shots = 1 }
                        Button("Double", systemImage: "plus") { shots = 2 }
                    }
                    Menu("Favorites", systemImage: "star") {
                        Button("Flat white") { roast = "Medium" }
                        Button("Espresso") { roast = "Dark" }
                    } primaryAction: {
                        orders += 1
                    }
                    Button("Order") { orders += 1 }
                        .buttonStyle(PressableStyle(color: tint))
                }
            }
            .navigationTitle("Coffee")
            .controlSize(.regular)
        }
    }
}
