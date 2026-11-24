// Name: Converter
// Icon: ruler
// Tint: mint
// Covers: Units

import SwiftUI

enum Quantity: String, CaseIterable, Identifiable {
    case length = "Length"
    case mass = "Mass"
    case temperature = "Temperature"
    case volume = "Volume"
    case speed = "Speed"
    var id: String { rawValue }

    var units: [Dimension] {
        switch self {
        case .length: return [UnitLength.meters, UnitLength.kilometers, UnitLength.feet, UnitLength.miles, Converter.smoot]
        case .mass: return [UnitMass.grams, UnitMass.kilograms, UnitMass.ounces, UnitMass.pounds]
        case .temperature: return [UnitTemperature.celsius, UnitTemperature.fahrenheit, UnitTemperature.kelvin]
        case .volume: return [UnitVolume.milliliters, UnitVolume.liters, UnitVolume.cups, UnitVolume.gallons]
        case .speed: return [UnitSpeed.kilometersPerHour, UnitSpeed.milesPerHour, UnitSpeed.metersPerSecond, UnitSpeed.knots]
        }
    }
}

enum Converter {
    static let smoot = UnitLength(symbol: "smoot", converter: UnitConverterLinear(coefficient: 1.70180))
}

struct ContentView: View {
    @State private var quantity: Quantity = .length
    @State private var value = 5.0
    @State private var from = 1
    @State private var to = 3

    var input: Measurement<Dimension> { Measurement(value: value, unit: quantity.units[min(from, quantity.units.count - 1)]) }
    var output: Measurement<Dimension> { input.converted(to: quantity.units[min(to, quantity.units.count - 1)]) }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Quantity", selection: $quantity) {
                    ForEach(Quantity.allCases) { q in Text(q.rawValue).tag(q) }
                }
                .pickerStyle(.segmented)
                .onChange(of: quantity) { from = 0; to = 1 }
                Section("From") {
                    TextField("Value", value: $value, format: .number)
                    Picker("Unit", selection: $from) {
                        ForEach(quantity.units.indices, id: \.self) { i in Text(quantity.units[i].symbol).tag(i) }
                    }
                }
                Section("To") {
                    Picker("Unit", selection: $to) {
                        ForEach(quantity.units.indices, id: \.self) { i in Text(quantity.units[i].symbol).tag(i) }
                    }
                    Text(output.formatted(.measurement(width: .wide, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...2)))))
                        .font(.title2.bold())
                }
                Section("A run") {
                    let run = Measurement(value: 5, unit: UnitLength.kilometers)
                    let warmUp = Measurement(value: 800, unit: UnitLength.meters)
                    LabeledContent("Total", value: (run + warmUp).formatted(.measurement(width: .abbreviated, usage: .road)))
                    LabeledContent("Longer than 3 miles", value: run + warmUp > Measurement(value: 3, unit: UnitLength.miles) ? "Yes" : "No")
                    LabeledContent("Pace", value: paceText)
                }
                Section("Here") {
                    LabeledContent("Measurement system", value: system)
                    LabeledContent("Body temperature", value: Measurement(value: 37, unit: UnitTemperature.celsius).formatted(.measurement(width: .abbreviated, usage: .person)))
                }
            }
            .navigationTitle("Converter")
        }
    }

    var paceText: String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = 1
        let pace = Measurement(value: 5.8, unit: UnitLength.kilometers) / 0.5
        return formatter.string(from: pace) + " per hour"
    }

    var system: String {
        switch Locale.current.measurementSystem {
        case .metric: return "Metric"
        case .us: return "US"
        case .uk: return "UK"
        default: return "Other"
        }
    }
}
