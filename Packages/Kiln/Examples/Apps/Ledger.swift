import SwiftUI
import Combine
import CryptoKit

// Round 2C in one app: Foundation and the standard library. Calendar and
// DateComponents, format styles, Decimal, collections (grouping, merging,
// KeyPathComparator, difference, zip), a seeded RandomNumberGenerator,
// fixed-width integers, CryptoKit, Combine, and the language features apps
// lean on (callAsFunction, @dynamicMemberLookup, key paths, subscript
// setters, labeled tuples, Result). Every value is fixed, so the native app
// and Kiln show the same screen.

enum Category: String, CaseIterable, Identifiable, Comparable {
    case food = "Food", travel = "Travel", home = "Home", fun = "Fun"
    var id: String { rawValue }
    static func < (a: Category, b: Category) -> Bool { a.rawValue < b.rawValue }
}

struct Expense: Identifiable, Equatable {
    var id: Int
    var title: String
    var amount: Decimal
    var category: Category
    var day: Int
}

/// The same numbers every run: a linear congruential generator.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

/// `budget(…)` reads as a call.
struct Budget {
    var limit: Decimal
    func callAsFunction(_ spent: Decimal) -> Decimal { limit - spent }
}

/// Settings read by name, through a key path.
struct Settings {
    var currency = "USD"
    var showCents = true
}

@dynamicMemberLookup
struct Preferences {
    var settings = Settings()
    subscript<T>(dynamicMember path: WritableKeyPath<Settings, T>) -> T {
        get { settings[keyPath: path] }
        set { settings[keyPath: path] = newValue }
    }
}

/// Totals by category, with a subscript that writes.
struct Totals {
    var values: [Category: Decimal] = [:]
    subscript(_ c: Category) -> Decimal {
        get { values[c] ?? 0 }
        set { values[c] = newValue }
    }
}

/// The days of a month, as a sequence of its own.
struct MonthDays: Sequence, IteratorProtocol {
    let count: Int
    var day = 0
    mutating func next() -> Int? {
        day += 1
        return day <= count ? day : nil
    }
}

final class Activity: ObservableObject {
    @Published var changes = 0
}

enum LedgerError: Error { case empty }

struct ContentView: View {
    @State private var expenses: [Expense] = ContentView.sample(seed: 7)
    @State private var monthOffset = 0
    @State private var previous: [Int] = []
    @State private var lastChange = "No changes yet"
    @State private var prefs = Preferences()
    @StateObject private var activity = Activity()
    private let edits = PassthroughSubject<String, Never>()

    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    static func sample(seed: UInt64) -> [Expense] {
        var g = SeededGenerator(state: seed)
        let titles = ["Groceries", "Train", "Lamp", "Cinema", "Coffee", "Hotel", "Plants", "Concert"]
        return titles.enumerated().map { i, title in
            let cents = Int.random(in: 300...9_000, using: &g)
            let category = Category.allCases[Int(g.next() % 4)]
            return Expense(id: i, title: title, amount: Decimal(cents) / 100, category: category, day: i * 3 + 1)
        }
    }

    var monthStart: Date {
        let base = Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        return Self.calendar.date(byAdding: .month, value: monthOffset, to: base)!
    }

    var monthTitle: String {
        let f = DateFormatter()
        f.timeZone = Self.calendar.timeZone
        f.dateFormat = "MMMM yyyy"
        return f.string(from: monthStart)
    }

    var daysInMonth: Int { Self.calendar.range(of: .day, in: .month, for: monthStart)!.count }

    var weekdays: String {
        let first = Self.calendar.component(.weekday, from: monthStart)
        return Self.calendar.shortWeekdaySymbols[first - 1]
    }

    var total: Decimal { expenses.reduce(0) { $0 + $1.amount } }

    var totals: Totals {
        var t = Totals()
        for e in expenses { t[e.category] += e.amount }
        return t
    }

    var spread: (smallest: Decimal, largest: Decimal) {
        let amounts = expenses.map(\.amount)
        return (amounts.min() ?? 0, amounts.max() ?? 0)
    }

    var byCategory: [Category: [Expense]] { Dictionary(grouping: expenses, by: \.category) }

    var sorted: [Expense] { expenses.sorted(using: [KeyPathComparator(\.amount, order: .reverse), KeyPathComparator(\.title)]) }

    var checksum: UInt8 { expenses.map(\.title).joined().utf8.reduce(UInt8(0)) { $0 &+ $1 } }

    var fingerprint: String {
        let digest = SHA256.hash(data: Data(expenses.map(\.title).joined(separator: ",").utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    var busiestDay: String {
        let counts = expenses.reduce(into: [Int: Int]()) { $0[$1.day % 7, default: 0] += 1 }
        let best = counts.max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }
        return best.map { "day \($0.key)" } ?? "none"
    }

    var change: String {
        let diff = expenses.map(\.id).difference(from: previous)
        return "\(diff.insertions.count) added, \(diff.removals.count) removed"
    }

    var latest: Result<Expense, LedgerError> {
        guard let last = expenses.last else { return .failure(.empty) }
        return .success(last)
    }

    func money(_ d: Decimal) -> String {
        d.formatted(.currency(code: prefs.currency).precision(.fractionLength(prefs.showCents ? 2 : 0)))
    }

    var body: some View {
        NavigationStack {
            List {
                Section(monthTitle) {
                    LabeledContent("Days", value: "\(daysInMonth), starting \(weekdays)")
                    LabeledContent("Week of year", value: "\(Self.calendar.component(.weekOfYear, from: monthStart))")
                    LabeledContent("Days left after the 10th", value: "\(Array(MonthDays(count: daysInMonth)).filter { $0 > 10 }.count)")
                    LabeledContent("Starts", value: monthStart.ISO8601Format())
                }
                Section("Spending") {
                    LabeledContent("Total", value: money(total))
                    LabeledContent("Left of 400", value: money(Budget(limit: 400)(total)))
                    LabeledContent("Range", value: "\(money(spread.smallest)) – \(money(spread.largest))")
                    LabeledContent("Share of food", value: (NSDecimalNumber(decimal: totals[.food]).doubleValue / max(NSDecimalNumber(decimal: total).doubleValue, 1)).formatted(.percent.precision(.fractionLength(1))))
                    LabeledContent("Yearly", value: (NSDecimalNumber(decimal: total).doubleValue * 12).formatted(.number.notation(.compactName)))
                    LabeledContent("Categories", value: byCategory.keys.sorted().map(\.rawValue).formatted(.list(type: .and)))
                }
                Section("By category") {
                    ForEach(Category.allCases) { c in
                        LabeledContent(c.rawValue, value: money(totals[c]))
                    }
                }
                Section("Largest first") {
                    ForEach(Array(zip(1..., sorted.prefix(4))), id: \.1.id) { rank, e in
                        LabeledContent("\(rank). \(e.title)", value: money(e.amount))
                    }
                }
                Section("Checks") {
                    LabeledContent("Checksum", value: "\(checksum)")
                    LabeledContent("Fingerprint", value: fingerprint)
                    LabeledContent("Busiest", value: busiestDay)
                    LabeledContent("Changes", value: "\(activity.changes): \(lastChange)")
                    LabeledContent("Latest", value: (try? latest.get().title) ?? "none")
                    LabeledContent("Report size", value: Int64(expenses.count * 1_536).formatted(.byteCount(style: .file)))
                }
                Section {
                    Toggle("Show cents", isOn: $prefs.showCents)
                    Button("Next month") {
                        monthOffset += 1
                        edits.send("month")
                    }
                    Button("Add coffee") {
                        previous = expenses.map(\.id)
                        expenses.append(Expense(id: expenses.count, title: "Coffee \(expenses.count)", amount: Decimal(string: "3.75")!, category: .food, day: 2))
                        edits.send("coffee")
                    }
                    Button("Reshuffle") {
                        previous = expenses.map(\.id)
                        expenses = Self.sample(seed: UInt64(expenses.count) &* 31)
                        edits.send("reshuffle")
                    }
                }
            }
            .navigationTitle("Ledger")
            .onReceive(edits) { what in
                activity.changes += 1
                lastChange = "\(what), \(change)"
            }
        }
    }
}
