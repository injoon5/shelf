// Name: Launches
// Icon: airplane.departure
// Tint: indigo
// Covers: Networking, Foundation

import SwiftUI

struct Launch: Decodable, Identifiable {
    let id: String
    let name: String
    let dateUtc: Date
    let success: Bool?
    let details: String?
    let links: Links
    let status: Status

    struct Links: Decodable {
        let webcast: URL?
    }
}

enum Status: String, Decodable {
    case upcoming
    case done
}

struct Rocket: Decodable {
    let rocketName: String
    let firstFlight: String

    enum CodingKeys: String, CodingKey {
        case rocketName = "name"
        case firstFlight = "first_flight"
    }
}

struct Report: Encodable {
    let launchID: String
    let note: String
}

struct ContentView: View {
    @State private var launches: [Launch] = []
    @State private var rocket: Rocket? = nil
    @State private var loading = false
    @State private var message: String? = nil
    @State private var query = "falcon"

    var body: some View {
        NavigationStack {
            List {
                if let message {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                if let rocket {
                    Section("Rocket") {
                        LabeledContent(rocket.rocketName, value: rocket.firstFlight)
                    }
                }
                Section("Launches") {
                    if loading {
                        ProgressView()
                    } else if launches.isEmpty {
                        ContentUnavailableView("No Launches", systemImage: "airplane")
                    }
                    ForEach(launches) { launch in
                        VStack(alignment: .leading) {
                            Text(launch.name).font(.headline)
                            Text(launch.dateUtc.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let details = launch.details {
                                Text(details).font(.caption).lineLimit(2)
                            }
                        }
                        .swipeActions {
                            Button("Report") { report(launch) }
                        }
                    }
                }
            }
            .navigationTitle("Launches")
            .searchable(text: $query)
            .onSubmit(of: .search) { load() }
            .refreshable { load() }
            .onAppear { load() }
        }
    }

    func load() {
        var components = URLComponents(string: "https://api.example.com/v4/launches")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "20"),
        ]
        guard let url = components.url else { return }
        loading = true
        message = nil
        URLSession.shared.dataTask(with: url) { data, response, error in
            loading = false
            if let error {
                message = error.localizedDescription
                return
            }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, let data else {
                message = "The server didn't answer."
                return
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            do {
                launches = try decoder.decode([Launch].self, from: data)
            } catch {
                message = "Couldn't read the launches."
            }
        }.resume()

        URLSession.shared.dataTask(with: URL(string: "https://api.example.com/v4/rockets/falcon9")!) { data, _, _ in
            if let data {
                rocket = try? JSONDecoder().decode(Rocket.self, from: data)
            }
        }.resume()
    }

    func report(_ launch: Launch) {
        var request = URLRequest(url: URL(string: "https://api.example.com/v4/reports")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(Report(launchID: launch.id, note: "Watched"))
        URLSession.shared.dataTask(with: request) { _, response, error in
            if error != nil || (response as? HTTPURLResponse)?.statusCode != 201 {
                message = "The report wasn't sent."
            }
        }.resume()
    }
}
