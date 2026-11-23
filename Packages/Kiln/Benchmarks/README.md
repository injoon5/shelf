# Benchmarks

How fast Kiln runs Shelf's apps, recorded at each step of the rewrite. PLAN.md §1.3: the bytecode VM must not be slower than 0.2.1 on any input. §1.10: a regression past 10% on any input blocks the merge.

```sh
Benchmarks/run.sh /tmp/now.json --compare Benchmarks/baseline-0.2.1.json
```

`run.sh` builds `Tools/KilnBench` in release and times every input; `--compare` marks each one more than 10% slower than the base as `SLOWER` and exits 1. `Tools/iterate.sh` runs exactly this.

## What's timed

The inputs:

- `Examples/Apps/*.swift`: Kiln's example apps.
- `Examples/AppleIntelligence/*.md`: model replies, merged into one source the way Haplo AI runs them.
- `Examples/Networking/*.swift`.
- `fixtures/apps/*.swift` (Shelf's, at the repo root): one app per section of Shelf's prompt. An app that uses `DB.` gets `shelf-db-prelude.swift` appended, as Shelf's `SourceRewriter` does.
- `Workloads/*.swift`: loops and arithmetic, collections, objects and closures. Their work runs in `onAppear`, so they time the interpreter rather than the parser. The apps above spend most of their time parsing.

Two calls per input:

- **run**: `Kiln.run`, which parses, sets up the interpreter and wraps the root view. No `body` is evaluated.
- **validate**: `Kiln.validate`, which does the same, then evaluates every `body` and fires every action once.

Each call is timed once cold, then in 21 samples. A sample repeats the call until it has lasted about 20 ms and divides, so a 1 ms app isn't lost in the clock's noise. The JSON has the cold time, the median and the minimum per call. **Comparisons use the minimum.** It's the steadiest number on a busy machine: on identical code, minimums moved by up to ±12% between two runs here, medians by up to ±46%. An input that comes out more than 10% slower is timed twice more and the fastest kept, before it counts.

Nothing touches the network. Every http(s) request fails at once with "not connected", as in Shelf's fixture tests, and `db://` requests are answered from memory, as Shelf's `ShelfDBProtocol` does.

## Results

Validate, minimum per call, in ms. "run" is `Kiln.run`'s minimum.

| Input | 0.2.1 run | 0.2.1 validate | §1.2 run | §1.2 validate |
|---|---:|---:|---:|---:|
| Apps/Chess.swift | 10.57 | 19.13 | | |
| Apps/ExpenseTracker.swift | 2.46 | 2.64 | | |
| Apps/FocusTimer.swift | 1.70 | 1.77 | | |
| Apps/HabitTracker.swift | 1.93 | 2.23 | | |
| Apps/MemoryMatch.swift | 1.71 | 2.01 | | |
| Apps/ReadingList.swift | 3.00 | 3.30 | | |
| Apps/TipCalculator.swift | 1.01 | 1.11 | | |
| AppleIntelligence/expense.md | 1.39 | 1.41 | | |
| AppleIntelligence/habit.md | 1.01 | 1.07 | | |
| AppleIntelligence/memory.md | 1.32 | 1.45 | | |
| AppleIntelligence/timer.md | 1.83 | 1.99 | | |
| AppleIntelligence/tip.md | 0.99 | 1.22 | | |
| Networking/OpenLibrarySearch.swift | 1.33 | 1.57 | | |
| apps/images.swift | 1.48 | 1.66 | | |
| apps/network.swift | 2.33 | 2.50 | | |
| apps/saving-data.swift | 2.97 | 3.85 | | |
| apps/state.swift | 1.65 | 1.80 | | |
| apps/swift-language.swift | 3.46 | 3.79 | | |
| apps/time.swift | 1.60 | 1.77 | | |
| apps/todos-db.swift | 1.18 | 1.61 | | |
| apps/views-layout-drawing.swift | 3.61 | 3.79 | | |
| apps/views-lists-controls.swift | 2.47 | 2.77 | | |
| apps/views-navigation.swift | 2.61 | 2.82 | | |
| Workloads/Arithmetic.swift | 0.73 | 317.28 | | |
| Workloads/Collections.swift | 0.81 | 32.27 | | |
| Workloads/Objects.swift | 0.97 | 31.97 | | |
| **Total** | | **448.78** | | |

### baseline-0.2.1.json

Kiln 0.2.1 with Shelf's patch (`JSONEncoder.encode`, `[T].self`, decoded `UUID`), as Shelf ran it from `Vendor/Kiln` before the move: commit `e816069`, with only `Tools/` changed to time it. Every input passes `validate` with no errors.

- Machine: Mac with an Apple M2 Pro, 16 GB, macOS 27.3. Other builds were running (load average 6 to 12).
- Toolchain: Xcode 27.1 (27A9269), Swift 6.4. `swift build -c release`.
- Command: `Benchmarks/run.sh Benchmarks/baseline-0.2.1.json` (21 samples).
- Date: 24 November 2026.
