# Differential check

Every input run on the engine before §1.3 (`cc388b1`) and on this one, comparing their transcripts: the view tree each body evaluates to, the console, errors and warnings with their lines, and all of it again after each scripted action (`onAppear` and `.task` first, then each button and tap). `Tools/diff.sh` writes this file.

**48 inputs: 47 identical, 1 different as expected, 0 different otherwise.**

| Input | Transcript lines | Steps | Result |
|---|---:|---:|---|
| Packages/Kiln/Examples/Apps/Chess.swift | 21125 | 13 | identical |
| Packages/Kiln/Examples/Apps/ExpenseTracker.swift | 1654 | 13 | identical |
| Packages/Kiln/Examples/Apps/FocusTimer.swift | 910 | 13 | identical |
| Packages/Kiln/Examples/Apps/HabitTracker.swift | 1105 | 13 | identical |
| Packages/Kiln/Examples/Apps/MemoryMatch.swift | 2656 | 14 | identical |
| Packages/Kiln/Examples/Apps/ReadingList.swift | 125 | 1 | identical |
| Packages/Kiln/Examples/Apps/TipCalculator.swift | 42 | 1 | identical |
| Packages/Kiln/Examples/AppleIntelligence/expense.md | 754 | 13 | identical |
| Packages/Kiln/Examples/AppleIntelligence/habit.md | 377 | 13 | identical |
| Packages/Kiln/Examples/AppleIntelligence/memory.md | 31 | 1 | identical |
| Packages/Kiln/Examples/AppleIntelligence/timer.md | 338 | 13 | identical |
| Packages/Kiln/Examples/AppleIntelligence/tip.md | 1092 | 13 | identical |
| Packages/Kiln/Examples/Networking/OpenLibrarySearch.swift | 22 | 2 | identical |
| Packages/Kiln/Examples/LibraryApp.swift | 64 | 2 | identical |
| fixtures/apps/images.swift | 663 | 13 | identical |
| fixtures/apps/network.swift | 211 | 14 | identical |
| fixtures/apps/saving-data.swift | 1076 | 14 | identical |
| fixtures/apps/state.swift | 599 | 13 | identical |
| fixtures/apps/swift-language.swift | 1213 | 13 | identical |
| fixtures/apps/time.swift | 372 | 13 | identical |
| fixtures/apps/todos-db.swift | 296 | 14 | identical |
| fixtures/apps/views-layout-drawing.swift | 2560 | 13 | identical |
| fixtures/apps/views-lists-controls.swift | 1547 | 13 | identical |
| fixtures/apps/views-navigation.swift | 861 | 13 | identical |
| Packages/Kiln/Benchmarks/Workloads/Arithmetic.swift | 8 | 2 | identical |
| Packages/Kiln/Benchmarks/Workloads/Collections.swift | 112 | 2 | identical |
| Packages/Kiln/Benchmarks/Workloads/Objects.swift | 8 | 2 | identical |
| tests/AppTypesRepro-0.swift | 1742 | 13 | identical |
| tests/AppTypesRepro-1.swift | 17 | 1 | identical |
| tests/AppTypesRepro-2.swift | 234 | 13 | identical |
| tests/AppTypesRepro-3.swift | 327 | 13 | identical |
| tests/BreakoutRepro-0.swift | 8 | 2 | identical |
| tests/KilnEngineTests-0.swift | 5 | 1 | identical |
| tests/KilnEngineTests-1.swift | 6 | 1 | identical |
| tests/KilnEngineTests-2.swift | 9 | 1 | identical |
| tests/KilnEngineTests-3.swift | 3 | 1 | identical |
| tests/KilnEngineTests-4.swift | 3 | 1 | identical |
| tests/KilnEngineTests-5.swift | 3 | 1 | identical |
| tests/KilnValidateTests-0.swift | 299 | 13 | identical |
| tests/KilnValidateTests-1.swift | 4 | 1 | identical |
| tests/KilnValidateTests-2.swift | 4 | 1 | identical |
| tests/KilnValidateTests-3.swift | 12 | 1 | identical |
| tests/KilnValidateTests-4.swift | 4 | 1 | identical |
| tests/SnakeGameTests-0.swift | 3 | 1 | identical |
| tests/SnakeGameTests-1.swift | 8 | 2 | identical |
| tests/SnakeGameTests-2.swift | 3 | 1 | identical |
| tests/WeatherRepro-0.swift | 209 | 13 | expected (A button calls fetchWeather(), which isn't async but awaits URLSession: §1.3 reports that with its line, where 0.2.1 blocked the main thread on the request.) |
| tests/WeatherRepro-1.swift | 183 | 14 | identical |

## tests/WeatherRepro-0.swift

```diff
--- before
+++ after
@@ -17,193 +17,193 @@
 == after Button(action)@12
-error: Uncaught error: The operation couldn’t be completed. (NSURLErrorDomain error -1009.)
-ContentView {temperature=0.0, condition="N/A"}
-  VStack(spacing: 20, {fn})
-    Text(_literal: "New York City Weather")
-      .font(Font)
-    HStack({fn})
-      Text(_literal: "0.000000°F")
-        .font(Font)
-      Text("N/A")
-        .font(Font)
-    Button(action: {fn}, label: {fn})
-      Label("Refresh", systemImage: "arrow.clockwise")
-        .padding()
-        .background(Color)
-        .foregroundColor(Color)
-        .cornerRadius(10)
-== after Button(action)@12
-ContentView {temperature=0.0, condition="N/A"}
-  VStack(spacing: 20, {fn})
-    Text(_literal: "New York City Weather")
-      .font(Font)
-    HStack({fn})
-      Text(_literal: "0.000000°F")
-        .font(Font)
-      Text("N/A")
-        .font(Font)
-    Button(action: {fn}, label: {fn})
-      Label("Refresh", systemImage: "arrow.clockwise")
-        .padding()
-        .background(Color)
-        .foregroundColor(Color)
-        .cornerRadius(10)
-== after Button(action)@12
-ContentView {temperature=0.0, condition="N/A"}
-  VStack(spacing: 20, {fn})
-    Text(_literal: "New York City Weather")
-      .font(Font)
-    HStack({fn})
-      Text(_literal: "0.000000°F")
-        .font(Font)
-      Text("N/A")
-        .font(Font)
-    Button(action: {fn}, label: {fn})
-      Label("Refresh", systemImage: "arrow.clockwise")
-        .padding()
-        .background(Color)
-        .foregroundColor(Color)
-        .cornerRadius(10)
-== after Button(action)@12
-ContentView {temperature=0.0, condition="N/A"}
-  VStack(spacing: 20, {fn})
-    Text(_literal: "New York City Weather")
-      .font(Font)
-    HStack({fn})
-      Text(_literal: "0.000000°F")
-        .font(Font)
-      Text("N/A")
-        .font(Font)
-    Button(action: {fn}, label: {fn})
-      Label("Refresh", systemImage: "arrow.clockwise")
-        .padding()
-        .background(Color)
-        .foregroundColor(Color)
-        .cornerRadius(10)
-== after Button(action)@12
-ContentView {temperature=0.0, condition="N/A"}
-  VStack(spacing: 20, {fn})
-    Text(_literal: "New York City Weather")
-      .font(Font)
-    HStack({fn})
-      Text(_literal: "0.000000°F")
-        .font(Font)
-      Text("N/A")
-        .font(Font)
-    Button(action: {fn}, label: {fn})
-      Label("Refresh", systemImage: "arrow.clockwise")
-        .padding()
-        .background(Color)
-        .foregroundColor(Color)
-        .cornerRadius(10)
-== after Button(action)@12
-ContentView {temperature=0.0, condition="N/A"}
-  VStack(spacing: 20, {fn})
-    Text(_literal: "New York City Weather")
-      .font(Font)
-    HStack({fn})
-      Text(_literal: "0.000000°F")
-        .font(Font)
-      Text("N/A")
-        .font(Font)
-    Button(action: {fn}, label: {fn})
-      Label("Refresh", systemImage: "arrow.clockwise")
-        .padding()
-        .background(Color)
-        .foregroundColor(Color)
-        .cornerRadius(10)
-== after Button(action)@12
-ContentView {temperature=0.0, condition="N/A"}
-  VStack(spacing: 20, {fn})
-    Text(_literal: "New York City Weather")
-      .font(Font)
-    HStack({fn})
-      Text(_literal: "0.000000°F")
-        .font(Font)
-      Text("N/A")
-        .font(Font)
-    Button(action: {fn}, label: {fn})
-      Label("Refresh", systemImage: "arrow.clockwise")
-        .padding()
-        .background(Color)
-        .foregroundColor(Color)
-        .cornerRadius(10)
-== after Button(action)@12
-ContentView {temperature=0.0, condition="N/A"}
-  VStack(spacing: 20, {fn})
-    Text(_literal: "New York City Weather")
…
```
