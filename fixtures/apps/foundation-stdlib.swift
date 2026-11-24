// Name: Day Planner
// Icon: calendar.badge.clock
// Tint: teal
// Covers: Foundation, Language, Concurrency

import SwiftUI
import Combine
import CryptoKit
import OSLog

// Round 2C's fixture: Foundation and the standard library as a planner uses
// them. Calendar and DateComponents, format styles, Duration, Combine,
// NotificationCenter, Logger, Dispatch, the system's values, CryptoKit and
// the language features (callAsFunction, key paths, Result, fixed-width
// integers, a seeded generator).

struct Slot: Identifiable, Hashable {
    let id: Int
    var title: String
    var start: DateComponents
    var minutes: Int
}

struct Rounder {
    let step: Int
    func callAsFunction(_ minutes: Int) -> Int { (minutes + step - 1) / step * step }
}

struct Seeded: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

final class Planner: ObservableObject {
    @Published var query = ""
    @Published var slots: [Slot] = [
        Slot(id: 0, title: "Standup", start: DateComponents(hour: 9, minute: 30), minutes: 15),
        Slot(id: 1, title: "Design review", start: DateComponents(hour: 11, minute: 0), minutes: 50),
        Slot(id: 2, title: "Lunch", start: DateComponents(hour: 12, minute: 30), minutes: 45),
        Slot(id: 3, title: "Focus time", start: DateComponents(hour: 14, minute: 0), minutes: 120),
    ]
    private var bag = Set<AnyCancellable>()
    let log = Logger(subsystem: "app.dayplanner", category: "planner")

    init() {
        $query
            .removeDuplicates()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] q in self?.log.info("search: \(q)") }
            .store(in: &bag)
    }
}

enum PlanError: Error { case overbooked(Int) }

extension Notification.Name {
    static let planChanged = Notification.Name("planChanged")
}

struct ContentView: View {
    @StateObject private var planner = Planner()
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var changes = 0
    @State private var group = DispatchGroup()
    @State private var loaded = "Loading…"

    private let rounder = Rounder(step: 15)
    private let calendar = Calendar.current

    var visible: [Slot] {
        let q = planner.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let found = q.isEmpty ? planner.slots : planner.slots.filter { $0.title.localizedCaseInsensitiveContains(q) }
        return found.sorted(using: KeyPathComparator(\.start.hour))
    }

    func date(_ slot: Slot) -> Date {
        calendar.date(bySettingHour: slot.start.hour ?? 0, minute: slot.start.minute ?? 0, second: 0, of: day) ?? day
    }

    var booked: Result<Int, PlanError> {
        let total = planner.slots.map { rounder($0.minutes) }.reduce(0, +)
        return total > 8 * 60 ? .failure(.overbooked(total)) : .success(total)
    }

    var summary: String {
        switch booked {
        case .success(let m): return Duration.seconds(m * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
        case .failure(.overbooked(let m)): return "Overbooked by \(m - 480) min"
        }
    }

    var week: String {
        let interval = calendar.dateInterval(of: .weekOfYear, for: day)!
        let days = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0
        return "\(interval.start.formatted(.dateTime.month(.abbreviated).day())), \(days) days"
    }

    var tag: String {
        var g = Seeded(state: UInt64(planner.slots.count))
        let n = UInt8(truncatingIfNeeded: g.next())
        let digest = SHA256.hash(data: Data(planner.slots.map(\.title).joined().utf8))
        return "\(n &+ 7)-" + digest.prefix(3).map { String(format: "%02x", $0) }.joined()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Day", value: day.formatted(date: .complete, time: .omitted))
                    LabeledContent("Week", value: week)
                    LabeledContent("Booked", value: summary)
                    LabeledContent("Tag", value: tag)
                    LabeledContent("Device", value: "\(UIDevice.current.model), \(ProcessInfo.processInfo.processorCount) cores")
                    LabeledContent("Loaded", value: loaded)
                    LabeledContent("Changes", value: "\(changes)")
                }
                Section("Schedule") {
                    ForEach(visible) { slot in
                        HStack {
                            Text(slot.title)
                            Spacer()
                            Text(date(slot).formatted(.dateTime.hour().minute()))
                                .monospacedDigit()
                            Text(Duration.seconds(rounder(slot.minutes) * 60).formatted(.time(pattern: .hourMinute)))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Button("Tomorrow") {
                        day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
                        NotificationCenter.default.post(name: .planChanged, object: nil)
                    }
                    Button("Add break") {
                        planner.slots.append(Slot(id: planner.slots.count, title: "Break \(planner.slots.count)",
                                                  start: DateComponents(hour: 16, minute: 0), minutes: 10))
                        NotificationCenter.default.post(name: .planChanged, object: nil)
                    }
                }
            }
            .searchable(text: $planner.query)
            .navigationTitle("Day Planner")
            .onReceive(NotificationCenter.default.publisher(for: .planChanged)) { _ in changes += 1 }
            .onAppear {
                group.enter()
                DispatchQueue.main.async {
                    loaded = "\(Bundle.main.bundleIdentifier?.isEmpty == false ? "ready" : "ready") at \(Date.now.formatted(date: .omitted, time: .shortened))"
                    group.leave()
                }
                group.notify(queue: .main) { planner.log.debug("loaded") }
            }
        }
    }
}
