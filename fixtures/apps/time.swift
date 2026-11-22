// Name: Steeper
// Icon: timer
// Tint: brown

import SwiftUI

struct Tea: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var seconds: Int
}

struct ContentView: View {
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @State private var teas = [
        Tea(name: "Green", seconds: 120),
        Tea(name: "Black", seconds: 240),
        Tea(name: "Herbal", seconds: 300),
    ]
    @State private var selected: Tea? = nil
    @State private var remaining = 0
    @State private var running = false
    @State private var finished = false
    @State private var copied = false

    var progress: Double {
        guard let selected, selected.seconds > 0 else { return 0 }
        return 1 - Double(remaining) / Double(selected.seconds)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Now") {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        LabeledContent("Time", value: context.date.formatted(date: .omitted, time: .shortened))
                    }
                    if let selected {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(selected.name).font(.headline)
                            Text(format(remaining))
                                .font(.largeTitle.monospacedDigit())
                            ProgressView(value: progress)
                        }
                        Button(running ? "Pause" : "Resume") { running.toggle() }
                    } else {
                        Text("Pick a tea").foregroundStyle(.secondary)
                    }
                    if finished {
                        Label("Ready", systemImage: "cup.and.saucer.fill")
                            .foregroundStyle(.green)
                        Button(copied ? "Noted" : "Note It") {
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copied = false
                            }
                        }
                    }
                }
                Section("Teas") {
                    ForEach(teas) { tea in
                        Button {
                            start(tea)
                        } label: {
                            LabeledContent(tea.name, value: format(tea.seconds))
                        }
                    }
                }
            }
            .navigationTitle("Steeper")
            .onReceive(timer) { _ in
                guard running else { return }
                if remaining > 0 {
                    remaining -= 1
                }
                if remaining == 0 {
                    running = false
                    finished = true
                }
            }
        }
    }

    func start(_ tea: Tea) {
        selected = tea
        remaining = tea.seconds
        running = true
        finished = false
    }

    func format(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let rest = seconds % 60
        return String(format: "%d:%02d", minutes, rest)
    }
}
