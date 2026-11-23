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
> - A differential harness: `Kiln.transcript` and `Tools/diff.sh` compare everything a run shows against the engine before a change, on every input ([Benchmarks/differential.md](Benchmarks/differential.md)).
> - Code that can wait: `async`/`await` really suspends and resumes, on frames that live on the heap (see [Code that can wait](#code-that-can-wait)).
> - A registry of bridges: every native view, modifier, type and function is declared once, by family, with its SwiftUI overloads; anything it doesn't have is an error with its line, and it exports `kiln-manifest.json` (see [Bridges](#bridges)).
> - A coverage report: [COVERAGE.md](COVERAGE.md) compares Kiln with every view, modifier and style in the iOS SDK (see [Coverage](#coverage)).
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

**Swift.** Structs as values (copies, `mutating`, memberwise and custom `init`s, `didSet`), classes as references (`ObservableObject` with `@Published`, `@Observable`), enums with raw values, payloads, `CaseIterable` and methods, closures that capture by reference, `switch` with patterns, ranges, tuples and `where`, `if let` / `guard let` / `while let`, optionals with `?.` and `??`, `defer`, `do` / `catch` / `throw`, extensions on your types and on built-in ones, and `Int` and `Double` kept apart. Protocols with extensions, default implementations, constrained extensions and inheritance, `any P` and `some P`, generics, and classes that inherit (with `super`); `Equatable`, `Hashable`, `Comparable` and `CaseIterable` synthesized as Swift does, or your own `==`, `hash(into:)` and `<`. `@resultBuilder` and `@ViewBuilder` (functions, properties and parameters), your own `@propertyWrapper`s, custom `init(from:)` and `encode(to:)` with every kind of container, regex literals, and `@Entry`, `@Observable` and `@Animatable` read as declarations. Wrong labels and unknown members of your own types are errors with their lines, as the compiler's would be. Runaway loops and runaway recursion are stopped and reported; they never hang the app.

**SwiftUI.** Every `View` struct you write is hosted by a real SwiftUI view, so `@State` lives and dies by SwiftUI's own identity rules, and `@Binding`, `@StateObject`, `@ObservedObject`, `@EnvironmentObject`, `@Environment(\.dismiss)` and `@AppStorage` behave as compiled. `List` (rows, sections, `onDelete`), `Form`, `Section` headers and footers, `Picker` with tags (segmented, menu, wheel), `Stepper`, `Toggle`, `Slider`, `TextField` with text or `value:format:`, `DatePicker`, `NavigationStack` with `navigationDestination`, `TabView`, `.searchable`, sheets, alerts, toolbars, `Timer.publish` with `onReceive`, `withAnimation` and transitions, Swift Charts, custom `Shape`s and `Path`, grids, `GeometryReader`, and about 120 modifiers. Text is formatted the way SwiftUI formats it (`Text("\(1400) pages")` reads "1,400 pages").

**Waiting.** `async` functions and closures, `await`, `Task {}` and `Task.detached {}`, `.task {}` and `.task(id:)` (cancelled when the view goes away), `.refreshable` that waits, `Task.sleep(for:)` and `(nanoseconds:)` that really wait, `Task.isCancelled` and `checkCancellation()`, `async let`, `withTaskGroup` and `withThrowingTaskGroup`, `for await` over task groups and `AsyncStream`s (`yield`, `finish`, `onTermination`, `makeStream`), `withCheckedContinuation`, and `await MainActor.run {}`. All of it runs on the main actor, like a SwiftUI app's own code, and none of it blocks the main thread.

**Networking.** `try await URLSession.shared.data(from:)` (or `for:` a `URLRequest`), which waits without blocking, `dataTask(with:) { … }.resume()`, `URLComponents` and `URLQueryItem`, and `JSONDecoder().decode(T.self, from:)` into your own `Decodable` types, with `CodingKeys`, `.convertFromSnakeCase`, optionals, defaults, nested types and raw-value enums.

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
| Bridges in a registry (§1.4): unknown modifiers are errors | 7 of 7 | 100% | 4 of 5: `expense.md` writes `.stepValue(0.1)`, which isn't SwiftUI |

## Coverage

[COVERAGE.md](COVERAGE.md) lists every public view, modifier and style in the iOS SDK's SwiftUI, SwiftUICore, Charts and `_*_SwiftUI` overlays. For each one it says whether Kiln supports it, or won't and why. [coverage.json](coverage.json) holds the same data with every overload's signature, for tools and agents. To regenerate both:

```sh
Packages/Kiln/Tools/coverage.sh
```

Run it after each round and after each Xcode update. It reads the SDK that `xcrun --sdk iphoneos --show-sdk-path` finds, and the same inputs always give the same files, so a diff shows only what changed.

- **"Supported"** comes from `kiln-manifest.json` ([Docs/manifest.md](Docs/manifest.md)), which the bridge registry will export. Until then the tool reads the engine's string switches and writes an interim manifest, `Tools/coverage/kiln-manifest.interim.json`.
- **Families** come from `Tools/coverage/families.json`. A symbol that no rule matches is listed as Unsorted.
- **Won't do:** each entry, with its one-line reason, is in `Tools/coverage/wont-do.json`.
- **Tests:** `swift test --package-path Packages/Kiln/Tools/coverage`.

## One engine

Upstream 0.2.1 had two: the engine described above, and the original interpreter, which still ran code written in its guided dialect (`GameCanvas`, `.onTick`, `.onSwipe`, `.dragToMove`, `Storage`, `BarChart(` / `LineChart(`, `Map(latitude:`). This copy deletes the original interpreter, `Kiln.engine` with it, and `Kiln.register`, whose bridges only that interpreter read. Everything runs on one engine; code in the old dialect fails with its line (`Cannot find 'GameCanvas' in scope`).

## Code that can wait

Code with no `await` in it runs on the tree-walker, straight through. A function or closure whose body has an `await` runs as a task on a small resumable evaluator (`Engine/KEAsync.swift`): a stack of frames on the heap, each a state machine over one statement or expression, that steps until it needs a child frame, finishes, or waits on a suspension. When the suspension can't answer at once the task parks with its frames intact, and resumes on the main actor when it does. Inside a task, the statements that don't wait still run on the tree-walker.

- **What can't wait.** Calling a function that waits doesn't run it: it returns a suspension that `await` runs in the awaiting task's own frames. So a view's `body`, computed properties, `init` and everything else the tree-walker runs go to the end, as in compiled Swift; an `await` there is an error with its line, and so is calling an `async` function without `await`.
- **Natives that wait** return a `KSuspension`: `.async { … }` wraps Swift `async` work (cancelling the app's task cancels it), `.callback { ctx, resume in … }` wraps a callback. `KAsyncSequence.wrapping(name, sequence) { element in … }` makes a native `AsyncSequence` something the app can `for await` over.
- **The budget is per stretch.** The step limit applies between two waits: a task that waits between steps runs as long as it likes, and a loop that never waits is still stopped, with its line.
- **Teardown.** `KilnResult.tearDown()` cancels every task of a run, invalidates its timers, and runs none of its code again.
- **Checking.** `validate` runs headless: sleeps return at once, the network fails at once (unless the host answers), and the tasks it starts run to their end before it returns, then are torn down.

Why this and not a bytecode VM for all code, yet: [Benchmarks/README.md](Benchmarks/README.md#13-code-that-can-wait).

## Bridges

Everything native that an app's code can name is a bridge in one registry (`Sources/Kiln/Registry/`), declared in its family's folder (`Sources/Kiln/Bridges/Controls/`, `Layout/`, `Navigation/`, `Drawing/`, `Language/`, `Foundation/` and so on):

- **views**, each with the overloads SwiftUI declares (`Toggle(_:isOn:)`, `Toggle(isOn:label:)`) and how it's built;
- **modifiers**, the same way;
- **types** (`Date`, `URLSession`, `String`): initializers, static members, properties and methods, where an `async` method returns what `await` waits on;
- **global functions** (`print`, `withAnimation`);
- **protocols** an app's types adopt, environment values and property wrappers, as declarations.

A call picks its overload by labels and by how each argument is written (a closure, a string literal), as Swift does, then by what the running OS has. Each argument is evaluated against its parameter's kind: `.font(.title)` against `Font`, a title's string literal as a `LocalizedStringKey`, a binding checked to be one. The bridge gets values, through helpers that read the same everywhere (`c.binding("selection", Date.self)`, `c.content()`).

**Nothing is skipped silently.** An unknown modifier is `Line 12: Kiln doesn't support the .glassEffect() modifier`, an unknown view is `Cannot find 'Canvas3D' in scope`, and a call no overload takes says which ones there are. Modifiers Kiln accepts without an effect yet (`.sensoryFeedback`, `.focused`, `.gesture`) are declared as stubs, and the manifest says so.

The registry exports [`kiln-manifest.json`](kiln-manifest.json) (format: [Docs/manifest.md](Docs/manifest.md)), which the coverage report ([COVERAGE.md](COVERAGE.md)) and Shelf's prompt read. `Tools/manifest.sh` rewrites it; a test fails when it's stale.

**The host adds its own** with the same rules: `Kiln.registerType("DB") { t in t.staticMethod("load", "_:string") { call in … } }`.

How to add a bridge, with an example of each kind: [Docs/bridges.md](Docs/bridges.md).

## Checked against the engine before

`Tools/diff.sh` runs every input (the example apps and replies, Shelf's fixtures, the workloads, the SwiftUI in Kiln's tests) on the engine at a base commit (by default `b466f9c`, the engine before the registry) and on this checkout, and compares their transcripts: the view tree each body evaluates to, the console, errors and warnings with their lines, and all of it again after each scripted action. Inputs meant to differ are listed, with the reason, in `Tools/diff-expected.txt`. The last run is [Benchmarks/differential.md](Benchmarks/differential.md).

## API

```swift
public enum Kiln {
    @MainActor static func run(_ code: String) -> KilnResult                              // KilnContext.standard()
    /// One app's run: its settings, folder, capability gate, teardown and errors (PLAN.md §1.7).
    @MainActor static func run(_ code: String, context: KilnContext) -> KilnResult
    @MainActor static func run(_ parsed: KilnParsedSource, context: KilnContext) -> KilnResult
    /// Any thread: parse before the screen is up, run on the main actor.
    static func parse(_ code: String) -> KilnParsedSource
    @MainActor static func validate(_ code: String, ticks: Int = 8, fuel: Int = 2_000_000,
                                    context: KilnContext? = nil) -> KilnValidation    // KilnContext.stub()
    static func swiftSource(fromMarkdown markdown: String) -> String
    static func swiftSource(running block: String, inReply markdown: String) -> String
    static func looksLikeApp(_ code: String) -> Bool
    @MainActor static var randomSeed: UInt64?
    @MainActor static var hostImageProvider: ((String) -> Image?)?
    /// A host bridge: a native type the app's code can name (Docs/bridges.md).
    @MainActor static func registerType(_ name: String, family: KilnFamily = .host, notes: String? = nil, _ build: (KilnTypeBuilder) -> Void)
    @MainActor static func registerFunction(_ name: String, signature: String? = nil, family: KilnFamily = .host, notes: String? = nil,
                                            _ run: @escaping (KilnCall) throws -> KilnValue)
    /// kiln-manifest.json's contents, the host's bridges included.
    @MainActor static func manifestJSON() throws -> Data
}

public struct KilnTypeBuilder {   // initializer, staticProperty, staticMethod, property, method
    func staticMethod(_ name: String, _ signature: String? = nil, notes: String? = nil, _ run: @escaping (KilnCall) throws -> KilnValue)
    …
}
public final class KilnCall {      // the arguments: string(_:), int(_:), double(_:), bool(_:), value(_:), json(_:), decode(_:as:), error(_:)
    var receiver: KilnValue; var line: Int
}
public struct KilnValue {          // .void, .nil, (string:), (int:), (double:), (bool:), (date:), (url:), (data:), (array:), (dictionary:),
                                   // (object:type:), .async { … }
}

public struct KilnResult {
    let view: AnyView?; let consoleOutput: String; let errors: [String]; var context: KilnContext?
    @MainActor func tearDown()               // cancel every task, stop timers and the context's stoppers, run nothing more
    @MainActor var activeTaskCount: Int
}

public final class KilnContext {           // one run of one app (Docs/bridges.md, "The run's context")
    init(slug: String, name: String, defaults: UserDefaults, files: KilnFiles, capabilities: KilnCapabilityGate? = nil)
    static func stub(slug:name:capabilities:) -> KilnContext     // throwaway settings and folder, answers at once
    let slug: String; let name: String; var defaults: UserDefaults; let files: KilnFiles
    let capabilities: KilnCapabilities; let isStub: Bool
    func provide<T>(_ value: T); func provided<T>(_ type: T.Type) -> T?
    func onTearDown(_ stop: @escaping () -> Void) -> KilnTeardownToken; func tearDown()
    var onError: ((KilnError) -> Void)?    // .check, .body or .runtime, with its line
}
public struct KilnHostResponse { var statusCode: Int; var body: Data? }
public struct KilnValidation { let errors: [String]; let warnings: [String]; var isValid: Bool }
public struct KilnView<ErrorContent: View>: View { init(code: String) }
public struct KilnRandom: RandomNumberGenerator { init(seed: UInt64?) }
```

## Limitations

Kiln interprets; it does not compile, so some things are out of reach:

- No UIKit or AppKit bridges (`UIViewRepresentable`), no SwiftData or Core Data, no third-party packages.
- Only what's in the registry runs. A view, modifier or initializer it doesn't have, or argument labels SwiftUI doesn't have, stop the code with an error and a line; [COVERAGE.md](COVERAGE.md) lists what's there.
- `await` inside an `if` or `switch` *expression*, on the left of an assignment, or in a `case` pattern isn't supported; use a statement. Inside an expression, the parts that wait are evaluated before the rest of it.
- Macros are read as declarations (`@Observable`, `@Entry`, `@Animatable`), not expanded; others are ignored. `@Animatable` marks what animates, but custom shapes don't interpolate until §1.5's proxies.
- Overloads of your own functions are picked by argument labels, not by argument types.

When something is out of reach Kiln reports the line it stopped on instead of crashing.

## License

MIT. See [LICENSE](LICENSE).

## Credits

Built by [@jc_builds](https://twitter.com/jc_builds) at [Haplo](https://haploapp.com), where it runs the code in Haplo AI's chat replies.
