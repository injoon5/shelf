#if DEBUG
import UIKit

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

    /// Enough more to fill page one and start page two: add `-ShelfDemoFull YES`.
    static let moreApps: [(String, String, String?, Tint)] = [
        ("sleep", "Sleep", "bed.double.fill", .indigo),
        ("recipes", "Recipes", "fork.knife", .orange),
        ("plants", "Plants", "leaf.fill", .green),
        ("flights", "Flights", "airplane", .blue),
        ("music", "Practice", "music.note", .pink),
        ("steps", "Steps", "shoeprints.fill", .teal),
        ("gifts", "Gift Ideas", "gift.fill", .red),
        ("packing", "Packing", "suitcase.fill", .brown),
        ("pomodoro", "Focus", "hourglass", .purple),
        ("bills", "Bills", "creditcard.fill", .mint),
        ("cards", "Flashcards", "rectangle.stack.fill", .yellow),
        ("parking", "Parking", "car.fill", .cyan),
        ("dice", "Dice", "dice.fill", .gray),
        ("scores", "Scores", "trophy.fill", .orange),
    ]

    /// A picture to draw instead of the chosen wallpaper: launch with
    /// `-ShelfWallpaperFile <path on the Mac>`. For comparing Shelf with a
    /// Springboard capture over the same backdrop (plain black, say).
    static let wallpaperFile: UIImage? = UserDefaults.standard.string(forKey: "ShelfWallpaperFile")
        .flatMap(UIImage.init(contentsOfFile:))

    static func library() -> LibraryStore {
        // `-ShelfDemoEmpty YES` shows the empty library instead.
        let defaults = UserDefaults.standard
        let all = defaults.bool(forKey: "ShelfDemoEmpty") ? [] : apps + (defaults.bool(forKey: "ShelfDemoFull") ? moreApps : [])
        let cached = all.enumerated().map { index, app in
            CachedApp(meta: AppMeta(slug: app.0, name: app.1, icon: app.2, tint: app.3, version: "demo"),
                      cachedVersion: index == 4 ? nil : "demo", isNew: index == 2)
        }
        return LibraryStore(demo: cached, dock: all.isEmpty ? [] : ["habits", "todos"])
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
