// Name: Reading Log
// Icon: books.vertical.fill
// Tint: indigo

import SwiftUI

protocol Shelved {
    var title: String { get }
    var pages: Int { get }
}

extension Shelved {
    var summary: String { "\(title), \(pages) pages" }
    func hours(atPagesPerHour rate: Int = 40) -> Double { Double(pages) / Double(rate) }
}

extension Shelved where Self: Comparable {
    var rankLabel: String { "ranked " + title }
}

protocol Rated: Shelved {
    var stars: Int { get }
}

extension Rated {
    var starText: String { String(repeating: "★", count: stars) }
}

enum Genre: String, CaseIterable, Identifiable {
    case fiction = "Fiction"
    case history = "History"
    case science = "Science"

    var id: String { rawValue }
}

struct Book: Rated, Identifiable, Hashable, Comparable {
    var id: Int
    var title: String
    var pages: Int
    var stars: Int
    var genre: Genre

    // Two copies of the same book are the same book.
    static func == (a: Book, b: Book) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func < (a: Book, b: Book) -> Bool { a.title < b.title }
}

struct Magazine: Shelved {
    var title: String
    var pages: Int
}

class Reader {
    let name: String
    init(name: String) { self.name = name }
    func greeting() -> String { "Happy reading, \(name)" }
}

final class Member: Reader {
    let since: Int
    init(name: String, since: Int) {
        self.since = since
        super.init(name: name)
    }
    override func greeting() -> String { super.greeting() + " (member since \(since))" }
}

extension Collection where Element: Shelved {
    var totalPages: Int { reduce(0) { $0 + $1.pages } }
}

func badge(for pages: Int) -> String {
    switch pages {
    case 500...: return "Epic"
    case 200..<500: return "Novel"
    case ..<50: return "Short"
    default: return "Novella"
    }
}

func longest<T: Shelved>(_ items: [T]) -> T? {
    items.max { $0.pages < $1.pages }
}

struct ContentView: View {
    @State private var books: [Book] = [
        Book(id: 1, title: "Dune", pages: 612, stars: 5, genre: .fiction),
        Book(id: 2, title: "SPQR", pages: 448, stars: 4, genre: .history),
        Book(id: 3, title: "Cosmos", pages: 384, stars: 4, genre: .science),
    ]
    @State private var log: [String] = []

    private var shelf: [any Shelved] {
        books + [Magazine(title: "Wired", pages: 30)]
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Books") {
                    ForEach(books.sorted()) { book in
                        VStack(alignment: .leading) {
                            Text(book.summary)
                            Text("\(book.starText) · \(badge(for: book.pages)) · \(book.rankLabel)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Shelf") {
                    ForEach(Array(shelf.enumerated()), id: \.offset) { _, item in
                        LabeledContent(item.title, value: badge(for: item.pages))
                    }
                    LabeledContent("Pages", value: "\(books.totalPages)")
                    LabeledContent("Longest", value: longest(books)?.title ?? "None")
                    LabeledContent("Genres", value: Genre.allCases.map(\.rawValue).joined(separator: ", "))
                }
                Section {
                    Button("Add a duplicate of Dune") {
                        let copy = Book(id: 1, title: "Dune (paperback)", pages: 612, stars: 5, genre: .fiction)
                        let unique = Set(books + [copy])
                        log.append("Unique: \(unique.count); same book: \(copy == books[0])")
                    }
                    Button("Reading time") {
                        let hours = books.map { $0.hours() }.reduce(0, +)
                        log.append("Hours: \(Int(hours))")
                        log.append(Member(name: "Ann", since: 2020).greeting())
                        let magazines = shelf.filter { $0 is Magazine }.count
                        log.append("Magazines: \(magazines)")
                    }
                    ForEach(log, id: \.self) { Text($0).font(.caption) }
                }
            }
            .navigationTitle("Reading Log")
        }
    }
}
