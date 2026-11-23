// Name: Field Notes
// Icon: map.fill
// Tint: green
// Covers: Navigation

import SwiftUI

struct Place: Identifiable, Hashable {
    let id: Int
    var name: String
    var region: String
    var symbol: String
}

struct PlacesView: View {
    let places: [Place]
    @Namespace private var zoom
    @State private var path: [Place] = []
    @State private var query = ""
    @State private var showsFilters = false
    @State private var region = "All"

    var shown: [Place] {
        places.filter { (region == "All" || $0.region == region) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List(shown) { place in
                NavigationLink(value: place) {
                    Label(place.name, systemImage: place.symbol)
                }
                .matchedTransitionSource(id: place.id, in: zoom)
            }
            .navigationTitle("Places")
            .navigationSubtitle("\(shown.count) of \(places.count)")
            .navigationDestination(for: Place.self) { place in
                VStack(spacing: 12) {
                    Image(systemName: place.symbol).font(.system(size: 64))
                    Text(place.name).font(.title.bold())
                    Text(place.region).foregroundStyle(.secondary)
                }
                .navigationTransition(.zoom(sourceID: place.id, in: zoom))
            }
            .searchable(text: $query, prompt: "Find a place")
            .searchScopes($region) {
                Text("All").tag("All")
                Text("North").tag("North")
                Text("South").tag("South")
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Filters", systemImage: "line.3.horizontal.decrease") { showsFilters = true }
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Button("Random", systemImage: "dice") { if let p = places.randomElement() { path.append(p) } }
                }
                .visibilityPriority(.high)
            }
            .sheet(isPresented: $showsFilters) {
                Form {
                    Picker("Region", selection: $region) {
                        Text("All").tag("All")
                        Text("North").tag("North")
                        Text("South").tag("South")
                    }
                    .pickerStyle(.inline)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}

struct ContentView: View {
    @State private var tab = 0
    @State private var visits = 0
    let places = [
        Place(id: 1, name: "Lighthouse", region: "North", symbol: "light.beacon.max"),
        Place(id: 2, name: "Old Mill", region: "South", symbol: "wind"),
        Place(id: 3, name: "Harbor", region: "North", symbol: "ferry"),
    ]

    var body: some View {
        TabView(selection: $tab) {
            Tab("Places", systemImage: "map", value: 0) {
                PlacesView(places: places)
            }
            .badge(places.count)
            Tab("Journal", systemImage: "book", value: 1) {
                NavigationStack {
                    List {
                        Section("This week") {
                            Text("\(visits) visits")
                            Button("Log a visit") { visits += 1 }
                        }
                    }
                    .navigationTitle("Journal")
                }
            }
            Tab(value: 2, role: .search) {
                PlacesView(places: places)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
