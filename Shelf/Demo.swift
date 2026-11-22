#if DEBUG
import Foundation

/// A library with no server behind it: launch with `-ShelfDemo YES`.
/// For previews, screenshots and working on the Home Screen offline.
@MainActor
enum Demo {
    static let apps: [(String, String, String?, Tint)] = [
        ("habits", "Habits", "checkmark.circle.fill", .green),
        ("tip-jar", "Tip Jar", "dollarsign.circle.fill", .mint),
        ("todos", "Todos", "checklist", .blue),
        ("weather", "Weather", "cloud.sun.fill", .cyan),
        ("notes", "Notes", "note.text", .yellow),
        ("timer", "Timer", "timer", .orange),
        ("budget", "Budget", "chart.pie.fill", .indigo),
        ("reading", "Reading List", "books.vertical.fill", .brown),
        ("workout", "Workout", "figure.run", .red),
        ("journal", "Journal", "book.closed.fill", .purple),
        ("water", "Water", "drop.fill", .teal),
        ("mood", "Mood", "face.smiling", .pink),
        ("counter", "A Very Long App Name", nil, .gray),
    ]

    static func library() -> LibraryStore {
        let cached = apps.enumerated().map { index, app in
            CachedApp(meta: AppMeta(slug: app.0, name: app.1, icon: app.2, tint: app.3, version: "demo"),
                      cachedVersion: index == 4 ? nil : "demo", isNew: index == 2)
        }
        return LibraryStore(demo: cached, dock: ["habits", "todos"])
    }

    static let source = """
    // Name: Demo
    // Icon: sparkles
    // Tint: blue
    import SwiftUI

    struct ContentView: View {
        @State private var count = 0
        var body: some View {
            NavigationStack {
                List {
                    Section {
                        Stepper("Count: \\(count)", value: $count)
                    }
                    Section("Rows") {
                        ForEach(0..<30, id: \\.self) { row in
                            Label("Row \\(row)", systemImage: "circle")
                        }
                    }
                }
                .navigationTitle("Demo")
            }
        }
    }
    """
}
#endif
