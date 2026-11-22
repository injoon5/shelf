// Name: Reading Log
// Icon: books.vertical.fill
// Tint: purple

import SwiftUI

enum Shelf: String, Codable, CaseIterable, Identifiable {
    case reading
    case finished
    case wishlist
    var id: String { rawValue }
}

struct Progress: Codable, Equatable {
    var page: Int = 0
    var total: Int = 0
}

struct Book: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String = ""
    var author: String? = nil
    var shelf: Shelf = .reading
    var added = Date()
    var progress = Progress()
    var rating: Int? = nil
    var tags: [String] = []
}

struct ContentView: View {
    @AppStorage("showFinished") private var showFinished = true
    @AppStorage("sortTitle") private var sortTitle = "added"
    @AppStorage("dailyPages") private var dailyPages = 20
    @AppStorage("fontScale") private var fontScale = 1.0

    @State private var books: [Book] = []
    @State private var notes: [String: String] = [:]
    @State private var loadFailed = false
    @State private var draft = ""

    var visible: [Book] {
        let list = showFinished ? books : books.filter { $0.shelf != .finished }
        return sortTitle == "title" ? list.sorted { $0.title < $1.title } : list
    }

    var body: some View {
        NavigationStack {
            List {
                if loadFailed {
                    Label("Saved books couldn't be read, so changes aren't saved.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Section("Books") {
                    ForEach(visible) { book in
                        VStack(alignment: .leading) {
                            Text(book.title).font(.headline)
                            Text(book.author ?? "Unknown author")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if book.progress.total > 0 {
                                ProgressView(value: Double(book.progress.page), total: Double(book.progress.total))
                            }
                            if let note = notes[book.id.uuidString] {
                                Text(note).font(.caption)
                            }
                        }
                        .swipeActions {
                            Button("Finished") { finish(book) }
                        }
                    }
                    .onDelete { offsets in
                        books.remove(atOffsets: offsets)
                    }
                    HStack {
                        TextField("Title", text: $draft)
                        Button("Add") {
                            books.append(Book(title: draft.isEmpty ? "Untitled" : draft, tags: ["new"]))
                            draft = ""
                        }
                    }
                }
                Section("Settings") {
                    Toggle("Show finished", isOn: $showFinished)
                    Picker("Sort", selection: $sortTitle) {
                        Text("Added").tag("added")
                        Text("Title").tag("title")
                    }
                    Stepper("\(dailyPages) pages a day", value: $dailyPages, in: 5...200, step: 5)
                    Slider(value: $fontScale, in: 0.8...1.4)
                    Button("Clear Notes", role: .destructive) {
                        notes = [:]
                        DB.remove("notes")
                    }
                }
            }
            .navigationTitle("Reading Log")
            .onAppear(perform: load)
            .onChange(of: books) {
                if !loadFailed, let data = try? JSONEncoder().encode(books) {
                    DB.save("books", data)
                }
            }
            .onChange(of: notes) {
                if let data = try? JSONEncoder().encode(notes) {
                    DB.save("notes", data)
                }
            }
        }
    }

    func load() {
        if let data = DB.load("books") {
            if let saved = try? JSONDecoder().decode([Book].self, from: data) {
                books = saved
            } else {
                loadFailed = true
            }
        }
        if let data = DB.load("notes"), let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            notes = saved
        }
    }

    func finish(_ book: Book) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index].shelf = .finished
        books[index].progress.page = books[index].progress.total
        notes[book.id.uuidString] = "Finished on \(Date().formatted(date: .abbreviated, time: .omitted))"
    }
}
