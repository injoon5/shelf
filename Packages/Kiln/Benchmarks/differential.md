# Differential check

Every input run on the engine at `b466f9c` and on this one, comparing their transcripts: the view tree each body evaluates to, the console, errors and warnings with their lines, and all of it again after each scripted action (`onAppear` and `.task` first, then each button and tap). `Tools/diff.sh` writes this file.

**94 inputs: 70 identical, 24 different as expected, 0 different otherwise.**

| Input | Transcript lines | Steps | Result |
|---|---:|---:|---|
| Packages/Kiln/Examples/Apps/CardStyles.swift | 242 | 13 | identical |
| Packages/Kiln/Examples/Apps/Chess.swift | 21125 | 13 | identical |
| Packages/Kiln/Examples/Apps/ExpenseTracker.swift | 1654 | 13 | identical |
| Packages/Kiln/Examples/Apps/FocusTimer.swift | 910 | 13 | identical |
| Packages/Kiln/Examples/Apps/HabitTracker.swift | 1105 | 13 | identical |
| Packages/Kiln/Examples/Apps/MemoryMatch.swift | 2656 | 14 | identical |
| Packages/Kiln/Examples/Apps/PlantCare.swift | 1027 | 13 | expected (Round 1A's Lab example: before, the custom ToggleStyle and ButtonStyle, List(selection:) and the path weren't bridged.) |
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
| fixtures/apps/controls-styles.swift | 508 | 13 | expected (Round 1A's Controls fixture: before, custom styles, MultiDatePicker and Menu(primaryAction:) weren't bridged.) |
| fixtures/apps/images.swift | 663 | 13 | identical |
| fixtures/apps/layout-scrolling.swift | 2 | 1 | expected (Round 1A's Layout fixture: before, @Entry on ContainerValues and ForEach(subviews:) stopped the body.) |
| fixtures/apps/lists-selection.swift | 8 | 1 | expected (Round 1A's Lists fixture: before, ForEach(editActions:) and OutlineGroup weren't bridged, and the probe read List(selection:)'s binding as its data.) |
| fixtures/apps/navigation-tabs.swift | 1431 | 13 | expected (Round 1A's Navigation fixture: before, Tab, ToolbarSpacer, zoom transitions and search scopes weren't bridged.) |
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
| fixtures/apps/views-input.swift | 502 | 14 | identical |
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
| tests/BridgeTestSupport-0.swift | 2 | 1 | identical |
| tests/CheckSamples-0.swift | 634 | 13 | identical |
| tests/CheckSamples-1.swift | 637 | 13 | identical |
| tests/CheckSamples-2.swift | 338 | 13 | identical |
| tests/CheckSamples-3.swift | 139 | 14 | identical |
| tests/CheckSamples-4.swift | 336 | 13 | identical |
| tests/CheckSamples-5.swift | 2214 | 14 | identical |
| tests/CheckTests-0.swift | 2 | 1 | identical |
| tests/CheckTests-7.swift | 3 | 1 | identical |
| tests/ContextTests-0.swift | 2 | 1 | identical |
| tests/ContextTests-4.swift | 9 | 2 | identical |
| tests/ContextTests-8.swift | 6 | 1 | identical |
| tests/ControlsBridgeTests-7.swift | 4 | 1 | expected (Round 1A: `\.isEnabled` and `\.controlSize` are read from SwiftUI's environment; before, nil.) |
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
| tests/LayoutBridgeTests-0.swift | 2 | 1 | identical |
| tests/ListsBridgeTests-7.swift | 3 | 1 | expected (Round 1A: `\.defaultMinListRowHeight` and `\.isScrollEnabled` are read from SwiftUI's environment; before, nil.) |
| tests/NavigationBridgeTests-5.swift | 40 | 13 | expected (Round 1A: `\.isSearching` and `\.dismissSearch` are read from SwiftUI's environment; before, nil.) |
| tests/NavigationBridgeTests-8.swift | 39 | 13 | expected (Round 1A: `\.isPresented` is read from SwiftUI's environment; before, nil.) |
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

## Packages/Kiln/Examples/Apps/PlantCare.swift

```diff
--- before
+++ after
@@ -6,2 +6,22 @@
         List(selection: $Set(), {fn})
+          Section("Thirsty soon", {fn})
+            ForEach([Plant(id: 1, name: "Monstera", days: 2, symbol: "leaf.fill"), Plant(id: 2, name: "Cactus", days: 12, symbol: "sun.max"), Plant(id: 3, name: "Basil", days: 1, symbol: "drop")], {fn})
+              row 1
+                NavigationLink(value: Plant(id: 1, name: "Monstera", days: 2, symbol: "leaf.fill"), {fn})
+                  Label("Monstera, 2 days", systemImage: "leaf.fill")
+                  .swipeActions({fn})
+                    Button("Water", {fn})
+                      .tint(Color)
+              row 2
+                NavigationLink(value: Plant(id: 2, name: "Cactus", days: 12, symbol: "sun.max"), {fn})
+                  Label("Cactus, 12 days", systemImage: "sun.max")
+                  .swipeActions({fn})
+                    Button("Water", {fn})
+                      .tint(Color)
+              row 3
+                NavigationLink(value: Plant(id: 3, name: "Basil", days: 1, symbol: "drop"), {fn})
+                  Label("Basil, 1 days", systemImage: "drop")
+                  .swipeActions({fn})
+                    Button("Water", {fn})
+                      .tint(Color)
           .navigationTitle("Plants")
@@ -79,8 +99,28 @@
         Label("Settings", systemImage: "gear")
-== after Button[Water now]@64
-ContentView {plants=[Plant(id: 1, name: "Monstera", days: 2, symbol: "leaf.fill"), Plant(id: 2, name: "Cactus", days: 12, symbol: "sun.max"), Plant(id: 3, name: "Basil", days: 1, symbol: "drop")]}
+== after Button[Water]@53
+ContentView {plants=[Plant(id: 1, name: "Monstera", days: 7, symbol: "leaf.fill"), Plant(id: 2, name: "Cactus", days: 12, symbol: "sun.max"), Plant(id: 3, name: "Basil", days: 1, symbol: "drop")]}
   TabView({fn})
-    PlantList {plants=$[Plant(id: 1, name: "Monstera", days: 2, symbol: "leaf.fill"), Plant(id: 2, name: "Cactus", days: 12, symbol: "sun.max"), Plant(id: 3, name: "Basil", days: 1, symbol: "drop")], path=[], selection=Set(), adding=false}
+    PlantList {plants=$[Plant(id: 1, name: "Monstera", days: 7, symbol: "leaf.fill"), Plant(id: 2, name: "Cactus", days: 12, symbol: "sun.max"), Plant(id: 3, name: "Basil", days: 1, symbol: "drop")], path=[], selection=Set(), adding=false}
       NavigationStack(path: $[], {fn})
         List(selection: $Set(), {fn})
+          Section("Thirsty soon", {fn})
+            ForEach([Plant(id: 1, name: "Monstera", days: 7, symbol: "leaf.fill"), Plant(id: 2, name: "Cactus", days: 12, symbol: "sun.max"), Plant(id: 3, name: "Basil", days: 1, symbol: "drop")], {fn})
+              row 1
+                NavigationLink(value: Plant(id: 1, name: "Monstera", days: 7, symbol: "leaf.fill"), {fn})
+                  Label("Monstera, 7 days", systemImage: "leaf.fill")
+                  .swipeActions({fn})
+                    Button("Water", {fn})
+                      .tint(Color)
+              row 2
+                NavigationLink(value: Plant(id: 2, name: "Cactus", days: 12, symbol: "sun.max"), {fn})
+                  Label("Cactus, 12 days", systemImage: "sun.max")
+                  .swipeActions({fn})
+                    Button("Water", {fn})
+                      .tint(Color)
+              row 3
+                NavigationLink(value: Plant(id: 3, name: "Basil", days: 1, symbol: "drop"), {fn})
+                  Label("Basil, 1 days", systemImage: "drop")
+                  .swipeActions({fn})
+                    Button("Water", {fn})
+                      .tint(Color)
           .navigationTitle("Plants")
@@ -107,3 +147,3 @@
         Label("Plants", systemImage: "leaf")
-      .badge(2)
+      .badge(1)
     SettingsForm {reminders=true, quiet=false, hour=8.0, units="Days", snooze=1}
@@ -158,8 +198,28 @@
         Label("Settings", systemImage: "gear")
-== after Button[Add]@69
-ContentView {plants=[Plant(id: 1, name: "Monstera", days: 2, symbol: "leaf.fill"), Plant(id: 2, name: "Cactus", days: 12, symbol: "sun.max"), Plant(id: 3, name: "Basil", days: 1, symbol: "drop")]}
+== after Button[Water]@53
+ContentView {plants=[Plant(id: 1, name: "Monstera", days: 7, symbol: "leaf.fill"), Plant(id: 2, name: "Cactus", days: 7, symbol: "sun.max"), Plant(id: 3, name: "Basil", days: 1, symbol: "drop")]}
   TabView({fn})
-    PlantList {plants=$[Plant(id: 1, name: "Monstera", days: 2, symbol: "leaf.fill"), Plant(id: 2, name: "Cactus", days: 12, symbol: "sun.max"), Plant(id: 3, name: "Basil", days: 1, symbol: "drop")], path=[], selection=Set(), adding=true}
+    PlantList {plants=$[Plant(id: 1, name: "Monstera", days: 7, symbol: "leaf.fill"), Plant(id: 2, name: "Cactus", days: 7, symbol: "sun.max"), Plant(id: 3, name: "Basil", days: 1, symbol: "drop")], path=[], selection=Set(), adding=false}
       NavigationStack(path: $[], {fn})
         List(selection: $Set(), {fn})
+          Section("Thirsty soon", {fn})
+            ForEach([Plant(id: 1, name: "Monstera", days: 7, symbol: "leaf.fill"), Plant(id: 2, name: "Cactus", days: 7, symbol: "sun.max"), Plant(id: 3, name: "Basil", days: 1, symbol: "drop")], {fn})
+              row 1
+                NavigationLink(value: Plant(id: 1, name: "Monstera", days: 7, symbol: "leaf.fill"), {fn})
+                  Label("Monstera, 7 days", systemImage: "leaf.fill")
+                  .swipeActions({fn})
+                    Button("Water", {fn})
+                      .tint(Color)
+              row 2
+                NavigationLink(value: Plant(id: 2, name: "Cactus", days: 7, symbol: "sun.max"), {fn})
+                  Label("Cactus, 7 days", systemImage: "sun.max")
+                  .swipeActions({fn})
+                    Button("Water", {fn})
+                      .tint(Color)
+              row 3
+                NavigationLink(value: Plant(id: 3, name: "Basil", days: 1, symbol: "drop"), {fn})
+                  Label("Basil, 1 days", systemImage: "drop")
+                  .swipeActions({fn})
+                    Button("Water", {fn})
+                      .tint(Color)
           .navigationTitle("Plants")
@@ -177,3 +237,3 @@
               Button("Add", {fn})
-          .sheet(isPresented: $true, {fn})
+          .sheet(isPresented: $false, {fn})
             VStack(spacing: 16, {fn})
@@ -186,3 +246,3 @@
         Label("Plants", systemImage: "leaf")
-      .badge(2)
+      .badge(1)
     SettingsForm {reminders=true, quiet=false, hour=8.0, units="Days", snooze=1}
@@ -237,8 +297,28 @@
         Label("Settings", systemImage: "gear")
-== after Button[Add a fern]@75
-ContentView {plants=[Plant(id: 1, name: "Monstera", days: 2, symbol: "leaf.fill"), Plant(id: 2, name: "Cactus", days: 12, symbol: "sun.max"), Plant(id: 3, name: "Basil", days: 1, symbol: "drop"), Plant(id: 4, name: "Fern", days: 4, symbol: "leaf")]}
+== after Button[Water]@53
+ContentView {plants=[Plant(id: 1, name: "Monstera", days: 7, symbol: "leaf.fill"), Plant(id: 2, name: "Cactus", days: 7, symbol: "sun.max"), Plant(id: 3, name: "Basil", days: 7, symbol: "drop")]}
   TabView({fn})
-    PlantList {plants=$[Plant(id: 1, name: "Monstera", days: 2, symbol: "leaf.fill"), Plant(id: 2, name: "Cactus", days: 12, symbol: "sun.max"), Plant(id: 3, name: "Basil", days: 1, symbol: "drop"), Plant(id: 4, name: "Fern", days: 4, symbol: "leaf")], path=[], selection=Set(), adding=false}
+    PlantList {plants=$[Plant(id: 1, name: "Monstera", days: 7, symbol: "leaf.fill"), Plant(id: 2, name: "Cactus", days: 7, symbol: "sun.max"), Plant(id: 3, name: "Basil", days: 7, symbol: "drop")], path=[], selection=Set(), adding=false}
       NavigationStack(path: $[], {fn})
         List(selection: $Set(), {fn})
+          Section("Thirsty soon", {fn})
+            ForEach([Plant(id: 1, name: "Monstera", days: 7, symbol: "leaf.fill"), Plant(id: 2, name: "Cactus", days: 7, symbol: "sun.max"), Plant(id: 3, name: "Basil", days: 7, symbol: "drop")], {fn})
+              row 1
+                NavigationLink(value: Plant(id: 1, name: "Monstera", days: 7, symbol: "leaf.fill"), {fn})
+                  Label("Monstera, 7 days", systemImage: "leaf.fill")
…
```

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

## fixtures/apps/controls-styles.swift

```diff
--- before
+++ after
@@ -27,15 +27,19 @@
       Section("Pickup", {fn})
-        content failed
-      Section({fn})
-        ControlGroup({fn})
-          Button("Reset", systemImage: "arrow.counterclockwise", {fn})
-          Button("Double", systemImage: "plus", {fn})
-        Menu("Favorites", systemImage: "star", {fn}, primaryAction: {fn})
-          Button("Flat white", {fn})
-          Button("Espresso", {fn})
-        Button("Order", {fn})
-          .buttonStyle(PressableStyle(color: Color))
-      .navigationTitle("Coffee")
-      .controlSize(.regular)
-error: Line 74: Cannot find 'MultiDatePicker' in scope
+        DatePicker("Time", selection: $<date>, in: Nov 24, 2026 at <time>...nil, displayedComponents: .hourAndMinute)
+        MultiDatePicker("Weekly", selection: $Set())
+        ColorPicker("Cup", selection: $Color, supportsOpacity: false)
+        TextField("Note for the barista", text: $"", axis: .vertical)
+          .lineLimit(2...4)
+        LabeledContent("Orders today", value: "0")
+      Section({fn})
+        ControlGroup({fn})
+          Button("Reset", systemImage: "arrow.counterclockwise", {fn})
+          Button("Double", systemImage: "plus", {fn})
+        Menu("Favorites", systemImage: "star", {fn}, primaryAction: {fn})
+          Button("Flat white", {fn})
+          Button("Espresso", {fn})
+        Button("Order", {fn})
+          .buttonStyle(PressableStyle(color: Color))
+      .navigationTitle("Coffee")
+      .controlSize(.regular)
 == after Button[Flat white]@86
@@ -67,3 +71,8 @@
       Section("Pickup", {fn})
-        content failed
+        DatePicker("Time", selection: $<date>, in: Nov 24, 2026 at <time>...nil, displayedComponents: .hourAndMinute)
+        MultiDatePicker("Weekly", selection: $Set())
+        ColorPicker("Cup", selection: $Color, supportsOpacity: false)
+        TextField("Note for the barista", text: $"", axis: .vertical)
+          .lineLimit(2...4)
+        LabeledContent("Orders today", value: "1")
       Section({fn})
@@ -106,3 +115,8 @@
       Section("Pickup", {fn})
-        content failed
+        DatePicker("Time", selection: $<date>, in: Nov 24, 2026 at <time>...nil, displayedComponents: .hourAndMinute)
+        MultiDatePicker("Weekly", selection: $Set())
+        ColorPicker("Cup", selection: $Color, supportsOpacity: false)
+        TextField("Note for the barista", text: $"", axis: .vertical)
+          .lineLimit(2...4)
+        LabeledContent("Orders today", value: "2")
       Section({fn})
@@ -145,3 +159,8 @@
       Section("Pickup", {fn})
-        content failed
+        DatePicker("Time", selection: $<date>, in: Nov 24, 2026 at <time>...nil, displayedComponents: .hourAndMinute)
+        MultiDatePicker("Weekly", selection: $Set())
+        ColorPicker("Cup", selection: $Color, supportsOpacity: false)
+        TextField("Note for the barista", text: $"", axis: .vertical)
+          .lineLimit(2...4)
+        LabeledContent("Orders today", value: "4")
       Section({fn})
@@ -184,3 +203,8 @@
       Section("Pickup", {fn})
-        content failed
+        DatePicker("Time", selection: $<date>, in: Nov 24, 2026 at <time>...nil, displayedComponents: .hourAndMinute)
+        MultiDatePicker("Weekly", selection: $Set())
+        ColorPicker("Cup", selection: $Color, supportsOpacity: false)
+        TextField("Note for the barista", text: $"", axis: .vertical)
+          .lineLimit(2...4)
+        LabeledContent("Orders today", value: "5")
       Section({fn})
@@ -223,3 +247,8 @@
       Section("Pickup", {fn})
-        content failed
+        DatePicker("Time", selection: $<date>, in: Nov 24, 2026 at <time>...nil, displayedComponents: .hourAndMinute)
+        MultiDatePicker("Weekly", selection: $Set())
+        ColorPicker("Cup", selection: $Color, supportsOpacity: false)
+        TextField("Note for the barista", text: $"", axis: .vertical)
+          .lineLimit(2...4)
+        LabeledContent("Orders today", value: "6")
       Section({fn})
@@ -262,3 +291,8 @@
       Section("Pickup", {fn})
-        content failed
+        DatePicker("Time", selection: $<date>, in: Nov 24, 2026 at <time>...nil, displayedComponents: .hourAndMinute)
+        MultiDatePicker("Weekly", selection: $Set())
+        ColorPicker("Cup", selection: $Color, supportsOpacity: false)
+        TextField("Note for the barista", text: $"", axis: .vertical)
+          .lineLimit(2...4)
+        LabeledContent("Orders today", value: "8")
       Section({fn})
@@ -301,3 +335,8 @@
       Section("Pickup", {fn})
-        content failed
+        DatePicker("Time", selection: $<date>, in: Nov 24, 2026 at <time>...nil, displayedComponents: .hourAndMinute)
+        MultiDatePicker("Weekly", selection: $Set())
+        ColorPicker("Cup", selection: $Color, supportsOpacity: false)
+        TextField("Note for the barista", text: $"", axis: .vertical)
+          .lineLimit(2...4)
+        LabeledContent("Orders today", value: "9")
       Section({fn})
@@ -340,3 +379,8 @@
       Section("Pickup", {fn})
-        content failed
+        DatePicker("Time", selection: $<date>, in: Nov 24, 2026 at <time>...nil, displayedComponents: .hourAndMinute)
+        MultiDatePicker("Weekly", selection: $Set())
+        ColorPicker("Cup", selection: $Color, supportsOpacity: false)
+        TextField("Note for the barista", text: $"", axis: .vertical)
+          .lineLimit(2...4)
+        LabeledContent("Orders today", value: "10")
       Section({fn})
@@ -379,3 +423,8 @@
       Section("Pickup", {fn})
-        content failed
+        DatePicker("Time", selection: $<date>, in: Nov 24, 2026 at <time>...nil, displayedComponents: .hourAndMinute)
+        MultiDatePicker("Weekly", selection: $Set())
…
```

## fixtures/apps/layout-scrolling.swift

```diff
--- before
+++ after
@@ -1,2 +1,1807 @@
 == start
-error: Line 35: Cannot find 'ScrollPosition' in scope
+ContentView {position=ScrollPosition, offset=0.0, cards=[Card(id: 0, title: "Dunes", color: Color), Card(id: 1, title: "Fjord", color: Color), Card(id: 2, title: "Forest", color: Color), Card(id: 3, title: "Glacier", color: Color)]}
+  ScrollView({fn})
+    VStack(alignment: .leading, spacing: 20, {fn})
+      ScrollView(.horizontal, {fn})
+        LazyHStack(spacing: 12, {fn})
+          ForEach([Card(id: 0, title: "Dunes", color: Color), Card(id: 1, title: "Fjord", color: Color), Card(id: 2, title: "Forest", color: Color), Card(id: 3, title: "Glacier", color: Color)], {fn})
+            row 0
+              RoundedRectangle(cornerRadius: 20)
+                .fill(<view>)
+                  LinearGradient(colors: [Color, Color])
+                .overlay(<view>)
+                  Text("Dunes")
+                    .font(Font)
+                    .foregroundStyle(Color)
+                .containerRelativeFrame(.horizontal, count: 5, span: 4, spacing: 12)
+                .frame(height: 180)
+                .scrollTransition({fn})
+                  Empty
+                    .opacity(1)
+                    .scaleEffect(1)
+                .id(0)
+            row 1
+              RoundedRectangle(cornerRadius: 20)
+                .fill(<view>)
+                  LinearGradient(colors: [Color, Color])
+                .overlay(<view>)
+                  Text("Fjord")
+                    .font(Font)
+                    .foregroundStyle(Color)
+                .containerRelativeFrame(.horizontal, count: 5, span: 4, spacing: 12)
+                .frame(height: 180)
+                .scrollTransition({fn})
+                  Empty
+                    .opacity(1)
+                    .scaleEffect(1)
+                .id(1)
+            row 2
+              RoundedRectangle(cornerRadius: 20)
+                .fill(<view>)
+                  LinearGradient(colors: [Color, Color])
+                .overlay(<view>)
+                  Text("Forest")
+                    .font(Font)
+                    .foregroundStyle(Color)
+                .containerRelativeFrame(.horizontal, count: 5, span: 4, spacing: 12)
+                .frame(height: 180)
+                .scrollTransition({fn})
+                  Empty
+                    .opacity(1)
+                    .scaleEffect(1)
+                .id(2)
+            row 3
+              RoundedRectangle(cornerRadius: 20)
+                .fill(<view>)
+                  LinearGradient(colors: [Color, Color])
+                .overlay(<view>)
+                  Text("Glacier")
+                    .font(Font)
+                    .foregroundStyle(Color)
+                .containerRelativeFrame(.horizontal, count: 5, span: 4, spacing: 12)
+                .frame(height: 180)
+                .scrollTransition({fn})
+                  Empty
+                    .opacity(1)
+                    .scaleEffect(1)
+                .id(3)
+          .scrollTargetLayout()
+        .scrollTargetBehavior(.viewAligned)
+        .scrollPosition($ScrollPosition)
+        .contentMargins(.horizontal, 20, for: .scrollContent)
+        .scrollIndicators(.hidden)
+        .onScrollGeometryChange(for: Double, {fn}, action: {fn})
+      HStack({fn})
+        Button("First", {fn})
+        Button("Last", {fn})
+        Spacer()
+        Text(_literal: "0 pt")
+          .monospacedDigit()
+        .padding(.horizontal, 20)
+      Captioned {content=<view>}
+        VStack(alignment: .leading, spacing: 8, {fn})
+          ForEach(subviews: <view>, {fn})
+            row 0
+              VStack(alignment: .leading, {fn})
+                Text(_literal: "Sunrise")
+                  .font(Font)
+                  .containerValue(KeyPath, "<time>")
+                Text("<time>")
+                  .font(Font)
+                  .foregroundStyle(Color)
+            row 1
+              VStack(alignment: .leading, {fn})
+                Text(_literal: "Sunset")
+                  .font(Font)
+                  .containerValue(KeyPath, "<time>")
+                Text("<time>")
+                  .font(Font)
+                  .foregroundStyle(Color)
+        .padding(.horizontal, 20)
+      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8, {fn})
+        GridRow({fn})
+          Text(_literal: "Place")
+            .font(Font)
+          Text(_literal: "Photos")
+            .font(Font)
+            .gridColumnAlignment(.trailing)
+        ForEach([Card(id: 0, title: "Dunes", color: Color), Card(id: 1, title: "Fjord", color: Color), Card(id: 2, title: "Forest", color: Color), Card(id: 3, title: "Glacier", color: Color)], {fn})
+          row 0
+            GridRow({fn})
+              Text("Dunes")
+              Text(_literal: "4")
+          row 1
+            GridRow({fn})
+              Text("Fjord")
+              Text(_literal: "16")
…
```

## fixtures/apps/lists-selection.swift

```diff
--- before
+++ after
@@ -4,2 +4,57 @@
     List(selection: $Set(), {fn})
+      Section("To read", {fn})
+        ForEach($[Book(id: 1, title: "Dune", author: "Herbert"), Book(id: 2, title: "Emma", author: "Austen"), Book(id: 3, title: "Ulysses", author: "Joyce"), Book(id: 4, title: "Beloved", author: "Morrison")], editActions: .all, {fn})
+          row 1
+            VStack(alignment: .leading, {fn})
+              Text("Dune")
+                .font(Font)
+              Text("Herbert")
+                .font(Font)
+                .foregroundStyle(Color)
+              .swipeActions(edge: .leading, {fn})
+                Button("Top", systemImage: "arrow.up", {fn})
+                  .tint(Color)
+              .listRowSeparatorTint(Color)
+          row 2
+            VStack(alignment: .leading, {fn})
+              Text("Emma")
+                .font(Font)
+              Text("Austen")
+                .font(Font)
+                .foregroundStyle(Color)
+              .swipeActions(edge: .leading, {fn})
+                Button("Top", systemImage: "arrow.up", {fn})
+                  .tint(Color)
+              .listRowSeparatorTint(Color)
+          row 3
+            VStack(alignment: .leading, {fn})
+              Text("Ulysses")
+                .font(Font)
+              Text("Joyce")
+                .font(Font)
+                .foregroundStyle(Color)
+              .swipeActions(edge: .leading, {fn})
+                Button("Top", systemImage: "arrow.up", {fn})
+                  .tint(Color)
+              .listRowSeparatorTint(Color)
+          row 4
+            VStack(alignment: .leading, {fn})
+              Text("Beloved")
+                .font(Font)
+              Text("Morrison")
+                .font(Font)
+                .foregroundStyle(Color)
+              .swipeActions(edge: .leading, {fn})
+                Button("Top", systemImage: "arrow.up", {fn})
+                  .tint(Color)
+              .listRowSeparatorTint(Color)
+        .sectionIndexLabel("R")
+      Section("Shelves", isExpanded: $true, {fn})
+        OutlineGroup([Shelf(id: 10, name: "Fiction", children: [Shelf(id: 11, name: "Classics", children: nil), Shelf(id: 12, name: "Sci-fi", children: nil)]), Shelf(id: 20, name: "Poetry", children: nil)], children: KeyPath, {fn})
+          row 10
+            Label("Fiction", systemImage: "folder")
+          row 20
+            Label("Poetry", systemImage: "folder")
+          .selectionDisabled()
+        .headerProminence(.increased)
       .listSectionSpacing(.compact)
```

## fixtures/apps/navigation-tabs.swift

```diff
--- before
+++ after
@@ -39,4 +39,10 @@
             .toolbar({fn})
-              content failed
-            .sheet(isPresented: $false, {fn})
+              ToolbarItem(placement: .topBarLeading, {fn})
+                Button("Filters", systemImage: "line.3.horizontal.decrease", {fn})
+              ToolbarSpacer(.flexible, placement: .bottomBar)
+              ToolbarItem(placement: .bottomBar, {fn})
+                Button("Random", systemImage: "dice", {fn})
+                  If true
+                .visibilityPriority(.high)
+            .sheet(isPresented: $true, {fn})
               Form({fn})
@@ -96,4 +102,10 @@
             .toolbar({fn})
-              content failed
-            .sheet(isPresented: $false, {fn})
+              ToolbarItem(placement: .topBarLeading, {fn})
+                Button("Filters", systemImage: "line.3.horizontal.decrease", {fn})
+              ToolbarSpacer(.flexible, placement: .bottomBar)
+              ToolbarItem(placement: .bottomBar, {fn})
+                Button("Random", systemImage: "dice", {fn})
+                  If true
+                .visibilityPriority(.high)
+            .sheet(isPresented: $true, {fn})
               Form({fn})
@@ -110,3 +122,2 @@
     .tabBarMinimizeBehavior(.onScrollDown)
-error: Line 55: Cannot find 'ToolbarSpacer' in scope
 == after Button[Log a visit]@97
@@ -115,39 +126,45 @@
     Tab("Places", systemImage: "map", value: 0, {fn})
-      PlacesView {places=[Place(id: 1, name: "Lighthouse", region: "North", symbol: "light.beacon.max"), Place(id: 2, name: "Old Mill", region: "South", symbol: "wind"), Place(id: 3, name: "Harbor", region: "North", symbol: "ferry")], zoom=(), path=[], query="", showsFilters=false, region="All"}
-        NavigationStack(path: $[], {fn})
-          List([Place(id: 1, name: "Lighthouse", region: "North", symbol: "light.beacon.max"), Place(id: 2, name: "Old Mill", region: "South", symbol: "wind"), Place(id: 3, name: "Harbor", region: "North", symbol: "ferry")], {fn})
-            row 1
-              NavigationLink(value: Place(id: 1, name: "Lighthouse", region: "North", symbol: "light.beacon.max"), {fn})
-                Label("Lighthouse", systemImage: "light.beacon.max")
-                .matchedTransitionSource(id: 1, in: ())
-            row 2
-              NavigationLink(value: Place(id: 2, name: "Old Mill", region: "South", symbol: "wind"), {fn})
-                Label("Old Mill", systemImage: "wind")
-                .matchedTransitionSource(id: 2, in: ())
-            row 3
-              NavigationLink(value: Place(id: 3, name: "Harbor", region: "North", symbol: "ferry"), {fn})
-                Label("Harbor", systemImage: "ferry")
-                .matchedTransitionSource(id: 3, in: ())
-            .navigationTitle("Places")
-            .navigationSubtitle("3 of 3")
-            .navigationDestination(for: Place, {fn})
-              VStack(spacing: 12, {fn})
-                Image(systemName: nil)
-                  .font(Font)
-                Text(nil)
-                  .font(Font)
-                Text(nil)
-                  .foregroundStyle(Color)
-                .navigationTransition(.zoom(nil, ()))
-            .searchable(text: $"", prompt: "Find a place")
-            .searchScopes($"All", {fn})
-              Text(_literal: "All")
-                .tag("All")
-              Text(_literal: "North")
-                .tag("North")
-              Text(_literal: "South")
-                .tag("South")
-            .toolbar({fn})
-              content failed
-            .sheet(isPresented: $false, {fn})
+      PlacesView {places=[Place(id: 1, name: "Lighthouse", region: "North", symbol: "light.beacon.max"), Place(id: 2, name: "Old Mill", region: "South", symbol: "wind"), Place(id: 3, name: "Harbor", region: "North", symbol: "ferry")], zoom=(), path=[Place(id: 2, name: "Old Mill", region: "South", symbol: "wind")], query="", showsFilters=true, region="All"}
+        NavigationStack(path: $[Place(id: 2, name: "Old Mill", region: "South", symbol: "wind")], {fn})
+          List([Place(id: 1, name: "Lighthouse", region: "North", symbol: "light.beacon.max"), Place(id: 2, name: "Old Mill", region: "South", symbol: "wind"), Place(id: 3, name: "Harbor", region: "North", symbol: "ferry")], {fn})
+            row 1
+              NavigationLink(value: Place(id: 1, name: "Lighthouse", region: "North", symbol: "light.beacon.max"), {fn})
+                Label("Lighthouse", systemImage: "light.beacon.max")
+                .matchedTransitionSource(id: 1, in: ())
+            row 2
+              NavigationLink(value: Place(id: 2, name: "Old Mill", region: "South", symbol: "wind"), {fn})
+                Label("Old Mill", systemImage: "wind")
+                .matchedTransitionSource(id: 2, in: ())
+            row 3
+              NavigationLink(value: Place(id: 3, name: "Harbor", region: "North", symbol: "ferry"), {fn})
+                Label("Harbor", systemImage: "ferry")
+                .matchedTransitionSource(id: 3, in: ())
+            .navigationTitle("Places")
+            .navigationSubtitle("3 of 3")
+            .navigationDestination(for: Place, {fn})
+              VStack(spacing: 12, {fn})
+                Image(systemName: nil)
+                  .font(Font)
+                Text(nil)
+                  .font(Font)
+                Text(nil)
+                  .foregroundStyle(Color)
+                .navigationTransition(.zoom(nil, ()))
+            .searchable(text: $"", prompt: "Find a place")
+            .searchScopes($"All", {fn})
+              Text(_literal: "All")
+                .tag("All")
+              Text(_literal: "North")
+                .tag("North")
+              Text(_literal: "South")
+                .tag("South")
+            .toolbar({fn})
+              ToolbarItem(placement: .topBarLeading, {fn})
+                Button("Filters", systemImage: "line.3.horizontal.decrease", {fn})
+              ToolbarSpacer(.flexible, placement: .bottomBar)
+              ToolbarItem(placement: .bottomBar, {fn})
+                Button("Random", systemImage: "dice", {fn})
+                  If true
+                .visibilityPriority(.high)
+            .sheet(isPresented: $true, {fn})
               Form({fn})
@@ -172,39 +189,45 @@
     Tab(value: 2, role: .search, {fn})
-      PlacesView {places=[Place(id: 1, name: "Lighthouse", region: "North", symbol: "light.beacon.max"), Place(id: 2, name: "Old Mill", region: "South", symbol: "wind"), Place(id: 3, name: "Harbor", region: "North", symbol: "ferry")], zoom=(), path=[], query="", showsFilters=false, region="All"}
-        NavigationStack(path: $[], {fn})
-          List([Place(id: 1, name: "Lighthouse", region: "North", symbol: "light.beacon.max"), Place(id: 2, name: "Old Mill", region: "South", symbol: "wind"), Place(id: 3, name: "Harbor", region: "North", symbol: "ferry")], {fn})
…
```

## fixtures/apps/network.swift

```diff
--- before
+++ after
@@ -17,195 +17,247 @@
 == appeared (List.onAppear@89)
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
-== after List.onSubmit@87
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
-== after List.refreshable@88
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
-== after List.onSubmit@87
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
-== after List.refreshable@88
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
-== after List.onSubmit@87
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
-== after List.refreshable@88
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
-== after List.onSubmit@87
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
-error: Line 89: Cannot find 'modifier' in scope
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
+== after Button[High Tide]@133
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
+== after Button[Low Tide]@133
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
@@ -4,3 +4,22 @@
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
+      Text(_literal: "Saves as .txt")
+        .font(Font)
+        .foregroundStyle(Color)
       .padding()
@@ -8,2 +27,351 @@
       .sheet(isPresented: $false, {fn})
-error: Line 113: Cannot find 'SharePreview' in scope
+        ImagePicker {image=$nil, dismiss=DismissAction}
+          (no body)
+== after Button[Choose Photo]@111
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
+      Text(_literal: "Saves as .txt")
+        .font(Font)
+        .foregroundStyle(Color)
+      .padding()
+      .navigationTitle("Photo Card")
+      .sheet(isPresented: $true, {fn})
+        ImagePicker {image=$nil, dismiss=DismissAction}
+          (no body)
+== after Button[Choose Photo]@111
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
+      Text(_literal: "Saves as .txt")
+        .font(Font)
+        .foregroundStyle(Color)
+      .padding()
+      .navigationTitle("Photo Card")
+      .sheet(isPresented: $true, {fn})
+        ImagePicker {image=$nil, dismiss=DismissAction}
+          (no body)
+== after Button[Choose Photo]@111
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
+      Text(_literal: "Saves as .txt")
+        .font(Font)
+        .foregroundStyle(Color)
+      .padding()
+      .navigationTitle("Photo Card")
+      .sheet(isPresented: $true, {fn})
+        ImagePicker {image=$nil, dismiss=DismissAction}
+          (no body)
+== after Button[Choose Photo]@111
+ContentView {image=nil, picking=true, caption="A day at the sea"}
…
```

## tests/ControlsBridgeTests-7.swift

```diff
--- before
+++ after
@@ -1,4 +1,4 @@
 == start
-Probe {isEnabled=nil, size=nil}
-  Text("off")
+Probe {isEnabled=true, size=.regular}
+  Text("on")
     .foregroundStyle(Color)
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

## tests/ListsBridgeTests-7.swift

```diff
--- before
+++ after
@@ -1,3 +1,3 @@
 == start
-Probe {rowHeight=nil, scrolls=nil}
-  Text(_literal: "0 fixed")
+Probe {rowHeight=24.0, scrolls=true}
+  Text(_literal: "24 scrolls")
```

## tests/NavigationBridgeTests-5.swift

```diff
--- before
+++ after
@@ -2,39 +2,39 @@
 error: Line 1: Cannot find 'item' in scope
-Probe {searching=nil, dismissSearch=nil}
+Probe {searching=false, dismissSearch=DismissAction}
   Button("Idle", {fn})
 == after Button[Idle]@5
-Probe {searching=nil, dismissSearch=nil}
+Probe {searching=false, dismissSearch=DismissAction}
   Button("Idle", {fn})
 == after Button[Idle]@5
-Probe {searching=nil, dismissSearch=nil}
+Probe {searching=false, dismissSearch=DismissAction}
   Button("Idle", {fn})
 == after Button[Idle]@5
-Probe {searching=nil, dismissSearch=nil}
+Probe {searching=false, dismissSearch=DismissAction}
   Button("Idle", {fn})
 == after Button[Idle]@5
-Probe {searching=nil, dismissSearch=nil}
+Probe {searching=false, dismissSearch=DismissAction}
   Button("Idle", {fn})
 == after Button[Idle]@5
-Probe {searching=nil, dismissSearch=nil}
+Probe {searching=false, dismissSearch=DismissAction}
   Button("Idle", {fn})
 == after Button[Idle]@5
-Probe {searching=nil, dismissSearch=nil}
+Probe {searching=false, dismissSearch=DismissAction}
   Button("Idle", {fn})
 == after Button[Idle]@5
-Probe {searching=nil, dismissSearch=nil}
+Probe {searching=false, dismissSearch=DismissAction}
   Button("Idle", {fn})
 == after Button[Idle]@5
-Probe {searching=nil, dismissSearch=nil}
+Probe {searching=false, dismissSearch=DismissAction}
   Button("Idle", {fn})
 == after Button[Idle]@5
-Probe {searching=nil, dismissSearch=nil}
+Probe {searching=false, dismissSearch=DismissAction}
   Button("Idle", {fn})
 == after Button[Idle]@5
-Probe {searching=nil, dismissSearch=nil}
+Probe {searching=false, dismissSearch=DismissAction}
   Button("Idle", {fn})
 == after Button[Idle]@5
-Probe {searching=nil, dismissSearch=nil}
+Probe {searching=false, dismissSearch=DismissAction}
   Button("Idle", {fn})
 == after Button[Idle]@5
-Probe {searching=nil, dismissSearch=nil}
+Probe {searching=false, dismissSearch=DismissAction}
   Button("Idle", {fn})
```

## tests/NavigationBridgeTests-8.swift

```diff
--- before
+++ after
@@ -1,39 +1,39 @@
 == start
-Editor {editMode=nil, isPresented=nil}
+Editor {editMode=nil, isPresented=false}
   Button("Edit", {fn})
 == after Button[Edit]@5
-Editor {editMode=nil, isPresented=nil}
+Editor {editMode=nil, isPresented=false}
   Button("Edit", {fn})
 == after Button[Edit]@5
-Editor {editMode=nil, isPresented=nil}
+Editor {editMode=nil, isPresented=false}
   Button("Edit", {fn})
 == after Button[Edit]@5
-Editor {editMode=nil, isPresented=nil}
+Editor {editMode=nil, isPresented=false}
   Button("Edit", {fn})
 == after Button[Edit]@5
-Editor {editMode=nil, isPresented=nil}
+Editor {editMode=nil, isPresented=false}
   Button("Edit", {fn})
 == after Button[Edit]@5
-Editor {editMode=nil, isPresented=nil}
+Editor {editMode=nil, isPresented=false}
   Button("Edit", {fn})
 == after Button[Edit]@5
-Editor {editMode=nil, isPresented=nil}
+Editor {editMode=nil, isPresented=false}
   Button("Edit", {fn})
 == after Button[Edit]@5
-Editor {editMode=nil, isPresented=nil}
+Editor {editMode=nil, isPresented=false}
   Button("Edit", {fn})
 == after Button[Edit]@5
-Editor {editMode=nil, isPresented=nil}
+Editor {editMode=nil, isPresented=false}
   Button("Edit", {fn})
 == after Button[Edit]@5
-Editor {editMode=nil, isPresented=nil}
+Editor {editMode=nil, isPresented=false}
   Button("Edit", {fn})
 == after Button[Edit]@5
-Editor {editMode=nil, isPresented=nil}
+Editor {editMode=nil, isPresented=false}
   Button("Edit", {fn})
 == after Button[Edit]@5
-Editor {editMode=nil, isPresented=nil}
+Editor {editMode=nil, isPresented=false}
   Button("Edit", {fn})
 == after Button[Edit]@5
-Editor {editMode=nil, isPresented=nil}
+Editor {editMode=nil, isPresented=false}
   Button("Edit", {fn})
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
