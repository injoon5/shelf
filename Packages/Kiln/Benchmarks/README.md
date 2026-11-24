# Benchmarks

How fast Kiln runs Shelf's apps, recorded at each step of the rewrite. PLAN.md §1.3: the bytecode VM must not be slower than 0.2.1 on any input. §1.10: a regression past 10% on any input blocks the merge.

```sh
Benchmarks/run.sh /tmp/now.json --compare Benchmarks/after-1.5-proxies.json
```

`run.sh` builds `Tools/KilnBench` in release and times every input; `--compare` marks each one more than 10% slower than the base as `SLOWER` and exits 1. `Tools/iterate.sh` runs exactly this.

**Compare with the latest step (now `after-1.5-proxies.json`), not with 0.2.1.** §1.2 made every app's `run` about five times faster without touching the interpreter (see below), so "not slower than 0.2.1" would let the VM give all of that back unnoticed. Each step's file is the bar for the next.

## What's timed

The inputs:

- `Examples/Apps/*.swift`: Kiln's example apps.
- `Examples/AppleIntelligence/*.md`: model replies, merged into one source the way Haplo AI runs them.
- `Examples/Networking/*.swift`.
- `fixtures/apps/*.swift` (Shelf's, at the repo root): one app per section of Shelf's prompt. An app that uses `DB.` reaches a `DB` host bridge over an in-memory store, as Shelf's since PLAN.md §1.7 (before it, KilnBench appended `shelf-db-prelude.swift`, as Shelf's `SourceRewriter` did; `Tools/diff.sh` still does for its baseline engine).
- `Workloads/*.swift`: loops and arithmetic, collections, objects and closures. Their work runs in `onAppear`, so they time the interpreter rather than the parser. The apps above spend most of their time parsing.

Two calls per input:

- **run**: `Kiln.run`, which parses, sets up the interpreter and wraps the root view. No `body` is evaluated.
- **validate**: `Kiln.validate`, which does the same, then evaluates every `body` and fires every action once.

Each call is timed once cold, then in 21 samples. A sample repeats the call until it has lasted about 20 ms and divides, so a 1 ms app isn't lost in the clock's noise. The JSON has the cold time, the median and the minimum per call. **Comparisons use the minimum.** It's the steadiest number on a busy machine: on identical code, minimums moved by up to ±12% between two runs here, medians by up to ±46%. An input that comes out more than 10% slower is timed twice more and the fastest kept, before it counts.

Nothing touches the network. Every http(s) request fails at once with "not connected", as in Shelf's fixture tests, and `DB` is answered from memory.

## Results

Validate, minimum per call, in ms. "run" is `Kiln.run`'s minimum.

| Input | 0.2.1 run | 0.2.1 validate | §1.2 run | §1.2 validate |
|---|---:|---:|---:|---:|
| Apps/Chess.swift | 10.57 | 19.13 | 2.66 | 12.57 |
| Apps/ExpenseTracker.swift | 2.46 | 2.64 | 0.53 | 0.80 |
| Apps/FocusTimer.swift | 1.70 | 1.77 | 0.38 | 0.52 |
| Apps/HabitTracker.swift | 1.93 | 2.23 | 0.39 | 0.72 |
| Apps/MemoryMatch.swift | 1.71 | 2.01 | 0.38 | 0.56 |
| Apps/ReadingList.swift | 3.00 | 3.30 | 0.64 | 1.11 |
| Apps/TipCalculator.swift | 1.01 | 1.11 | 0.23 | 0.32 |
| AppleIntelligence/expense.md | 1.39 | 1.41 | 0.27 | 0.35 |
| AppleIntelligence/habit.md | 1.01 | 1.07 | 0.21 | 0.27 |
| AppleIntelligence/memory.md | 1.32 | 1.45 | 0.28 | 0.32 |
| AppleIntelligence/timer.md | 1.83 | 1.99 | 0.38 | 0.48 |
| AppleIntelligence/tip.md | 0.99 | 1.22 | 0.22 | 0.48 |
| Networking/OpenLibrarySearch.swift | 1.33 | 1.57 | 0.27 | 0.58 |
| apps/images.swift | 1.48 | 1.66 | 0.28 | 0.40 |
| apps/network.swift | 2.33 | 2.50 | 0.48 | 0.68 |
| apps/saving-data.swift | 2.97 | 3.85 | 0.59 | 1.40 |
| apps/state.swift | 1.65 | 1.80 | 0.35 | 0.47 |
| apps/swift-language.swift | 3.46 | 3.79 | 0.73 | 1.09 |
| apps/time.swift | 1.60 | 1.77 | 0.32 | 0.47 |
| apps/todos-db.swift | 1.18 | 1.61 | 0.25 | 0.64 |
| apps/views-layout-drawing.swift | 3.61 | 3.79 | 0.72 | 1.15 |
| apps/views-lists-controls.swift | 2.47 | 2.77 | 0.47 | 0.80 |
| apps/views-navigation.swift | 2.61 | 2.82 | 0.56 | 0.76 |
| Workloads/Arithmetic.swift | 0.73 | 317.28 | 0.16 | 315.89 |
| Workloads/Collections.swift | 0.81 | 32.27 | 0.18 | 31.88 |
| Workloads/Objects.swift | 0.97 | 31.97 | 0.26 | 32.13 |
| **Total** | | **448.78** | | **406.84** |

### baseline-0.2.1.json

Kiln 0.2.1 with Shelf's patch (`JSONEncoder.encode`, `[T].self`, decoded `UUID`), as Shelf ran it from `Vendor/Kiln` before the move: commit `e816069`, with only `Tools/` changed to time it. Every input passes `validate` with no errors.

- Machine: Mac with an Apple M2 Pro, 16 GB, macOS 27.3. Other builds were running (load average 6 to 12).
- Toolchain: Xcode 27.1 (27A9269), Swift 6.4. `swift build -c release`.
- Command: `Benchmarks/run.sh Benchmarks/baseline-0.2.1.json` (21 samples).
- Date: 24 November 2026.

### after-1.2-one-engine.json

The same, after §1.2 deleted the original interpreter. Every input still passes with no errors.

- Command: `Benchmarks/run.sh Benchmarks/after-1.2-one-engine.json --compare Benchmarks/baseline-0.2.1.json` (21 samples). Load average 6 to 10. Date: 24 November 2026.
- **`run` is 4 to 5 times faster on every app, and `validate` 1.5 to 4.5 times.** None of it is the interpreter: the compute workloads are unchanged (within ±1.2%). It's the dialect check. Before running anything, 0.2.1 scanned the whole source for ten strings (`GameCanvas(`, `.onTick(` …) to pick an engine, in both `run` and `validate`, with Foundation's `String.contains`. That costs 0.9 ms on TipCalculator's 2 KB and 8.7 ms on Chess's 21 KB, measured alone with `swiftc -O`. That's three quarters of what `Kiln.run` took on a typical app, and Shelf calls it each time an app opens.
- What's left is parsing and the walk: `run` is now 0.2 to 0.7 ms per app (Chess 2.7 ms), and `validate` adds the body and the actions.


### after-1.3-async.json

After §1.3 (code that can wait). Every input still passes with no errors. `Tools/iterate.sh` now compares against this file.

- Command: `Benchmarks/run.sh Benchmarks/after-1.3-async.json --compare Benchmarks/after-1.2-one-engine.json` (21 samples). Load average about 5. Date: 24 November 2026.
- **No input is slower.** Code without an `await` runs on the same tree-walker as before; what §1.3 adds to its hot path is a cached flag read per call and an enum check per expression statement.
- **Apps that use `DB` are about twice as fast to validate** (saving-data −46%, todos-db −55%): `DB` is answered by the host at once (`Kiln.hostRequestHandler`) instead of a round trip through `URLSession` and a semaphore. OpenLibrarySearch (−48%) no longer starts a request at all: `validate` is headless and fails it at once.
- The compute workloads are 4% faster, which is within what a quieter machine gives; nothing in them changed.

Validate, minimum per call, in ms:

| Input | §1.2 | §1.3 | Change |
|---|---:|---:|---:|
| Apps/Chess.swift | 12.57 | 10.95 | -13% |
| Apps/ExpenseTracker.swift | 0.80 | 0.70 | -13% |
| Apps/FocusTimer.swift | 0.52 | 0.48 | -8% |
| Apps/HabitTracker.swift | 0.72 | 0.67 | -7% |
| Apps/MemoryMatch.swift | 0.56 | 0.53 | -5% |
| Apps/ReadingList.swift | 1.11 | 0.95 | -14% |
| Apps/TipCalculator.swift | 0.32 | 0.30 | -6% |
| AppleIntelligence/expense.md | 0.35 | 0.32 | -9% |
| AppleIntelligence/habit.md | 0.27 | 0.25 | -7% |
| AppleIntelligence/memory.md | 0.32 | 0.30 | -6% |
| AppleIntelligence/timer.md | 0.48 | 0.44 | -8% |
| AppleIntelligence/tip.md | 0.48 | 0.44 | -8% |
| Networking/OpenLibrarySearch.swift | 0.58 | 0.30 | -48% |
| apps/async.swift | – | 0.55 | new |
| apps/images.swift | 0.40 | 0.37 | -8% |
| apps/network.swift | 0.68 | 0.68 | +0% |
| apps/saving-data.swift | 1.40 | 0.75 | -46% |
| apps/state.swift | 0.47 | 0.45 | -4% |
| apps/swift-language.swift | 1.09 | 1.04 | -5% |
| apps/time.swift | 0.47 | 0.45 | -4% |
| apps/todos-db.swift | 0.64 | 0.29 | -55% |
| apps/views-layout-drawing.swift | 1.15 | 1.02 | -11% |
| apps/views-lists-controls.swift | 0.80 | 0.72 | -10% |
| apps/views-navigation.swift | 0.76 | 0.71 | -7% |
| Workloads/Arithmetic.swift | 315.89 | 302.15 | -4% |
| Workloads/Collections.swift | 31.88 | 30.49 | -4% |
| Workloads/Objects.swift | 32.13 | 30.86 | -4% |
| **Total (inputs in both)** | **406.84** | **386.61** | -5% |

### after-1.4-registry.json

After §1.4 (bridges in a registry). `Tools/iterate.sh` now compares against this file.

- Command: `Benchmarks/run.sh Benchmarks/after-1.4-registry.json --compare Benchmarks/after-1.3-async.json` (21 samples). Date: 24 November 2026.
- **No input is more than 10% slower.** The worst is views-layout-drawing, 5.9% slower. The compute workloads are within 2%.
- `expense.md` now fails `validate` on purpose: it writes `.stepValue(0.1)`, which isn't SwiftUI, and an unknown modifier is an error.
- **What it costs.** A view or modifier call now:
  - picks an overload by labels and argument syntax;
  - evaluates each argument against its parameter's kind;
  - keeps the overload it picked.

  The first port was 10 to 16% slower on view-heavy apps. These made it cheap again:
  - an error message, a member name (`Date.now`) or an argument-syntax array is no longer built until it's needed;
  - a value's fallback type (a `String`'s characters, for `map`) is made only when its own type lacks the member;
  - each parameter's expected type is made once, at registration;
  - the interpreter keeps the registry.
- **Back to back.** Run back to back on this machine against the engine before the registry (b466f9c), apps are 0 to 5% slower to validate, and 2.5% in total. One 0.01 ms clock tick is 2 to 3% on these sub-millisecond inputs.

Validate, minimum per call, in ms:

| Input | §1.3 | §1.4 | Change |
|---|---:|---:|---:|
| Apps/Chess.swift | 10.95 | 11.29 | +3% |
| Apps/ExpenseTracker.swift | 0.70 | 0.73 | +4% |
| Apps/FocusTimer.swift | 0.48 | 0.49 | +2% |
| Apps/HabitTracker.swift | 0.67 | 0.70 | +4% |
| Apps/MemoryMatch.swift | 0.53 | 0.52 | -2% |
| Apps/ReadingList.swift | 0.95 | 0.98 | +3% |
| Apps/TipCalculator.swift | 0.30 | 0.31 | +3% |
| AppleIntelligence/expense.md | 0.32 | 0.32 | +0% |
| AppleIntelligence/habit.md | 0.25 | 0.25 | +0% |
| AppleIntelligence/memory.md | 0.30 | 0.30 | +0% |
| AppleIntelligence/timer.md | 0.44 | 0.45 | +2% |
| AppleIntelligence/tip.md | 0.44 | 0.46 | +5% |
| Networking/OpenLibrarySearch.swift | 0.30 | 0.29 | -3% |
| apps/async.swift | 0.55 | 0.56 | +2% |
| apps/images.swift | 0.37 | 0.38 | +3% |
| apps/network.swift | 0.68 | 0.65 | -4% |
| apps/saving-data.swift | 0.75 | 0.76 | +1% |
| apps/state.swift | 0.45 | 0.46 | +2% |
| apps/swift-language.swift | 1.04 | 1.07 | +3% |
| apps/time.swift | 0.45 | 0.45 | +0% |
| apps/todos-db.swift | 0.29 | 0.30 | +3% |
| apps/views-layout-drawing.swift | 1.02 | 1.08 | +6% |
| apps/views-lists-controls.swift | 0.72 | 0.75 | +4% |
| apps/views-navigation.swift | 0.71 | 0.73 | +3% |
| Workloads/Arithmetic.swift | 302.15 | 303.03 | +0% |
| Workloads/Collections.swift | 30.49 | 30.31 | -1% |
| Workloads/Objects.swift | 30.86 | 30.28 | -2% |

## §1.3: Code that can wait

PLAN.md §1.3 asked for a spike first: a bytecode VM with lowering for everything, frames on the heap and resolved slots, running every input with output identical to the tree-walker's, with no bridges changed; Go if it matched everywhere and was slower nowhere, else the fallback, a second evaluator for code that contains `await`.

**Decision: the fallback.** I scoped the VM against the code and chose not to build it in this step; no VM was written, so there are no VM numbers. Two things decided it.

1. **"No bridges changed" can't hold for a VM with resolved slots.** The bridges take syntax, not values. `KBuiltins.callGlobal`, `callStatic` and `color`, and `KInterpreter.evalCall`/`callMethod`/`viewMethod`, receive the unevaluated arguments and a live `KEnv`. They evaluate each argument themselves with an expected type picked per callee and label (so `.red`, `.title` and `.segmented` resolve), turn a string literal into a `LocalizedStringKey` only when it is a `Text` or title (that's how `Text("\(n) pages")` reads "1,400 pages"), and resolve names at run time by asking the environment (`isBuiltinTypeName` checks `env.lookup` before treating `Color` as a type; implicit `self` members, `@State` storage, globals, functions and types are tried in that order on every lookup). A VM whose locals are slots has no `KEnv` to hand them. Making those calls take values is exactly §1.4's work (the registry, with `call.binding("selection", …)`-style decoding), so doing it here would be doing §1.4 inside §1.3, under the stricter "identical output" bar.
2. **The fallback can be as good at waiting.** What Round 3 needs (the photo picker, Foundation Models, WebSockets, `WebPage`, `CLLocationUpdate.liveUpdates()`) is real suspension and resumption, which the second evaluator gives fully.

The second evaluator isn't Swift `async`, which would have been shorter. I measured why not: `Kiln.validate` is synchronous and is called from main-actor jobs (Swift Testing, XCTest, SwiftUI), and a nested run loop doesn't run other main-actor jobs while one is executing (a 1 ms `Task.sleep` started from inside a main-queue block hadn't run after 1 s of `RunLoop.main.run`; from top-level code it ran in 1 ms). So a Swift-`async` evaluator could never let `validate` check code after an `await`. Instead the second evaluator is resumable and explicit (`Engine/KEAsync.swift`): a task is a stack of `KFrame`s on the heap, each a state machine over one statement or expression. It runs synchronously until a suspension really has to wait, so headless `validate` drives tasks to their end, while a live run parks and resumes on the main actor. That is the heap-frame half of the VM, and the suspension API (`KSuspension`) is the one the VM will need.

**Where the VM's speed would come from.** Sampling the Arithmetic workload: most of the time is `swift_retain`/`swift_release`, copies of `KV`, and array copies of the tree's indirect enums as the walker switches over them. Lowering to instructions with slots removes exactly that. **Recommendation:** build the VM after §1.4, when the bridges take decoded values; lower all code to it then, keeping `KEAsync`'s frame and suspension model, and retire the tree-walker.

**Differential:** [differential.md](differential.md): 49 inputs (Kiln's example apps and model replies, Networking, LibraryApp, Shelf's `fixtures/apps`, the workloads, and the SwiftUI sources in Kiln's tests), 47 identical to the engine before §1.3, 2 different as expected and listed in `Tools/diff-expected.txt` (a button calling a non-`async` function that awaits is now an error with its line instead of blocking the main thread on the request; and the new async fixture, which the old engine couldn't run).

### after-1.7-context.json

After §1.7 (a context for each run). Every input still passes as before. `Tools/iterate.sh` now compares against this file.

- Command: `Benchmarks/run.sh Benchmarks/after-1.7-context.json --compare <the base commit's run, the same session>` (21 samples): the base (`08fd535`) was benched minutes before, on the same machine, so the two differ only by the change. Load average about 4. Date: 24 November 2026.
- **No input is slower than 10%.** Each check now has a stub context, which costs nothing until the app uses it: its folder is named only when a file is touched, and its settings are in memory (`KilnMemoryDefaults`), not a suite cfprefsd has to make and remove. A first version made both every time, and small inputs were 5 to 12% slower.
- **Apps that use `DB` are faster again** (saving-data −24%, todos-db −47%): `DB` is a host bridge now, with no `URLRequest` built and answered per call. saving-data's `@AppStorage` is in memory during a check.
- KilnBench registers an in-memory `DB` host bridge instead of appending the old prelude.

### after-1.6-language.json

PLAN.md §1.6: protocols, result builders, property wrappers, custom Codable, regex literals, macros as declarations, and errors about the app's own types. Measured after merging §1.7, so the base is `after-1.7-context.json`.

- **The command.** `Benchmarks/run.sh Benchmarks/after-1.6-language.json --compare Benchmarks/after-1.7-context.json` (21 samples). Date: 24 November 2026.
- **No input is more than 10% slower.** The worst is Chess, 8% slower. Apps are 0 to 6% slower, and the compute workloads are within 2%.
- **What it costs.** Loading a program now does two more things:
  - closing each type's conformances over inheritance;
  - adopting default implementations.

  Each call to one of the app's functions now checks its labels as Swift does.
- **How it was made cheap.** The first version was 10 to 28% slower than the engine before it, timed the same hour; Objects, method calls and memberwise inits, was the 28%. These brought it back:
  - Closure flags are built only when a call has a closure literal.
  - The memberwise labels are kept per type.
  - The wrapped-property check runs only for types that have wrapped properties.
  - The nested-type lookup runs only for names that are nested somewhere.
  - The extension-on-a-native-type `self` check runs only after the registry has no such name.
  - Loading skips conformance walks, adoption, hooks and requirement checks when the program has nothing for them.

Validate, minimum per call, in ms:

| Input | §1.7 | §1.6 | Change |
|---|---:|---:|---:|
| Apps/Chess.swift | 11.47 | 12.40 | +8% |
| Apps/ExpenseTracker.swift | 0.74 | 0.77 | +4% |
| Apps/FocusTimer.swift | 0.50 | 0.51 | +2% |
| Apps/HabitTracker.swift | 0.72 | 0.75 | +4% |
| Apps/MemoryMatch.swift | 0.53 | 0.55 | +4% |
| Apps/ReadingList.swift | 0.99 | 1.04 | +5% |
| Apps/TipCalculator.swift | 0.31 | 0.32 | +3% |
| AppleIntelligence/expense.md | 0.33 | 0.34 | +3% |
| AppleIntelligence/habit.md | 0.26 | 0.27 | +4% |
| AppleIntelligence/memory.md | 0.30 | 0.31 | +3% |
| AppleIntelligence/timer.md | 0.45 | 0.46 | +2% |
| AppleIntelligence/tip.md | 0.46 | 0.47 | +2% |
| Networking/OpenLibrarySearch.swift | 0.30 | 0.31 | +3% |
| apps/async.swift | 0.56 | 0.58 | +4% |
| apps/images.swift | 0.39 | 0.40 | +3% |
| apps/network.swift | 0.63 | 0.65 | +3% |
| apps/saving-data.swift | 0.58 | 0.60 | +3% |
| apps/state.swift | 0.47 | 0.50 | +6% |
| apps/swift-builders.swift (new) | | 0.67 | |
| apps/swift-codable.swift (new) | | 0.89 | |
| apps/swift-language.swift | 1.08 | 1.13 | +5% |
| apps/swift-protocols.swift (new) | | 0.74 | |
| apps/time.swift | 0.46 | 0.48 | +4% |
| apps/todos-db.swift | 0.17 | 0.17 | +0% |
| apps/views-layout-drawing.swift | 1.08 | 1.11 | +3% |
| apps/views-lists-controls.swift | 0.75 | 0.77 | +3% |
| apps/views-navigation.swift | 0.74 | 0.77 | +4% |
| Workloads/Arithmetic.swift | 303.31 | 303.99 | +0% |
| Workloads/Collections.swift | 30.43 | 30.56 | +0% |
| Workloads/Objects.swift | 30.56 | 31.09 | +2% |

### after-1.8-check.json

PLAN.md §1.8: `Kiln.check`, the static checker, measured with §1.6 merged, so the base is `after-1.6-language.json`.

- **The command.** `Benchmarks/run.sh Benchmarks/after-1.8-check.json --compare Benchmarks/after-1.6-language.json` (21 samples). Date: 24 November 2026.
- **No input is slower.** Every input is within 3% of §1.6. `check` isn't on the path `run` and `validate` take; what §1.8 adds to it is the parser keeping `async` on functions and two flags on each overload.
- Against `after-1.7-context.json` one run showed `apps/images.swift` 10.3% slower (0.39 to 0.43 ms) and the next 2.6%: noise at that size.
- **`check` itself** takes a few milliseconds on the largest app (`CheckTests.testCheckIsFast`), and Shelf's slowest fixture checks and validates in about 12 ms on the simulator (`NewAppCheckTests.checkAndValidateAreFastEnough`).

### after-1.5-proxies.json

PLAN.md §1.5: protocol proxies (Shape, Animatable, Layout, ViewModifier, Transition, representables, delegates, Transferable, FileDocument, async requirements). Measured with §1.8 merged, so the base is `after-1.8-check.json`.

- **The command.** `Benchmarks/run.sh Benchmarks/after-1.5-proxies.json --compare Benchmarks/after-1.8-check.json` (21 samples). Load average about 3. Date: 24 November 2026.
- **No input is more than 10% slower.** The worst are the model replies, 6 to 7% slower at about 0.3 ms each (a few hundredths of a millisecond); the example apps and fixtures are within 5%, and the compute workloads within 5%. Before the merge, against `after-1.6-language.json`, the worst was 4.4%.
- **What it costs.** Loading a program checks each type that adopts one of the registry's protocols against its requirements (a set lookup per conformance). A proxy costs nothing until native code calls the app's value through it.
- **New inputs.** Three Lab examples (`WaveStudio`, `TagCloud`, `CardStyles`) and two Shelf fixtures (`views-custom-protocols`, `views-uikit`), with nothing to compare against.

### after-2-round1-rest.json

PLAN.md §2, Round 1's second half (gestures, drawing, focus, environment, charts, text, accessibility), measured with Round 1A merged, against the bar `after-1.5-proxies.json`.

- **The command.** `Benchmarks/run.sh Benchmarks/after-2-round1-rest.json --compare Benchmarks/after-1.5-proxies.json`. Date: 24 November 2026.
- **No input is more than 10% slower.** The compute workloads are within 1% (`Collections` 7% and `Objects` 13% faster), Chess within 2%. A first run made while other builds ran showed `Arithmetic` 23% slower; run alone it was under 4%.
- **Validate does more for Round 1 inputs.** Bridges' probes now run a `Canvas` renderer, a gesture's `onChanged` and an animator's content with sample arguments, where `validate` used to skip them, so `gestures-canvas` and `DoodlePad` take longer than before that change (recorded here after it).
- **Kiln Lab** (`Tools/iterate.sh`): 12 of 12 apps match native on every step, labels 100%.
- **What it costs.** A view that reads SwiftUI's environment, or has a `@FocusState` or `@Namespace`, is hosted inside one more view (`KHostInputs`); others are hosted as before.
- **New inputs.** The four Round 1 fixtures (`gestures-canvas`, `focus-environment`, `charts`, `accessibility-motion`) and Lab's `DoodlePad`.

### after-3a-round2a.json

PLAN.md §3.1–§3.4, Round 2A (haptics, share and paste, text parsing, units), against the bar `after-2-round1-rest.json`.

- **The command.** `Benchmarks/run.sh Benchmarks/after-3a-round2a.json --compare Benchmarks/after-2-round1-rest.json`. Date: 24 November 2026.
- **No input is more than 10% slower.** By minimum, the worst is `AppleIntelligence/habit.md` at 7% (0.3 ms); by median, `apps/navigation-tabs.swift` at 9.9% (0.71 to 0.78 ms, 4% by minimum). The compute workloads are within 4%, Chess within 2%.
- **What it costs.** An operator on two values the engine doesn't know first asks the operand's type bridge (`t.operator`), after every built-in case; a member of a native type that names a nested type (`NSTextCheckingResult.CheckingType`) is one more dictionary lookup.
- **Kiln Lab:** `TripNotes` matches native on every step, labels and screenshots.
- **New inputs.** The four Round 2A fixtures (`haptics`, `sharing`, `text-parsing`, `units`) and Lab's `TripNotes`. `text-parsing` and `TripNotes` validate in about 4 ms: NaturalLanguage's taggers and the data detector load their models on first use.

### after-3c-round2c.json

PLAN.md §3, Round 2C (Foundation and the standard library), with Round 2B merged, against the bar `after-3a-round2a.json`.

- **The command.** `Benchmarks/run.sh Benchmarks/after-3c-round2c.json --compare Benchmarks/after-3a-round2a.json`. Date: 24 November 2026.
- **No input is more than 10% slower.** The worst is `Apps/TripNotes.swift` at 4.5%, then `apps/time.swift` and `apps/accessibility-motion.swift` at 4.1%; the compute workloads are 1% slower to 4% faster (`Arithmetic` −3.7%, `Collections` −3.5%), Chess within 1%.
- **A first run was 15–35% slower.** Most of it was one call: deciding whether an app names `Result` or `AnyIterator` (Swift's types Kiln writes in Swift, `KSwiftPrelude`) searched the whole source with Foundation's Unicode-aware `contains`, about a quarter of a small app's run; it's a byte search now. Also cut: a literal-coercion lookup in every `coerce`, a second lookup for each interpolated name, and a cast in every `KRef` comparison. Measured against `shelf-fixes` on the same machine, interleaved: the same within noise.
- **What it costs.** A static member the type's bridge doesn't have is checked against the registry's symbolic types (`requireSymbolic`); a closure's `$n` are scanned once per closure (`KEClosureScan`); a `Sequence` method on an app's value first looks for its iterator.
- **Kiln Lab** (`Tools/iterate.sh`): 16 of 16 apps match native on every step but `Terrain`, whose last step reads the slider after the UI test drags it (2.9 against 3.0, and the other way on a rerun); `Ledger` matches on every step, labels 100%.
- **New inputs.** The fixture `foundation-stdlib` and Lab's `Ledger`, with nothing to compare against.

### after-4a-round3a.json

PLAN.md §4, Round 3A (files, photos, the camera and recording), against the base commit `0d20cf9` (`after-3c-round2c`'s engine) measured back to back on the same machine.

- **The command.** `Benchmarks/run.sh base.json` in a worktree at `0d20cf9`, then `Benchmarks/run.sh Benchmarks/after-4a-round3a.json --compare base.json` here. Date: 24 November 2026.
- **No input is more than 10% slower.** The worst is +4.6%; the compute workloads are within 3% (`Arithmetic` −2.2%).
- **Why not against `after-3c-round2c.json` directly.** The Mac was busy (other agents' builds and simulators): a first run against the checked-in file was 5–12% slower on every input, the pure-arithmetic workload included, which this round doesn't touch. Back to back with the base engine, the difference is gone.
- **What it costs.** Deciding whether an app needs the prelude's `Result` now also searches for five bridge names (`fileImporter`, `loadTransferable`…), a byte search each.
- **Kiln Lab:** `Scrapbook` (files, `UTType`, `resourceValues`, drag and drop) matches native on every step.
- **New inputs.** The fixtures `files`, `photos`, `camera` and `recorder`, and Lab's `Scrapbook`, with nothing to compare against.

## §3.7: SurfacePlot

`SurfacePlot(x:y:z:) { x, z in … }` hands Swift Charts a function it calls once per sample: 256 × 256 per pass, and two passes when a chart first draws. Each call is the app's closure, run by the interpreter.

- **The input.** The function a model writes for a surface, `{ x, z in sin(frequency * x) * cos(frequency * z) }`, called over a `side` × `side` grid in `onAppear`, timed with `Tools/bench.py --runs 7` (release KilnBench). Apple M2 Pro. Date: 24 November 2026.

| Grid | Calls | validate (min) | Per call |
|---|---:|---:|---:|
| 48 × 48 | 2,304 | 17.13 ms | 7.4 µs |
| 256 × 256 | 65,536 | 502.55 ms | 7.7 µs |

- **Uncapped, a chart's first draw would take about a second** of the main thread on this Mac (two 256 × 256 passes), and again whenever the app's state gives the chart a new function. So the sample count is capped: Kiln runs the app's function on a 48 × 48 grid over the domain Swift Charts asks about, and Swift Charts' 256 × 256 calls interpolate it natively (`KSurfaceSampler`, Bridges/Chart3D). A sampling costs 17 ms here; the grid is redrawn only when the function or the domain changes.
- **Not measured on an iPhone yet.** The per-call cost scales with the closure; a function with more arithmetic samples proportionally slower.
