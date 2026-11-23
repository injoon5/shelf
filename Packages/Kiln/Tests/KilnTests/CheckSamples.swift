//
//  CheckSamples.swift
//  KilnTests
//
//  Apps written the way chat models write them for Shelf, for the checker's
//  false-positive guard (`CheckTests.testModelWrittenAppsCheckClean`, and
//  `CheckCorpusTests`, which reads every app in these tests).
//

enum CheckSamples {
    static let apps: [(String, String)] = [("habits", habits), ("expenses", expenses), ("timer", timer),
                                           ("quotes", quotes), ("notes", notes), ("game", game)]

    static let habits = #"""
    import SwiftUI

    struct Habit: Identifiable, Codable, Equatable {
        var id = UUID()
        var name: String
        var icon: String = "star.fill"
        var completedDates: [Date] = []

        var streak: Int {
            var count = 0
            var day = Calendar.current.startOfDay(for: Date())
            while completedDates.contains(where: { Calendar.current.isDate($0, inSameDayAs: day) }) {
                count += 1
                day = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
            }
            return count
        }

        func isDone(on date: Date) -> Bool {
            completedDates.contains { Calendar.current.isDate($0, inSameDayAs: date) }
        }
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case name = "Name"
        case streak = "Streak"
        var id: String { rawValue }
    }

    struct ContentView: View {
        @State private var habits: [Habit] = [Habit(name: "Read"), Habit(name: "Walk", icon: "figure.walk")]
        @State private var showingAdd = false
        @State private var newName = ""
        @State private var sort: SortOrder = .name
        @AppStorage("showStreaks") private var showStreaks = true

        private var sorted: [Habit] {
            switch sort {
            case .name: return habits.sorted { $0.name < $1.name }
            case .streak: return habits.sorted { $0.streak > $1.streak }
            }
        }

        var body: some View {
            NavigationStack {
                List {
                    Section {
                        Picker("Sort", selection: $sort) {
                            ForEach(SortOrder.allCases) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                        .pickerStyle(.segmented)
                        Toggle("Show Streaks", isOn: $showStreaks)
                    }
                    Section("Today") {
                        ForEach(sorted) { habit in
                            HStack {
                                Image(systemName: habit.icon)
                                    .foregroundStyle(.tint)
                                    .frame(width: 28)
                                VStack(alignment: .leading) {
                                    Text(habit.name).font(.headline)
                                    if showStreaks {
                                        Text("\(habit.streak) day streak")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button {
                                    toggle(habit)
                                } label: {
                                    Image(systemName: habit.isDone(on: Date()) ? "checkmark.circle.fill" : "circle")
                                        .font(.title2)
                                }
                                .buttonStyle(.plain)
                            }
                            .swipeActions {
                                Button("Delete", role: .destructive) { delete(habit) }
                            }
                        }
                        .onDelete { offsets in habits.remove(atOffsets: offsets) }
                    }
                }
                .navigationTitle("Habits")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showingAdd = true } label: { Label("Add", systemImage: "plus") }
                    }
                }
                .sheet(isPresented: $showingAdd) {
                    NavigationStack {
                        Form {
                            TextField("Name", text: $newName)
                        }
                        .navigationTitle("New Habit")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingAdd = false } }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Add") {
                                    habits.append(Habit(name: newName.trimmingCharacters(in: .whitespaces)))
                                    newName = ""
                                    showingAdd = false
                                }
                                .disabled(newName.isEmpty)
                            }
                        }
                    }
                    .presentationDetents([.medium])
                }
                .overlay {
                    if habits.isEmpty {
                        ContentUnavailableView("No Habits", systemImage: "list.bullet", description: Text("Add one with +."))
                    }
                }
            }
        }

        private func toggle(_ habit: Habit) {
            guard let index = habits.firstIndex(where: { $0.id == habit.id }) else { return }
            if habit.isDone(on: Date()) {
                habits[index].completedDates.removeAll { Calendar.current.isDate($0, inSameDayAs: Date()) }
            } else {
                withAnimation { habits[index].completedDates.append(Date()) }
            }
        }

        private func delete(_ habit: Habit) {
            habits.removeAll { $0.id == habit.id }
        }
    }
    """#

    static let expenses = #"""
    import SwiftUI
    import Charts

    struct Expense: Identifiable, Codable {
        var id = UUID()
        var title: String
        var amount: Double
        var category: Category
        var date = Date()
    }

    enum Category: String, Codable, CaseIterable, Identifiable {
        case food, travel, fun
        var id: Self { self }
        var color: Color {
            switch self {
            case .food: return .orange
            case .travel: return .blue
            case .fun: return .purple
            }
        }
        var symbol: String {
            switch self {
            case .food: "fork.knife"
            case .travel: "airplane"
            case .fun: "gamecontroller"
            }
        }
    }

    @Observable
    final class ExpenseStore {
        var expenses: [Expense] = []
        var total: Double { expenses.reduce(0) { $0 + $1.amount } }

        func add(_ title: String, _ amount: Double, _ category: Category) {
            expenses.append(Expense(title: title, amount: amount, category: category))
        }

        func total(for category: Category) -> Double {
            expenses.filter { $0.category == category }.map(\.amount).reduce(0, +)
        }
    }

    struct ContentView: View {
        @State private var store = ExpenseStore()
        @State private var title = ""
        @State private var amount = 0.0
        @State private var category: Category = .food

        var body: some View {
            NavigationStack {
                Form {
                    Section("Spent") {
                        Text(store.total, format: .currency(code: "USD"))
                            .font(.largeTitle.bold())
                        Chart(Category.allCases) { category in
                            BarMark(x: .value("Category", category.rawValue.capitalized),
                                    y: .value("Total", store.total(for: category)))
                                .foregroundStyle(category.color)
                        }
                        .frame(height: 160)
                    }
                    Section("Add") {
                        TextField("Title", text: $title)
                        TextField("Amount", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                        Picker("Category", selection: $category) {
                            ForEach(Category.allCases) { c in
                                Label(c.rawValue.capitalized, systemImage: c.symbol).tag(c)
                            }
                        }
                        Button("Add Expense") {
                            store.add(title, amount, category)
                            title = ""
                            amount = 0
                        }
                        .disabled(title.isEmpty || amount <= 0)
                    }
                    Section("Recent") {
                        ForEach(store.expenses.reversed()) { e in
                            LabeledContent(e.title) {
                                Text(e.amount, format: .currency(code: "USD"))
                            }
                        }
                    }
                }
                .navigationTitle("Expenses")
            }
        }
    }
    """#

    static let timer = #"""
    import SwiftUI

    struct ContentView: View {
        @State private var remaining = 25 * 60
        @State private var running = false
        @State private var sessions = 0
        let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

        var progress: Double { 1 - Double(remaining) / Double(25 * 60) }

        var timeText: String {
            String(format: "%02d:%02d", remaining / 60, remaining % 60)
        }

        var body: some View {
            VStack(spacing: 32) {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 16)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.red, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: progress)
                    Text(timeText)
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(width: 260, height: 260)

                HStack(spacing: 20) {
                    Button(running ? "Pause" : "Start") { running.toggle() }
                        .buttonStyle(.borderedProminent)
                    Button("Reset", role: .destructive) {
                        running = false
                        remaining = 25 * 60
                    }
                    .buttonStyle(.bordered)
                }
                Text("Sessions: \(sessions)")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .onReceive(timer) { _ in
                guard running else { return }
                if remaining > 0 {
                    remaining -= 1
                } else {
                    running = false
                    sessions += 1
                    remaining = 25 * 60
                }
            }
        }
    }
    """#

    static let quotes = #"""
    import SwiftUI

    struct Quote: Codable, Identifiable {
        let id = UUID()
        let text: String
        let author: String

        enum CodingKeys: String, CodingKey {
            case text = "q"
            case author = "a"
        }
    }

    enum LoadState {
        case idle, loading, loaded([Quote]), failed(String)
    }

    struct ContentView: View {
        @State private var state: LoadState = .idle

        var body: some View {
            NavigationStack {
                Group {
                    switch state {
                    case .idle, .loading:
                        ProgressView("Loading…")
                    case .loaded(let quotes):
                        List(quotes) { quote in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("“\(quote.text)”")
                                Text("— \(quote.author)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    case .failed(let message):
                        ContentUnavailableView("Couldn't Load", systemImage: "wifi.slash", description: Text(message))
                    }
                }
                .navigationTitle("Quotes")
                .task { await load() }
                .refreshable { await load() }
            }
        }

        func load() async {
            state = .loading
            do {
                guard let url = URL(string: "https://zenquotes.io/api/quotes") else { return }
                let (data, _) = try await URLSession.shared.data(from: url)
                let quotes = try JSONDecoder().decode([Quote].self, from: data)
                state = .loaded(quotes)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
    """#

    static let notes = #"""
    import SwiftUI

    struct Note: Identifiable, Codable, Hashable {
        var id = UUID()
        var title: String = ""
        var body: String = ""
        var pinned = false
        var updated = Date()
    }

    class NotesModel: ObservableObject {
        @Published var notes: [Note] = []
        @Published var search = ""

        var filtered: [Note] {
            let list = search.isEmpty ? notes : notes.filter { $0.title.localizedCaseInsensitiveContains(search) }
            return list.sorted { ($0.pinned ? 1 : 0, $0.updated) > ($1.pinned ? 1 : 0, $1.updated) }
        }

        func add() -> Note {
            let note = Note(title: "New Note")
            notes.insert(note, at: 0)
            return note
        }
    }

    struct NoteEditor: View {
        @Binding var note: Note
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            Form {
                TextField("Title", text: $note.title)
                TextEditor(text: $note.body)
                    .frame(minHeight: 200)
                Toggle("Pinned", isOn: $note.pinned)
            }
            .navigationTitle(note.title.isEmpty ? "Untitled" : note.title)
            .onChange(of: note.body) { note.updated = Date() }
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }

    struct ContentView: View {
        @StateObject private var model = NotesModel()
        @State private var path: [UUID] = []

        var body: some View {
            NavigationStack {
                List {
                    ForEach($model.notes) { $note in
                        NavigationLink {
                            NoteEditor(note: $note)
                        } label: {
                            HStack {
                                if note.pinned { Image(systemName: "pin.fill").foregroundStyle(.orange) }
                                VStack(alignment: .leading) {
                                    Text(note.title).font(.headline)
                                    Text(note.updated, style: .relative).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .contextMenu {
                            Button(note.pinned ? "Unpin" : "Pin") { note.pinned.toggle() }
                        }
                    }
                    .onDelete { model.notes.remove(atOffsets: $0) }
                }
                .searchable(text: $model.search)
                .navigationTitle("Notes")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { _ = model.add() } label: { Image(systemName: "square.and.pencil") }
                    }
                }
            }
        }
    }
    """#

    static let game = #"""
    import SwiftUI

    struct Card: Identifiable {
        let id: Int
        let symbol: String
        var isFaceUp = false
        var isMatched = false
    }

    struct CardView: View {
        let card: Card

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(card.isFaceUp || card.isMatched ? Color.white : Color.blue)
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.blue, lineWidth: 2)
                if card.isFaceUp || card.isMatched {
                    Text(card.symbol).font(.largeTitle)
                }
            }
            .aspectRatio(2/3, contentMode: .fit)
            .opacity(card.isMatched ? 0.4 : 1)
            .rotation3DEffect(.degrees(card.isFaceUp ? 0 : 180), axis: (x: 0, y: 1, z: 0))
        }
    }

    struct ContentView: View {
        @State private var cards: [Card] = []
        @State private var firstIndex: Int?
        @State private var moves = 0
        private let symbols = ["🍎", "🍌", "🍇", "🍒", "🥝", "🍋"]
        private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

        var won: Bool { !cards.isEmpty && cards.allSatisfy(\.isMatched) }

        var body: some View {
            VStack {
                HStack {
                    Text("Moves: \(moves)").font(.headline)
                    Spacer()
                    Button("New Game", action: deal)
                }
                .padding(.horizontal)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(cards.indices, id: \.self) { i in
                        CardView(card: cards[i])
                            .onTapGesture { flip(i) }
                    }
                }
                .padding()
                if won {
                    Text("You won in \(moves) moves!")
                        .font(.title2.bold())
                        .transition(.scale.combined(with: .opacity))
                }
                Spacer()
            }
            .onAppear(perform: deal)
        }

        func deal() {
            cards = (symbols + symbols).shuffled().enumerated().map { Card(id: $0.offset, symbol: $0.element) }
            firstIndex = nil
            moves = 0
        }

        func flip(_ i: Int) {
            guard !cards[i].isFaceUp, !cards[i].isMatched else { return }
            withAnimation(.easeInOut(duration: 0.3)) { cards[i].isFaceUp = true }
            if let first = firstIndex {
                moves += 1
                if cards[first].symbol == cards[i].symbol {
                    cards[first].isMatched = true
                    cards[i].isMatched = true
                    firstIndex = nil
                } else {
                    firstIndex = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        withAnimation {
                            cards[first].isFaceUp = false
                            cards[i].isFaceUp = false
                        }
                    }
                }
            } else {
                firstIndex = i
            }
        }
    }
    """#
}
