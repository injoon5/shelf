// Name: Daily Quote
// Icon: quote.bubble
// Tint: teal

import SwiftUI

struct Quote: Decodable {
    let text: String
    let author: String
}

enum Phase {
    case waiting, loading, loaded, failed
}

enum QuoteError: Error {
    case badStatus(Int)
}

struct ContentView: View {
    @State private var quote: Quote? = nil
    @State private var phase = Phase.waiting
    @State private var message = ""
    @State private var countdown: [Int] = []
    @State private var refreshes = 0
    @State private var related: [String] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Today") {
                    switch phase {
                    case .waiting, .loading:
                        HStack {
                            ProgressView()
                            Text("Loading")
                                .foregroundStyle(.secondary)
                        }
                    case .loaded:
                        if let quote {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(quote.text)
                                    .font(.title3)
                                Text(quote.author)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    case .failed:
                        Label(message, systemImage: "wifi.slash")
                            .foregroundStyle(.orange)
                    }
                }
                Section("Countdown") {
                    Text(countdown.isEmpty ? "Starting" : countdown.map { "\($0)" }.joined(separator: " · "))
                        .monospacedDigit()
                }
                if !related.isEmpty {
                    Section("Also by") {
                        ForEach(related, id: \.self) { name in
                            Text(name)
                        }
                    }
                }
            }
            .navigationTitle("Daily Quote")
            .toolbar {
                Button {
                    refreshes += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .task(id: refreshes) {
                await load()
            }
            .task {
                await count()
            }
            .refreshable {
                await load()
            }
        }
    }

    func load() async {
        phase = .loading
        // A short pause, so the loading state shows.
        try? await Task.sleep(for: .milliseconds(300))
        print("slept")
        do {
            let url = URL(string: "https://quotes.example.com/today")!
            let (data, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw QuoteError.badStatus(status) }
            let loaded = try JSONDecoder().decode(Quote.self, from: data)
            quote = loaded
            phase = .loaded
            print("loaded \(loaded.author)")
            related = await moreBy(loaded.author)
        } catch {
            message = "Couldn't load today's quote."
            phase = .failed
            print("failed")
        }
    }

    /// Two lookups at once.
    func moreBy(_ author: String) async -> [String] {
        async let first = lookup(author, 1)
        async let second = lookup(author, 2)
        return await [first, second]
    }

    func lookup(_ author: String, _ n: Int) async -> String {
        try? await Task.sleep(for: .milliseconds(50))
        return "\(author) #\(n)"
    }

    func ticks(from start: Int) -> AsyncStream<Int> {
        AsyncStream { continuation in
            Task {
                var n = start
                while n > 0 {
                    continuation.yield(n)
                    n -= 1
                    try? await Task.sleep(for: .milliseconds(100))
                }
                continuation.finish()
            }
        }
    }

    func count() async {
        for await n in ticks(from: 3) {
            countdown.append(n)
        }
        print("counted \(countdown)")
    }
}
