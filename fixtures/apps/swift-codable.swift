// Name: Expenses Import
// Icon: tray.and.arrow.down.fill
// Tint: green

import SwiftUI

enum Payment: Codable, Equatable {
    case cash
    case card(last4: String)

    enum CodingKeys: String, CodingKey { case kind, last4 }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "cash": self = .cash
        case "card": self = .card(last4: try c.decode(String.self, forKey: .last4))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "Unknown payment")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .cash: try c.encode("cash", forKey: .kind)
        case .card(let last4):
            try c.encode("card", forKey: .kind)
            try c.encode(last4, forKey: .last4)
        }
    }
}

struct Expense: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var cents: Int
    var payment: Payment
    var tags: Set<String> = []

    enum CodingKeys: String, CodingKey { case id, title, cents = "amount_cents", payment, tags }

    init(title: String, cents: Int, payment: Payment, tags: Set<String> = []) {
        self.title = title
        self.cents = cents
        self.payment = payment
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        cents = try c.decode(Int.self, forKey: .cents)
        payment = try c.decodeIfPresent(Payment.self, forKey: .payment) ?? .cash
        tags = try c.decodeIfPresent(Set<String>.self, forKey: .tags) ?? []
    }
}

/// "Lunch 12.50 #food #work" → an expense.
func parse(_ line: String) -> Expense? {
    guard let m = line.firstMatch(of: /^(?<title>[A-Za-z ]+?)\s+(?<dollars>\d+)\.(?<cents>\d{2})/) else { return nil }
    let tags = Set(line.matches(of: /#(\w+)/).map { String($0.1) })
    let cents = (Int(String(m.dollars)) ?? 0) * 100 + (Int(String(m.cents)) ?? 0)
    return Expense(title: String(m.title), cents: cents, payment: line.contains(/card/) ? .card(last4: "4242") : .cash, tags: tags)
}

struct ContentView: View {
    @State private var expenses: [Expense] = []
    @State private var log: [String] = []

    private let input = """
        Lunch 12.50 #food #work
        Train 3.20 card #travel
        not an expense
        """

    var total: Int { expenses.reduce(0) { $0 + $1.cents } }

    var body: some View {
        NavigationStack {
            List {
                Section("Imported") {
                    ForEach(expenses) { e in
                        LabeledContent(e.title, value: (Double(e.cents) / 100).formatted(.currency(code: "USD")))
                    }
                    LabeledContent("Total", value: (Double(total) / 100).formatted(.currency(code: "USD")))
                }
                Section {
                    Button("Import") {
                        expenses = input.split(separator: "\n").compactMap { parse(String($0)) }
                        log.append("Imported \(expenses.count)")
                    }
                    Button("Round trip") {
                        do {
                            let data = try JSONEncoder().encode(expenses)
                            let back = try JSONDecoder().decode([Expense].self, from: data)
                            log.append("Same: \(back == expenses), tags are a set: \(back.first?.tags is Set<String>)")
                        } catch {
                            log.append(error.localizedDescription)
                        }
                    }
                    Button("Read old data") {
                        let old = Data(#"[{"title":"Old","amount_cents":500}]"#.utf8)
                        let read = (try? JSONDecoder().decode([Expense].self, from: old)) ?? []
                        log.append("Old: \(read.first?.title ?? "none") \(read.first?.payment == .cash)")
                        let bad = Data(#"{"kind":"cheque"}"#.utf8)
                        do { _ = try JSONDecoder().decode(Payment.self, from: bad) } catch { log.append("Rejected cheque") }
                    }
                    ForEach(log, id: \.self) { Text($0).font(.caption) }
                }
            }
            .navigationTitle("Expenses Import")
        }
    }
}
