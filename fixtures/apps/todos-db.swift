// Name: Todos
// Icon: checklist
// Tint: blue
// Covers: Lists

import SwiftUI

struct Todo: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String = ""
    var done: Bool = false
}

struct ContentView: View {
    @State private var todos: [Todo] = []
    @State private var loadFailed = false
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(todos) { todo in
                    Label(todo.title, systemImage: todo.done ? "checkmark.circle.fill" : "circle")
                }
                TextField("New", text: $draft)
                Button("Add") {
                    todos.append(Todo(title: draft.isEmpty ? "Untitled" : draft))
                    draft = ""
                }
            }
            .navigationTitle("Todos")
            .onAppear {
                if let data = DB.load("todos") {
                    if let saved = try? JSONDecoder().decode([Todo].self, from: data) { todos = saved } else { loadFailed = true }
                }
            }
            .onChange(of: todos) {
                if !loadFailed, let data = try? JSONEncoder().encode(todos) { DB.save("todos", data) }
            }
        }
    }
}
