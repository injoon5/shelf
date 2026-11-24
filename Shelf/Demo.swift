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

    /// Every UIKit spring this many times slower: `-ShelfSlowMotion 4`. For
    /// recording a motion being caught mid-flight, which a test driver's own
    /// latency can't do at full speed.
    static let slowMotion: Double = max(UserDefaults.standard.double(forKey: "ShelfSlowMotion"), 1)

    /// Search's warp held still at this progress, as a finger holding a
    /// pull there would: `-ShelfSearchProgress 0.5`. For pictures of the
    /// pull's frames, which a test driver can't stop mid-gesture.
    static let searchProgress: CGFloat? = UserDefaults.standard.object(forKey: "ShelfSearchProgress") == nil
        ? nil : CGFloat(UserDefaults.standard.double(forKey: "ShelfSearchProgress"))

    /// The demo's server refuses every Delete App, this long after it was
    /// asked: `-ShelfDemoDeleteFails YES`. The icon leaves, then comes back.
    static let deleteFails = UserDefaults.standard.bool(forKey: "ShelfDemoDeleteFails")
    static let deleteFailDelay: Double = 1

    /// `-ShelfDebugReply <Swift file on the Mac>`: New App opens once the
    /// Home Screen is up, with that file pasted as the reply, for seeing the
    /// preview and its error screen (the sheet has no Paste button).
    static var reply: String? {
        UserDefaults.standard.string(forKey: "ShelfDebugReply").flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }
    }

    /// Asks for capabilities as an app would, once the Home Screen is up:
    /// `-ShelfDebugAskPermission location` (or a list, `location,camera`),
    /// as the app `-ShelfDebugAskPermissionApp workout` (by default the
    /// library's first). For seeing the sheet, iOS's prompt after it, and
    /// Settings › Permissions filling in. Each answer is printed.
    static func askPermissions(_ library: LibraryStore) async {
        let defaults = UserDefaults.standard
        guard let list = defaults.string(forKey: "ShelfDebugAskPermission") else { return }
        let capabilities = list.split(separator: ",").compactMap { Capability(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
        let slug = defaults.string(forKey: "ShelfDebugAskPermissionApp")
        guard let app = (slug.flatMap(library.app) ?? library.apps.first)?.meta else { return }
        try? await Task.sleep(for: .seconds(1))
        for capability in capabilities {
            let allowed = await library.permissions.request(capability, for: app)
            print("ShelfDebugAskPermission: \(app.slug) \(capability.rawValue) → \(allowed ? "allowed" : "denied")")
        }
    }

    static func library() -> LibraryStore {
        // `-ShelfDemoFixtures <folder on the Mac>`: the fixture apps there,
        // one icon each, for trying them in a card (plan §2, Round 1).
        if let folder = UserDefaults.standard.string(forKey: "ShelfDemoFixtures") { return fixtures(URL(filePath: folder)) }
        // `-ShelfDemoEmpty YES` shows the empty library instead.
        let defaults = UserDefaults.standard
        let all = defaults.bool(forKey: "ShelfDemoEmpty") ? [] : apps + (defaults.bool(forKey: "ShelfDemoFull") ? moreApps : [])
        let cached = all.enumerated().map { index, app in
            CachedApp(meta: AppMeta(slug: app.0, name: app.1, icon: app.2, tint: app.3, version: "demo"),
                      cachedVersion: index == 4 ? nil : "demo", isNew: index == 2)
        }
        let cache = AppCache(root: URL.temporaryDirectory.appending(path: "shelf-demo"))
        for app in cached { try? cache.writeSource(sources[app.slug] ?? source, for: app.slug) }
        return LibraryStore(demo: cached, dock: all.isEmpty ? [] : ["habits", "todos"], cache: cache)
    }

    static func fixtures(_ folder: URL) -> LibraryStore {
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "swift" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let cache = AppCache(root: URL.temporaryDirectory.appending(path: "shelf-demo-fixtures"))
        var cached: [CachedApp] = []
        for file in files {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let slug = file.deletingPathExtension().lastPathComponent
            let reply = ReplyParser.parse(source)
            let app = CachedApp(meta: AppMeta(slug: slug, name: reply.name ?? slug, icon: reply.icon, tint: reply.tint, version: "demo"),
                                cachedVersion: "demo", isNew: false)
            try? cache.writeSource(source, for: slug)
            cached.append(app)
        }
        return LibraryStore(demo: cached, dock: [], cache: cache)
    }

    /// Demo apps that keep something: Habits its count in `@AppStorage`,
    /// Todos its list in `DB`, so a value surviving a close and a relaunch
    /// can be seen.
    static let sources: [String: String] = [
        "habits": """
        // Name: Habits
        // Icon: checkmark.circle.fill
        // Tint: green
        import SwiftUI

        struct ContentView: View {
            @AppStorage("count") private var count = 0
            var body: some View {
                NavigationStack {
                    List {
                        Section("Kept with @AppStorage") {
                            Stepper("Count: \\(count)", value: $count)
                        }
                    }
                    .navigationTitle("Habits")
                }
            }
        }
        """,
        "todos": """
        // Name: Todos
        // Icon: checklist
        // Tint: blue
        import SwiftUI

        struct Todo: Identifiable, Codable, Equatable {
            var id = UUID()
            var title: String
        }

        struct ContentView: View {
            @State private var todos: [Todo] = []
            @State private var loadFailed = false
            var body: some View {
                NavigationStack {
                    List {
                        Section("Kept with DB") {
                            ForEach(todos) { todo in Text(todo.title) }
                                .onDelete { todos.remove(atOffsets: $0) }
                        }
                    }
                    .navigationTitle("Todos")
                    .toolbar {
                        Button("Add", systemImage: "plus") { todos.append(Todo(title: "Todo \\(todos.count + 1)")) }
                    }
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
        """,
    ]

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
