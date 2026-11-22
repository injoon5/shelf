// Name: Workouts
// Icon: figure.run
// Tint: green

import SwiftUI
import Observation

class WorkoutStore: ObservableObject {
    @Published var workouts: [String] = ["Run", "Swim"]
    @Published var goal = 3

    func add(_ name: String) {
        workouts.append(name)
    }
}

@Observable
class Timer2 {
    var seconds = 0
    var running = false

    func tick() {
        if running { seconds += 1 }
    }
}

class Settings: ObservableObject {
    @Published var useMiles = false
}

struct ContentView: View {
    @StateObject private var store = WorkoutStore()
    @StateObject private var settings = Settings()
    @State private var stopwatch = Timer2()
    @State private var showingAdd = false
    @State private var count = 0

    var body: some View {
        NavigationStack {
            List {
                Section("Workouts") {
                    ForEach(store.workouts, id: \.self) { name in
                        Text(name)
                    }
                    GoalRow(store: store)
                }
                Section("Stopwatch") {
                    Text("\(stopwatch.seconds) s")
                    Button(stopwatch.running ? "Stop" : "Start") {
                        stopwatch.running.toggle()
                        stopwatch.tick()
                    }
                }
                Section("Counter") {
                    CounterRow(count: $count)
                    Text("Count is \(count)")
                }
                UnitsRow()
            }
            .navigationTitle("Workouts")
            .toolbar {
                Button("Add", systemImage: "plus") { showingAdd = true }
            }
            .sheet(isPresented: $showingAdd) {
                AddWorkoutView(store: store)
            }
        }
        .environmentObject(settings)
    }
}

struct GoalRow: View {
    @ObservedObject var store: WorkoutStore

    var body: some View {
        Stepper("Goal: \(store.goal) a week", value: $store.goal, in: 1...7)
    }
}

struct CounterRow: View {
    @Binding var count: Int

    var body: some View {
        HStack {
            Button("Less") { count -= 1 }
            Spacer()
            Button("More") { count += 1 }
        }
        .buttonStyle(.borderless)
    }
}

struct UnitsRow: View {
    @EnvironmentObject var settings: Settings

    var body: some View {
        Section("Units") {
            Toggle("Miles", isOn: $settings.useMiles)
            Text(settings.useMiles ? "Distances in miles" : "Distances in kilometres")
        }
    }
}

struct AddWorkoutView: View {
    @ObservedObject var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .onSubmit { save() }
            }
            .navigationTitle("New Workout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    func save() {
        store.add(name.isEmpty ? "Workout" : name)
        dismiss()
    }
}
