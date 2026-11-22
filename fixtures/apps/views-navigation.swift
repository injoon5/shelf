// Name: Recipes
// Icon: fork.knife
// Tint: red

import SwiftUI

struct Recipe: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var minutes: Int
    var steps: [String]
}

enum Course: String, CaseIterable, Identifiable {
    case starter = "Starters"
    case main = "Mains"
    case dessert = "Desserts"
    var id: String { rawValue }
}

struct ContentView: View {
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            RecipesTab()
                .tabItem { Label("Recipes", systemImage: "book") }
                .tag(0)
            CoursesTab()
                .tabItem { Label("Courses", systemImage: "list.bullet") }
                .tag(1)
                .badge(3)
        }
    }
}

struct RecipesTab: View {
    @State private var recipes = [
        Recipe(name: "Pancakes", minutes: 20, steps: ["Mix", "Fry"]),
        Recipe(name: "Soup", minutes: 45, steps: ["Chop", "Simmer", "Blend"]),
    ]
    @State private var search = ""
    @State private var showingNew = false
    @State private var confirmClear = false
    @State private var deleting: Recipe? = nil
    @State private var showingDelete = false
    @State private var path: [Recipe] = []

    var filtered: [Recipe] {
        search.isEmpty ? recipes : recipes.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(filtered) { recipe in
                    NavigationLink(value: recipe) {
                        LabeledContent(recipe.name, value: "\(recipe.minutes) min")
                    }
                    .contextMenu {
                        Button("Open") { path.append(recipe) }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            deleting = recipe
                            showingDelete = true
                        }
                    }
                }
            }
            .navigationTitle("Recipes")
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetail(recipe: recipe)
            }
            .searchable(text: $search, prompt: "Search recipes")
            .refreshable {
                recipes.sort { $0.name < $1.name }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New", systemImage: "plus") { showingNew = true }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") { confirmClear = true }
                }
            }
            .sheet(isPresented: $showingNew) {
                NewRecipeSheet { recipe in recipes.append(recipe) }
                    .presentationDetents([.medium, .large])
            }
            .alert("Delete Recipe?", isPresented: $showingDelete) {
                Button("Delete", role: .destructive) {
                    recipes.removeAll { $0.id == deleting?.id }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleting?.name ?? "")
            }
            .confirmationDialog("Clear all recipes?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Keep Them", role: .cancel) {}
            }
        }
    }
}

struct RecipeDetail: View {
    let recipe: Recipe

    var body: some View {
        List {
            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                Label(step, systemImage: "\(index + 1).circle")
            }
        }
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NewRecipeSheet: View {
    var onSave: (Recipe) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var minutes = 30

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Stepper("\(minutes) minutes", value: $minutes, in: 5...240, step: 5)
            }
            .navigationTitle("New Recipe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave(Recipe(name: name.isEmpty ? "Untitled" : name, minutes: minutes, steps: []))
                        dismiss()
                    }
                }
            }
        }
    }
}

struct CoursesTab: View {
    @State private var selection: Course? = .main

    var body: some View {
        NavigationSplitView {
            List(Course.allCases, selection: $selection) { course in
                Text(course.rawValue).tag(course)
            }
            .navigationTitle("Courses")
        } detail: {
            if let selection {
                Text(selection.rawValue).font(.largeTitle)
            } else {
                ContentUnavailableView("Pick a Course", systemImage: "fork.knife")
            }
        }
    }
}
