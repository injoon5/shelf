// Name: Reading List
// Icon: books.vertical.fill
// Tint: orange
// Covers: Lists

import SwiftUI

struct Book: Identifiable, Hashable {
    let id: Int
    var title: String
    var author: String
}

struct Shelf: Identifiable {
    let id: Int
    var name: String
    var children: [Shelf]?
}

struct ContentView: View {
    @State private var books = [
        Book(id: 1, title: "Dune", author: "Herbert"),
        Book(id: 2, title: "Emma", author: "Austen"),
        Book(id: 3, title: "Ulysses", author: "Joyce"),
        Book(id: 4, title: "Beloved", author: "Morrison"),
    ]
    @State private var selection = Set<Int>()
    @State private var showsArchive = true
    let shelves = [
        Shelf(id: 10, name: "Fiction", children: [Shelf(id: 11, name: "Classics", children: nil), Shelf(id: 12, name: "Sci-fi", children: nil)]),
        Shelf(id: 20, name: "Poetry", children: nil),
    ]

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                Section("To read") {
                    ForEach($books, editActions: .all) { $book in
                        VStack(alignment: .leading) {
                            Text(book.title).font(.headline)
                            Text(book.author).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .swipeActions(edge: .leading) {
                            Button("Top", systemImage: "arrow.up") { moveToTop(book) }.tint(.orange)
                        }
                        .listRowSeparatorTint(.orange)
                    }
                }
                .sectionIndexLabel("R")
                Section("Shelves", isExpanded: $showsArchive) {
                    OutlineGroup(shelves, children: \.children) { shelf in
                        Label(shelf.name, systemImage: "folder")
                    }
                    .selectionDisabled()
                }
                .headerProminence(.increased)
            }
            .listSectionSpacing(.compact)
            .navigationTitle("\(selection.count) selected")
            .toolbar {
                EditButton()
            }
        }
    }

    func moveToTop(_ book: Book) {
        books.removeAll { $0.id == book.id }
        books.insert(book, at: 0)
    }
}
