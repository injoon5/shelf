# Kiln — Support Status & Roadmap

## Engine 2 (2026-10-26) — real Swift semantics, real SwiftUI state

`Kiln.run` and `Kiln.validate` now use a second interpreter core in
`Sources/Kiln/Engine/`.

**Language.** A real lexer and recursive-descent parser that follow Swift's
whitespace rules for operators; lexical scopes; closures that capture by
reference; structs as values (copies, `mutating`, memberwise inits, `didSet`);
classes as references (`ObservableObject`, `@Published`, `@Observable`); enums
with raw values, payloads and methods; `switch` with patterns, `where`, ranges
and tuples; `if`/`guard`/`while let`; `defer`; `do`/`catch`/`throw`; optionals,
`?.`, `??`; generics in signatures; `Int` and `Double` kept apart; extensions on
user and built-in types; protocols (accepted, conformance not checked);
`#if` (first branch). Runaway code is stopped by a step budget and a call-depth
limit and reported, never hangs the app.

**SwiftUI.** Every interpreted `View` struct is hosted by a real SwiftUI view
that owns its `@State`, so identity, `@State` lifetime, `@Binding`,
`@StateObject`/`@ObservedObject`/`@EnvironmentObject`, `@Environment(\.dismiss)`
and `@AppStorage` behave as compiled. Rendered with the real controls: `List`
(data, `ForEach`, `onDelete`, `onMove`), `Form`, `Section` (titles, headers,
footers), `Picker` with tags (segmented, menu, wheel), `Stepper`, `Toggle`,
`Slider`, `TextField` (text or `value:format:`), `DatePicker`, `NavigationStack`
with `navigationDestination`, `TabView`, sheets, alerts, confirmation dialogs,
toolbars, `Timer.publish`/`onReceive`, `withAnimation` and transitions, Swift
Charts, custom `Shape`s and `Path`, grids, `GeometryReader`, and about 120
modifiers.

**Networking.** `URLSession.shared.data(from:)` / `data(for:)` (waits for the
response, at most 20 s), `dataTask(with:completionHandler:)` + `resume()` (calls
back on the main thread), `URLComponents`, `URLQueryItem`, `URLRequest`, and
`JSONDecoder().decode(T.self, from:)` into user `Decodable` types (CodingKeys,
`.convertFromSnakeCase`, `.iso8601`, optionals, defaults, nested and raw-value
enum types). Caught errors are `Error` values with `localizedDescription`.

**Seeded runs.** `Kiln.randomSeed` makes `shuffled()`, `randomElement()` and
`random(in:)` repeatable; `KilnRandom(seed:)` gives native code the same numbers.

**How it is checked.** `Lab/` builds Kiln Lab, an iOS app that shows each
example in `Examples/Apps/` either compiled natively or run by Kiln. The same
UI test drives both and saves every screen; `Tools/iterate.sh` runs the engine
bench and the UI tests and writes a side-by-side report (native, Kiln, and the
blocks that differ) to `~/Desktop/Kiln Iterations/`. All six example apps
(habit tracker, tip calculator, focus timer, memory game, expense tracker,
reading list) match native on every scripted step. `Lab/quick.sh` runs a few
scenarios while fixing a bug; `-example /path/to/File.swift` runs any file.

## One engine (Shelf, 2026-11-24)

The original interpreter (`Parser/`, `Runtime/`, `Renderer/`, `Interpreter/`,
`Validator/`, `SwiftRunner.swift`), which ran Bond's guided dialect
(`GameCanvas`, `.onTick`, `.onSwipe`, `.dragToMove`, `BarChart(`/`LineChart(`,
`Storage`, `Map(latitude:`), is deleted, with `Kiln.engine`, `Kiln.register`
and `KilnValue` (only that interpreter read the bridges), its tests and
`KILN_GUIDE.md`. Code in that dialect now fails with its line (`Cannot find
'GameCanvas' in scope`). Every source goes to `Engine/`. Its history, Plans
1 to 8, is in git before this commit.

## Code that can wait (Shelf, 2026-11-24)

PLAN.md §1.3, as its fallback: code with no `await` still runs on the
tree-walker; a function or closure with an `await` runs as a task on a
resumable evaluator (`Engine/KEAsync.swift`) whose frames live on the heap,
so it parks at a real wait and resumes on the main actor. `Task {}`, `.task`,
real `Task.sleep`, cancellation, `async let`, task groups, `for await` over
`AsyncStream` and native sequences, continuations, `MainActor.run`, and
`URLSession.data` without blocking. The step budget is per stretch between
waits; `KilnResult.tearDown()` stops a run. `Tools/diff.sh` compares every
input against the engine before ([Benchmarks/differential.md](Benchmarks/differential.md)).

## Swift that should work (Shelf, 2026-11-24)

PLAN.md §1.6. Protocols are real: requirements are checked, extensions give
default implementations (constrained ones win, the type's own members win
over both), conformance closes over protocol and class inheritance, and
behaviour follows it (a custom `==` and `hash(into:)` decide equality and
hashing everywhere; `==`, `<`, `allCases` and `ForEach` without `id:` need
the conformance). `@resultBuilder` with Swift's whole transform, and
`@ViewBuilder` on functions, properties, parameters and stored content.
Custom property wrappers (`_x`, `wrappedValue`, `projectedValue`). Custom
`init(from:)` and `encode(to:)` with keyed, unkeyed and single-value
containers; sets round-trip. Regex literals as `Regex<AnyRegexOutput>`.
Macros read as declarations (`Engine/KEMacros.swift`). Wrong labels and
unknown members of the app's own types are errors worded like the
registry's. One-sided `case` ranges, `$x.animation()`, `allCases.map`,
`Data(text.utf8)`, `super`. The engine files are `KEProtocols`,
`KEBuilders`, `KEWrappers`, `KEMacros` and `KEDiagnostics`.
