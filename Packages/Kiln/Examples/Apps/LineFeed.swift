import SwiftUI

// Round 2 (PLAN.md §3.8): a response read line by line as it arrives, compared against native in Kiln Lab.

struct ContentView: View {
    @State private var lines: [String] = []
    @State private var status = "Idle"
    @State private var newlines = 0

    let feed = URL(string: "data:text/plain;charset=utf-8,Kettle%20on%0AWater%20boiling%0ATea%20steeping%0ATea%20ready%0A")!

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Status", value: status)
                    LabeledContent("Line breaks", value: "\(newlines)")
                }
                Section("Lines") {
                    ForEach(lines, id: \.self) { line in
                        Label(line, systemImage: "text.alignleft")
                    }
                }
            }
            .navigationTitle("Line Feed")
            .toolbar {
                Button("Load") {
                    Task { await load() }
                }
            }
        }
    }

    func load() async {
        lines = []
        newlines = 0
        status = "Loading"
        do {
            let (bytes, _) = try await URLSession.shared.bytes(from: feed)
            for try await line in bytes.lines {
                lines.append(line)
            }
            let (again, _) = try await URLSession.shared.bytes(from: feed)
            for try await byte in again where byte == 10 {
                newlines += 1
            }
            status = "Done"
        } catch {
            status = "Failed"
        }
    }
}
