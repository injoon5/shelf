<p align="center">
  <img src="https://github.com/haplollc/Kiln/raw/0.2.1/assets/banner.gif" width="864" alt="Three iPhones running apps Kiln built from chat replies in Haplo AI: a habit tracker, a dark chess board showing a queen's legal moves, and an expense form">
</p>

<h1 align="center">Kiln</h1>

<p align="center">
  Run SwiftUI from a string, on device. Real views, real state, no compiler.<br />
  It is the Run button on Swift code in <a href="https://haploapp.com">Haplo AI</a>: ask for an app, tap Run, use it.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white" alt="Swift 5.9+" />
  <img src="https://img.shields.io/badge/iOS-17+-000000?logo=apple&logoColor=white" alt="iOS 17+" />
  <img src="https://img.shields.io/badge/macOS-14+-000000?logo=apple&logoColor=white" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/SPM-compatible-brightgreen" alt="Swift Package Manager" />
  <img src="https://img.shields.io/badge/License-MIT-blue" alt="MIT License" />
</p>

<p align="center">
  <a href="https://buymeacoffee.com/jcbuilds"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me a Coffee" width="200"></a>
  <br>
  <sub>If Kiln is useful to you, a coffee keeps it going.</sub>
</p>

---

> **This is Shelf's copy of Kiln.** It started as [haplollc/Kiln](https://github.com/haplollc/Kiln) at tag `0.2.1` (commit `70ed7d8`), MIT-licensed, by [@jc_builds](https://twitter.com/jc_builds) at [Haplo](https://haploapp.com). Thank you. Shelf runs every app through it, and is rebuilding it in place ([PLAN.md](../../PLAN.md), §1): one engine, a bytecode VM with real `async`, and a registry of bridges.
>
> What has changed since 0.2.1, in order. Each fix that would help upstream is its own commit, so it can be offered back:
>
> - `JSONEncoder().encode`, `[T].self`, and a decoded `UUID` staying a `UUID` (Shelf's former `kiln-0.2.1.patch`).
> - `Tools/KilnBench` times Shelf's fixtures too, and [Benchmarks/](Benchmarks/) keeps the numbers each step is held to.
> - One engine: the original interpreter is deleted (see [One engine](#one-engine)).
>
> The module is still `Kiln`, and Shelf uses it as a local package (`path: Packages/Kiln` in `project.yml`). The README below is upstream's, kept as it was for 0.2.1 except where this copy differs; `assets/` (its GIFs and video) is left out and linked on GitHub.

```swift
let result = Kiln.run(source)   // result.view is a live SwiftUI view
```

Kiln parses Swift source at runtime and interprets it: structs, classes, enums, closures and the rest of the language, with every `View` you write hosted by a real SwiftUI view that owns its own `@State`. Lists, forms, pickers, sheets, navigation, timers and charts are the real SwiftUI controls, so an app a model writes in a chat reply runs on the phone a moment later and behaves the way it would if you compiled it.

**[Download the demo video (MP4)](https://github.com/haplollc/Kiln/raw/0.2.1/assets/demo.mp4)**

## What it looks like

| A chess game | A habit tracker | An expense tracker |
|:---:|:---:|:---:|
| <img src="https://github.com/haplollc/Kiln/raw/0.2.1/assets/chess.gif" width="260" alt="Asked for a chess game, the reply's code runs in Kiln: legal moves show as dots, pieces slide, and Scholar's mate ends in a checkmate card"> | <img src="https://github.com/haplollc/Kiln/raw/0.2.1/assets/habits.gif" width="260" alt="Asked for a habit tracker, the reply's code runs in Kiln: habits are checked off, the ring fills and a new habit is added"> | <img src="https://github.com/haplollc/Kiln/raw/0.2.1/assets/expenses.gif" width="260" alt="Asked for an expense tracker, the reply's code runs in Kiln: a $12 lunch is added in a sheet and the total and chart update"> |
| Legal moves, check and checkmate, castling and promotion; pieces slide on a spring. About 550 lines. | A `List` with sections and a progress ring that fills as habits are checked off. | Swift Charts, a sheet with a form, and a section per category. |

<sub>Staged demos, recorded in the iOS Simulator inside <a href="https://haploapp.com">Haplo AI</a>. The model's replies are scripted so every take has the same code (each is one of the apps in <a href="Examples/Apps">Examples/Apps</a>); tapping Run, the sheet and the app Kiln runs from that code are real, and the taps come from a UI test.</sub>

## Installation

In Xcode: **File > Add Package Dependencies** and paste

```
https://github.com/haplollc/Kiln
```

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/haplollc/Kiln", from: "0.2.0")
]
```

Then add `Kiln` to your target's dependencies.

## Quick start

`KilnView` runs whatever source you give it and re-runs when it changes.

```swift
import SwiftUI
import Kiln

struct Playground: View {
    @State private var source = """
    struct ContentView: View {
        @State private var count = 0
        var body: some View {
            Button("Tapped \\(count) times") { count += 1 }
        }
    }
    """

    var body: some View {
        VStack {
            TextEditor(text: $source).font(.body.monospaced())
            KilnView(code: source)
        }
    }
}
```

Kiln shows `ContentView` if there is one; otherwise an `@main App`, a `#Preview`, a `PreviewProvider`, or the view no other view uses.

## Running code from a chat reply

Models often split one app across several code blocks (the model type in one, the view in the next). Kiln has helpers for exactly that:

```swift
// Everything in the reply, in order; a later block that redeclares a type replaces it.
let source = Kiln.swiftSource(fromMarkdown: reply)

// The block a person tapped Run on, plus only the blocks it needs from the same reply.
let source = Kiln.swiftSource(running: tappedBlock, inReply: reply)

// A whole app screen (navigation, List, Form, TabView …) wants the full height.
let fullHeight = Kiln.looksLikeApp(source)

// Check code before showing it: evaluates every view and fires every action once, headless.
let check = Kiln.validate(source)   // check.isValid, check.errors
```

## What Kiln runs

**Swift.** Structs as values (copies, `mutating`, memberwise and custom `init`s, `didSet`), classes as references (`ObservableObject` with `@Published`, `@Observable`), enums with raw values, payloads, `CaseIterable` and methods, closures that capture by reference, `switch` with patterns, ranges, tuples and `where`, `if let` / `guard let` / `while let`, optionals with `?.` and `??`, `defer`, `do` / `catch` / `throw`, extensions on your types and on built-in ones, and `Int` and `Double` kept apart. Runaway loops and runaway recursion are stopped and reported; they never hang the app.

**SwiftUI.** Every `View` struct you write is hosted by a real SwiftUI view, so `@State` lives and dies by SwiftUI's own identity rules, and `@Binding`, `@StateObject`, `@ObservedObject`, `@EnvironmentObject`, `@Environment(\.dismiss)` and `@AppStorage` behave as compiled. `List` (rows, sections, `onDelete`), `Form`, `Section` headers and footers, `Picker` with tags (segmented, menu, wheel), `Stepper`, `Toggle`, `Slider`, `TextField` with text or `value:format:`, `DatePicker`, `NavigationStack` with `navigationDestination`, `TabView`, `.searchable`, sheets, alerts, toolbars, `Timer.publish` with `onReceive`, `withAnimation` and transitions, Swift Charts, custom `Shape`s and `Path`, grids, `GeometryReader`, and about 120 modifiers. Text is formatted the way SwiftUI formats it (`Text("\(1400) pages")` reads "1,400 pages").

**Networking.** `try await URLSession.shared.data(from:)` (or `for:` a `URLRequest`), `dataTask(with:) { … }.resume()`, `URLComponents` and `URLQueryItem`, and `JSONDecoder().decode(T.self, from:)` into your own `Decodable` types, with `CodingKeys`, `.convertFromSnakeCase`, optionals, defaults, nested types and raw-value enums.

**Repeatable runs.** Set `Kiln.randomSeed` and `shuffled()`, `randomElement()` and `random(in:)` give the same numbers every run; `KilnRandom(seed:)` gives native Swift the same ones. A host app launched with `-KilnRandomSeed 7` starts seeded, which is handy in UI tests that need the same deal every run.

## Checked against native SwiftUI

`Lab/` is Kiln Lab, an iOS app that shows each example in [Examples/Apps](Examples/Apps) either compiled natively or run by Kiln. One UI test drives both the same way (tap, type, wait for a timer, swipe to delete) and saves every screen. `Tools/iterate.sh` runs a headless check of every example and of Apple Intelligence's own replies in [Examples/AppleIntelligence](Examples/AppleIntelligence), then the UI tests, and writes a report with native, Kiln, and the blocks that differ side by side.

| Pass | Apps matching native on every step | Labels matching | Apple Intelligence replies that run |
|---|---|---|---|
| The original interpreter | 0 of 5 | 0% | 1 of 4 |
| Kiln engine 2, first run | 1 of 5 | 79% | 5 of 5 |
| Computed properties read live `@State`; a title bug | 4 of 5 | 98% | 5 of 5 |
| Seeded runs; `Color` opacity as a style | 5 of 5 | 100% | 5 of 5 |
| A sixth app (tabs, search, a shared store); SwiftUI's number formatting | 6 of 6 | 100% | 5 of 5 |

## One engine

Upstream 0.2.1 had two: the engine described above, and the original interpreter, which still ran code written in its guided dialect (`GameCanvas`, `.onTick`, `.onSwipe`, `.dragToMove`, `Storage`, `BarChart(` / `LineChart(`, `Map(latitude:`). This copy deletes the original interpreter, `Kiln.engine` with it, and `Kiln.register`, whose bridges only that interpreter read. Everything runs on one engine; code in the old dialect fails with its line (`Cannot find 'GameCanvas' in scope`).

## API

```swift
public enum Kiln {
    @MainActor static func run(_ code: String) -> KilnResult
    @MainActor static func validate(_ code: String, ticks: Int = 8, fuel: Int = 2_000_000) -> KilnValidation
    static func swiftSource(fromMarkdown markdown: String) -> String
    static func swiftSource(running block: String, inReply markdown: String) -> String
    static func looksLikeApp(_ code: String) -> Bool
    @MainActor static var randomSeed: UInt64?
    @MainActor static var hostImageProvider: ((String) -> Image?)?
}

public struct KilnResult { let view: AnyView?; let consoleOutput: String; let errors: [String] }
public struct KilnValidation { let errors: [String]; let warnings: [String]; var isValid: Bool }
public struct KilnView<ErrorContent: View>: View { init(code: String) }
public struct KilnRandom: RandomNumberGenerator { init(seed: UInt64?) }
```

## Limitations

Kiln interprets; it does not compile, so some things are out of reach:

- No UIKit or AppKit bridges (`UIViewRepresentable`), no SwiftData or Core Data, no third-party packages.
- `async` code runs straight through: `Task.sleep` does not wait, and `await URLSession.shared.data(from:)` waits for the response (up to 20 seconds) before the next line runs. `dataTask(with:)` with a completion handler does not wait.
- Protocols are accepted but conformance is not checked; user-defined property wrappers and result builders are not supported.

When something is out of reach Kiln reports the line it stopped on instead of crashing.

## License

MIT. See [LICENSE](LICENSE).

## Credits

Built by [@jc_builds](https://twitter.com/jc_builds) at [Haplo](https://haploapp.com), where it runs the code in Haplo AI's chat replies.
