// Name: Pantry
// Icon: cart.fill
// Tint: orange
// Covers: Language

import SwiftUI

enum Aisle: String, CaseIterable, Codable, Identifiable {
    case produce = "Produce"
    case dairy = "Dairy"
    case bakery = "Bakery"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .produce: return "leaf"
        case .dairy: return "drop"
        case .bakery: return "birthday.cake"
        }
    }
}

enum Amount {
    case count(Int)
    case weight(grams: Double)
    case none

    func describe() -> String {
        switch self {
        case .count(let n) where n > 1: return "\(n) pieces"
        case .count(let n): return "\(n) piece"
        case .weight(let g) where g >= 1000: return "\(g / 1000) kg"
        case .weight(let g): return "\(Int(g)) g"
        case .none: return "—"
        }
    }
}

enum PantryError: Error {
    case emptyName
}

struct Item: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var aisle: Aisle = .produce
    var quantity: Int = 1 {
        didSet { if quantity < 0 { quantity = 0 } }
    }
    var bought: Date? = nil

    mutating func use() {
        quantity -= 1
    }
}

struct Budget {
    var limit: Double
    var spent: Double

    init(limit: Double) {
        self.limit = limit
        self.spent = 0
    }

    var remaining: Double { limit - spent }
}

class Counter {
    var total = 0
    func bump() { total += 1 }
}

extension Item {
    var label: String { "\(name) × \(quantity)" }
}

extension Int {
    var doubled: Int { self * 2 }
}

func makeItem(_ name: String) throws -> Item {
    guard !name.isEmpty else { throw PantryError.emptyName }
    return Item(name: name)
}

func firstLong(_ names: [String]) -> String? {
    var queue = Array(names.reversed())
    while let next = queue.popLast() {
        if next.count > 4 { return next }
    }
    return nil
}

struct ContentView: View {
    @State private var items: [Item] = [
        Item(name: "Apples", aisle: .produce, quantity: 3),
        Item(name: "Milk", aisle: .dairy),
        Item(name: "Bread", aisle: .bakery, quantity: 2),
    ]
    @State private var budget = Budget(limit: 40)
    @State private var message = ""
    @State private var log: [String] = []

    private let counter = Counter()

    var summary: (count: Int, total: Int) {
        (count: items.count, total: items.reduce(0) { $0 + $1.quantity })
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Items") {
                    ForEach(items) { item in
                        HStack {
                            Image(systemName: item.aisle.symbol)
                            Text(item.label)
                            Spacer()
                            Text(item.bought?.formatted(date: .abbreviated, time: .omitted) ?? "Not bought")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("By aisle") {
                    ForEach(Aisle.allCases) { aisle in
                        let names = items.filter { $0.aisle == aisle }.map(\.name)
                        LabeledContent(aisle.rawValue, value: names.isEmpty ? "None" : names.joined(separator: ", "))
                    }
                }
                Section("Details") {
                    LabeledContent("Items", value: "\(summary.count)")
                    LabeledContent("Units", value: "\(summary.total)")
                    LabeledContent("Doubled", value: "\(summary.total.doubled)")
                    LabeledContent("Left", value: budget.remaining.formatted(.currency(code: "USD")))
                    LabeledContent("Average", value: "\(Double(summary.total) / Double(max(summary.count, 1)))")
                    LabeledContent("Amounts", value: [Amount.count(3), .count(1), .weight(grams: 1500), .weight(grams: 250), .none].map { $0.describe() }.joined(separator: ", "))
                    LabeledContent("Long name", value: firstLong(items.map(\.name)) ?? "None")
                    LabeledContent("Range", value: (1...3).map { String($0) }.joined(separator: "-"))
                    if !message.isEmpty {
                        Text(message).foregroundStyle(.red)
                    }
                    ForEach(log, id: \.self) { line in
                        Text(line).font(.caption)
                    }
                }
                Section {
                    Button("Use one apple") {
                        if let index = items.firstIndex(where: { $0.name == "Apples" }) {
                            items[index].use()
                            items[index].bought = Date()
                        }
                        counter.bump()
                        budget.spent += 2.5
                    }
                    Button("Add empty item") {
                        do {
                            items.append(try makeItem(""))
                        } catch PantryError.emptyName {
                            message = "Give the item a name."
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                    Button("Run checks") {
                        defer { log.append("Checks done") }
                        let pair = (name: "Eggs", count: 12)
                        let (a, b) = (1, 2)
                        let half = pair.count / 5
                        let exact = Double(pair.count) / 5
                        log.append("\(pair.name) \(pair.count) \(a + b) \(half) \(exact)")
                        let sorted = items.sorted { $0.quantity > $1.quantity }
                        log.append(sorted.first?.name ?? "")
                        let maybe: String? = nil
                        log.append(maybe?.uppercased() ?? "nil")
                        let today = Calendar.current.startOfDay(for: Date())
                        let formatter = DateFormatter()
                        formatter.dateStyle = .medium
                        log.append(formatter.string(from: today))
                        if let next = Calendar.current.date(byAdding: .day, value: 1, to: today) {
                            log.append(next.formatted(.dateTime.weekday(.wide)))
                        }
                        switch pair.count {
                        case 0..<10: log.append("few")
                        case 10..<100: log.append("many")
                        default: break
                        }
                        log.append("Taps \(counter.total)")
                    }
                }
            }
            .navigationTitle("Pantry")
        }
    }
}
