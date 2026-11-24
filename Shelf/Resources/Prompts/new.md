Write a small iPhone app for Shelf. Shelf runs SwiftUI source on the phone with an interpreter called Kiln. There is no compiler and no Xcode project, so the whole app is one Swift file.

App idea:
{{IDEA}}

## Reply format

Reply with one ```swift block. Start it with these three comment lines:

```swift
// Name: Habits
// Icon: checkmark.circle.fill
// Tint: green
```

- Name: up to 20 characters. It's the label under the app's icon.
- Icon: an SF Symbol name.
- Tint: one of red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray.

The app starts at `struct ContentView: View`. Don't add an `@main App`, a `#Preview` or a `PreviewProvider`.

<!-- if install -->
## Installing

If you can run shell commands, install the app yourself after writing it. Save the file as `App.swift`, then run:

```sh
curl -sS -X PUT {{ORIGIN}}/api/apps/<slug> \
  -H "Authorization: Bearer {{KEY}}" \
  -H "Content-Type: text/x-swift" \
  --data-binary @App.swift
```

- `<slug>` is the name in lowercase with hyphens, for example `habit-tracker`.
- `201`: installed. Tell the user it's on their phone.
- `409`: the slug is taken. Pick another and run it again.
- `422` or `413`: the response says what's wrong. Fix it and run it again. A failed attempt doesn't use up the key.
- `401`: the key is used or has expired. Stop, and reply with the code instead.

The key installs one new app. It can't change existing apps, and it expires at {{EXPIRES}}. Never print the key back, or store it anywhere else.

If you can't run commands, reply with the code as described above.

<!-- end -->
## What works

Kiln runs Swift, and the parts of SwiftUI, Foundation, Charts and Swift concurrency listed here. Before installing an app, Shelf checks it: a view, modifier, type or argument label that isn't here is reported with its line, so stay within this list.

**Swift**
- Structs (memberwise and custom `init`, `mutating`, `didSet`), classes, enums (raw values, associated values, `CaseIterable`, methods).
- Closures, `switch` with patterns and `where`, tuples, ranges.
- Optionals with `?.` and `??`, `if let` / `guard let` / `while let`, `defer`, `do` / `catch` / `throw`.
- Extensions on your own types and on built-in ones, `Codable` types, `Identifiable`.
- Protocols with extensions and default implementations (`extension P where Self: Q` too), `any P` and `some P`, generics, and classes that inherit with `super`.
- `Equatable`, `Hashable`, `Comparable` and `CaseIterable` as Swift synthesizes them, or with your own `==`, `hash(into:)` and `<`. Declare them: `==`, `sorted()`, `allCases` and `ForEach` without `id:` need them.
- `@ViewBuilder` functions, properties and parameters (with `if`, `switch` and `for`), and your own `@resultBuilder` and `@propertyWrapper` types.
- Regex literals (`/\d+/`, `#/…/#`) with `firstMatch(of:)`, `wholeMatch(of:)`, `matches(of:)`, `contains` and `replacing`.
- `@Observable` classes, also passed down with `.environment(model)` and read with `@Environment(Model.self)`; your own environment values declared with `@Entry` in `extension EnvironmentValues`.
- `Int` and `Double` are distinct, as in compiled Swift.

**Waiting**
- `async` functions, called with `await` from `.task { }`, `Task { }` or another `async` function. All of it runs on the main thread, so it can update state directly.
- `.task { }` and `.task(id:)`, which stop when the view goes away and start again when the id changes. `.refreshable` waits for its closure.
- `try await Task.sleep(for: .seconds(1))` waits without freezing the screen. `Task.isCancelled` and `try Task.checkCancellation()`.
- `async let`, `withTaskGroup`, `AsyncStream` read with `for await`, and `await MainActor.run { }`.
- A view's `body`, computed properties and `init` can't wait, and nor can a button's action or `.onAppear`: start a `Task { }` there.

**By family**, with what to know about each:

{{WORKS}}

## Saving data

Use `@AppStorage("key")` only for small preferences that wouldn't matter if lost: a `Bool`, `Int`, `Double` or `String`. It stays on this device, and each app has its own (so does `UserDefaults.standard`).

Use `DB` for everything else. Shelf provides it, so don't declare your own `DB`. Values are JSON `Data`. DB data syncs to the user's other devices and works offline. Calls return immediately.

Files the app writes (`URL.documentsDirectory`, `FileManager`) stay on this iPhone in the app's own folder, and go when it's deleted. Only `DB` syncs, so keep what the user would miss in `DB`, and use files for things like recordings and exports.

```swift
DB.load("todos") -> Data?          // nil if the key was never saved
DB.save("todos", data)             // data: Data
DB.remove("todos")
```

The usual pattern is to load in `.onAppear` and save in `.onChange`:

```swift
@State private var todos: [Todo] = []
@State private var loadFailed = false

List { … }
    .onAppear {
        if let data = DB.load("todos") {
            if let saved = try? JSONDecoder().decode([Todo].self, from: data) { todos = saved } else { loadFailed = true }
        }
    }
    .onChange(of: todos) {
        if !loadFailed, let data = try? JSONEncoder().encode(todos) { DB.save("todos", data) }
    }
```

Keys are 1–128 characters with no `/`. A value can be up to 64 KB. Store one key per collection, not one key per item.

Saved data has to survive future versions of the app:
- Give every field of a saved type a default value, or make it optional, so older saved data still decodes.
- If decoding fails, don't save over the stored data. Keep a flag such as `loadFailed`, and skip saving while it's set.

Kiln reads and writes JSON by a type's stored properties and its `CodingKeys`, or by your own `init(from:)` and `encode(to:)`:
- Saved enums need raw values (`enum Priority: String, Codable`). An enum with associated values needs its own `init(from:)` and `encode(to:)`.

## What doesn't work

{{DOESNT}}

## Design

- Make it look like an Apple app:
  - `NavigationStack` with a `navigationTitle`, then `List` or `Form` where they fit
  - system colors (`.primary`, `.secondary`, `Color(.systemGroupedBackground)`) and the tint above as the accent
  - SF Symbols, and text styles (`.headline`, `.body`, `.caption`) rather than fixed sizes
- It must work in light and dark mode.
- The app fills the screen, and swiping down from the top edge closes it. Keep controls out of the top 44 points unless they're in a navigation bar.
- Keep it under about 600 lines.
- Make every visible piece of text mean something. Don't add taglines or explanatory captions.
