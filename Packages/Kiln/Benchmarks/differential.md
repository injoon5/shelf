# Differential check

Every input run on the engine at `b466f9c` and on this one, comparing their transcripts: the view tree each body evaluates to, the console, errors and warnings with their lines, and all of it again after each scripted action (`onAppear` and `.task` first, then each button and tap). `Tools/diff.sh` writes this file.

**50 inputs: 49 identical, 1 different as expected, 0 different otherwise.**

| Input | Transcript lines | Steps | Result |
|---|---:|---:|---|
| Packages/Kiln/Examples/Apps/Chess.swift | 21125 | 13 | identical |
| Packages/Kiln/Examples/Apps/ExpenseTracker.swift | 1654 | 13 | identical |
| Packages/Kiln/Examples/Apps/FocusTimer.swift | 910 | 13 | identical |
| Packages/Kiln/Examples/Apps/HabitTracker.swift | 1105 | 13 | identical |
| Packages/Kiln/Examples/Apps/MemoryMatch.swift | 2656 | 14 | identical |
| Packages/Kiln/Examples/Apps/ReadingList.swift | 125 | 1 | identical |
| Packages/Kiln/Examples/Apps/TipCalculator.swift | 42 | 1 | identical |
| Packages/Kiln/Examples/AppleIntelligence/expense.md | 754 | 13 | expected (The reply writes .stepValue(0.1), which isn't a SwiftUI modifier: §1.4 reports it with its line, where before it was skipped silently.) |
| Packages/Kiln/Examples/AppleIntelligence/habit.md | 377 | 13 | identical |
| Packages/Kiln/Examples/AppleIntelligence/memory.md | 31 | 1 | identical |
| Packages/Kiln/Examples/AppleIntelligence/timer.md | 338 | 13 | identical |
| Packages/Kiln/Examples/AppleIntelligence/tip.md | 1092 | 13 | identical |
| Packages/Kiln/Examples/Networking/OpenLibrarySearch.swift | 22 | 2 | identical |
| Packages/Kiln/Examples/LibraryApp.swift | 64 | 2 | identical |
| fixtures/apps/async.swift | 283 | 14 | identical |
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
| tests/RegistryTests-0.swift | 2 | 1 | identical |
| tests/SnakeGameTests-0.swift | 3 | 1 | identical |
| tests/SnakeGameTests-1.swift | 8 | 2 | identical |
| tests/SnakeGameTests-2.swift | 3 | 1 | identical |
| tests/WeatherRepro-0.swift | 209 | 13 | identical |
| tests/WeatherRepro-1.swift | 183 | 14 | identical |

## Packages/Kiln/Examples/AppleIntelligence/expense.md

```diff
--- before
+++ after
@@ -7,8 +7,3 @@
           Text(_literal: "New Expense")
-          TextField("Category", text: $"")
-            .textFieldStyle(.roundedBorder)
-          Stepper(value: $0.0, {fn})
-            Text(_literal: "0.00")
-            .stepValue(0.1)
-          DatePicker("Date", selection: $<date>, displayedComponents: .date)
+          content failed
         .padding()
@@ -22,2 +17,3 @@
         Button("Add Expense", {fn})
+error: Line 40: Kiln doesn't support the .stepValue() modifier
 == after Button[Add Expense]@65
@@ -29,8 +25,3 @@
           Text(_literal: "New Expense")
-          TextField("Category", text: $"")
-            .textFieldStyle(.roundedBorder)
-          Stepper(value: $0.0, {fn})
-            Text(_literal: "0.00")
-            .stepValue(0.1)
-          DatePicker("Date", selection: $<date>, displayedComponents: .date)
+          content failed
         .padding()
@@ -57,8 +48,3 @@
           Text(_literal: "New Expense")
-          TextField("Category", text: $"")
-            .textFieldStyle(.roundedBorder)
-          Stepper(value: $0.0, {fn})
-            Text(_literal: "0.00")
-            .stepValue(0.1)
-          DatePicker("Date", selection: $<date>, displayedComponents: .date)
+          content failed
         .padding()
@@ -91,8 +77,3 @@
           Text(_literal: "New Expense")
-          TextField("Category", text: $"")
-            .textFieldStyle(.roundedBorder)
-          Stepper(value: $0.0, {fn})
-            Text(_literal: "0.00")
-            .stepValue(0.1)
-          DatePicker("Date", selection: $<date>, displayedComponents: .date)
+          content failed
         .padding()
@@ -131,8 +112,3 @@
           Text(_literal: "New Expense")
-          TextField("Category", text: $"")
-            .textFieldStyle(.roundedBorder)
-          Stepper(value: $0.0, {fn})
-            Text(_literal: "0.00")
-            .stepValue(0.1)
-          DatePicker("Date", selection: $<date>, displayedComponents: .date)
+          content failed
         .padding()
@@ -177,8 +153,3 @@
           Text(_literal: "New Expense")
-          TextField("Category", text: $"")
-            .textFieldStyle(.roundedBorder)
-          Stepper(value: $0.0, {fn})
-            Text(_literal: "0.00")
-            .stepValue(0.1)
-          DatePicker("Date", selection: $<date>, displayedComponents: .date)
+          content failed
         .padding()
@@ -229,8 +200,3 @@
           Text(_literal: "New Expense")
-          TextField("Category", text: $"")
-            .textFieldStyle(.roundedBorder)
-          Stepper(value: $0.0, {fn})
-            Text(_literal: "0.00")
-            .stepValue(0.1)
-          DatePicker("Date", selection: $<date>, displayedComponents: .date)
+          content failed
         .padding()
@@ -287,8 +253,3 @@
           Text(_literal: "New Expense")
-          TextField("Category", text: $"")
-            .textFieldStyle(.roundedBorder)
-          Stepper(value: $0.0, {fn})
-            Text(_literal: "0.00")
-            .stepValue(0.1)
-          DatePicker("Date", selection: $<date>, displayedComponents: .date)
+          content failed
         .padding()
@@ -351,8 +312,3 @@
           Text(_literal: "New Expense")
-          TextField("Category", text: $"")
-            .textFieldStyle(.roundedBorder)
-          Stepper(value: $0.0, {fn})
-            Text(_literal: "0.00")
-            .stepValue(0.1)
-          DatePicker("Date", selection: $<date>, displayedComponents: .date)
+          content failed
         .padding()
@@ -421,8 +377,3 @@
           Text(_literal: "New Expense")
-          TextField("Category", text: $"")
-            .textFieldStyle(.roundedBorder)
-          Stepper(value: $0.0, {fn})
-            Text(_literal: "0.00")
-            .stepValue(0.1)
-          DatePicker("Date", selection: $<date>, displayedComponents: .date)
+          content failed
         .padding()
@@ -497,8 +448,3 @@
           Text(_literal: "New Expense")
-          TextField("Category", text: $"")
-            .textFieldStyle(.roundedBorder)
-          Stepper(value: $0.0, {fn})
-            Text(_literal: "0.00")
-            .stepValue(0.1)
-          DatePicker("Date", selection: $<date>, displayedComponents: .date)
+          content failed
         .padding()
@@ -579,8 +525,3 @@
           Text(_literal: "New Expense")
-          TextField("Category", text: $"")
-            .textFieldStyle(.roundedBorder)
…
```
