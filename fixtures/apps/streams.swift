// Name: Echo Chat
// Icon: bubble.left.and.bubble.right
// Tint: indigo
// Covers: Networking

import SwiftUI

struct ChatLine: Identifiable {
    let id = UUID()
    let text: String
    let mine: Bool
}

struct ContentView: View {
    @State private var socket: URLSessionWebSocketTask?
    @State private var lines: [ChatLine] = []
    @State private var draft = ""
    @State private var status = "Connecting…"
    @State private var headlines: [String] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    Text(status)
                        .foregroundStyle(.secondary)
                }
                Section("Chat") {
                    ForEach(lines) { line in
                        HStack {
                            if line.mine { Spacer() }
                            Text(line.text)
                                .padding(8)
                                .background(line.mine ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15),
                                            in: .rect(cornerRadius: 10))
                            if !line.mine { Spacer() }
                        }
                    }
                }
                Section("Headlines") {
                    ForEach(headlines, id: \.self) { headline in
                        Text(headline)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    TextField("Message", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await send() } }
                    Button("Send") {
                        Task { await send() }
                    }
                    .disabled(draft.isEmpty)
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("Echo Chat")
            .task { await connect() }
            .task { await loadHeadlines() }
            .onDisappear {
                socket?.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    func connect() async {
        let s = URLSession.shared.webSocketTask(with: URL(string: "wss://echo.websocket.org")!)
        socket = s
        s.resume()
        status = "Connected"
        do {
            while true {
                let message = try await s.receive()
                switch message {
                case .string(let text):
                    lines.append(ChatLine(text: text, mine: false))
                case .data(let data):
                    lines.append(ChatLine(text: "\(data.count) bytes", mine: false))
                @unknown default:
                    break
                }
            }
        } catch {
            status = "Disconnected: \(error.localizedDescription)"
        }
    }

    func send() async {
        guard let socket, !draft.isEmpty else { return }
        let text = draft
        draft = ""
        lines.append(ChatLine(text: text, mine: true))
        do {
            try await socket.send(.string(text))
        } catch {
            status = "Not sent: \(error.localizedDescription)"
        }
    }

    func loadHeadlines() async {
        guard let url = URL(string: "https://example.com/headlines.txt") else { return }
        do {
            let (bytes, response) = try await URLSession.shared.bytes(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            for try await line in bytes.lines where !line.isEmpty {
                headlines.append(line)
            }
        } catch {
            headlines = ["Offline"]
        }
    }
}
