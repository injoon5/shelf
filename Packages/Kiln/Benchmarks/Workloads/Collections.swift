// Workload: arrays and dictionaries, higher-order functions, sorting.
import SwiftUI

struct Item: Identifiable {
    let id: Int
    var name: String
    var score: Int
}

func makeItems(_ count: Int) -> [Item] {
    var items: [Item] = []
    var seed = 7
    for i in 0..<count {
        seed = (seed * 1103 + 12345) % 65536
        items.append(Item(id: i, name: "item\(seed % 97)", score: seed % 1000))
    }
    return items
}

func crunch(_ items: [Item]) -> String {
    let sorted = items.sorted { $0.score > $1.score }
    let top = sorted.prefix(10).map { $0.name }
    let evens = items.filter { $0.score % 2 == 0 }.count
    let total = items.map { $0.score }.reduce(0, +)
    var byName: [String: Int] = [:]
    for item in items {
        byName[item.name] = (byName[item.name] ?? 0) + item.score
    }
    let busiest = byName.keys.sorted().first ?? ""
    return "\(top.count) \(evens) \(total) \(byName.count) \(busiest)"
}

struct ContentView: View {
    @State private var items: [Item] = []
    @State private var summary = ""

    var body: some View {
        List(items.prefix(20)) { item in
            HStack {
                Text(item.name)
                Spacer()
                Text("\(item.score)")
            }
        }
        .overlay(Text(summary))
        .onAppear {
            items = makeItems(600)
            summary = crunch(items)
        }
    }
}
