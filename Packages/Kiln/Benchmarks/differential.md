# Differential check

Every input run on the engine at `b466f9c` and on this one, comparing their transcripts: the view tree each body evaluates to, the console, errors and warnings with their lines, and all of it again after each scripted action (`onAppear` and `.task` first, then each button and tap). `Tools/diff.sh` writes this file.

**74 inputs: 59 identical, 15 different as expected, 0 different otherwise.**

| Input | Transcript lines | Steps | Result |
|---|---:|---:|---|
| Packages/Kiln/Examples/Apps/CardStyles.swift | 242 | 13 | identical |
| Packages/Kiln/Examples/Apps/Chess.swift | 21125 | 13 | identical |
| Packages/Kiln/Examples/Apps/ExpenseTracker.swift | 1654 | 13 | identical |
| Packages/Kiln/Examples/Apps/FocusTimer.swift | 910 | 13 | identical |
| Packages/Kiln/Examples/Apps/HabitTracker.swift | 1105 | 13 | identical |
| Packages/Kiln/Examples/Apps/MemoryMatch.swift | 2656 | 14 | identical |
| Packages/Kiln/Examples/Apps/ReadingList.swift | 125 | 1 | identical |
| Packages/Kiln/Examples/Apps/TagCloud.swift | 4 | 1 | expected (§1.5's Lab example: before, `AnyLayout` and the app's `Layout` didn't exist and the body stopped.) |
| Packages/Kiln/Examples/Apps/TipCalculator.swift | 42 | 1 | identical |
| Packages/Kiln/Examples/Apps/WaveStudio.swift | 341 | 13 | identical |
| Packages/Kiln/Examples/AppleIntelligence/expense.md | 754 | 13 | expected (The reply writes .stepValue(0.1), which isn't a SwiftUI modifier: §1.4 reports it with its line, where before it was skipped silently.) |
| Packages/Kiln/Examples/AppleIntelligence/habit.md | 377 | 13 | identical |
| Packages/Kiln/Examples/AppleIntelligence/memory.md | 31 | 1 | identical |
| Packages/Kiln/Examples/AppleIntelligence/timer.md | 338 | 13 | identical |
| Packages/Kiln/Examples/AppleIntelligence/tip.md | 1092 | 13 | identical |
| Packages/Kiln/Examples/Networking/OpenLibrarySearch.swift | 22 | 2 | identical |
| Packages/Kiln/Examples/LibraryApp.swift | 64 | 2 | identical |
| fixtures/apps/async.swift | 283 | 14 | identical |
| fixtures/apps/images.swift | 663 | 13 | identical |
| fixtures/apps/network.swift | 211 | 14 | expected (Its dataTask handlers now run in a check: since §1.7 a check never touches the network, so the handler gets the offline error at once and the app shows its error state, where before the request started and its handler never ran.) |
| fixtures/apps/saving-data.swift | 1076 | 14 | identical |
| fixtures/apps/state.swift | 599 | 13 | identical |
| fixtures/apps/swift-builders.swift | 339 | 13 | expected (§1.6's fixture: before, the Card's @ViewBuilder content and the @Entry tint were missing and the steps builder stopped the body.) |
| fixtures/apps/swift-codable.swift | 2 | 1 | expected (§1.6's fixture: before, the regex literal didn't parse.) |
| fixtures/apps/swift-language.swift | 1213 | 13 | identical |
| fixtures/apps/swift-protocols.swift | 2 | 1 | expected (§1.6's fixture: before, `case 500...:` didn't parse.) |
| fixtures/apps/time.swift | 372 | 13 | identical |
| fixtures/apps/todos-db.swift | 296 | 14 | identical |
| fixtures/apps/views-custom-protocols.swift | 9 | 1 | expected (§1.5's fixture: before, `modifier(…)` called from a View extension wasn't found, and nothing below it showed.) |
| fixtures/apps/views-layout-drawing.swift | 2560 | 13 | identical |
| fixtures/apps/views-lists-controls.swift | 1547 | 13 | identical |
| fixtures/apps/views-navigation.swift | 861 | 13 | identical |
| fixtures/apps/views-uikit.swift | 9 | 1 | expected (§1.5's fixture: before, the representable, its picker and `SharePreview` didn't exist.) |
| Packages/Kiln/Benchmarks/Workloads/Arithmetic.swift | 8 | 2 | identical |
| Packages/Kiln/Benchmarks/Workloads/Collections.swift | 112 | 2 | identical |
| Packages/Kiln/Benchmarks/Workloads/Objects.swift | 8 | 2 | identical |
| tests/AppTypesRepro-0.swift | 1742 | 13 | identical |
| tests/AppTypesRepro-1.swift | 17 | 1 | identical |
| tests/AppTypesRepro-2.swift | 234 | 13 | identical |
| tests/AppTypesRepro-3.swift | 327 | 13 | identical |
| tests/BreakoutRepro-0.swift | 8 | 2 | identical |
| tests/ContextTests-0.swift | 2 | 1 | identical |
| tests/ContextTests-4.swift | 9 | 2 | identical |
| tests/ContextTests-8.swift | 6 | 1 | identical |
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
| tests/LanguageTests-18.swift | 21 | 1 | expected (§1.6: a closure given to `@ViewBuilder let content: Content` or a `@ViewBuilder` parameter now builds its views; before, Card and Panel showed nothing.) |
| tests/LanguageTests-28.swift | 5 | 1 | expected (§1.6: `$on.animation()` and a method straight on `allCases` used to stop with an error; now they work.) |
| tests/LanguageTests-29.swift | 8 | 1 | expected (§1.6: `@Entry`, `@Animatable`, `@FocusedValue` and `.focusedValue` are read as declarations; before, `.focusedValue` stopped the body.) |
| tests/ProxyTests-1.swift | 1 | 1 | identical |
| tests/ProxyTests-10.swift | 3 | 1 | expected (§1.5: `Diagonal(step: 5) { … }` is the app's Layout with its content; before, the closure was an ignored argument.) |
| tests/ProxyTests-11.swift | 4 | 1 | expected (§1.5: `AnyLayout` over the app's Layout and `HStackLayout`; before, `AnyLayout` didn't exist.) |
| tests/ProxyTests-13.swift | 1 | 1 | identical |
| tests/ProxyTests-14.swift | 18 | 2 | identical |
| tests/ProxyTests-15.swift | 11 | 2 | identical |
| tests/ProxyTests-16.swift | 1 | 1 | identical |
| tests/ProxyTests-20.swift | 5 | 1 | expected (§1.5: `ShareLink(item:preview:)` with the app's Transferable and `SharePreview`; before, `SharePreview` didn't exist.) |
| tests/ProxyTests-8.swift | 4 | 1 | expected (§1.5: `modifier(Card(…))` from a View extension now applies the app's ViewModifier; before, it wasn't found.) |
| tests/ProxyTests-9.swift | 4 | 1 | identical |
| tests/RegistryTests-0.swift | 2 | 1 | identical |
| tests/SnakeGameTests-0.swift | 3 | 1 | identical |
| tests/SnakeGameTests-1.swift | 8 | 2 | identical |
| tests/SnakeGameTests-2.swift | 3 | 1 | identical |
| tests/WeatherRepro-0.swift | 209 | 13 | identical |
| tests/WeatherRepro-1.swift | 183 | 14 | identical |

## Packages/Kiln/Examples/Apps/TagCloud.swift

```diff
--- before
+++ after
@@ -2,3 +2,1365 @@
 ContentView {tags=["Swift", "SwiftUI", "Layout", "Kiln", "Shelf", "Animation", "Protocols"], flowing=true, extra=["Proxies", "Delegates", "Shapes", "Transitions", "Modifiers"]}
-  body failed
-error: Line 51: Cannot find 'AnyLayout' in scope
+  VStack(alignment: .leading, spacing: 20, {fn})
+    Text("Flow")
+      .font(Font)
+    LayoutView(AnyLayout, content: {fn})
+      ForEach(["Swift", "SwiftUI", "Layout", "Kiln", "Shelf", "Animation", "Protocols"], id: KeyPath, {fn})
+        row "Swift"
+          Text("Swift")
+            .padding(.horizontal, 12)
+            .padding(.vertical, 6)
+            .background(<view>)
+              Capsule()
+                .fill(<view>)
+                  Color(Color)
+                    .opacity(0.2)
+        row "SwiftUI"
+          Text("SwiftUI")
+            .padding(.horizontal, 12)
+            .padding(.vertical, 6)
+            .background(<view>)
+              Capsule()
+                .fill(<view>)
+                  Color(Color)
+                    .opacity(0.2)
+        row "Layout"
+          Text("Layout")
+            .padding(.horizontal, 12)
+            .padding(.vertical, 6)
+            .background(<view>)
+              Capsule()
+                .fill(<view>)
+                  Color(Color)
+                    .opacity(0.2)
+        row "Kiln"
+          Text("Kiln")
+            .padding(.horizontal, 12)
+            .padding(.vertical, 6)
+            .background(<view>)
+              Capsule()
+                .fill(<view>)
+                  Color(Color)
+                    .opacity(0.2)
+        row "Shelf"
+          Text("Shelf")
+            .padding(.horizontal, 12)
+            .padding(.vertical, 6)
+            .background(<view>)
+              Capsule()
+                .fill(<view>)
+                  Color(Color)
+                    .opacity(0.2)
+        row "Animation"
+          Text("Animation")
+            .padding(.horizontal, 12)
+            .padding(.vertical, 6)
+            .background(<view>)
+              Capsule()
+                .fill(<view>)
+                  Color(Color)
+                    .opacity(0.2)
+        row "Protocols"
+          Text("Protocols")
+            .padding(.horizontal, 12)
+            .padding(.vertical, 6)
+            .background(<view>)
+              Capsule()
+                .fill(<view>)
+                  Color(Color)
+                    .opacity(0.2)
+    HStack({fn})
+      Button("Add Tag", {fn})
+      Button("Switch Layout", {fn})
+      .buttonStyle(.bordered)
+    Spacer()
+    .padding()
+== after Button[Add Tag]@64
+ContentView {tags=["Swift", "SwiftUI", "Layout", "Kiln", "Shelf", "Animation", "Protocols", "Shapes"], flowing=true, extra=["Proxies", "Delegates", "Shapes", "Transitions", "Modifiers"]}
+  VStack(alignment: .leading, spacing: 20, {fn})
+    Text("Flow")
+      .font(Font)
+    LayoutView(AnyLayout, content: {fn})
+      ForEach(["Swift", "SwiftUI", "Layout", "Kiln", "Shelf", "Animation", "Protocols", "Shapes"], id: KeyPath, {fn})
+        row "Swift"
+          Text("Swift")
+            .padding(.horizontal, 12)
+            .padding(.vertical, 6)
+            .background(<view>)
+              Capsule()
+                .fill(<view>)
+                  Color(Color)
+                    .opacity(0.2)
+        row "SwiftUI"
+          Text("SwiftUI")
+            .padding(.horizontal, 12)
+            .padding(.vertical, 6)
+            .background(<view>)
+              Capsule()
+                .fill(<view>)
+                  Color(Color)
+                    .opacity(0.2)
+        row "Layout"
+          Text("Layout")
+            .padding(.horizontal, 12)
+            .padding(.vertical, 6)
+            .background(<view>)
+              Capsule()
+                .fill(<view>)
+                  Color(Color)
+                    .opacity(0.2)
+        row "Kiln"
+          Text("Kiln")
+            .padding(.horizontal, 12)
+            .padding(.vertical, 6)
+            .background(<view>)
+              Capsule()
…
```

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

## fixtures/apps/network.swift

```diff
--- before
+++ after
@@ -17,195 +17,247 @@
 == appeared (List.onAppear@88)
-ContentView {launches=[], rocket=nil, loading=true, message=nil, query="falcon"}
-  NavigationStack({fn})
-    List({fn})
-      If false
-      If false
-      Section("Launches", {fn})
-        If true
-          ProgressView()
-        ForEach([], {fn})
-      .navigationTitle("Launches")
-      .searchable(text: $"falcon")
-      .onSubmit(of: .search, {fn})
-      .refreshable({fn})
-      .onAppear({fn})
-== after List.onSubmit@86
-ContentView {launches=[], rocket=nil, loading=true, message=nil, query="falcon"}
-  NavigationStack({fn})
-    List({fn})
-      If false
-      If false
-      Section("Launches", {fn})
-        If true
-          ProgressView()
-        ForEach([], {fn})
-      .navigationTitle("Launches")
-      .searchable(text: $"falcon")
-      .onSubmit(of: .search, {fn})
-      .refreshable({fn})
-      .onAppear({fn})
-== after List.refreshable@87
-ContentView {launches=[], rocket=nil, loading=true, message=nil, query="falcon"}
-  NavigationStack({fn})
-    List({fn})
-      If false
-      If false
-      Section("Launches", {fn})
-        If true
-          ProgressView()
-        ForEach([], {fn})
-      .navigationTitle("Launches")
-      .searchable(text: $"falcon")
-      .onSubmit(of: .search, {fn})
-      .refreshable({fn})
-      .onAppear({fn})
-== after List.onSubmit@86
-ContentView {launches=[], rocket=nil, loading=true, message=nil, query="falcon"}
-  NavigationStack({fn})
-    List({fn})
-      If false
-      If false
-      Section("Launches", {fn})
-        If true
-          ProgressView()
-        ForEach([], {fn})
-      .navigationTitle("Launches")
-      .searchable(text: $"falcon")
-      .onSubmit(of: .search, {fn})
-      .refreshable({fn})
-      .onAppear({fn})
-== after List.refreshable@87
-ContentView {launches=[], rocket=nil, loading=true, message=nil, query="falcon"}
-  NavigationStack({fn})
-    List({fn})
-      If false
-      If false
-      Section("Launches", {fn})
-        If true
-          ProgressView()
-        ForEach([], {fn})
-      .navigationTitle("Launches")
-      .searchable(text: $"falcon")
-      .onSubmit(of: .search, {fn})
-      .refreshable({fn})
-      .onAppear({fn})
-== after List.onSubmit@86
-ContentView {launches=[], rocket=nil, loading=true, message=nil, query="falcon"}
-  NavigationStack({fn})
-    List({fn})
-      If false
-      If false
-      Section("Launches", {fn})
-        If true
-          ProgressView()
-        ForEach([], {fn})
-      .navigationTitle("Launches")
-      .searchable(text: $"falcon")
-      .onSubmit(of: .search, {fn})
-      .refreshable({fn})
-      .onAppear({fn})
-== after List.refreshable@87
-ContentView {launches=[], rocket=nil, loading=true, message=nil, query="falcon"}
-  NavigationStack({fn})
-    List({fn})
-      If false
-      If false
-      Section("Launches", {fn})
-        If true
-          ProgressView()
-        ForEach([], {fn})
-      .navigationTitle("Launches")
-      .searchable(text: $"falcon")
-      .onSubmit(of: .search, {fn})
-      .refreshable({fn})
-      .onAppear({fn})
-== after List.onSubmit@86
-ContentView {launches=[], rocket=nil, loading=true, message=nil, query="falcon"}
-  NavigationStack({fn})
-    List({fn})
-      If false
-      If false
-      Section("Launches", {fn})
-        If true
-          ProgressView()
-        ForEach([], {fn})
-      .navigationTitle("Launches")
-      .searchable(text: $"falcon")
…
```

## fixtures/apps/swift-builders.swift

```diff
--- before
+++ after
@@ -1,12 +1,28 @@
 == start
-ContentView {recipe=Recipe(name: "Chili", servings: 4, vegetarian: true), showSteps=true, pantry=Pantry{cups: 3}}
-  NavigationStack({fn})
-    List({fn})
-      Card {title="Chili", content={fn}, tint=nil}
-        VStack(alignment: .leading, spacing: 6, {fn})
-          Text("Chili")
-            .font(Font)
-            .foregroundStyle(nil)
-      Section("Steps", {fn})
-        content failed
+ContentView {recipe=Recipe(name: "Chili", vegetarian: true), showSteps=true, pantry=Pantry{cups: 3}}
+  NavigationStack({fn})
+    List({fn})
+      Card {title="Chili", content=<view>, tint=Color}
+        VStack(alignment: .leading, spacing: 6, {fn})
+          Text("Chili")
+            .font(Font)
+            .foregroundStyle(Color)
+          Group
+            Text(_literal: "Serves 4 (4 of 12)")
+            If true
+              Text(_literal: "Vegetarian")
+      Section("Steps", {fn})
+        Toggle("Show steps", isOn: $true)
+        If true
+          ForEach([(offset: 0, element: "Heat the pan"), (offset: 1, element: "Add the beans"), (offset: 2, element: "Stir, minute 1"), (offset: 3, element: "Stir, minute 2"), (offset: 4, element: "Serve")], id: KeyPath, {fn})
+            row 0
+              Text(_literal: "1. Heat the pan")
+            row 1
+              Text(_literal: "2. Add the beans")
+            row 2
+              Text(_literal: "3. Stir, minute 1")
+            row 3
+              Text(_literal: "4. Stir, minute 2")
+            row 4
+              Text(_literal: "5. Serve")
       Section("Progress", {fn})
@@ -26,14 +42,29 @@
       .navigationTitle("Recipe Card")
-error: Line 101: Value of type 'Binding' has no method 'animation'
 == after Button[More servings]@110
-ContentView {recipe=Recipe(name: "Chili", servings: 9, vegetarian: true), showSteps=true, pantry=Pantry{cups: 3}}
-  NavigationStack({fn})
-    List({fn})
-      Card {title="Chili", content={fn}, tint=nil}
-        VStack(alignment: .leading, spacing: 6, {fn})
-          Text("Chili")
-            .font(Font)
-            .foregroundStyle(nil)
-      Section("Steps", {fn})
-        content failed
+ContentView {recipe=Recipe(name: "Chili", vegetarian: true), showSteps=true, pantry=Pantry{cups: 3}}
+  NavigationStack({fn})
+    List({fn})
+      Card {title="Chili", content=<view>, tint=Color}
+        VStack(alignment: .leading, spacing: 6, {fn})
+          Text("Chili")
+            .font(Font)
+            .foregroundStyle(Color)
+          Group
+            Text(_literal: "Serves 9 (9 of 12)")
+            If true
+              Text(_literal: "Vegetarian")
+      Section("Steps", {fn})
+        Toggle("Show steps", isOn: $true)
+        If true
+          ForEach([(offset: 0, element: "Heat the pan"), (offset: 1, element: "Add the beans"), (offset: 2, element: "Stir, minute 1"), (offset: 3, element: "Stir, minute 2"), (offset: 4, element: "Serve")], id: KeyPath, {fn})
+            row 0
+              Text(_literal: "1. Heat the pan")
+            row 1
+              Text(_literal: "2. Add the beans")
+            row 2
+              Text(_literal: "3. Stir, minute 1")
+            row 3
+              Text(_literal: "4. Stir, minute 2")
+            row 4
+              Text(_literal: "5. Serve")
       Section("Progress", {fn})
@@ -54,12 +85,110 @@
 == after Button[Fewer servings]@111
-ContentView {recipe=Recipe(name: "Chili", servings: -11, vegetarian: true), showSteps=true, pantry=Pantry{cups: 3}}
-  NavigationStack({fn})
-    List({fn})
-      Card {title="Chili", content={fn}, tint=nil}
-        VStack(alignment: .leading, spacing: 6, {fn})
-          Text("Chili")
-            .font(Font)
-            .foregroundStyle(nil)
-      Section("Steps", {fn})
-        content failed
+ContentView {recipe=Recipe(name: "Chili", vegetarian: true), showSteps=true, pantry=Pantry{cups: 3}}
+  NavigationStack({fn})
+    List({fn})
+      Card {title="Chili", content=<view>, tint=Color}
+        VStack(alignment: .leading, spacing: 6, {fn})
+          Text("Chili")
+            .font(Font)
+            .foregroundStyle(Color)
+          Group
+            Text(_literal: "Serves 1 (1 of 12)")
+            If true
+              Text(_literal: "Vegetarian")
+      Section("Steps", {fn})
+        Toggle("Show steps", isOn: $true)
+        If true
+          ForEach([(offset: 0, element: "Heat the pan"), (offset: 1, element: "Add the beans"), (offset: 2, element: "Stir, minute 1"), (offset: 3, element: "Stir, minute 2"), (offset: 4, element: "Serve")], id: KeyPath, {fn})
+            row 0
+              Text(_literal: "1. Heat the pan")
+            row 1
+              Text(_literal: "2. Add the beans")
+            row 2
+              Text(_literal: "3. Stir, minute 1")
+            row 3
+              Text(_literal: "4. Stir, minute 2")
+            row 4
+              Text(_literal: "5. Serve")
…
```

## fixtures/apps/swift-codable.swift

```diff
--- before
+++ after
@@ -1,2 +1,543 @@
-compile error: Line 61: unexpected '/^'
-  61 | guard let m = line.firstMatch(of: /^(?<title>[A-Za-z ]+?)\s+(?<dollars>\d+)\.(?<cents>\d{2})/) else { return nil }
+== start
+ContentView {expenses=[], log=[], input="Lunch 12.50 #food #work
+Train 3.20 card #travel
+not an expense"}
+  NavigationStack({fn})
+    List({fn})
+      Section("Imported", {fn})
+        ForEach([], {fn})
+        LabeledContent("Total", value: "$0.00")
+      Section({fn})
+        Button("Import", {fn})
+        Button("Round trip", {fn})
+        Button("Read old data", {fn})
+        ForEach([], id: KeyPath, {fn})
+      .navigationTitle("Expenses Import")
+== after Button[Import]@89
+ContentView {expenses=[Expense(id: <uuid>, title: "Lunch", cents: 1250, payment: .cash, tags: Set("food", "work")), Expense(id: <uuid>, title: "Train", cents: 320, payment: .card("4242"), tags: Set("travel"))], log=["Imported 2"], input="Lunch 12.50 #food #work
+Train 3.20 card #travel
+not an expense"}
+  NavigationStack({fn})
+    List({fn})
+      Section("Imported", {fn})
+        ForEach([Expense(id: <uuid>, title: "Lunch", cents: 1250, payment: .cash, tags: Set("food", "work")), Expense(id: <uuid>, title: "Train", cents: 320, payment: .card("4242"), tags: Set("travel"))], {fn})
+          row <uuid>
+            LabeledContent("Lunch", value: "$12.50")
+          row <uuid>
+            LabeledContent("Train", value: "$3.20")
+        LabeledContent("Total", value: "$15.70")
+      Section({fn})
+        Button("Import", {fn})
+        Button("Round trip", {fn})
+        Button("Read old data", {fn})
+        ForEach(["Imported 2"], id: KeyPath, {fn})
+          row "Imported 2"
+            Text("Imported 2")
+              .font(Font)
+      .navigationTitle("Expenses Import")
+== after Button[Round trip]@93
+ContentView {expenses=[Expense(id: <uuid>, title: "Lunch", cents: 1250, payment: .cash, tags: Set("food", "work")), Expense(id: <uuid>, title: "Train", cents: 320, payment: .card("4242"), tags: Set("travel"))], log=["Imported 2", "Same: true, tags are a set: true"], input="Lunch 12.50 #food #work
+Train 3.20 card #travel
+not an expense"}
+  NavigationStack({fn})
+    List({fn})
+      Section("Imported", {fn})
+        ForEach([Expense(id: <uuid>, title: "Lunch", cents: 1250, payment: .cash, tags: Set("food", "work")), Expense(id: <uuid>, title: "Train", cents: 320, payment: .card("4242"), tags: Set("travel"))], {fn})
+          row <uuid>
+            LabeledContent("Lunch", value: "$12.50")
+          row <uuid>
+            LabeledContent("Train", value: "$3.20")
+        LabeledContent("Total", value: "$15.70")
+      Section({fn})
+        Button("Import", {fn})
+        Button("Round trip", {fn})
+        Button("Read old data", {fn})
+        ForEach(["Imported 2", "Same: true, tags are a set: true"], id: KeyPath, {fn})
+          row "Imported 2"
+            Text("Imported 2")
+              .font(Font)
+          row "Same: true, tags are a set: true"
+            Text("Same: true, tags are a set: true")
+              .font(Font)
+      .navigationTitle("Expenses Import")
+== after Button[Read old data]@102
+ContentView {expenses=[Expense(id: <uuid>, title: "Lunch", cents: 1250, payment: .cash, tags: Set("food", "work")), Expense(id: <uuid>, title: "Train", cents: 320, payment: .card("4242"), tags: Set("travel"))], log=["Imported 2", "Same: true, tags are a set: true", "Old: Old true", "Rejected cheque"], input="Lunch 12.50 #food #work
+Train 3.20 card #travel
+not an expense"}
+  NavigationStack({fn})
+    List({fn})
+      Section("Imported", {fn})
+        ForEach([Expense(id: <uuid>, title: "Lunch", cents: 1250, payment: .cash, tags: Set("food", "work")), Expense(id: <uuid>, title: "Train", cents: 320, payment: .card("4242"), tags: Set("travel"))], {fn})
+          row <uuid>
+            LabeledContent("Lunch", value: "$12.50")
+          row <uuid>
+            LabeledContent("Train", value: "$3.20")
+        LabeledContent("Total", value: "$15.70")
+      Section({fn})
+        Button("Import", {fn})
+        Button("Round trip", {fn})
+        Button("Read old data", {fn})
+        ForEach(["Imported 2", "Same: true, tags are a set: true", "Old: Old true", "Rejected cheque"], id: KeyPath, {fn})
+          row "Imported 2"
+            Text("Imported 2")
+              .font(Font)
+          row "Same: true, tags are a set: true"
+            Text("Same: true, tags are a set: true")
+              .font(Font)
+          row "Old: Old true"
+            Text("Old: Old true")
+              .font(Font)
+          row "Rejected cheque"
+            Text("Rejected cheque")
+              .font(Font)
+      .navigationTitle("Expenses Import")
+== after Button[Import]@89
+ContentView {expenses=[Expense(id: <uuid>, title: "Lunch", cents: 1250, payment: .cash, tags: Set("food", "work")), Expense(id: <uuid>, title: "Train", cents: 320, payment: .card("4242"), tags: Set("travel"))], log=["Imported 2", "Same: true, tags are a set: true", "Old: Old true", "Rejected cheque", "Imported 2"], input="Lunch 12.50 #food #work
+Train 3.20 card #travel
+not an expense"}
+  NavigationStack({fn})
+    List({fn})
+      Section("Imported", {fn})
+        ForEach([Expense(id: <uuid>, title: "Lunch", cents: 1250, payment: .cash, tags: Set("food", "work")), Expense(id: <uuid>, title: "Train", cents: 320, payment: .card("4242"), tags: Set("travel"))], {fn})
+          row <uuid>
+            LabeledContent("Lunch", value: "$12.50")
+          row <uuid>
+            LabeledContent("Train", value: "$3.20")
+        LabeledContent("Total", value: "$15.70")
+      Section({fn})
+        Button("Import", {fn})
+        Button("Round trip", {fn})
+        Button("Read old data", {fn})
+        ForEach(["Imported 2", "Same: true, tags are a set: true", "Old: Old true", "Rejected cheque", "Imported 2"], id: KeyPath, {fn})
+          row 0
+            Text("Imported 2")
+              .font(Font)
+          row 1
…
```

## fixtures/apps/swift-protocols.swift

```diff
--- before
+++ after
@@ -1,2 +1,996 @@
-compile error: Line 76: unexpected ':'
-  76 | case 500...: return "Epic"
+== start
+ContentView {books=[Book(id: 1, title: "Dune", pages: 612, stars: 5, genre: .fiction), Book(id: 2, title: "SPQR", pages: 448, stars: 4, genre: .history), Book(id: 3, title: "Cosmos", pages: 384, stars: 4, genre: .science)], log=[]}
+  NavigationStack({fn})
+    List({fn})
+      Section("Books", {fn})
+        ForEach([Book(id: 3, title: "Cosmos", pages: 384, stars: 4, genre: .science), Book(id: 1, title: "Dune", pages: 612, stars: 5, genre: .fiction), Book(id: 2, title: "SPQR", pages: 448, stars: 4, genre: .history)], {fn})
+          row 3
+            VStack(alignment: .leading, {fn})
+              Text("Cosmos, 384 pages")
+              Text(_literal: "★★★★ · Novel · ranked Cosmos")
+                .font(Font)
+                .foregroundStyle(Color)
+          row 1
+            VStack(alignment: .leading, {fn})
+              Text("Dune, 612 pages")
+              Text(_literal: "★★★★★ · Epic · ranked Dune")
+                .font(Font)
+                .foregroundStyle(Color)
+          row 2
+            VStack(alignment: .leading, {fn})
+              Text("SPQR, 448 pages")
+              Text(_literal: "★★★★ · Novel · ranked SPQR")
+                .font(Font)
+                .foregroundStyle(Color)
+      Section("Shelf", {fn})
+        ForEach([(offset: 0, element: Book(id: 1, title: "Dune", pages: 612, stars: 5, genre: .fiction)), (offset: 1, element: Book(id: 2, title: "SPQR", pages: 448, stars: 4, genre: .history)), (offset: 2, element: Book(id: 3, title: "Cosmos", pages: 384, stars: 4, genre: .science)), (offset: 3, element: Magazine(title: "Wired", pages: 30))], id: KeyPath, {fn})
+          row 0
+            LabeledContent("Dune", value: "Epic")
+          row 1
+            LabeledContent("SPQR", value: "Novel")
+          row 2
+            LabeledContent("Cosmos", value: "Novel")
+          row 3
+            LabeledContent("Wired", value: "Short")
+        LabeledContent("Pages", value: "1444")
+        LabeledContent("Longest", value: "Dune")
+        LabeledContent("Genres", value: "Fiction, History, Science")
+      Section({fn})
+        Button("Add a duplicate of Dune", {fn})
+        Button("Reading time", {fn})
+        ForEach([], id: KeyPath, {fn})
+      .navigationTitle("Reading Log")
+== after Button[Add a duplicate of Dune]@121
+ContentView {books=[Book(id: 1, title: "Dune", pages: 612, stars: 5, genre: .fiction), Book(id: 2, title: "SPQR", pages: 448, stars: 4, genre: .history), Book(id: 3, title: "Cosmos", pages: 384, stars: 4, genre: .science)], log=["Unique: 3; same book: true"]}
+  NavigationStack({fn})
+    List({fn})
+      Section("Books", {fn})
+        ForEach([Book(id: 3, title: "Cosmos", pages: 384, stars: 4, genre: .science), Book(id: 1, title: "Dune", pages: 612, stars: 5, genre: .fiction), Book(id: 2, title: "SPQR", pages: 448, stars: 4, genre: .history)], {fn})
+          row 3
+            VStack(alignment: .leading, {fn})
+              Text("Cosmos, 384 pages")
+              Text(_literal: "★★★★ · Novel · ranked Cosmos")
+                .font(Font)
+                .foregroundStyle(Color)
+          row 1
+            VStack(alignment: .leading, {fn})
+              Text("Dune, 612 pages")
+              Text(_literal: "★★★★★ · Epic · ranked Dune")
+                .font(Font)
+                .foregroundStyle(Color)
+          row 2
+            VStack(alignment: .leading, {fn})
+              Text("SPQR, 448 pages")
+              Text(_literal: "★★★★ · Novel · ranked SPQR")
+                .font(Font)
+                .foregroundStyle(Color)
+      Section("Shelf", {fn})
+        ForEach([(offset: 0, element: Book(id: 1, title: "Dune", pages: 612, stars: 5, genre: .fiction)), (offset: 1, element: Book(id: 2, title: "SPQR", pages: 448, stars: 4, genre: .history)), (offset: 2, element: Book(id: 3, title: "Cosmos", pages: 384, stars: 4, genre: .science)), (offset: 3, element: Magazine(title: "Wired", pages: 30))], id: KeyPath, {fn})
+          row 0
+            LabeledContent("Dune", value: "Epic")
+          row 1
+            LabeledContent("SPQR", value: "Novel")
+          row 2
+            LabeledContent("Cosmos", value: "Novel")
+          row 3
+            LabeledContent("Wired", value: "Short")
+        LabeledContent("Pages", value: "1444")
+        LabeledContent("Longest", value: "Dune")
+        LabeledContent("Genres", value: "Fiction, History, Science")
+      Section({fn})
+        Button("Add a duplicate of Dune", {fn})
+        Button("Reading time", {fn})
+        ForEach(["Unique: 3; same book: true"], id: KeyPath, {fn})
+          row "Unique: 3; same book: true"
+            Text("Unique: 3; same book: true")
+              .font(Font)
+      .navigationTitle("Reading Log")
+== after Button[Reading time]@126
+ContentView {books=[Book(id: 1, title: "Dune", pages: 612, stars: 5, genre: .fiction), Book(id: 2, title: "SPQR", pages: 448, stars: 4, genre: .history), Book(id: 3, title: "Cosmos", pages: 384, stars: 4, genre: .science)], log=["Unique: 3; same book: true", "Hours: 36", "Happy reading, Ann (member since 2020)", "Magazines: 1"]}
+  NavigationStack({fn})
+    List({fn})
+      Section("Books", {fn})
+        ForEach([Book(id: 3, title: "Cosmos", pages: 384, stars: 4, genre: .science), Book(id: 1, title: "Dune", pages: 612, stars: 5, genre: .fiction), Book(id: 2, title: "SPQR", pages: 448, stars: 4, genre: .history)], {fn})
+          row 3
+            VStack(alignment: .leading, {fn})
+              Text("Cosmos, 384 pages")
+              Text(_literal: "★★★★ · Novel · ranked Cosmos")
+                .font(Font)
+                .foregroundStyle(Color)
+          row 1
+            VStack(alignment: .leading, {fn})
+              Text("Dune, 612 pages")
+              Text(_literal: "★★★★★ · Epic · ranked Dune")
+                .font(Font)
+                .foregroundStyle(Color)
+          row 2
+            VStack(alignment: .leading, {fn})
+              Text("SPQR, 448 pages")
+              Text(_literal: "★★★★ · Novel · ranked SPQR")
+                .font(Font)
+                .foregroundStyle(Color)
+      Section("Shelf", {fn})
+        ForEach([(offset: 0, element: Book(id: 1, title: "Dune", pages: 612, stars: 5, genre: .fiction)), (offset: 1, element: Book(id: 2, title: "SPQR", pages: 448, stars: 4, genre: .history)), (offset: 2, element: Book(id: 3, title: "Cosmos", pages: 384, stars: 4, genre: .science)), (offset: 3, element: Magazine(title: "Wired", pages: 30))], id: KeyPath, {fn})
+          row 0
+            LabeledContent("Dune", value: "Epic")
…
```

## fixtures/apps/views-custom-protocols.swift

```diff
--- before
+++ after
@@ -5,5 +5,567 @@
       VStack(spacing: 16, {fn})
-        content failed
-        .padding()
-      .navigationTitle("Tide Board")
-error: Line 88: Cannot find 'modifier' in scope
+        UserShape(Tide(level: 0.3, swell: 4.0))
+          .fill(<view>)
+            LinearGradient(colors: [Color, Color])
+          .frame(height: 140)
+          .clipShape(<view>)
+            RoundedRectangle(cornerRadius: 16)
+        LayoutView(AnyLayout, content: {fn})
+          ForEach(["Harbor", "Point", "Cove", "Reef", "Bay", "Inlet"], id: KeyPath, {fn})
+            row "Harbor"
+              Text("Harbor")
+                .modifier(Tile(tint: Color))
+            row "Point"
+              Text("Point")
+                .modifier(Tile(tint: Color))
+            row "Cove"
+              Text("Cove")
+                .modifier(Tile(tint: Color))
+            row "Reef"
+              Text("Reef")
+                .modifier(Tile(tint: Color))
+            row "Bay"
+              Text("Bay")
+                .modifier(Tile(tint: Color))
+            row "Inlet"
+              Text("Inlet")
+                .modifier(Tile(tint: Color))
+        Text(_literal: "Tap to pin")
+          .modifier(Pinned(pinned: false))
+          .modifier(Tile(tint: Color))
+        If true
+          Text(_literal: "High tide at <time>")
+            .modifier(Tile(tint: Color))
+            .transition(Rise())
+        If false
+        Button("High Tide", {fn})
+          .buttonStyle(.borderedProminent)
+        .padding()
+      .navigationTitle("Tide Board")
+== after Button[High Tide]@132
+ContentView {high=true, showTip=true, places=["Harbor", "Point", "Cove", "Reef", "Bay", "Inlet"]}
+  NavigationStack({fn})
+    ScrollView({fn})
+      VStack(spacing: 16, {fn})
+        UserShape(Tide(level: 0.8, swell: 12.0))
+          .fill(<view>)
+            LinearGradient(colors: [Color, Color])
+          .frame(height: 140)
+          .clipShape(<view>)
+            RoundedRectangle(cornerRadius: 16)
+        LayoutView(AnyLayout, content: {fn})
+          ForEach(["Harbor", "Point", "Cove", "Reef", "Bay", "Inlet"], id: KeyPath, {fn})
+            row "Harbor"
+              Text("Harbor")
+                .modifier(Tile(tint: Color))
+            row "Point"
+              Text("Point")
+                .modifier(Tile(tint: Color))
+            row "Cove"
+              Text("Cove")
+                .modifier(Tile(tint: Color))
+            row "Reef"
+              Text("Reef")
+                .modifier(Tile(tint: Color))
+            row "Bay"
+              Text("Bay")
+                .modifier(Tile(tint: Color))
+            row "Inlet"
+              Text("Inlet")
+                .modifier(Tile(tint: Color))
+        Text(_literal: "Tap to pin")
+          .modifier(Pinned(pinned: false))
+          .modifier(Tile(tint: Color))
+        If true
+          Text(_literal: "High tide at <time>")
+            .modifier(Tile(tint: Color))
+            .transition(Rise())
+        If true
+          Text(_literal: "Swell rising")
+            .transition(.modifier(Fade(amount: 1.0), Fade(amount: 0.0)))
+        Button("Low Tide", {fn})
+          .buttonStyle(.borderedProminent)
+        .padding()
+      .navigationTitle("Tide Board")
+== after Button[Low Tide]@132
+ContentView {high=false, showTip=true, places=["Harbor", "Point", "Cove", "Reef", "Bay", "Inlet"]}
+  NavigationStack({fn})
+    ScrollView({fn})
+      VStack(spacing: 16, {fn})
+        UserShape(Tide(level: 0.3, swell: 4.0))
+          .fill(<view>)
+            LinearGradient(colors: [Color, Color])
+          .frame(height: 140)
+          .clipShape(<view>)
+            RoundedRectangle(cornerRadius: 16)
+        LayoutView(AnyLayout, content: {fn})
+          ForEach(["Harbor", "Point", "Cove", "Reef", "Bay", "Inlet"], id: KeyPath, {fn})
+            row "Harbor"
+              Text("Harbor")
+                .modifier(Tile(tint: Color))
+            row "Point"
+              Text("Point")
+                .modifier(Tile(tint: Color))
+            row "Cove"
+              Text("Cove")
+                .modifier(Tile(tint: Color))
+            row "Reef"
+              Text("Reef")
+                .modifier(Tile(tint: Color))
+            row "Bay"
+              Text("Bay")
+                .modifier(Tile(tint: Color))
+            row "Inlet"
…
```

## fixtures/apps/views-uikit.swift

```diff
--- before
+++ after
@@ -4,3 +4,19 @@
     VStack(spacing: 20, {fn})
-      content failed
+      ZStack(alignment: .bottom, {fn})
+        If false
+          Image(systemName: "photo")
+            .font(Font)
+            .foregroundStyle(Color)
+        Text("A day at the sea")
+          .padding(8)
+          .frame(maxWidth: inf)
+          .background(Blur())
+        .frame(height: 260)
+        .clipShape(<view>)
+          RoundedRectangle(cornerRadius: 16)
+      TextField("Caption", text: $"A day at the sea")
+        .textFieldStyle(.roundedBorder)
+      Button("Choose Photo", {fn})
+        .buttonStyle(.borderedProminent)
+      ShareLink(item: Caption(text: "A day at the sea"), preview: SharePreview)
       .padding()
@@ -8,2 +24,315 @@
       .sheet(isPresented: $false, {fn})
-error: Line 93: Cannot find 'SharePreview' in scope
+        ImagePicker {image=$nil, dismiss=DismissAction}
+          (no body)
+== after Button[Choose Photo]@91
+ContentView {image=nil, picking=true, caption="A day at the sea"}
+  NavigationStack({fn})
+    VStack(spacing: 20, {fn})
+      ZStack(alignment: .bottom, {fn})
+        If false
+          Image(systemName: "photo")
+            .font(Font)
+            .foregroundStyle(Color)
+        Text("A day at the sea")
+          .padding(8)
+          .frame(maxWidth: inf)
+          .background(Blur())
+        .frame(height: 260)
+        .clipShape(<view>)
+          RoundedRectangle(cornerRadius: 16)
+      TextField("Caption", text: $"A day at the sea")
+        .textFieldStyle(.roundedBorder)
+      Button("Choose Photo", {fn})
+        .buttonStyle(.borderedProminent)
+      ShareLink(item: Caption(text: "A day at the sea"), preview: SharePreview)
+      .padding()
+      .navigationTitle("Photo Card")
+      .sheet(isPresented: $true, {fn})
+        ImagePicker {image=$nil, dismiss=DismissAction}
+          (no body)
+== after Button[Choose Photo]@91
+ContentView {image=nil, picking=true, caption="A day at the sea"}
+  NavigationStack({fn})
+    VStack(spacing: 20, {fn})
+      ZStack(alignment: .bottom, {fn})
+        If false
+          Image(systemName: "photo")
+            .font(Font)
+            .foregroundStyle(Color)
+        Text("A day at the sea")
+          .padding(8)
+          .frame(maxWidth: inf)
+          .background(Blur())
+        .frame(height: 260)
+        .clipShape(<view>)
+          RoundedRectangle(cornerRadius: 16)
+      TextField("Caption", text: $"A day at the sea")
+        .textFieldStyle(.roundedBorder)
+      Button("Choose Photo", {fn})
+        .buttonStyle(.borderedProminent)
+      ShareLink(item: Caption(text: "A day at the sea"), preview: SharePreview)
+      .padding()
+      .navigationTitle("Photo Card")
+      .sheet(isPresented: $true, {fn})
+        ImagePicker {image=$nil, dismiss=DismissAction}
+          (no body)
+== after Button[Choose Photo]@91
+ContentView {image=nil, picking=true, caption="A day at the sea"}
+  NavigationStack({fn})
+    VStack(spacing: 20, {fn})
+      ZStack(alignment: .bottom, {fn})
+        If false
+          Image(systemName: "photo")
+            .font(Font)
+            .foregroundStyle(Color)
+        Text("A day at the sea")
+          .padding(8)
+          .frame(maxWidth: inf)
+          .background(Blur())
+        .frame(height: 260)
+        .clipShape(<view>)
+          RoundedRectangle(cornerRadius: 16)
+      TextField("Caption", text: $"A day at the sea")
+        .textFieldStyle(.roundedBorder)
+      Button("Choose Photo", {fn})
+        .buttonStyle(.borderedProminent)
+      ShareLink(item: Caption(text: "A day at the sea"), preview: SharePreview)
+      .padding()
+      .navigationTitle("Photo Card")
+      .sheet(isPresented: $true, {fn})
+        ImagePicker {image=$nil, dismiss=DismissAction}
+          (no body)
+== after Button[Choose Photo]@91
+ContentView {image=nil, picking=true, caption="A day at the sea"}
+  NavigationStack({fn})
+    VStack(spacing: 20, {fn})
+      ZStack(alignment: .bottom, {fn})
+        If false
+          Image(systemName: "photo")
+            .font(Font)
+            .foregroundStyle(Color)
+        Text("A day at the sea")
+          .padding(8)
+          .frame(maxWidth: inf)
+          .background(Blur())
+        .frame(height: 260)
…
```

## tests/LanguageTests-18.swift

```diff
--- before
+++ after
@@ -13,4 +13,7 @@
         Text(_literal: "two")
-    Card {content={fn}}
+    Card {content=<view>}
       VStack({fn})
+        Group
+          Text(_literal: "in card")
+          Text(_literal: "twice")
     Panel {title="P", content={fn}}
@@ -18,2 +21,6 @@
         Text("P")
+        Group
+          Text(_literal: "p1")
+          If true
+            Text(_literal: "p2")
     HStack({fn})
```

## tests/LanguageTests-28.swift

```diff
--- before
+++ after
@@ -3,3 +3,5 @@
   VStack({fn})
-    content failed
-error: Line 7: Value of type 'Binding' has no method 'animation'
+    Toggle("On", isOn: $false)
+    Toggle("Spring", isOn: $false)
+    Text("small/large")
+    Text(_literal: "2 sizes, first small")
```

## tests/LanguageTests-29.swift

```diff
--- before
+++ after
@@ -3,3 +3,6 @@
   VStack({fn})
-    content failed
+    Child {greeting="hello", legacy=42, model=nil, selection=nil}
+      Text(_literal: "hello 42 none")
+    UserShape(Wave(phase: 1.0, amplitude: 4.0, label: "w"))
+      .stroke(Color)
     .environment(KeyPath, "hi")
@@ -7,2 +10 @@
     .focusedValue(KeyPath, "x")
-error: Line 34: Missing argument 'selection' in call to Child
```

## tests/ProxyTests-10.swift

```diff
--- before
+++ after
@@ -2,2 +2,6 @@
 ContentView {}
-warning: Ignored argument '_' in Diagonal(…)
+  LayoutView(AnyLayout, content: {fn})
+    Color(Color)
+      .frame(width: 20, height: 10)
+    Color(Color)
+      .frame(width: 30, height: 10)
```

## tests/ProxyTests-11.swift

```diff
--- before
+++ after
@@ -2,3 +2,6 @@
 ContentView {fancy=true}
-  body failed
-error: Line 23: Cannot find 'AnyLayout' in scope
+  LayoutView(AnyLayout, content: {fn})
+    Color(Color)
+      .frame(width: 20, height: 7)
+    Color(Color)
+      .frame(width: 20, height: 9)
```

## tests/ProxyTests-20.swift

```diff
--- before
+++ after
@@ -3,3 +3,3 @@
   VStack({fn})
-    content failed
-error: Line 9: Cannot find 'SharePreview' in scope
+    ShareLink(item: Link(url: URL(https://example.com)), preview: SharePreview)
+    ShareLink("Text", item: "hello")
```

## tests/ProxyTests-8.swift

```diff
--- before
+++ after
@@ -2,3 +2,3 @@
 ContentView {}
-  body failed
-error: Line 13: Cannot find 'modifier' in scope
+  Text(_literal: "Inside")
+    .modifier(Card(title: "Hello"))
```
