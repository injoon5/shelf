// Name: Trip Planner
// Icon: suitcase.fill
// Tint: teal

import SwiftUI

struct Stop: Identifiable {
    let id = UUID()
    var city: String
    var nights: Int
}

enum Transport: String, CaseIterable, Identifiable {
    case train = "Train"
    case car = "Car"
    case plane = "Plane"
    var id: String { rawValue }
}

struct ContentView: View {
    @State private var stops = [
        Stop(city: "Lisbon", nights: 3),
        Stop(city: "Porto", nights: 2),
        Stop(city: "Madrid", nights: 4),
    ]
    @State private var transport = Transport.train
    @State private var pace = "Relaxed"
    @State private var travellers = 2
    @State private var budget = 1200.0
    @State private var dailyLimit = 150.0
    @State private var name = ""
    @State private var start = Date()
    @State private var insured = true
    @State private var packed = 0.4
    @State private var rating = 3

    var nights: Int { stops.reduce(0) { $0 + $1.nights } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Trip name", text: $name)
                    DatePicker("Leaving", selection: $start, displayedComponents: .date)
                    Toggle("Travel insurance", isOn: $insured)
                } header: {
                    Text("Trip")
                } footer: {
                    Text("\(nights) nights in \(stops.count) cities")
                }

                Section("Getting Around") {
                    Picker("Transport", selection: $transport) {
                        ForEach(Transport.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker("Pace", selection: $pace) {
                        Text("Relaxed").tag("Relaxed")
                        Text("Busy").tag("Busy")
                    }
                    .pickerStyle(.menu)
                    Picker("Rating", selection: $rating) {
                        ForEach(1...5, id: \.self) { n in
                            Text("\(n) stars").tag(n)
                        }
                    }
                    .pickerStyle(.wheel)
                    Stepper("\(travellers) travellers", value: $travellers, in: 1...8)
                }

                Section("Money") {
                    TextField("Budget", value: $budget, format: .currency(code: "EUR"))
                        .keyboardType(.decimalPad)
                    LabeledContent("Per person", value: (budget / Double(travellers)).formatted(.currency(code: "EUR")))
                    Slider(value: $dailyLimit, in: 50...500, step: 10) {
                        Text("Daily limit")
                    }
                    LabeledContent("Daily limit", value: "\(Int(dailyLimit)) €")
                }

                Section("Packing") {
                    ProgressView(value: packed) {
                        Text("Packed")
                    }
                    Gauge(value: packed) {
                        Text("Bag")
                    } currentValueLabel: {
                        Text("\(Int(packed * 100))%")
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    Menu("Mark Packed") {
                        Button("Half") { packed = 0.5 }
                        Button("All") { packed = 1 }
                    }
                }

                Section("Stops") {
                    if stops.isEmpty {
                        ContentUnavailableView("No Stops", systemImage: "map", description: Text("Add a city to start."))
                    }
                    ForEach(stops) { stop in
                        Label("\(stop.city), \(stop.nights) nights", systemImage: "mappin")
                            .swipeActions(edge: .leading) {
                                Button("Longer") {
                                    if let i = stops.firstIndex(where: { $0.id == stop.id }) {
                                        stops[i].nights += 1
                                    }
                                }
                                .tint(.green)
                            }
                    }
                    .onDelete { offsets in
                        stops.remove(atOffsets: offsets)
                    }
                    .onMove { source, destination in
                        stops.move(fromOffsets: source, toOffset: destination)
                    }
                    Button("Add Stop", systemImage: "plus") {
                        stops.append(Stop(city: "Seville", nights: 2))
                    }
                }
            }
            .navigationTitle("Trip Planner")
            .toolbar { EditButton() }
        }
    }
}
