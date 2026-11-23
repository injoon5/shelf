import SwiftUI

// Round 1A in one app: tabs (Tab, badge), a navigation stack with a path and
// a destination, a list with selection and swipe actions, a toolbar, a sheet
// with detents, a form of controls with a custom ToggleStyle and ButtonStyle,
// and a paging scroll view of cards.

struct Plant: Identifiable, Hashable {
    let id: Int
    var name: String
    var days: Int
    var symbol: String
}

struct CheckStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}

struct PillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.green.opacity(configuration.isPressed ? 0.5 : 0.25), in: Capsule())
    }
}

struct PlantList: View {
    @Binding var plants: [Plant]
    @State private var path: [Plant] = []
    @State private var selection = Set<Int>()
    @State private var adding = false

    var body: some View {
        NavigationStack(path: $path) {
            List(selection: $selection) {
                Section("Thirsty soon") {
                    ForEach(plants) { plant in
                        NavigationLink(value: plant) {
                            Label("\(plant.name), \(plant.days) days", systemImage: plant.symbol)
                        }
                        .swipeActions {
                            Button("Water") { water(plant) }.tint(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Plants")
            .navigationDestination(for: Plant.self) { plant in
                VStack(spacing: 12) {
                    Image(systemName: plant.symbol).font(.largeTitle)
                    Text(plant.name).font(.title2)
                    Text("Water every \(plant.days) days")
                    Button("Water now") { water(plant) }.buttonStyle(PillStyle())
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") { adding = true }
                }
            }
            .sheet(isPresented: $adding) {
                VStack(spacing: 16) {
                    Text("New plant").font(.headline)
                    Button("Add a fern") {
                        plants.append(Plant(id: plants.count + 1, name: "Fern", days: 4, symbol: "leaf"))
                        adding = false
                    }
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
    }

    func water(_ plant: Plant) {
        if let i = plants.firstIndex(where: { $0.id == plant.id }) { plants[i].days = 7 }
    }
}

struct SettingsForm: View {
    @State private var reminders = true
    @State private var quiet = false
    @State private var hour = 8.0
    @State private var units = "Days"
    @State private var snooze = 1

    var body: some View {
        Form {
            Section("Reminders") {
                Toggle("Remind me", isOn: $reminders).toggleStyle(CheckStyle())
                Toggle("Quiet at night", isOn: $quiet)
                Slider(value: $hour, in: 6...12, step: 1) {
                    Text("Hour")
                } minimumValueLabel: {
                    Text("6")
                } maximumValueLabel: {
                    Text("12")
                }
                Stepper("Snooze \(snooze) h", value: $snooze, in: 1...6)
                Picker("Units", selection: $units) {
                    Text("Days").tag("Days")
                    Text("Weeks").tag("Weeks")
                }
                .pickerStyle(.segmented)
                LabeledContent("Next reminder", value: "\(Int(hour)):00")
            }
            Section("Tips") {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(["Light", "Water", "Soil"], id: \.self) { tip in
                            Text(tip)
                                .frame(height: 80)
                                .containerRelativeFrame(.horizontal)
                                .background(Color.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
            }
        }
    }
}

struct ContentView: View {
    @State private var plants = [
        Plant(id: 1, name: "Monstera", days: 2, symbol: "leaf.fill"),
        Plant(id: 2, name: "Cactus", days: 12, symbol: "sun.max"),
        Plant(id: 3, name: "Basil", days: 1, symbol: "drop"),
    ]

    var body: some View {
        TabView {
            PlantList(plants: $plants)
                .tabItem { Label("Plants", systemImage: "leaf") }
                .badge(plants.filter { $0.days < 3 }.count)
            SettingsForm()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
