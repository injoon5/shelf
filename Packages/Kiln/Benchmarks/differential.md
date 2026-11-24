# Differential check

Every input run on the engine at `b466f9c` and on this one, comparing their transcripts: the view tree each body evaluates to, the console, errors and warnings with their lines, and all of it again after each scripted action (`onAppear` and `.task` first, then each button and tap). `Tools/diff.sh` writes this file.

**128 inputs: 79 identical, 49 different as expected, 0 different otherwise.**

| Input | Transcript lines | Steps | Result |
|---|---:|---:|---|
| Packages/Kiln/Examples/Apps/CardStyles.swift | 242 | 13 | identical |
| Packages/Kiln/Examples/Apps/Chess.swift | 21125 | 13 | identical |
| Packages/Kiln/Examples/Apps/DoodlePad.swift | 6 | 1 | expected (Round 1's Lab example: before, gestures, Canvas and focus weren't bridged (Canvas drew nothing; @FocusState and .gesture were stubs).) |
| Packages/Kiln/Examples/Apps/ExpenseTracker.swift | 1654 | 13 | identical |
| Packages/Kiln/Examples/Apps/FocusTimer.swift | 910 | 13 | identical |
| Packages/Kiln/Examples/Apps/HabitTracker.swift | 1105 | 13 | identical |
| Packages/Kiln/Examples/Apps/LineFeed.swift | 156 | 13 | identical |
| Packages/Kiln/Examples/Apps/MemoryMatch.swift | 2656 | 14 | identical |
| Packages/Kiln/Examples/Apps/PlantCare.swift | 1455 | 13 | identical |
| Packages/Kiln/Examples/Apps/ReadingList.swift | 125 | 1 | identical |
| Packages/Kiln/Examples/Apps/TagCloud.swift | 4 | 1 | expected (§1.5's Lab example: before, `AnyLayout` and the app's `Layout` didn't exist and the body stopped.) |
| Packages/Kiln/Examples/Apps/Terrain.swift | 29 | 1 | expected (Round 2 §3.7's Lab example: before, Chart3D and SurfacePlot weren't bridged.) |
| Packages/Kiln/Examples/Apps/TipCalculator.swift | 42 | 1 | identical |
| Packages/Kiln/Examples/Apps/WaveStudio.swift | 341 | 13 | identical |
| Packages/Kiln/Examples/AppleIntelligence/expense.md | 754 | 13 | expected (The reply writes .stepValue(0.1), which isn't a SwiftUI modifier: §1.4 reports it with its line, where before it was skipped silently.) |
| Packages/Kiln/Examples/AppleIntelligence/habit.md | 377 | 13 | identical |
| Packages/Kiln/Examples/AppleIntelligence/memory.md | 31 | 1 | identical |
| Packages/Kiln/Examples/AppleIntelligence/timer.md | 338 | 13 | identical |
| Packages/Kiln/Examples/AppleIntelligence/tip.md | 1092 | 13 | identical |
| Packages/Kiln/Examples/Networking/OpenLibrarySearch.swift | 22 | 2 | identical |
| Packages/Kiln/Examples/LibraryApp.swift | 64 | 2 | identical |
| fixtures/apps/accessibility-motion.swift | 2 | 1 | expected (Round 1's fixture: before, its gestures, Canvas, glass, animators, charts, focus, environment values or accessibility modifiers weren't bridged.) |
| fixtures/apps/async.swift | 283 | 14 | identical |
| fixtures/apps/audio.swift | 2 | 1 | expected (Round 2 §3.5's fixture: before, AVAudioPlayer, AVSpeechSynthesizer and VideoPlayer weren't bridged.) |
| fixtures/apps/chart3d.swift | 29 | 1 | expected (Round 2 §3.7's fixture: before, Chart3D and SurfacePlot weren't bridged.) |
| fixtures/apps/charts.swift | 81 | 1 | expected (Round 1's fixture: before, its gestures, Canvas, glass, animators, charts, focus, environment values or accessibility modifiers weren't bridged.) |
| fixtures/apps/controls-styles.swift | 508 | 13 | expected (Round 1A's Controls fixture: before, custom styles, MultiDatePicker and Menu(primaryAction:) weren't bridged.) |
| fixtures/apps/focus-environment.swift | 703 | 13 | expected (Round 1's fixture: before, its gestures, Canvas, glass, animators, charts, focus, environment values or accessibility modifiers weren't bridged.) |
| fixtures/apps/gestures-canvas.swift | 6 | 1 | expected (Round 1's fixture: before, its gestures, Canvas, glass, animators, charts, focus, environment values or accessibility modifiers weren't bridged.) |
| fixtures/apps/images.swift | 663 | 13 | identical |
| fixtures/apps/layout-scrolling.swift | 2 | 1 | expected (Round 1A's Layout fixture: before, @Entry on ContainerValues and ForEach(subviews:) stopped the body.) |
| fixtures/apps/lists-selection.swift | 59 | 1 | expected (Round 1A's Lists fixture: before, ForEach(editActions:) and OutlineGroup weren't bridged, and the probe read List(selection:)'s binding as its data.) |
| fixtures/apps/navigation-tabs.swift | 1431 | 13 | expected (Round 1A's Navigation fixture: before, Tab, ToolbarSpacer, zoom transitions and search scopes weren't bridged.) |
| fixtures/apps/network.swift | 211 | 14 | expected (Its dataTask handlers now run in a check: since §1.7 a check never touches the network, so the handler gets the offline error at once and the app shows its error state, where before the request started and its handler never ran.) |
| fixtures/apps/saving-data.swift | 1076 | 14 | identical |
| fixtures/apps/state.swift | 599 | 13 | identical |
| fixtures/apps/streams.swift | 363 | 14 | expected (Round 2 §3.8's fixture: before, webSocketTask and bytes(from:) weren't bridged.) |
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
| fixtures/apps/web.swift | 2 | 1 | expected (Round 2 §3.6's fixture: before, WebView and WebPage weren't bridged.) |
| Packages/Kiln/Benchmarks/Workloads/Arithmetic.swift | 8 | 2 | identical |
| Packages/Kiln/Benchmarks/Workloads/Collections.swift | 112 | 2 | identical |
| Packages/Kiln/Benchmarks/Workloads/Objects.swift | 8 | 2 | identical |
| tests/AppTypesRepro-0.swift | 1742 | 13 | identical |
| tests/AppTypesRepro-1.swift | 17 | 1 | identical |
| tests/AppTypesRepro-2.swift | 234 | 13 | identical |
| tests/AppTypesRepro-3.swift | 327 | 13 | identical |
| tests/AudioBridgeTests-1.swift | 3 | 1 | expected (Round 2 §3.5: before, AVSpeechSynthesizer and AVPlayer weren't bridged.) |
| tests/BreakoutRepro-0.swift | 8 | 2 | identical |
| tests/BridgeTestSupport-0.swift | 2 | 1 | identical |
| tests/Chart3DBridgeTests-0.swift | 5 | 1 | expected (Round 2 §3.7: before, Chart3D and SurfacePlot weren't bridged.) |
| tests/Chart3DBridgeTests-1.swift | 3 | 1 | identical |
| tests/Chart3DBridgeTests-2.swift | 3 | 1 | identical |
| tests/Chart3DBridgeTests-3.swift | 3 | 1 | identical |
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
| tests/RestOfSwiftUITests-0.swift | 5 | 1 | expected (Round 1 (rest of SwiftUI): before, what this test exercises (gestures, Canvas, animators, focus, environment values, preferences, charts, accessibility) wasn't bridged.) |
| tests/RestOfSwiftUITests-10.swift | 312 | 13 | expected (Round 1 (rest of SwiftUI): before, what this test exercises (gestures, Canvas, animators, focus, environment values, preferences, charts, accessibility) wasn't bridged.) |
| tests/RestOfSwiftUITests-11.swift | 10 | 2 | expected (Round 1 (rest of SwiftUI): before, what this test exercises (gestures, Canvas, animators, focus, environment values, preferences, charts, accessibility) wasn't bridged.) |
| tests/RestOfSwiftUITests-12.swift | 17 | 2 | expected (Round 1 (rest of SwiftUI): before, what this test exercises (gestures, Canvas, animators, focus, environment values, preferences, charts, accessibility) wasn't bridged.) |
| tests/RestOfSwiftUITests-13.swift | 15 | 2 | expected (Round 1 (rest of SwiftUI): before, what this test exercises (gestures, Canvas, animators, focus, environment values, preferences, charts, accessibility) wasn't bridged.) |
| tests/RestOfSwiftUITests-14.swift | 14 | 1 | expected (Round 1 (rest of SwiftUI): before, what this test exercises (gestures, Canvas, animators, focus, environment values, preferences, charts, accessibility) wasn't bridged.) |
| tests/RestOfSwiftUITests-15.swift | 8 | 2 | expected (Round 1 (rest of SwiftUI): before, what this test exercises (gestures, Canvas, animators, focus, environment values, preferences, charts, accessibility) wasn't bridged.) |
| tests/RestOfSwiftUITests-16.swift | 5 | 1 | expected (Round 1 (rest of SwiftUI): before, what this test exercises (gestures, Canvas, animators, focus, environment values, preferences, charts, accessibility) wasn't bridged.) |
| tests/RestOfSwiftUITests-19.swift | 2 | 1 | expected (Round 1 (rest of SwiftUI): before, what this test exercises (gestures, Canvas, animators, focus, environment values, preferences, charts, accessibility) wasn't bridged.) |
| tests/RestOfSwiftUITests-2.swift | 5 | 1 | identical |
| tests/RestOfSwiftUITests-20.swift | 9 | 1 | identical |
| tests/RestOfSwiftUITests-3.swift | 6 | 1 | expected (Round 1 (rest of SwiftUI): before, what this test exercises (gestures, Canvas, animators, focus, environment values, preferences, charts, accessibility) wasn't bridged.) |
| tests/RestOfSwiftUITests-6.swift | 6 | 1 | expected (Round 1 (rest of SwiftUI): before, what this test exercises (gestures, Canvas, animators, focus, environment values, preferences, charts, accessibility) wasn't bridged.) |
| tests/SnakeGameTests-0.swift | 3 | 1 | identical |
| tests/SnakeGameTests-1.swift | 8 | 2 | identical |
| tests/SnakeGameTests-2.swift | 3 | 1 | identical |
| tests/StreamsBridgeTests-3.swift | 3 | 1 | identical |
| tests/StreamsBridgeTests-4.swift | 3 | 1 | identical |
| tests/StreamsBridgeTests-5.swift | 12 | 2 | expected (Round 2 §3.8: before, webSocketTask wasn't bridged.) |
| tests/StreamsBridgeTests-6.swift | 13 | 2 | expected (Round 2 §3.8: before, webSocketTask wasn't bridged.) |
| tests/WeatherRepro-0.swift | 209 | 13 | identical |
| tests/WeatherRepro-1.swift | 183 | 14 | identical |
| tests/WebBridgeTests-0.swift | 2 | 1 | expected (Round 2 §3.6: before, WebView and WebPage weren't bridged.) |

## Packages/Kiln/Examples/Apps/DoodlePad.swift

```diff
--- before
+++ after
@@ -3,4 +3,531 @@
   VStack(spacing: 14, {fn})
-    content failed
-    .padding()
-error: Line 37: Cannot find 'DragGesture' in scope
+    Canvas({fn})
+      .frame(height: 220)
+      .gesture(<view>)
+        DragGesture(minimumDistance: 2)
+          .onChanged({fn})
+          .onEnded({fn})
+      .onTapGesture(count: 2, {fn})
+      .accessibilityLabel("Doodle canvas")
+    Text(_literal: "Drag me")
+      .padding(12)
+      .background(<view>, in: .capsule)
+        Color(Color)
+          .opacity(0.2)
+      .offset(x: 0.0, y: 0.0)
+      .gesture(<view>)
+        DragGesture()
+          .updating($Size(0.0, 0.0), {fn})
+          .onEnded({fn})
+    TextField("Title", text: $"")
+      .textFieldStyle(.roundedBorder)
+      .focused($nil, equals: .title)
+      .submitLabel(.next)
+      .onSubmit({fn})
+    TextField("Note", text: $"")
+      .textFieldStyle(.roundedBorder)
+      .focused($nil, equals: .note)
+      .submitLabel(.done)
+      .onSubmit({fn})
+    HStack({fn})
+      Button("Clear", {fn})
+      Button("Save", {fn})
+      Button("Edit title", {fn})
+      .buttonStyle(.bordered)
+    Text("Nothing saved")
+    Text("No field focused")
+    Text(_literal: "Hidden from VoiceOver")
+      .accessibilityHidden(true)
+    .padding()
+== after Canvas@22
+ContentView {strokes=[[Point(30.0, 40.0), Point(120.0, 90.0), Point(210.0, 50.0)]], current=[], stamps=[], offset=Size(0.0, 0.0), dragging=Size(0.0, 0.0), title="", note="", saved="Nothing saved", field=nil}
+  VStack(spacing: 14, {fn})
+    Canvas({fn})
+      .frame(height: 220)
+      .gesture(<view>)
+        DragGesture(minimumDistance: 2)
+          .onChanged({fn})
+          .onEnded({fn})
+      .onTapGesture(count: 2, {fn})
+      .accessibilityLabel("Doodle canvas")
+    Text(_literal: "Drag me")
+      .padding(12)
+      .background(<view>, in: .capsule)
+        Color(Color)
+          .opacity(0.2)
+      .offset(x: 0.0, y: 0.0)
+      .gesture(<view>)
+        DragGesture()
+          .updating($Size(0.0, 0.0), {fn})
+          .onEnded({fn})
+    TextField("Title", text: $"")
+      .textFieldStyle(.roundedBorder)
+      .focused($nil, equals: .title)
+      .submitLabel(.next)
+      .onSubmit({fn})
+    TextField("Note", text: $"")
+      .textFieldStyle(.roundedBorder)
+      .focused($nil, equals: .note)
+      .submitLabel(.done)
+      .onSubmit({fn})
+    HStack({fn})
+      Button("Clear", {fn})
+      Button("Save", {fn})
+      Button("Edit title", {fn})
+      .buttonStyle(.bordered)
+    Text("Nothing saved")
+    Text("No field focused")
+    Text(_literal: "Hidden from VoiceOver")
+      .accessibilityHidden(true)
+    .padding()
+== after DragGesture.onChanged@38
+ContentView {strokes=[[Point(30.0, 40.0), Point(120.0, 90.0), Point(210.0, 50.0)]], current=[Point(0.0, 0.0)], stamps=[], offset=Size(0.0, 0.0), dragging=Size(0.0, 0.0), title="", note="", saved="Nothing saved", field=nil}
+  VStack(spacing: 14, {fn})
+    Canvas({fn})
+      .frame(height: 220)
+      .gesture(<view>)
+        DragGesture(minimumDistance: 2)
+          .onChanged({fn})
+          .onEnded({fn})
+      .onTapGesture(count: 2, {fn})
+      .accessibilityLabel("Doodle canvas")
+    Text(_literal: "Drag me")
+      .padding(12)
+      .background(<view>, in: .capsule)
+        Color(Color)
+          .opacity(0.2)
+      .offset(x: 0.0, y: 0.0)
+      .gesture(<view>)
+        DragGesture()
+          .updating($Size(0.0, 0.0), {fn})
+          .onEnded({fn})
+    TextField("Title", text: $"")
+      .textFieldStyle(.roundedBorder)
+      .focused($nil, equals: .title)
+      .submitLabel(.next)
+      .onSubmit({fn})
+    TextField("Note", text: $"")
+      .textFieldStyle(.roundedBorder)
+      .focused($nil, equals: .note)
+      .submitLabel(.done)
+      .onSubmit({fn})
+    HStack({fn})
+      Button("Clear", {fn})
+      Button("Save", {fn})
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

## Packages/Kiln/Examples/Apps/Terrain.swift

```diff
--- before
+++ after
@@ -1,29 +1,832 @@
 == start
-ContentView {ripple=1.5, pose=.default, perspective=true, showPeaks=true, depth=nil, peaks=[Peak(id: <uuid>, name: "North", x: -1.5, height: 1.2, z: -1.0, kind: "Summit"), Peak(id: <uuid>, name: "Ridge", x: 0.5, height: 0.8, z: 1.5, kind: "Ridge"), Peak(id: <uuid>, name: "Saddle", x: 1.8, height: 0.2, z: -1.8, kind: "Pass"), Peak(id: <uuid>, name: "Spire", x: -0.4, height: 1.6, z: 0.3, kind: "Summit")]}
-  NavigationStack({fn})
-    Form({fn})
-      Section({fn})
-        content failed
-      Section("View", {fn})
-        HStack({fn})
-          Text(_literal: "Turned")
-          Spacer()
-          Text(_literal: "0°")
-            .foregroundStyle(Color)
-            .monospacedDigit()
-        Picker("Angle", selection: $0, {fn})
-          Text(_literal: "Default")
-            .tag(0)
-          Text(_literal: "Front")
-            .tag(1)
-          Text(_literal: "Top")
-            .tag(2)
-          .pickerStyle(.segmented)
-        Toggle("Perspective", isOn: $true)
-        Toggle("Peaks", isOn: $true)
-      Section("Terrain", {fn})
-        LabeledContent("Ripple", value: 1.5, format: FormatStyle)
-        Slider(value: $1.5, in: 0.5...3.0)
-        If false
-      .navigationTitle("Terrain")
-error: Line 32: Cannot find 'Chart3D' in scope
+ContentView {ripple=1.5, pose=Chart3DPose, perspective=true, showPeaks=true, depth=nil, peaks=[Peak(id: <uuid>, name: "North", x: -1.5, height: 1.2, z: -1.0, kind: "Summit"), Peak(id: <uuid>, name: "Ridge", x: 0.5, height: 0.8, z: 1.5, kind: "Ridge"), Peak(id: <uuid>, name: "Saddle", x: 1.8, height: 0.2, z: -1.8, kind: "Pass"), Peak(id: <uuid>, name: "Spire", x: -0.4, height: 1.6, z: 0.3, kind: "Summit")]}
+  NavigationStack({fn})
+    Form({fn})
+      Section({fn})
+        Chart3D({fn})
+          SurfacePlot(x: "East", y: "Height", z: "North", {fn})
+            .foregroundStyle(.heightBased)
+            .roughness(0.4)
+          If true
+            ForEach([Peak(id: <uuid>, name: "North", x: -1.5, height: 1.2, z: -1.0, kind: "Summit"), Peak(id: <uuid>, name: "Ridge", x: 0.5, height: 0.8, z: 1.5, kind: "Ridge"), Peak(id: <uuid>, name: "Saddle", x: 1.8, height: 0.2, z: -1.8, kind: "Pass"), Peak(id: <uuid>, name: "Spire", x: -0.4, height: 1.6, z: 0.3, kind: "Summit")], {fn})
+              row <uuid>
+                PointMark(x: .value("East", -1.5), y: .value("Height", 1.2), z: .value("North", -1.0))
+                  .foregroundStyle(by: .value("Kind", "Summit"))
+                  .symbol(.sphere)
+                  .symbolSize(0.06)
+                  .metalness(0.2)
+              row <uuid>
+                PointMark(x: .value("East", 0.5), y: .value("Height", 0.8), z: .value("North", 1.5))
+                  .foregroundStyle(by: .value("Kind", "Ridge"))
+                  .symbol(.sphere)
+                  .symbolSize(0.06)
+                  .metalness(0.2)
+              row <uuid>
+                PointMark(x: .value("East", 1.8), y: .value("Height", 0.2), z: .value("North", -1.8))
+                  .foregroundStyle(by: .value("Kind", "Pass"))
+                  .symbol(.sphere)
+                  .symbolSize(0.06)
+                  .metalness(0.2)
+              row <uuid>
+                PointMark(x: .value("East", -0.4), y: .value("Height", 1.6), z: .value("North", 0.3))
+                  .foregroundStyle(by: .value("Kind", "Summit"))
+                  .symbol(.sphere)
+                  .symbolSize(0.06)
+                  .metalness(0.2)
+          .chart3DPose($Chart3DPose)
+          .chart3DCameraProjection(.perspective)
+          .chartXScale(domain: -2...2)
+          .chartZScale(domain: -2...2)
+          .chartZAxisLabel("North")
+          .chartZSelection(value: $nil)
+          .frame(height: 320)
+      Section("View", {fn})
+        HStack({fn})
+          Text(_literal: "Turned")
+          Spacer()
+          Text(_literal: "-29°")
+            .foregroundStyle(Color)
+            .monospacedDigit()
+        Picker("Angle", selection: $0, {fn})
+          Text(_literal: "Default")
+            .tag(0)
+          Text(_literal: "Front")
+            .tag(1)
+          Text(_literal: "Top")
+            .tag(2)
+          .pickerStyle(.segmented)
+        Toggle("Perspective", isOn: $true)
+        Toggle("Peaks", isOn: $true)
+      Section("Terrain", {fn})
+        LabeledContent("Ripple", value: 1.5, format: FormatStyle)
+        Slider(value: $1.5, in: 0.5...3.0)
+        If false
+      .navigationTitle("Terrain")
+== after SurfacePlot@33
+ContentView {ripple=1.5, pose=Chart3DPose, perspective=true, showPeaks=true, depth=nil, peaks=[Peak(id: <uuid>, name: "North", x: -1.5, height: 1.2, z: -1.0, kind: "Summit"), Peak(id: <uuid>, name: "Ridge", x: 0.5, height: 0.8, z: 1.5, kind: "Ridge"), Peak(id: <uuid>, name: "Saddle", x: 1.8, height: 0.2, z: -1.8, kind: "Pass"), Peak(id: <uuid>, name: "Spire", x: -0.4, height: 1.6, z: 0.3, kind: "Summit")]}
+  NavigationStack({fn})
+    Form({fn})
+      Section({fn})
+        Chart3D({fn})
+          SurfacePlot(x: "East", y: "Height", z: "North", {fn})
+            .foregroundStyle(.heightBased)
+            .roughness(0.4)
+          If true
+            ForEach([Peak(id: <uuid>, name: "North", x: -1.5, height: 1.2, z: -1.0, kind: "Summit"), Peak(id: <uuid>, name: "Ridge", x: 0.5, height: 0.8, z: 1.5, kind: "Ridge"), Peak(id: <uuid>, name: "Saddle", x: 1.8, height: 0.2, z: -1.8, kind: "Pass"), Peak(id: <uuid>, name: "Spire", x: -0.4, height: 1.6, z: 0.3, kind: "Summit")], {fn})
+              row <uuid>
+                PointMark(x: .value("East", -1.5), y: .value("Height", 1.2), z: .value("North", -1.0))
+                  .foregroundStyle(by: .value("Kind", "Summit"))
+                  .symbol(.sphere)
+                  .symbolSize(0.06)
+                  .metalness(0.2)
+              row <uuid>
+                PointMark(x: .value("East", 0.5), y: .value("Height", 0.8), z: .value("North", 1.5))
+                  .foregroundStyle(by: .value("Kind", "Ridge"))
+                  .symbol(.sphere)
+                  .symbolSize(0.06)
+                  .metalness(0.2)
+              row <uuid>
+                PointMark(x: .value("East", 1.8), y: .value("Height", 0.2), z: .value("North", -1.8))
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

## fixtures/apps/accessibility-motion.swift

```diff
--- before
+++ after
@@ -1,2 +1,754 @@
 == start
-error: Missing argument 'announce' in call to ContentView
+ContentView {running=false, rounds=3, expanded=false, announce=(), reduceMotion=false, space=()}
+  VStack(spacing: 28, {fn})
+    TimelineView(.periodic(<date>, 1), {fn})
+      Text(<date>, style: .time)
+        .font(Font)
+        .foregroundStyle(Color)
+        .accessibilityHidden(true)
+    Circle()
+      .fill(<view>)
+        LinearGradient(colors: [Color, Color])
+      .frame(width: 140, height: 140)
+      .phaseAnimator([.inhale, .hold, .exhale], trigger: false, {fn}, animation: {fn})
+        NativeContent(AnyView)
+          .scaleEffect(1.4)
+          .opacity(1)
+        NativeContent(AnyView)
+          .scaleEffect(1.4)
+          .opacity(0.8)
+        NativeContent(AnyView)
+          .scaleEffect(0.8)
+          .opacity(1)
+      .accessibilityElement(children: .ignore)
+      .accessibilityLabel("Breathing circle")
+      .accessibilityValue("Paused")
+      .accessibilityAddTraits(.updatesFrequently)
+      .accessibilityAction(named: "Start", {fn})
+      .accessibilityFocused($())
+    HStack({fn})
+      Text(_literal: "Rounds")
+      Spacer()
+      Text(_literal: "3")
+        .contentTransition(.numericText(3.0))
+        .accessibilityHidden(true)
+      .padding()
+      .background(.thinMaterial, in: .rect(14))
+      .accessibilityElement(children: .combine)
+      .accessibilityValue("3 rounds")
+      .accessibilityAdjustableAction({fn})
+    Group({fn})
+      If false
+        Label("Tip", systemImage: "lightbulb")
+          .padding(10)
+          .background(<view>, in: .capsule)
+            Color(Color)
+              .opacity(0.15)
+          .matchedGeometryEffect(id: "tip", in: ())
+      .onTapGesture({fn})
+      .accessibilityAddTraits(.isButton)
+      .accessibilityHint("Shows how to breathe")
+    Button("Start", {fn})
+      .buttonStyle(.borderedProminent)
+      .accessibilitySortPriority(1)
+      .accessibilityInputLabels(["Start", "Go", "Pause"])
+    .padding()
+    .accessibilityRotor("Controls", {fn})
+      AccessibilityRotorEntry("Start button", id: "start")
+    .speechAnnouncementsQueued()
+== after Circle.phaseAnimator@40
+ContentView {running=true, rounds=3, expanded=false, announce=(), reduceMotion=false, space=()}
+  VStack(spacing: 28, {fn})
+    TimelineView(.periodic(<date>, 1), {fn})
+      Text(<date>, style: .time)
+        .font(Font)
+        .foregroundStyle(Color)
+        .accessibilityHidden(true)
+    Circle()
+      .fill(<view>)
+        LinearGradient(colors: [Color, Color])
+      .frame(width: 140, height: 140)
+      .phaseAnimator([.inhale, .hold, .exhale], trigger: true, {fn}, animation: {fn})
+        NativeContent(AnyView)
+          .scaleEffect(1.4)
+          .opacity(1)
+        NativeContent(AnyView)
+          .scaleEffect(1.4)
+          .opacity(0.8)
+        NativeContent(AnyView)
+          .scaleEffect(0.8)
+          .opacity(1)
+      .accessibilityElement(children: .ignore)
+      .accessibilityLabel("Breathing circle")
+      .accessibilityValue("Running")
+      .accessibilityAddTraits(.updatesFrequently)
+      .accessibilityAction(named: "Start", {fn})
+      .accessibilityFocused($())
+    HStack({fn})
+      Text(_literal: "Rounds")
+      Spacer()
+      Text(_literal: "3")
+        .contentTransition(.numericText(3.0))
+        .accessibilityHidden(true)
+      .padding()
+      .background(.thinMaterial, in: .rect(14))
+      .accessibilityElement(children: .combine)
+      .accessibilityValue("3 rounds")
+      .accessibilityAdjustableAction({fn})
+    Group({fn})
+      If false
+        Label("Tip", systemImage: "lightbulb")
+          .padding(10)
+          .background(<view>, in: .capsule)
+            Color(Color)
+              .opacity(0.15)
+          .matchedGeometryEffect(id: "tip", in: ())
+      .onTapGesture({fn})
+      .accessibilityAddTraits(.isButton)
+      .accessibilityHint("Shows how to breathe")
+    Button("Pause", {fn})
+      .buttonStyle(.borderedProminent)
+      .accessibilitySortPriority(1)
+      .accessibilityInputLabels(["Start", "Go", "Pause"])
+    .padding()
+    .accessibilityRotor("Controls", {fn})
+      AccessibilityRotorEntry("Start button", id: "start")
+    .speechAnnouncementsQueued()
…
```

## fixtures/apps/audio.swift

```diff
--- before
+++ after
@@ -1,2 +1,788 @@
 == start
-error: Line 43: Cannot find 'AVSpeechSynthesizer' in scope
+ContentView {player=nil, listener=Listener{onFinish: {fn}, onSpoken: {fn}}, synth=AVSpeechSynthesizer, stream=AVPlayer, frequency=440.0, volume=0.8, fast=false, loops=0, status="Ready", phrase="Hello from Shelf", voices=[], voiceID=""}
+  NavigationStack({fn})
+    Form({fn})
+      Section("Tone", {fn})
+        LabeledContent("Pitch", value: "440 Hz")
+        Slider(value: $440.0, in: 220...880, step: 20)
+        Slider(value: $0.8, in: 0...1, {fn})
+          Text(_literal: "Volume")
+          .onChange(of: 0.8, {fn})
+        Toggle("Faster", isOn: $false)
+        Stepper("Repeats: 0", value: $0, in: 0...5)
+        Button("Play Tone", systemImage: "play.fill", {fn})
+        Button("Save and Play File", systemImage: "doc", {fn})
+        Button("Stop", systemImage: "stop.fill", {fn})
+        Text("Ready")
+          .foregroundStyle(Color)
+      Section("System Sounds", {fn})
+        Button("Click", {fn})
+        Button("Vibrate", {fn})
+      Section("Speech", {fn})
+        TextField("Phrase", text: $"Hello from Shelf")
+        Picker("Voice", selection: $"", {fn})
+          Text(_literal: "Default")
+            .tag("")
+          ForEach([], id: KeyPath, {fn})
+        Button("Speak", systemImage: "waveform", {fn})
+        Button("Stop Speaking", {fn})
+      Section("Stream", {fn})
+        VideoPlayer(player: AVPlayer)
+          .frame(height: 180)
+        Button("Play Stream", {fn})
+      .navigationTitle("Tone Lab")
+      .onAppear({fn})
+== appeared (Form.onAppear@95)
+ContentView {player=AVAudioPlayer, listener=Listener{onFinish: {fn}, onSpoken: {fn}}, synth=AVSpeechSynthesizer, stream=AVPlayer, frequency=440.0, volume=0.8, fast=false, loops=0, status="Stopped", phrase="Hello from Shelf", voices=[AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, …], voiceID=""}
+  NavigationStack({fn})
+    Form({fn})
+      Section("Tone", {fn})
+        LabeledContent("Pitch", value: "440 Hz")
+        Slider(value: $440.0, in: 220...880, step: 20)
+        Slider(value: $0.8, in: 0...1, {fn})
+          Text(_literal: "Volume")
+          .onChange(of: 0.8, {fn})
+        Toggle("Faster", isOn: $false)
+        Stepper("Repeats: 0", value: $0, in: 0...5)
+        Button("Play Tone", systemImage: "play.fill", {fn})
+        Button("Save and Play File", systemImage: "doc", {fn})
+        Button("Stop", systemImage: "stop.fill", {fn})
+        Text("Stopped")
+          .foregroundStyle(Color)
+      Section("System Sounds", {fn})
+        Button("Click", {fn})
+        Button("Vibrate", {fn})
+      Section("Speech", {fn})
+        TextField("Phrase", text: $"Hello from Shelf")
+        Picker("Voice", selection: $"", {fn})
+          Text(_literal: "Default")
+            .tag("")
+          ForEach([AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice], id: KeyPath, {fn})
+            row "com.apple.voice.compact.en-US.Samantha"
+              Text("Samantha")
+                .tag("com.apple.voice.compact.en-US.Samantha")
+            row "com.apple.eloquence.en-US.Eddy"
+              Text("Eddy")
+                .tag("com.apple.eloquence.en-US.Eddy")
+            row "com.apple.eloquence.en-US.Flo"
+              Text("Flo")
+                .tag("com.apple.eloquence.en-US.Flo")
+            row "com.apple.eloquence.en-US.Grandma"
+              Text("Grandma")
+                .tag("com.apple.eloquence.en-US.Grandma")
+            row "com.apple.eloquence.en-US.Grandpa"
+              Text("Grandpa")
+                .tag("com.apple.eloquence.en-US.Grandpa")
+            row "com.apple.eloquence.en-US.Reed"
+              Text("Reed")
+                .tag("com.apple.eloquence.en-US.Reed")
+            row "com.apple.eloquence.en-US.Rocko"
+              Text("Rocko")
+                .tag("com.apple.eloquence.en-US.Rocko")
+            row "com.apple.eloquence.en-US.Sandy"
+              Text("Sandy")
+                .tag("com.apple.eloquence.en-US.Sandy")
+        Button("Speak", systemImage: "waveform", {fn})
+        Button("Stop Speaking", {fn})
+      Section("Stream", {fn})
+        VideoPlayer(player: AVPlayer)
+          .frame(height: 180)
+        Button("Play Stream", {fn})
+      .navigationTitle("Tone Lab")
+      .onAppear({fn})
+== after Button[Click]@74
+ContentView {player=AVAudioPlayer, listener=Listener{onFinish: {fn}, onSpoken: {fn}}, synth=AVSpeechSynthesizer, stream=AVPlayer, frequency=440.0, volume=0.8, fast=false, loops=0, status="Stopped", phrase="Hello from Shelf", voices=[AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, AVSpeechSynthesisVoice, …], voiceID=""}
+  NavigationStack({fn})
+    Form({fn})
+      Section("Tone", {fn})
+        LabeledContent("Pitch", value: "440 Hz")
+        Slider(value: $440.0, in: 220...880, step: 20)
+        Slider(value: $0.8, in: 0...1, {fn})
+          Text(_literal: "Volume")
+          .onChange(of: 0.8, {fn})
+        Toggle("Faster", isOn: $false)
+        Stepper("Repeats: 0", value: $0, in: 0...5)
+        Button("Play Tone", systemImage: "play.fill", {fn})
+        Button("Save and Play File", systemImage: "doc", {fn})
+        Button("Stop", systemImage: "stop.fill", {fn})
+        Text("Stopped")
+          .foregroundStyle(Color)
+      Section("System Sounds", {fn})
+        Button("Click", {fn})
+        Button("Vibrate", {fn})
+      Section("Speech", {fn})
+        TextField("Phrase", text: $"Hello from Shelf")
+        Picker("Voice", selection: $"", {fn})
+          Text(_literal: "Default")
…
```

## fixtures/apps/chart3d.swift

```diff
--- before
+++ after
@@ -1,29 +1,832 @@
 == start
-ContentView {ripple=1.5, pose=.default, perspective=true, showPeaks=true, depth=nil, peaks=[Peak(id: <uuid>, name: "North", x: -1.5, height: 1.2, z: -1.0, kind: "Summit"), Peak(id: <uuid>, name: "Ridge", x: 0.5, height: 0.8, z: 1.5, kind: "Ridge"), Peak(id: <uuid>, name: "Saddle", x: 1.8, height: 0.2, z: -1.8, kind: "Pass"), Peak(id: <uuid>, name: "Spire", x: -0.4, height: 1.6, z: 0.3, kind: "Summit")]}
-  NavigationStack({fn})
-    Form({fn})
-      Section({fn})
-        content failed
-      Section("View", {fn})
-        HStack({fn})
-          Text(_literal: "Turned")
-          Spacer()
-          Text(_literal: "0°")
-            .foregroundStyle(Color)
-            .monospacedDigit()
-        Picker("Angle", selection: $0, {fn})
-          Text(_literal: "Default")
-            .tag(0)
-          Text(_literal: "Front")
-            .tag(1)
-          Text(_literal: "Top")
-            .tag(2)
-          .pickerStyle(.segmented)
-        Toggle("Perspective", isOn: $true)
-        Toggle("Peaks", isOn: $true)
-      Section("Terrain", {fn})
-        LabeledContent("Ripple", value: 1.5, format: FormatStyle)
-        Slider(value: $1.5, in: 0.5...3.0)
-        If false
-      .navigationTitle("Terrain")
-error: Line 36: Cannot find 'Chart3D' in scope
+ContentView {ripple=1.5, pose=Chart3DPose, perspective=true, showPeaks=true, depth=nil, peaks=[Peak(id: <uuid>, name: "North", x: -1.5, height: 1.2, z: -1.0, kind: "Summit"), Peak(id: <uuid>, name: "Ridge", x: 0.5, height: 0.8, z: 1.5, kind: "Ridge"), Peak(id: <uuid>, name: "Saddle", x: 1.8, height: 0.2, z: -1.8, kind: "Pass"), Peak(id: <uuid>, name: "Spire", x: -0.4, height: 1.6, z: 0.3, kind: "Summit")]}
+  NavigationStack({fn})
+    Form({fn})
+      Section({fn})
+        Chart3D({fn})
+          SurfacePlot(x: "East", y: "Height", z: "North", {fn})
+            .foregroundStyle(.heightBased)
+            .roughness(0.4)
+          If true
+            ForEach([Peak(id: <uuid>, name: "North", x: -1.5, height: 1.2, z: -1.0, kind: "Summit"), Peak(id: <uuid>, name: "Ridge", x: 0.5, height: 0.8, z: 1.5, kind: "Ridge"), Peak(id: <uuid>, name: "Saddle", x: 1.8, height: 0.2, z: -1.8, kind: "Pass"), Peak(id: <uuid>, name: "Spire", x: -0.4, height: 1.6, z: 0.3, kind: "Summit")], {fn})
+              row <uuid>
+                PointMark(x: .value("East", -1.5), y: .value("Height", 1.2), z: .value("North", -1.0))
+                  .foregroundStyle(by: .value("Kind", "Summit"))
+                  .symbol(.sphere)
+                  .symbolSize(0.06)
+                  .metalness(0.2)
+              row <uuid>
+                PointMark(x: .value("East", 0.5), y: .value("Height", 0.8), z: .value("North", 1.5))
+                  .foregroundStyle(by: .value("Kind", "Ridge"))
+                  .symbol(.sphere)
+                  .symbolSize(0.06)
+                  .metalness(0.2)
+              row <uuid>
+                PointMark(x: .value("East", 1.8), y: .value("Height", 0.2), z: .value("North", -1.8))
+                  .foregroundStyle(by: .value("Kind", "Pass"))
+                  .symbol(.sphere)
+                  .symbolSize(0.06)
+                  .metalness(0.2)
+              row <uuid>
+                PointMark(x: .value("East", -0.4), y: .value("Height", 1.6), z: .value("North", 0.3))
+                  .foregroundStyle(by: .value("Kind", "Summit"))
+                  .symbol(.sphere)
+                  .symbolSize(0.06)
+                  .metalness(0.2)
+          .chart3DPose($Chart3DPose)
+          .chart3DCameraProjection(.perspective)
+          .chartXScale(domain: -2...2)
+          .chartZScale(domain: -2...2)
+          .chartZAxisLabel("North")
+          .chartZSelection(value: $nil)
+          .frame(height: 320)
+      Section("View", {fn})
+        HStack({fn})
+          Text(_literal: "Turned")
+          Spacer()
+          Text(_literal: "-29°")
+            .foregroundStyle(Color)
+            .monospacedDigit()
+        Picker("Angle", selection: $0, {fn})
+          Text(_literal: "Default")
+            .tag(0)
+          Text(_literal: "Front")
+            .tag(1)
+          Text(_literal: "Top")
+            .tag(2)
+          .pickerStyle(.segmented)
+        Toggle("Perspective", isOn: $true)
+        Toggle("Peaks", isOn: $true)
+      Section("Terrain", {fn})
+        LabeledContent("Ripple", value: 1.5, format: FormatStyle)
+        Slider(value: $1.5, in: 0.5...3.0)
+        If false
+      .navigationTitle("Terrain")
+== after SurfacePlot@37
+ContentView {ripple=1.5, pose=Chart3DPose, perspective=true, showPeaks=true, depth=nil, peaks=[Peak(id: <uuid>, name: "North", x: -1.5, height: 1.2, z: -1.0, kind: "Summit"), Peak(id: <uuid>, name: "Ridge", x: 0.5, height: 0.8, z: 1.5, kind: "Ridge"), Peak(id: <uuid>, name: "Saddle", x: 1.8, height: 0.2, z: -1.8, kind: "Pass"), Peak(id: <uuid>, name: "Spire", x: -0.4, height: 1.6, z: 0.3, kind: "Summit")]}
+  NavigationStack({fn})
+    Form({fn})
+      Section({fn})
+        Chart3D({fn})
+          SurfacePlot(x: "East", y: "Height", z: "North", {fn})
+            .foregroundStyle(.heightBased)
+            .roughness(0.4)
+          If true
+            ForEach([Peak(id: <uuid>, name: "North", x: -1.5, height: 1.2, z: -1.0, kind: "Summit"), Peak(id: <uuid>, name: "Ridge", x: 0.5, height: 0.8, z: 1.5, kind: "Ridge"), Peak(id: <uuid>, name: "Saddle", x: 1.8, height: 0.2, z: -1.8, kind: "Pass"), Peak(id: <uuid>, name: "Spire", x: -0.4, height: 1.6, z: 0.3, kind: "Summit")], {fn})
+              row <uuid>
+                PointMark(x: .value("East", -1.5), y: .value("Height", 1.2), z: .value("North", -1.0))
+                  .foregroundStyle(by: .value("Kind", "Summit"))
+                  .symbol(.sphere)
+                  .symbolSize(0.06)
+                  .metalness(0.2)
+              row <uuid>
+                PointMark(x: .value("East", 0.5), y: .value("Height", 0.8), z: .value("North", 1.5))
+                  .foregroundStyle(by: .value("Kind", "Ridge"))
+                  .symbol(.sphere)
+                  .symbolSize(0.06)
+                  .metalness(0.2)
+              row <uuid>
+                PointMark(x: .value("East", 1.8), y: .value("Height", 0.2), z: .value("North", -1.8))
…
```

## fixtures/apps/charts.swift

```diff
--- before
+++ after
@@ -21,3 +21,5 @@
         .chartYAxis({fn})
-          content failed
+          AxisMarks(position: .leading, values: .automatic(4), {fn})
+            AxisGridLine()
+            AxisValueLabel()
         .chartXAxisLabel("Day", position: .bottom)
@@ -26,3 +28,12 @@
       Chart({fn})
-        content failed
+        LinePlot(x: "x", y: "y", domain: 0...12, {fn})
+          .foregroundStyle(Color)
+          .interpolationMethod(.catmullRom)
+        AreaPlot(x: "x", y: "y", domain: 0...12, {fn})
+          .foregroundStyle(<view>)
+            Color(Color)
+              .opacity(0.2)
+        PointMark(x: .value("x", 1.57), y: .value("y", 1.0))
+          .symbol(.diamond)
+          .symbolSize(80)
         .chartXScale(domain: 0...12)
@@ -77,5 +88,1135 @@
         .chartPlotStyle({fn})
+          NativeContent(AnyView)
+            .background(<view>)
+              Color(Color)
+                .opacity(0.05)
         .frame(height: 160)
       .padding()
-error: Line 53: Cannot find 'AxisMarks' in scope
-error: Line 63: Cannot find 'LinePlot' in scope
+== after LinePlot@63
+ContentView {selectedDay=nil, selectedAngle=nil, amplitude=1.0, days=[Day(id: <uuid>, name: "Mon", steps: 6200, goal: 8000, kind: "Walk"), Day(id: <uuid>, name: "Tue", steps: 9100, goal: 8000, kind: "Run"), Day(id: <uuid>, name: "Wed", steps: 4300, goal: 8000, kind: "Walk"), Day(id: <uuid>, name: "Thu", steps: 10400, goal: 8000, kind: "Run"), Day(id: <uuid>, name: "Fri", steps: 7800, goal: 8000, kind: "Walk"), Day(id: <uuid>, name: "Sat", steps: 12000, goal: 8000, kind: "Hike"), Day(id: <uuid>, name: "Sun", steps: 3100, goal: 8000, kind: "Walk")]}
+  ScrollView({fn})
+    VStack(alignment: .leading, spacing: 24, {fn})
+      Text("Tap a bar")
+        .font(Font)
+      Chart([Day(id: <uuid>, name: "Mon", steps: 6200, goal: 8000, kind: "Walk"), Day(id: <uuid>, name: "Tue", steps: 9100, goal: 8000, kind: "Run"), Day(id: <uuid>, name: "Wed", steps: 4300, goal: 8000, kind: "Walk"), Day(id: <uuid>, name: "Thu", steps: 10400, goal: 8000, kind: "Run"), Day(id: <uuid>, name: "Fri", steps: 7800, goal: 8000, kind: "Walk"), Day(id: <uuid>, name: "Sat", steps: 12000, goal: 8000, kind: "Hike"), Day(id: <uuid>, name: "Sun", steps: 3100, goal: 8000, kind: "Walk")], {fn})
+        BarMark(x: .value("Day", nil), y: .value("Steps", nil))
+          .foregroundStyle(by: .value("Kind", nil))
+          .cornerRadius(6)
+          .opacity(1)
+          .annotation(position: .top, spacing: 2, {fn})
+            If true
+              Text(_literal: "nil")
+                .font(Font)
+        RuleMark(y: .value("Goal", nil))
+          .lineStyle(StrokeStyle)
+          .foregroundStyle(Color)
+        .chartXSelection(value: $nil)
+        .chartForegroundStyleScale(domain: ["Walk", "Run", "Hike"], range: [Color, Color, Color])
+        .chartYAxis({fn})
+          AxisMarks(position: .leading, values: .automatic(4), {fn})
+            AxisGridLine()
+            AxisValueLabel()
+        .chartXAxisLabel("Day", position: .bottom)
+        .chartLegend(position: .bottom, alignment: .center)
+        .frame(height: 220)
+      Chart({fn})
+        LinePlot(x: "x", y: "y", domain: 0...12, {fn})
+          .foregroundStyle(Color)
+          .interpolationMethod(.catmullRom)
+        AreaPlot(x: "x", y: "y", domain: 0...12, {fn})
+          .foregroundStyle(<view>)
+            Color(Color)
+              .opacity(0.2)
+        PointMark(x: .value("x", 1.57), y: .value("y", 1.0))
+          .symbol(.diamond)
+          .symbolSize(80)
+        .chartXScale(domain: 0...12)
+        .chartYScale(domain: -2...2)
+        .chartScrollableAxes(.horizontal)
+        .chartXVisibleDomain(length: 6)
+        .frame(height: 180)
+      Slider(value: $1.0, in: 0.2...2.0, {fn})
+        Text(_literal: "Amplitude")
+      Chart([Day(id: <uuid>, name: "Mon", steps: 6200, goal: 8000, kind: "Walk"), Day(id: <uuid>, name: "Tue", steps: 9100, goal: 8000, kind: "Run"), Day(id: <uuid>, name: "Wed", steps: 4300, goal: 8000, kind: "Walk"), Day(id: <uuid>, name: "Thu", steps: 10400, goal: 8000, kind: "Run"), Day(id: <uuid>, name: "Fri", steps: 7800, goal: 8000, kind: "Walk"), Day(id: <uuid>, name: "Sat", steps: 12000, goal: 8000, kind: "Hike"), Day(id: <uuid>, name: "Sun", steps: 3100, goal: 8000, kind: "Walk")], {fn})
+        SectorMark(angle: .value("Steps", nil), innerRadius: .ratio(0.6), angularInset: 2)
+          .foregroundStyle(by: .value("Day", nil))
+          .opacity(1)
+        .chartAngleSelection(value: $nil)
+        .chartLegend(.hidden)
+        .frame(height: 200)
+      Chart({fn})
+        ForEach([Day(id: <uuid>, name: "Mon", steps: 6200, goal: 8000, kind: "Walk"), Day(id: <uuid>, name: "Tue", steps: 9100, goal: 8000, kind: "Run"), Day(id: <uuid>, name: "Wed", steps: 4300, goal: 8000, kind: "Walk"), Day(id: <uuid>, name: "Thu", steps: 10400, goal: 8000, kind: "Run"), Day(id: <uuid>, name: "Fri", steps: 7800, goal: 8000, kind: "Walk"), Day(id: <uuid>, name: "Sat", steps: 12000, goal: 8000, kind: "Hike"), Day(id: <uuid>, name: "Sun", steps: 3100, goal: 8000, kind: "Walk")], {fn})
+          row <uuid>
+            LineMark(x: .value("Day", "Mon"), y: .value("Steps", 6200))
+            PointMark(x: .value("Day", "Mon"), y: .value("Steps", 6200))
+              .symbolSize(30)
+          row <uuid>
+            LineMark(x: .value("Day", "Tue"), y: .value("Steps", 9100))
+            PointMark(x: .value("Day", "Tue"), y: .value("Steps", 9100))
+              .symbolSize(30)
+          row <uuid>
+            LineMark(x: .value("Day", "Wed"), y: .value("Steps", 4300))
+            PointMark(x: .value("Day", "Wed"), y: .value("Steps", 4300))
+              .symbolSize(30)
+          row <uuid>
+            LineMark(x: .value("Day", "Thu"), y: .value("Steps", 10400))
+            PointMark(x: .value("Day", "Thu"), y: .value("Steps", 10400))
+              .symbolSize(30)
+          row <uuid>
+            LineMark(x: .value("Day", "Fri"), y: .value("Steps", 7800))
+            PointMark(x: .value("Day", "Fri"), y: .value("Steps", 7800))
+              .symbolSize(30)
+          row <uuid>
+            LineMark(x: .value("Day", "Sat"), y: .value("Steps", 12000))
+            PointMark(x: .value("Day", "Sat"), y: .value("Steps", 12000))
+              .symbolSize(30)
+          row <uuid>
+            LineMark(x: .value("Day", "Sun"), y: .value("Steps", 3100))
+            PointMark(x: .value("Day", "Sun"), y: .value("Steps", 3100))
+              .symbolSize(30)
+          .foregroundStyle(Color)
+        RectangleMark(xStart: .value("From", "Mon"), xEnd: .value("To", "Wed"), yStart: .value("Low", 0), yEnd: .value("High", 13000))
+          .foregroundStyle(<view>)
+            Color(Color)
+              .opacity(0.1)
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

## fixtures/apps/focus-environment.swift

```diff
--- before
+++ after
@@ -1,9 +1,15 @@
 == start
-ContentView {draft=Draft{name: "", email: "", password: "", saves: 0}, field=nil, bioFocused=(), bio="", filled=0, scenePhase=nil, openURL=nil, colorScheme=.light, sizeClass=.compact}
-  NavigationStack({fn})
-    Form({fn})
-      Section("You", {fn})
-        FieldRow {title="Name", text=$"", accent=nil, typeSize=nil}
-          VStack(alignment: .leading, spacing: 4, {fn})
-            content failed
+ContentView {draft=Draft{name: "", email: "", password: "", saves: 0}, field=nil, bioFocused=(), bio="", filled=0, scenePhase=.active, openURL=OpenURLAction, colorScheme=.light, sizeClass=.compact}
+  NavigationStack({fn})
+    Form({fn})
+      Section("You", {fn})
+        FieldRow {title="Name", text=$"", accent=Color, typeSize=DynamicTypeSize}
+          VStack(alignment: .leading, spacing: 4, {fn})
+            Text("Name")
+              .font(Font)
+              .foregroundStyle(Color)
+              .textCase(.uppercase)
+              .fontWidth(.condensed)
+            TextField("Name", text: $"")
+              .textFieldStyle(.roundedBorder)
             .preference(key: Filled, value: 0)
@@ -14,5 +20,11 @@
           .onSubmit({fn})
-        FieldRow {title="Email", text=$"", accent=nil, typeSize=nil}
-          VStack(alignment: .leading, spacing: 4, {fn})
-            content failed
+        FieldRow {title="Email", text=$"", accent=Color, typeSize=DynamicTypeSize}
+          VStack(alignment: .leading, spacing: 4, {fn})
+            Text("Email")
+              .font(Font)
+              .foregroundStyle(Color)
+              .textCase(.uppercase)
+              .fontWidth(.condensed)
+            TextField("Email", text: $"")
+              .textFieldStyle(.roundedBorder)
             .preference(key: Filled, value: 0)
@@ -38,3 +50,3 @@
       Section("Now", {fn})
-        LabeledContent("Scene", value: "nil")
+        LabeledContent("Scene", value: ".active")
         LabeledContent("Appearance", value: "Light")
@@ -53,12 +65,17 @@
       .navigationTitle("Sign Up")
-      .onChange(of: nil, {fn})
-error: Line 41: Can't compare nil and .accessibility1
+      .onChange(of: .active, {fn})
 == after view.onSubmit@69
-ContentView {draft=Draft{name: "", email: "", password: "", saves: 0}, field=.email, bioFocused=(), bio="", filled=nil, scenePhase=nil, openURL=nil, colorScheme=.light, sizeClass=.compact}
-  NavigationStack({fn})
-    Form({fn})
-      Section("You", {fn})
-        FieldRow {title="Name", text=$"", accent=nil, typeSize=nil}
-          VStack(alignment: .leading, spacing: 4, {fn})
-            content failed
+ContentView {draft=Draft{name: "", email: "", password: "", saves: 0}, field=.email, bioFocused=(), bio="", filled=0, scenePhase=.active, openURL=OpenURLAction, colorScheme=.light, sizeClass=.compact}
+  NavigationStack({fn})
+    Form({fn})
+      Section("You", {fn})
+        FieldRow {title="Name", text=$"", accent=Color, typeSize=DynamicTypeSize}
+          VStack(alignment: .leading, spacing: 4, {fn})
+            Text("Name")
+              .font(Font)
+              .foregroundStyle(Color)
+              .textCase(.uppercase)
+              .fontWidth(.condensed)
+            TextField("Name", text: $"")
+              .textFieldStyle(.roundedBorder)
             .preference(key: Filled, value: 0)
@@ -69,5 +86,11 @@
           .onSubmit({fn})
-        FieldRow {title="Email", text=$"", accent=nil, typeSize=nil}
-          VStack(alignment: .leading, spacing: 4, {fn})
-            content failed
+        FieldRow {title="Email", text=$"", accent=Color, typeSize=DynamicTypeSize}
+          VStack(alignment: .leading, spacing: 4, {fn})
+            Text("Email")
+              .font(Font)
+              .foregroundStyle(Color)
+              .textCase(.uppercase)
+              .fontWidth(.condensed)
+            TextField("Email", text: $"")
+              .textFieldStyle(.roundedBorder)
             .preference(key: Filled, value: 0)
@@ -89,7 +112,7 @@
           .focused($())
-        Text(_literal: "nil of 2 fields filled")
-          .contentTransition(.numericText(0.0))
-          .monospacedDigit()
-      Section("Now", {fn})
-        LabeledContent("Scene", value: "nil")
+        Text(_literal: "0 of 2 fields filled")
+          .contentTransition(.numericText(0.0))
+          .monospacedDigit()
+      Section("Now", {fn})
+        LabeledContent("Scene", value: ".active")
         LabeledContent("Appearance", value: "Light")
@@ -108,11 +131,17 @@
       .navigationTitle("Sign Up")
-      .onChange(of: nil, {fn})
+      .onChange(of: .active, {fn})
 == after view.onSubmit@77
-ContentView {draft=Draft{name: "", email: "", password: "", saves: 0}, field=.password, bioFocused=(), bio="", filled=nil, scenePhase=nil, openURL=nil, colorScheme=.light, sizeClass=.compact}
-  NavigationStack({fn})
-    Form({fn})
-      Section("You", {fn})
-        FieldRow {title="Name", text=$"", accent=nil, typeSize=nil}
-          VStack(alignment: .leading, spacing: 4, {fn})
-            content failed
+ContentView {draft=Draft{name: "", email: "", password: "", saves: 0}, field=.password, bioFocused=(), bio="", filled=0, scenePhase=.active, openURL=OpenURLAction, colorScheme=.light, sizeClass=.compact}
+  NavigationStack({fn})
+    Form({fn})
+      Section("You", {fn})
+        FieldRow {title="Name", text=$"", accent=Color, typeSize=DynamicTypeSize}
+          VStack(alignment: .leading, spacing: 4, {fn})
+            Text("Name")
+              .font(Font)
…
```

## fixtures/apps/gestures-canvas.swift

```diff
--- before
+++ after
@@ -3,4 +3,1193 @@
   VStack(spacing: 12, {fn})
-    content failed
-    .padding()
-error: Line 108: Cannot find 'GlassEffectContainer' in scope
+    ZStack({fn})
+      Canvas({fn})
+        .gesture(<view>)
+          DragGesture(minimumDistance: 1)
+            .onChanged({fn})
+            .onEnded({fn})
+        .onTapGesture(count: 2, {fn})
+      Image(systemName: "star.fill")
+        .font(Font)
+        .foregroundStyle(Color)
+        .symbolEffect(.bounce, value: 0)
+        .scaleEffect(1.0)
+        .rotationEffect(0.0°)
+        .offset(x: 0.0, y: 0.0)
+        .gesture(<view>)
+          DragGesture()
+            .updating($Size(0.0, 0.0), {fn})
+            .onEnded({fn})
+        .simultaneousGesture(<view>)
+          MagnifyGesture()
+            .updating($1.0, {fn})
+            .onEnded({fn})
+            .simultaneously(with: <view>)
+              RotateGesture()
+                .updating($0.0°, {fn})
+                .onEnded({fn})
+        .highPriorityGesture(<view>)
+          LongPressGesture(minimumDuration: 0.4)
+            .updating($false, {fn})
+            .onEnded({fn})
+      .frame(maxHeight: inf)
+    Text("Double-tap to stamp")
+      .font(Font)
+      .foregroundStyle(Color)
+      .contentTransition(.numericText)
+    GlassEffectContainer(spacing: 10, {fn})
+      HStack(spacing: 10, {fn})
+        ForEach([Color, Color, Color, Color], id: KeyPath, {fn})
+          row Color
+            Circle()
+              .fill(Color)
+              .frame(width: 34, height: 34)
+              .overlay({fn})
+                If true
+                  Circle()
+                    .strokeBorder(Color, lineWidth: 3)
+                    .matchedGeometryEffect(id: "ring", in: ())
+              .onTapGesture({fn})
+              .accessibilityLabel("Color")
+          row Color
+            Circle()
+              .fill(Color)
+              .frame(width: 34, height: 34)
+              .overlay({fn})
+                If false
+              .onTapGesture({fn})
+              .accessibilityLabel("Color")
+          row Color
+            Circle()
+              .fill(Color)
+              .frame(width: 34, height: 34)
+              .overlay({fn})
+                If false
+              .onTapGesture({fn})
+              .accessibilityLabel("Color")
+          row Color
+            Circle()
+              .fill(Color)
+              .frame(width: 34, height: 34)
+              .overlay({fn})
+                If false
+              .onTapGesture({fn})
+              .accessibilityLabel("Color")
+        Button("Undo", systemImage: "arrow.uturn.backward", {fn})
+          If false
+          .labelStyle(.iconOnly)
+          .padding(10)
+          .glassEffect(.regular.interactive, in: .circle)
+      .keyframeAnimator(initialValue: Bounce(scale: 1.0, lift: 0.0), trigger: 0, {fn}, keyframes: {fn})
+        NativeContent(AnyView)
+          .scaleEffect(1.0)
+          .offset(y: 0.0)
+        KeyframeTrack(KeyPath, {fn})
+          SpringKeyframe(1.08, duration: 0.15)
+          SpringKeyframe(1.0, duration: 0.3, spring: Spring)
+        KeyframeTrack(KeyPath, {fn})
+          LinearKeyframe(-6, duration: 0.15)
+          CubicKeyframe(0, duration: 0.3)
+    Slider(value: $6.0, in: 2...20, {fn})
+      Text(_literal: "Width")
+    .padding()
+== after Canvas@41
+ContentView {strokes=[], current=[], color=Color, width=6.0, stickerOffset=Size(0.0, 0.0), stickerDrag=Size(0.0, 0.0), stickerScale=1.0, pinch=1.0, stickerAngle=0.0°, twist=0.0°, pressing=false, stamps=0, lastTap="Double-tap to stamp", palette=(), colors=[Color, Color, Color, Color]}
+  VStack(spacing: 12, {fn})
+    ZStack({fn})
+      Canvas({fn})
+        .gesture(<view>)
+          DragGesture(minimumDistance: 1)
+            .onChanged({fn})
+            .onEnded({fn})
+        .onTapGesture(count: 2, {fn})
+      Image(systemName: "star.fill")
+        .font(Font)
+        .foregroundStyle(Color)
+        .symbolEffect(.bounce, value: 0)
+        .scaleEffect(1.0)
+        .rotationEffect(0.0°)
+        .offset(x: 0.0, y: 0.0)
+        .gesture(<view>)
+          DragGesture()
+            .updating($Size(0.0, 0.0), {fn})
+            .onEnded({fn})
+        .simultaneousGesture(<view>)
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
@@ -52,3 +52,8 @@
       Section("Shelves", isExpanded: $true, {fn})
-        content failed
+        OutlineGroup([Shelf(id: 10, name: "Fiction", children: [Shelf(id: 11, name: "Classics", children: nil), Shelf(id: 12, name: "Sci-fi", children: nil)]), Shelf(id: 20, name: "Poetry", children: nil)], children: KeyPath, {fn})
+          row 10
+            Label("Fiction", systemImage: "folder")
+          row 20
+            Label("Poetry", systemImage: "folder")
+          .selectionDisabled()
         .headerProminence(.increased)
@@ -58,2 +63 @@
         EditButton()
-error: Line 51: Cannot find 'OutlineGroup' in scope
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

## fixtures/apps/streams.swift

```diff
--- before
+++ after
@@ -25,339 +25,338 @@
 == appeared (List.task@60, List.task@61)
-error: Line 69: Value of type 'URLSession' has no method 'webSocketTask'
-ContentView {socket=nil, lines=[], draft="", status="Connecting…", headlines=["Offline"]}
-  NavigationStack({fn})
-    List({fn})
-      Section("Status", {fn})
-        Text("Connecting…")
-          .foregroundStyle(Color)
-      Section("Chat", {fn})
-        ForEach([], {fn})
-      Section("Headlines", {fn})
-        ForEach(["Offline"], id: KeyPath, {fn})
-          row "Offline"
-            Text("Offline")
-      .safeAreaInset(edge: .bottom, {fn})
-        HStack({fn})
-          TextField("Message", text: $"")
-            .textFieldStyle(.roundedBorder)
-            .onSubmit({fn})
-          Button("Send", {fn})
-            .disabled(true)
-          .padding()
-          .background(.bar)
-      .navigationTitle("Echo Chat")
-      .task({fn})
-      .task({fn})
-      .onDisappear({fn})
-== after TextField.onSubmit@50
-ContentView {socket=nil, lines=[], draft="", status="Connecting…", headlines=["Offline"]}
-  NavigationStack({fn})
-    List({fn})
-      Section("Status", {fn})
-        Text("Connecting…")
-          .foregroundStyle(Color)
-      Section("Chat", {fn})
-        ForEach([], {fn})
-      Section("Headlines", {fn})
-        ForEach(["Offline"], id: KeyPath, {fn})
-          row "Offline"
-            Text("Offline")
-      .safeAreaInset(edge: .bottom, {fn})
-        HStack({fn})
-          TextField("Message", text: $"")
-            .textFieldStyle(.roundedBorder)
-            .onSubmit({fn})
-          Button("Send", {fn})
-            .disabled(true)
-          .padding()
-          .background(.bar)
-      .navigationTitle("Echo Chat")
-      .task({fn})
-      .task({fn})
-      .onDisappear({fn})
-== after Button[Send]@51
-ContentView {socket=nil, lines=[], draft="", status="Connecting…", headlines=["Offline"]}
-  NavigationStack({fn})
-    List({fn})
-      Section("Status", {fn})
-        Text("Connecting…")
-          .foregroundStyle(Color)
-      Section("Chat", {fn})
-        ForEach([], {fn})
-      Section("Headlines", {fn})
-        ForEach(["Offline"], id: KeyPath, {fn})
-          row "Offline"
-            Text("Offline")
-      .safeAreaInset(edge: .bottom, {fn})
-        HStack({fn})
-          TextField("Message", text: $"")
-            .textFieldStyle(.roundedBorder)
-            .onSubmit({fn})
-          Button("Send", {fn})
-            .disabled(true)
-          .padding()
-          .background(.bar)
-      .navigationTitle("Echo Chat")
-      .task({fn})
-      .task({fn})
-      .onDisappear({fn})
-== after TextField.onSubmit@50
-ContentView {socket=nil, lines=[], draft="", status="Connecting…", headlines=["Offline"]}
-  NavigationStack({fn})
-    List({fn})
-      Section("Status", {fn})
-        Text("Connecting…")
-          .foregroundStyle(Color)
-      Section("Chat", {fn})
-        ForEach([], {fn})
-      Section("Headlines", {fn})
-        ForEach(["Offline"], id: KeyPath, {fn})
-          row "Offline"
-            Text("Offline")
-      .safeAreaInset(edge: .bottom, {fn})
-        HStack({fn})
-          TextField("Message", text: $"")
-            .textFieldStyle(.roundedBorder)
-            .onSubmit({fn})
-          Button("Send", {fn})
-            .disabled(true)
-          .padding()
-          .background(.bar)
-      .navigationTitle("Echo Chat")
-      .task({fn})
-      .task({fn})
-      .onDisappear({fn})
-== after Button[Send]@51
-ContentView {socket=nil, lines=[], draft="", status="Connecting…", headlines=["Offline"]}
-  NavigationStack({fn})
-    List({fn})
-      Section("Status", {fn})
-        Text("Connecting…")
-          .foregroundStyle(Color)
-      Section("Chat", {fn})
-        ForEach([], {fn})
-      Section("Headlines", {fn})
-        ForEach(["Offline"], id: KeyPath, {fn})
-          row "Offline"
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

## fixtures/apps/web.swift

```diff
--- before
+++ after
@@ -1,2 +1,629 @@
 == start
-error: Line 10: Cannot find 'WebPage' in scope
+ContentView {page=WebPage, address="https://www.apple.com", words=0, finding=false, showNotes=false}
+  NavigationStack({fn})
+    VStack(spacing: 0, {fn})
+      If false
+      WebView(WebPage)
+        .webViewBackForwardNavigationGestures(.enabled)
+        .webViewMagnificationGestures(.enabled)
+        .webViewLinkPreviews(.disabled)
+        .webViewTextSelection(.enabled)
+        .webViewContentBackground(.visible)
+        .webViewElementFullscreenBehavior(.enabled)
+        .findNavigator(isPresented: $false)
+      .navigationTitle("Browser")
+      .navigationBarTitleDisplayMode(.inline)
+      .toolbar({fn})
+        ToolbarItemGroup(placement: .bottomBar, {fn})
+          Button("Back", systemImage: "chevron.left", {fn})
+            If false
+            .disabled(true)
+          Button("Forward", systemImage: "chevron.right", {fn})
+            If false
+            .disabled(true)
+          Spacer()
+          Button("Count Words", systemImage: "textformat.size", {fn})
+          Button("Find", systemImage: "magnifyingglass", {fn})
+          Button("Reload", systemImage: "arrow.clockwise", {fn})
+        ToolbarItem(placement: .topBarTrailing, {fn})
+          Button("Notes", systemImage: "note.text", {fn})
+      .safeAreaInset(edge: .top, {fn})
+        TextField("Address", text: $"https://www.apple.com")
+          .textFieldStyle(.roundedBorder)
+          .keyboardType(.URL)
+          .textInputAutocapitalization(.never)
+          .autocorrectionDisabled()
+          .onSubmit({fn})
+          .padding(.horizontal)
+      .overlay(alignment: .bottomTrailing, {fn})
+        If false
+      .sheet(isPresented: $true, {fn})
+        NavigationStack({fn})
+          WebView(url: URL(https://developer.apple.com/documentation/webkit))
+            .navigationTitle("WebKit")
+      .onAppear({fn})
+== appeared (VStack.onAppear@76)
+ContentView {page=WebPage, address="https://www.apple.com", words=0, finding=true, showNotes=true}
+  NavigationStack({fn})
+    VStack(spacing: 0, {fn})
+      If true
+        ProgressView(value: 0.1)
+      WebView(WebPage)
+        .webViewBackForwardNavigationGestures(.enabled)
+        .webViewMagnificationGestures(.enabled)
+        .webViewLinkPreviews(.disabled)
+        .webViewTextSelection(.enabled)
+        .webViewContentBackground(.visible)
+        .webViewElementFullscreenBehavior(.enabled)
+        .findNavigator(isPresented: $true)
+      .navigationTitle("Browser")
+      .navigationBarTitleDisplayMode(.inline)
+      .toolbar({fn})
+        ToolbarItemGroup(placement: .bottomBar, {fn})
+          Button("Back", systemImage: "chevron.left", {fn})
+            If false
+            .disabled(true)
+          Button("Forward", systemImage: "chevron.right", {fn})
+            If false
+            .disabled(true)
+          Spacer()
+          Button("Count Words", systemImage: "textformat.size", {fn})
+          Button("Find", systemImage: "magnifyingglass", {fn})
+          Button("Reload", systemImage: "arrow.clockwise", {fn})
+        ToolbarItem(placement: .topBarTrailing, {fn})
+          Button("Notes", systemImage: "note.text", {fn})
+      .safeAreaInset(edge: .top, {fn})
+        TextField("Address", text: $"https://www.apple.com")
+          .textFieldStyle(.roundedBorder)
+          .keyboardType(.URL)
+          .textInputAutocapitalization(.never)
+          .autocorrectionDisabled()
+          .onSubmit({fn})
+          .padding(.horizontal)
+      .overlay(alignment: .bottomTrailing, {fn})
+        If false
+      .sheet(isPresented: $true, {fn})
+        NavigationStack({fn})
+          WebView(url: URL(https://developer.apple.com/documentation/webkit))
+            .navigationTitle("WebKit")
+      .onAppear({fn})
+== after TextField.onSubmit@58
+ContentView {page=WebPage, address="https://www.apple.com", words=0, finding=false, showNotes=true}
+  NavigationStack({fn})
+    VStack(spacing: 0, {fn})
+      If true
+        ProgressView(value: 0.1)
+      WebView(WebPage)
+        .webViewBackForwardNavigationGestures(.enabled)
+        .webViewMagnificationGestures(.enabled)
+        .webViewLinkPreviews(.disabled)
+        .webViewTextSelection(.enabled)
+        .webViewContentBackground(.visible)
+        .webViewElementFullscreenBehavior(.enabled)
+        .findNavigator(isPresented: $false)
+      .navigationTitle("Browser")
+      .navigationBarTitleDisplayMode(.inline)
+      .toolbar({fn})
+        ToolbarItemGroup(placement: .bottomBar, {fn})
+          Button("Back", systemImage: "chevron.left", {fn})
+            If false
+            .disabled(true)
+          Button("Forward", systemImage: "chevron.right", {fn})
+            If false
+            .disabled(true)
+          Spacer()
+          Button("Count Words", systemImage: "textformat.size", {fn})
+          Button("Find", systemImage: "magnifyingglass", {fn})
…
```

## tests/AudioBridgeTests-1.swift

```diff
--- before
+++ after
@@ -2,2 +2,143 @@
 error: Line 19: Cannot find 'tone' in scope
-error: Line 24: Cannot find 'AVSpeechSynthesizer' in scope
+ContentView {player=nil, sounds=Sounds{finished: 0, spoken: 0}, synth=AVSpeechSynthesizer, video=AVPlayer, status="idle"}
+  VStack({fn})
+    Text("idle")
+    Button("Beep", {fn})
+    Button("Click", {fn})
+    Button("Say", {fn})
+    VideoPlayer(player: AVPlayer)
+      .frame(height: 200)
+    VideoPlayer(player: AVPlayer, {fn})
+      Text(_literal: "Overlay")
+== after Button[Beep]@31
+ContentView {player=nil, sounds=Sounds{finished: 0, spoken: 0}, synth=AVSpeechSynthesizer, video=AVPlayer, status="error"}
+  VStack({fn})
+    Text("error")
+    Button("Beep", {fn})
+    Button("Click", {fn})
+    Button("Say", {fn})
+    VideoPlayer(player: AVPlayer)
+      .frame(height: 200)
+    VideoPlayer(player: AVPlayer, {fn})
+      Text(_literal: "Overlay")
+== after Button[Click]@32
+ContentView {player=nil, sounds=Sounds{finished: 0, spoken: 0}, synth=AVSpeechSynthesizer, video=AVPlayer, status="error"}
+  VStack({fn})
+    Text("error")
+    Button("Beep", {fn})
+    Button("Click", {fn})
+    Button("Say", {fn})
+    VideoPlayer(player: AVPlayer)
+      .frame(height: 200)
+    VideoPlayer(player: AVPlayer, {fn})
+      Text(_literal: "Overlay")
+== after Button[Say]@33
+ContentView {player=nil, sounds=Sounds{finished: 0, spoken: 0}, synth=AVSpeechSynthesizer, video=AVPlayer, status="error"}
+  VStack({fn})
+    Text("error")
+    Button("Beep", {fn})
+    Button("Click", {fn})
+    Button("Say", {fn})
+    VideoPlayer(player: AVPlayer)
+      .frame(height: 200)
+    VideoPlayer(player: AVPlayer, {fn})
+      Text(_literal: "Overlay")
+== after Button[Beep]@31
+ContentView {player=nil, sounds=Sounds{finished: 0, spoken: 0}, synth=AVSpeechSynthesizer, video=AVPlayer, status="error"}
+  VStack({fn})
+    Text("error")
+    Button("Beep", {fn})
+    Button("Click", {fn})
+    Button("Say", {fn})
+    VideoPlayer(player: AVPlayer)
+      .frame(height: 200)
+    VideoPlayer(player: AVPlayer, {fn})
+      Text(_literal: "Overlay")
+== after Button[Click]@32
+ContentView {player=nil, sounds=Sounds{finished: 0, spoken: 0}, synth=AVSpeechSynthesizer, video=AVPlayer, status="error"}
+  VStack({fn})
+    Text("error")
+    Button("Beep", {fn})
+    Button("Click", {fn})
+    Button("Say", {fn})
+    VideoPlayer(player: AVPlayer)
+      .frame(height: 200)
+    VideoPlayer(player: AVPlayer, {fn})
+      Text(_literal: "Overlay")
+== after Button[Say]@33
+ContentView {player=nil, sounds=Sounds{finished: 0, spoken: 0}, synth=AVSpeechSynthesizer, video=AVPlayer, status="error"}
+  VStack({fn})
+    Text("error")
+    Button("Beep", {fn})
+    Button("Click", {fn})
+    Button("Say", {fn})
+    VideoPlayer(player: AVPlayer)
+      .frame(height: 200)
+    VideoPlayer(player: AVPlayer, {fn})
+      Text(_literal: "Overlay")
+== after Button[Beep]@31
+ContentView {player=nil, sounds=Sounds{finished: 0, spoken: 0}, synth=AVSpeechSynthesizer, video=AVPlayer, status="error"}
+  VStack({fn})
+    Text("error")
+    Button("Beep", {fn})
+    Button("Click", {fn})
+    Button("Say", {fn})
+    VideoPlayer(player: AVPlayer)
+      .frame(height: 200)
+    VideoPlayer(player: AVPlayer, {fn})
+      Text(_literal: "Overlay")
+== after Button[Click]@32
+ContentView {player=nil, sounds=Sounds{finished: 0, spoken: 0}, synth=AVSpeechSynthesizer, video=AVPlayer, status="error"}
+  VStack({fn})
+    Text("error")
+    Button("Beep", {fn})
+    Button("Click", {fn})
+    Button("Say", {fn})
+    VideoPlayer(player: AVPlayer)
+      .frame(height: 200)
+    VideoPlayer(player: AVPlayer, {fn})
+      Text(_literal: "Overlay")
+== after Button[Say]@33
+ContentView {player=nil, sounds=Sounds{finished: 0, spoken: 0}, synth=AVSpeechSynthesizer, video=AVPlayer, status="error"}
+  VStack({fn})
+    Text("error")
+    Button("Beep", {fn})
+    Button("Click", {fn})
+    Button("Say", {fn})
+    VideoPlayer(player: AVPlayer)
+      .frame(height: 200)
+    VideoPlayer(player: AVPlayer, {fn})
+      Text(_literal: "Overlay")
+== after Button[Beep]@31
+ContentView {player=nil, sounds=Sounds{finished: 0, spoken: 0}, synth=AVSpeechSynthesizer, video=AVPlayer, status="error"}
+  VStack({fn})
+    Text("error")
+    Button("Beep", {fn})
+    Button("Click", {fn})
…
```

## tests/Chart3DBridgeTests-0.swift

```diff
--- before
+++ after
@@ -1,5 +1,364 @@
 == start
-ContentView {pose=.front, frequency=2.0, depth=nil, samples=[Sample(id: <uuid>, x: 0.0, y: 0.0, z: 0.0, kind: "Even"), Sample(id: <uuid>, x: 1.0, y: 0.25, z: 0.0, kind: "Odd"), Sample(id: <uuid>, x: 2.0, y: 0.5, z: 0.0, kind: "Even"), Sample(id: <uuid>, x: 3.0, y: 0.75, z: 0.0, kind: "Odd"), Sample(id: <uuid>, x: 4.0, y: 1.0, z: 0.0, kind: "Even"), Sample(id: <uuid>, x: 0.0, y: 1.25, z: 1.0, kind: "Odd"), Sample(id: <uuid>, x: 1.0, y: 1.5, z: 1.0, kind: "Even"), Sample(id: <uuid>, x: 2.0, y: 1.75, z: 1.0, kind: "Odd"), Sample(id: <uuid>, x: 3.0, y: 2.0, z: 1.0, kind: "Even"), Sample(id: <uuid>, x: 4.0, y: 2.25, z: 1.0, kind: "Odd"), Sample(id: <uuid>, x: 0.0, y: 2.5, z: 2.0, kind: "Even"), Sample(id: <uuid>, x: 1.0, y: 2.75, z: 2.0, kind: "Odd"), Sample(id: <uuid>, x: 2.0, y: 3.0, z: 2.0, kind: "Even"), Sample(id: <uuid>, x: 3.0, y: 3.25, z: 2.0, kind: "Odd"), Sample(id: <uuid>, x: 4.0, y: 3.5, z: 2.0, kind: "Even"), Sample(id: <uuid>, x: 0.0, y: 3.75, z: 3.0, kind: "Odd"), Sample(id: <uuid>, x: 1.0, y: 4.0, z: 3.0, kind: "Even"), Sample(id: <uuid>, x: 2.0, y: 4.25, z: 3.0, kind: "Odd"), Sample(id: <uuid>, x: 3.0, y: 4.5, z: 3.0, kind: "Even"), Sample(id: <uuid>, x: 4.0, y: 4.75, z: 3.0, kind: "Odd")]}
-  VStack({fn})
-    content failed
-error: Line 24: Cannot find 'Chart3D' in scope
+ContentView {pose=Chart3DPose, frequency=2.0, depth=nil, samples=[Sample(id: <uuid>, x: 0.0, y: 0.0, z: 0.0, kind: "Even"), Sample(id: <uuid>, x: 1.0, y: 0.25, z: 0.0, kind: "Odd"), Sample(id: <uuid>, x: 2.0, y: 0.5, z: 0.0, kind: "Even"), Sample(id: <uuid>, x: 3.0, y: 0.75, z: 0.0, kind: "Odd"), Sample(id: <uuid>, x: 4.0, y: 1.0, z: 0.0, kind: "Even"), Sample(id: <uuid>, x: 0.0, y: 1.25, z: 1.0, kind: "Odd"), Sample(id: <uuid>, x: 1.0, y: 1.5, z: 1.0, kind: "Even"), Sample(id: <uuid>, x: 2.0, y: 1.75, z: 1.0, kind: "Odd"), Sample(id: <uuid>, x: 3.0, y: 2.0, z: 1.0, kind: "Even"), Sample(id: <uuid>, x: 4.0, y: 2.25, z: 1.0, kind: "Odd"), Sample(id: <uuid>, x: 0.0, y: 2.5, z: 2.0, kind: "Even"), Sample(id: <uuid>, x: 1.0, y: 2.75, z: 2.0, kind: "Odd"), Sample(id: <uuid>, x: 2.0, y: 3.0, z: 2.0, kind: "Even"), Sample(id: <uuid>, x: 3.0, y: 3.25, z: 2.0, kind: "Odd"), Sample(id: <uuid>, x: 4.0, y: 3.5, z: 2.0, kind: "Even"), Sample(id: <uuid>, x: 0.0, y: 3.75, z: 3.0, kind: "Odd"), Sample(id: <uuid>, x: 1.0, y: 4.0, z: 3.0, kind: "Even"), Sample(id: <uuid>, x: 2.0, y: 4.25, z: 3.0, kind: "Odd"), Sample(id: <uuid>, x: 3.0, y: 4.5, z: 3.0, kind: "Even"), Sample(id: <uuid>, x: 4.0, y: 4.75, z: 3.0, kind: "Odd")]}
+  VStack({fn})
+    Chart3D([Sample(id: <uuid>, x: 0.0, y: 0.0, z: 0.0, kind: "Even"), Sample(id: <uuid>, x: 1.0, y: 0.25, z: 0.0, kind: "Odd"), Sample(id: <uuid>, x: 2.0, y: 0.5, z: 0.0, kind: "Even"), Sample(id: <uuid>, x: 3.0, y: 0.75, z: 0.0, kind: "Odd"), Sample(id: <uuid>, x: 4.0, y: 1.0, z: 0.0, kind: "Even"), Sample(id: <uuid>, x: 0.0, y: 1.25, z: 1.0, kind: "Odd"), Sample(id: <uuid>, x: 1.0, y: 1.5, z: 1.0, kind: "Even"), Sample(id: <uuid>, x: 2.0, y: 1.75, z: 1.0, kind: "Odd"), Sample(id: <uuid>, x: 3.0, y: 2.0, z: 1.0, kind: "Even"), Sample(id: <uuid>, x: 4.0, y: 2.25, z: 1.0, kind: "Odd"), Sample(id: <uuid>, x: 0.0, y: 2.5, z: 2.0, kind: "Even"), Sample(id: <uuid>, x: 1.0, y: 2.75, z: 2.0, kind: "Odd"), Sample(id: <uuid>, x: 2.0, y: 3.0, z: 2.0, kind: "Even"), Sample(id: <uuid>, x: 3.0, y: 3.25, z: 2.0, kind: "Odd"), Sample(id: <uuid>, x: 4.0, y: 3.5, z: 2.0, kind: "Even"), Sample(id: <uuid>, x: 0.0, y: 3.75, z: 3.0, kind: "Odd"), Sample(id: <uuid>, x: 1.0, y: 4.0, z: 3.0, kind: "Even"), Sample(id: <uuid>, x: 2.0, y: 4.25, z: 3.0, kind: "Odd"), Sample(id: <uuid>, x: 3.0, y: 4.5, z: 3.0, kind: "Even"), Sample(id: <uuid>, x: 4.0, y: 4.75, z: 3.0, kind: "Odd")], {fn})
+      PointMark(x: .value("X", nil), y: .value("Y", nil), z: .value("Z", nil))
+        .foregroundStyle(by: .value("Kind", nil))
+        .symbol(.cube)
+        .symbolSize(0.04)
+        .metalness(0.3)
+        .roughness(0.6)
+        .symbolRotation(Rotation3D)
+      .chart3DPose($Chart3DPose)
+      .chart3DCameraProjection(.perspective)
+      .chartZAxisLabel("Depth")
+      .chartZScale(domain: 0...4)
+      .chartZSelection(value: $nil)
+    Chart3D({fn})
+      SurfacePlot(x: "X", y: "Height", z: "Z", {fn})
+        .foregroundStyle(.heightBased)
+      PointMark(x: .value("X", 0.0), y: .value("Y", 1.0), z: .value("Z", 0.0))
+        .foregroundStyle(Color)
+      .chartXScale(domain: -3...3)
+      .chartZScale(domain: -3...3)
+      .chart3DPose(Chart3DPose)
+      .chartZAxis(.hidden)
+    Text(_literal: "0")
+    Button("Top", {fn})
+    Slider(value: $2.0, in: 1...4)
+== after SurfacePlot@40
+ContentView {pose=Chart3DPose, frequency=2.0, depth=nil, samples=[Sample(id: <uuid>, x: 0.0, y: 0.0, z: 0.0, kind: "Even"), Sample(id: <uuid>, x: 1.0, y: 0.25, z: 0.0, kind: "Odd"), Sample(id: <uuid>, x: 2.0, y: 0.5, z: 0.0, kind: "Even"), Sample(id: <uuid>, x: 3.0, y: 0.75, z: 0.0, kind: "Odd"), Sample(id: <uuid>, x: 4.0, y: 1.0, z: 0.0, kind: "Even"), Sample(id: <uuid>, x: 0.0, y: 1.25, z: 1.0, kind: "Odd"), Sample(id: <uuid>, x: 1.0, y: 1.5, z: 1.0, kind: "Even"), Sample(id: <uuid>, x: 2.0, y: 1.75, z: 1.0, kind: "Odd"), Sample(id: <uuid>, x: 3.0, y: 2.0, z: 1.0, kind: "Even"), Sample(id: <uuid>, x: 4.0, y: 2.25, z: 1.0, kind: "Odd"), Sample(id: <uuid>, x: 0.0, y: 2.5, z: 2.0, kind: "Even"), Sample(id: <uuid>, x: 1.0, y: 2.75, z: 2.0, kind: "Odd"), Sample(id: <uuid>, x: 2.0, y: 3.0, z: 2.0, kind: "Even"), Sample(id: <uuid>, x: 3.0, y: 3.25, z: 2.0, kind: "Odd"), Sample(id: <uuid>, x: 4.0, y: 3.5, z: 2.0, kind: "Even"), Sample(id: <uuid>, x: 0.0, y: 3.75, z: 3.0, kind: "Odd"), Sample(id: <uuid>, x: 1.0, y: 4.0, z: 3.0, kind: "Even"), Sample(id: <uuid>, x: 2.0, y: 4.25, z: 3.0, kind: "Odd"), Sample(id: <uuid>, x: 3.0, y: 4.5, z: 3.0, kind: "Even"), Sample(id: <uuid>, x: 4.0, y: 4.75, z: 3.0, kind: "Odd")]}
+  VStack({fn})
+    Chart3D([Sample(id: <uuid>, x: 0.0, y: 0.0, z: 0.0, kind: "Even"), Sample(id: <uuid>, x: 1.0, y: 0.25, z: 0.0, kind: "Odd"), Sample(id: <uuid>, x: 2.0, y: 0.5, z: 0.0, kind: "Even"), Sample(id: <uuid>, x: 3.0, y: 0.75, z: 0.0, kind: "Odd"), Sample(id: <uuid>, x: 4.0, y: 1.0, z: 0.0, kind: "Even"), Sample(id: <uuid>, x: 0.0, y: 1.25, z: 1.0, kind: "Odd"), Sample(id: <uuid>, x: 1.0, y: 1.5, z: 1.0, kind: "Even"), Sample(id: <uuid>, x: 2.0, y: 1.75, z: 1.0, kind: "Odd"), Sample(id: <uuid>, x: 3.0, y: 2.0, z: 1.0, kind: "Even"), Sample(id: <uuid>, x: 4.0, y: 2.25, z: 1.0, kind: "Odd"), Sample(id: <uuid>, x: 0.0, y: 2.5, z: 2.0, kind: "Even"), Sample(id: <uuid>, x: 1.0, y: 2.75, z: 2.0, kind: "Odd"), Sample(id: <uuid>, x: 2.0, y: 3.0, z: 2.0, kind: "Even"), Sample(id: <uuid>, x: 3.0, y: 3.25, z: 2.0, kind: "Odd"), Sample(id: <uuid>, x: 4.0, y: 3.5, z: 2.0, kind: "Even"), Sample(id: <uuid>, x: 0.0, y: 3.75, z: 3.0, kind: "Odd"), Sample(id: <uuid>, x: 1.0, y: 4.0, z: 3.0, kind: "Even"), Sample(id: <uuid>, x: 2.0, y: 4.25, z: 3.0, kind: "Odd"), Sample(id: <uuid>, x: 3.0, y: 4.5, z: 3.0, kind: "Even"), Sample(id: <uuid>, x: 4.0, y: 4.75, z: 3.0, kind: "Odd")], {fn})
+      PointMark(x: .value("X", nil), y: .value("Y", nil), z: .value("Z", nil))
+        .foregroundStyle(by: .value("Kind", nil))
+        .symbol(.cube)
+        .symbolSize(0.04)
+        .metalness(0.3)
+        .roughness(0.6)
+        .symbolRotation(Rotation3D)
+      .chart3DPose($Chart3DPose)
+      .chart3DCameraProjection(.perspective)
+      .chartZAxisLabel("Depth")
+      .chartZScale(domain: 0...4)
+      .chartZSelection(value: $nil)
+    Chart3D({fn})
+      SurfacePlot(x: "X", y: "Height", z: "Z", {fn})
+        .foregroundStyle(.heightBased)
+      PointMark(x: .value("X", 0.0), y: .value("Y", 1.0), z: .value("Z", 0.0))
+        .foregroundStyle(Color)
+      .chartXScale(domain: -3...3)
+      .chartZScale(domain: -3...3)
+      .chart3DPose(Chart3DPose)
+      .chartZAxis(.hidden)
+    Text(_literal: "0")
+    Button("Top", {fn})
+    Slider(value: $2.0, in: 1...4)
+== after Button[Top]@53
+ContentView {pose=Chart3DPose, frequency=2.0, depth=nil, samples=[Sample(id: <uuid>, x: 0.0, y: 0.0, z: 0.0, kind: "Even"), Sample(id: <uuid>, x: 1.0, y: 0.25, z: 0.0, kind: "Odd"), Sample(id: <uuid>, x: 2.0, y: 0.5, z: 0.0, kind: "Even"), Sample(id: <uuid>, x: 3.0, y: 0.75, z: 0.0, kind: "Odd"), Sample(id: <uuid>, x: 4.0, y: 1.0, z: 0.0, kind: "Even"), Sample(id: <uuid>, x: 0.0, y: 1.25, z: 1.0, kind: "Odd"), Sample(id: <uuid>, x: 1.0, y: 1.5, z: 1.0, kind: "Even"), Sample(id: <uuid>, x: 2.0, y: 1.75, z: 1.0, kind: "Odd"), Sample(id: <uuid>, x: 3.0, y: 2.0, z: 1.0, kind: "Even"), Sample(id: <uuid>, x: 4.0, y: 2.25, z: 1.0, kind: "Odd"), Sample(id: <uuid>, x: 0.0, y: 2.5, z: 2.0, kind: "Even"), Sample(id: <uuid>, x: 1.0, y: 2.75, z: 2.0, kind: "Odd"), Sample(id: <uuid>, x: 2.0, y: 3.0, z: 2.0, kind: "Even"), Sample(id: <uuid>, x: 3.0, y: 3.25, z: 2.0, kind: "Odd"), Sample(id: <uuid>, x: 4.0, y: 3.5, z: 2.0, kind: "Even"), Sample(id: <uuid>, x: 0.0, y: 3.75, z: 3.0, kind: "Odd"), Sample(id: <uuid>, x: 1.0, y: 4.0, z: 3.0, kind: "Even"), Sample(id: <uuid>, x: 2.0, y: 4.25, z: 3.0, kind: "Odd"), Sample(id: <uuid>, x: 3.0, y: 4.5, z: 3.0, kind: "Even"), Sample(id: <uuid>, x: 4.0, y: 4.75, z: 3.0, kind: "Odd")]}
+  VStack({fn})
+    Chart3D([Sample(id: <uuid>, x: 0.0, y: 0.0, z: 0.0, kind: "Even"), Sample(id: <uuid>, x: 1.0, y: 0.25, z: 0.0, kind: "Odd"), Sample(id: <uuid>, x: 2.0, y: 0.5, z: 0.0, kind: "Even"), Sample(id: <uuid>, x: 3.0, y: 0.75, z: 0.0, kind: "Odd"), Sample(id: <uuid>, x: 4.0, y: 1.0, z: 0.0, kind: "Even"), Sample(id: <uuid>, x: 0.0, y: 1.25, z: 1.0, kind: "Odd"), Sample(id: <uuid>, x: 1.0, y: 1.5, z: 1.0, kind: "Even"), Sample(id: <uuid>, x: 2.0, y: 1.75, z: 1.0, kind: "Odd"), Sample(id: <uuid>, x: 3.0, y: 2.0, z: 1.0, kind: "Even"), Sample(id: <uuid>, x: 4.0, y: 2.25, z: 1.0, kind: "Odd"), Sample(id: <uuid>, x: 0.0, y: 2.5, z: 2.0, kind: "Even"), Sample(id: <uuid>, x: 1.0, y: 2.75, z: 2.0, kind: "Odd"), Sample(id: <uuid>, x: 2.0, y: 3.0, z: 2.0, kind: "Even"), Sample(id: <uuid>, x: 3.0, y: 3.25, z: 2.0, kind: "Odd"), Sample(id: <uuid>, x: 4.0, y: 3.5, z: 2.0, kind: "Even"), Sample(id: <uuid>, x: 0.0, y: 3.75, z: 3.0, kind: "Odd"), Sample(id: <uuid>, x: 1.0, y: 4.0, z: 3.0, kind: "Even"), Sample(id: <uuid>, x: 2.0, y: 4.25, z: 3.0, kind: "Odd"), Sample(id: <uuid>, x: 3.0, y: 4.5, z: 3.0, kind: "Even"), Sample(id: <uuid>, x: 4.0, y: 4.75, z: 3.0, kind: "Odd")], {fn})
+      PointMark(x: .value("X", nil), y: .value("Y", nil), z: .value("Z", nil))
+        .foregroundStyle(by: .value("Kind", nil))
+        .symbol(.cube)
+        .symbolSize(0.04)
+        .metalness(0.3)
+        .roughness(0.6)
+        .symbolRotation(Rotation3D)
+      .chart3DPose($Chart3DPose)
+      .chart3DCameraProjection(.perspective)
+      .chartZAxisLabel("Depth")
+      .chartZScale(domain: 0...4)
+      .chartZSelection(value: $nil)
+    Chart3D({fn})
+      SurfacePlot(x: "X", y: "Height", z: "Z", {fn})
+        .foregroundStyle(.heightBased)
+      PointMark(x: .value("X", 0.0), y: .value("Y", 1.0), z: .value("Z", 0.0))
+        .foregroundStyle(Color)
+      .chartXScale(domain: -3...3)
+      .chartZScale(domain: -3...3)
+      .chart3DPose(Chart3DPose)
+      .chartZAxis(.hidden)
+    Text(_literal: "0")
+    Button("Top", {fn})
+    Slider(value: $2.0, in: 1...4)
+== after SurfacePlot@40
+ContentView {pose=Chart3DPose, frequency=2.0, depth=nil, samples=[Sample(id: <uuid>, x: 0.0, y: 0.0, z: 0.0, kind: "Even"), Sample(id: <uuid>, x: 1.0, y: 0.25, z: 0.0, kind: "Odd"), Sample(id: <uuid>, x: 2.0, y: 0.5, z: 0.0, kind: "Even"), Sample(id: <uuid>, x: 3.0, y: 0.75, z: 0.0, kind: "Odd"), Sample(id: <uuid>, x: 4.0, y: 1.0, z: 0.0, kind: "Even"), Sample(id: <uuid>, x: 0.0, y: 1.25, z: 1.0, kind: "Odd"), Sample(id: <uuid>, x: 1.0, y: 1.5, z: 1.0, kind: "Even"), Sample(id: <uuid>, x: 2.0, y: 1.75, z: 1.0, kind: "Odd"), Sample(id: <uuid>, x: 3.0, y: 2.0, z: 1.0, kind: "Even"), Sample(id: <uuid>, x: 4.0, y: 2.25, z: 1.0, kind: "Odd"), Sample(id: <uuid>, x: 0.0, y: 2.5, z: 2.0, kind: "Even"), Sample(id: <uuid>, x: 1.0, y: 2.75, z: 2.0, kind: "Odd"), Sample(id: <uuid>, x: 2.0, y: 3.0, z: 2.0, kind: "Even"), Sample(id: <uuid>, x: 3.0, y: 3.25, z: 2.0, kind: "Odd"), Sample(id: <uuid>, x: 4.0, y: 3.5, z: 2.0, kind: "Even"), Sample(id: <uuid>, x: 0.0, y: 3.75, z: 3.0, kind: "Odd"), Sample(id: <uuid>, x: 1.0, y: 4.0, z: 3.0, kind: "Even"), Sample(id: <uuid>, x: 2.0, y: 4.25, z: 3.0, kind: "Odd"), Sample(id: <uuid>, x: 3.0, y: 4.5, z: 3.0, kind: "Even"), Sample(id: <uuid>, x: 4.0, y: 4.75, z: 3.0, kind: "Odd")]}
+  VStack({fn})
+    Chart3D([Sample(id: <uuid>, x: 0.0, y: 0.0, z: 0.0, kind: "Even"), Sample(id: <uuid>, x: 1.0, y: 0.25, z: 0.0, kind: "Odd"), Sample(id: <uuid>, x: 2.0, y: 0.5, z: 0.0, kind: "Even"), Sample(id: <uuid>, x: 3.0, y: 0.75, z: 0.0, kind: "Odd"), Sample(id: <uuid>, x: 4.0, y: 1.0, z: 0.0, kind: "Even"), Sample(id: <uuid>, x: 0.0, y: 1.25, z: 1.0, kind: "Odd"), Sample(id: <uuid>, x: 1.0, y: 1.5, z: 1.0, kind: "Even"), Sample(id: <uuid>, x: 2.0, y: 1.75, z: 1.0, kind: "Odd"), Sample(id: <uuid>, x: 3.0, y: 2.0, z: 1.0, kind: "Even"), Sample(id: <uuid>, x: 4.0, y: 2.25, z: 1.0, kind: "Odd"), Sample(id: <uuid>, x: 0.0, y: 2.5, z: 2.0, kind: "Even"), Sample(id: <uuid>, x: 1.0, y: 2.75, z: 2.0, kind: "Odd"), Sample(id: <uuid>, x: 2.0, y: 3.0, z: 2.0, kind: "Even"), Sample(id: <uuid>, x: 3.0, y: 3.25, z: 2.0, kind: "Odd"), Sample(id: <uuid>, x: 4.0, y: 3.5, z: 2.0, kind: "Even"), Sample(id: <uuid>, x: 0.0, y: 3.75, z: 3.0, kind: "Odd"), Sample(id: <uuid>, x: 1.0, y: 4.0, z: 3.0, kind: "Even"), Sample(id: <uuid>, x: 2.0, y: 4.25, z: 3.0, kind: "Odd"), Sample(id: <uuid>, x: 3.0, y: 4.5, z: 3.0, kind: "Even"), Sample(id: <uuid>, x: 4.0, y: 4.75, z: 3.0, kind: "Odd")], {fn})
+      PointMark(x: .value("X", nil), y: .value("Y", nil), z: .value("Z", nil))
+        .foregroundStyle(by: .value("Kind", nil))
+        .symbol(.cube)
+        .symbolSize(0.04)
+        .metalness(0.3)
+        .roughness(0.6)
+        .symbolRotation(Rotation3D)
+      .chart3DPose($Chart3DPose)
+      .chart3DCameraProjection(.perspective)
+      .chartZAxisLabel("Depth")
+      .chartZScale(domain: 0...4)
+      .chartZSelection(value: $nil)
+    Chart3D({fn})
+      SurfacePlot(x: "X", y: "Height", z: "Z", {fn})
+        .foregroundStyle(.heightBased)
+      PointMark(x: .value("X", 0.0), y: .value("Y", 1.0), z: .value("Z", 0.0))
+        .foregroundStyle(Color)
+      .chartXScale(domain: -3...3)
+      .chartZScale(domain: -3...3)
+      .chart3DPose(Chart3DPose)
+      .chartZAxis(.hidden)
+    Text(_literal: "0")
+    Button("Top", {fn})
+    Slider(value: $2.0, in: 1...4)
+== after Button[Top]@53
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

## tests/RestOfSwiftUITests-0.swift

```diff
--- before
+++ after
@@ -3,3 +3,492 @@
   VStack({fn})
-    content failed
-error: Line 20: Cannot find 'DragGesture' in scope
+    Circle()
+      .fill(Color)
+      .frame(width: 80, height: 80)
+      .offset(x: 0.0, y: 0.0)
+      .scaleEffect(1.0)
+      .rotationEffect(0.0°)
+      .gesture(<view>)
+        DragGesture(minimumDistance: 0)
+          .updating($Size(0.0, 0.0), {fn})
+          .onEnded({fn})
+      .simultaneousGesture(<view>)
+        MagnifyGesture()
+          .onChanged({fn})
+      .highPriorityGesture(<view>, including: .all)
+        RotateGesture()
+          .onChanged({fn})
+    Rectangle()
+      .frame(width: 60, height: 60)
+      .gesture(<view>)
+        LongPressGesture(minimumDuration: 0.3)
+          .updating($false, {fn})
+          .sequenced(before: <view>)
+            DragGesture()
+          .onEnded({fn})
+      .onTapGesture(count: 2, {fn})
+      .onLongPressGesture(minimumDuration: 0.5, {fn}, onPressingChanged: {fn})
+    Text("none")
+      .gesture(<view>)
+        TapGesture(count: 2)
+          .exclusively(before: <view>)
+            TapGesture()
+          .onEnded({fn})
+      .gesture(<view>, isEnabled: true)
+        SpatialTapGesture()
+          .onEnded({fn})
+== after DragGesture.updating@21
+ContentView {offset=Size(0.0, 0.0), drag=Size(0.0, 0.0), pressing=false, scale=1.0, angle=0.0°, log=[]}
+  VStack({fn})
+    Circle()
+      .fill(Color)
+      .frame(width: 80, height: 80)
+      .offset(x: 0.0, y: 0.0)
+      .scaleEffect(1.0)
+      .rotationEffect(0.0°)
+      .gesture(<view>)
+        DragGesture(minimumDistance: 0)
+          .updating($Size(0.0, 0.0), {fn})
+          .onEnded({fn})
+      .simultaneousGesture(<view>)
+        MagnifyGesture()
+          .onChanged({fn})
+      .highPriorityGesture(<view>, including: .all)
+        RotateGesture()
+          .onChanged({fn})
+    Rectangle()
+      .frame(width: 60, height: 60)
+      .gesture(<view>)
+        LongPressGesture(minimumDuration: 0.3)
+          .updating($false, {fn})
+          .sequenced(before: <view>)
+            DragGesture()
+          .onEnded({fn})
+      .onTapGesture(count: 2, {fn})
+      .onLongPressGesture(minimumDuration: 0.5, {fn}, onPressingChanged: {fn})
+    Text("none")
+      .gesture(<view>)
+        TapGesture(count: 2)
+          .exclusively(before: <view>)
+            TapGesture()
+          .onEnded({fn})
+      .gesture(<view>, isEnabled: true)
+        SpatialTapGesture()
+          .onEnded({fn})
+== after DragGesture.onEnded@24
+ContentView {offset=Size(0.0, 0.0), drag=Size(0.0, 0.0), pressing=false, scale=1.0, angle=0.0°, log=["ended 0.0"]}
+  VStack({fn})
+    Circle()
+      .fill(Color)
+      .frame(width: 80, height: 80)
+      .offset(x: 0.0, y: 0.0)
+      .scaleEffect(1.0)
+      .rotationEffect(0.0°)
+      .gesture(<view>)
+        DragGesture(minimumDistance: 0)
+          .updating($Size(0.0, 0.0), {fn})
+          .onEnded({fn})
+      .simultaneousGesture(<view>)
+        MagnifyGesture()
+          .onChanged({fn})
+      .highPriorityGesture(<view>, including: .all)
+        RotateGesture()
+          .onChanged({fn})
+    Rectangle()
+      .frame(width: 60, height: 60)
+      .gesture(<view>)
+        LongPressGesture(minimumDuration: 0.3)
+          .updating($false, {fn})
+          .sequenced(before: <view>)
+            DragGesture()
+          .onEnded({fn})
+      .onTapGesture(count: 2, {fn})
+      .onLongPressGesture(minimumDuration: 0.5, {fn}, onPressingChanged: {fn})
+    Text("ended 0.0")
+      .gesture(<view>)
+        TapGesture(count: 2)
+          .exclusively(before: <view>)
+            TapGesture()
+          .onEnded({fn})
+      .gesture(<view>, isEnabled: true)
+        SpatialTapGesture()
+          .onEnded({fn})
+== after MagnifyGesture.onChanged@30
+ContentView {offset=Size(0.0, 0.0), drag=Size(0.0, 0.0), pressing=false, scale=1.0, angle=0.0°, log=["ended 0.0"]}
+  VStack({fn})
…
```

## tests/RestOfSwiftUITests-10.swift

```diff
--- before
+++ after
@@ -96,2 +96,26 @@
     .onKeyPress(.escape, {fn})
+== after Form.onKeyPress@34
+ContentView {field=nil, notesFocused=true, name="", email="", notes=""}
+  Form({fn})
+    TextField("Name", text: $"")
+      .focused($nil, equals: .name)
+      .textContentType(.name)
+      .textInputAutocapitalization(.words)
+      .submitLabel(.next)
+      .onSubmit({fn})
+    TextField("Email", text: $"")
+      .focused($nil, equals: .email)
+      .keyboardType(.emailAddress)
+      .textContentType(.emailAddress)
+      .autocorrectionDisabled()
+      .submitLabel(.done)
+      .onSubmit({fn})
+    TextEditor(text: $"")
+      .focused($true)
+    Button("Edit notes", {fn})
+      .keyboardShortcut("n", modifiers: [.command, .shift])
+      .focusedValue(KeyPath, "")
+    .scrollDismissesKeyboard(.interactively)
+    .defaultFocus($nil, .name)
+    .onKeyPress(.escape, {fn})
 == after TextField.onSubmit@19
@@ -168,2 +192,26 @@
     .onKeyPress(.escape, {fn})
+== after Form.onKeyPress@34
+ContentView {field=nil, notesFocused=true, name="", email="", notes=""}
+  Form({fn})
+    TextField("Name", text: $"")
+      .focused($nil, equals: .name)
+      .textContentType(.name)
+      .textInputAutocapitalization(.words)
+      .submitLabel(.next)
+      .onSubmit({fn})
+    TextField("Email", text: $"")
+      .focused($nil, equals: .email)
+      .keyboardType(.emailAddress)
+      .textContentType(.emailAddress)
+      .autocorrectionDisabled()
+      .submitLabel(.done)
+      .onSubmit({fn})
+    TextEditor(text: $"")
+      .focused($true)
+    Button("Edit notes", {fn})
+      .keyboardShortcut("n", modifiers: [.command, .shift])
+      .focusedValue(KeyPath, "")
+    .scrollDismissesKeyboard(.interactively)
+    .defaultFocus($nil, .name)
+    .onKeyPress(.escape, {fn})
 == after TextField.onSubmit@19
@@ -240,73 +288,25 @@
     .onKeyPress(.escape, {fn})
-== after TextField.onSubmit@19
-ContentView {field=.email, notesFocused=true, name="", email="", notes=""}
-  Form({fn})
-    TextField("Name", text: $"")
-      .focused($.email, equals: .name)
-      .textContentType(.name)
-      .textInputAutocapitalization(.words)
-      .submitLabel(.next)
-      .onSubmit({fn})
-    TextField("Email", text: $"")
-      .focused($.email, equals: .email)
-      .keyboardType(.emailAddress)
-      .textContentType(.emailAddress)
-      .autocorrectionDisabled()
-      .submitLabel(.done)
-      .onSubmit({fn})
-    TextEditor(text: $"")
-      .focused($true)
-    Button("Edit notes", {fn})
-      .keyboardShortcut("n", modifiers: [.command, .shift])
-      .focusedValue(KeyPath, "")
-    .scrollDismissesKeyboard(.interactively)
-    .defaultFocus($.email, .name)
-    .onKeyPress(.escape, {fn})
-== after TextField.onSubmit@26
-ContentView {field=nil, notesFocused=true, name="", email="", notes=""}
-  Form({fn})
-    TextField("Name", text: $"")
-      .focused($nil, equals: .name)
-      .textContentType(.name)
-      .textInputAutocapitalization(.words)
-      .submitLabel(.next)
-      .onSubmit({fn})
-    TextField("Email", text: $"")
-      .focused($nil, equals: .email)
-      .keyboardType(.emailAddress)
-      .textContentType(.emailAddress)
-      .autocorrectionDisabled()
-      .submitLabel(.done)
-      .onSubmit({fn})
-    TextEditor(text: $"")
-      .focused($true)
-    Button("Edit notes", {fn})
-      .keyboardShortcut("n", modifiers: [.command, .shift])
-      .focusedValue(KeyPath, "")
-    .scrollDismissesKeyboard(.interactively)
-    .defaultFocus($nil, .name)
-    .onKeyPress(.escape, {fn})
-== after Button[Edit notes]@28
-ContentView {field=nil, notesFocused=true, name="", email="", notes=""}
-  Form({fn})
-    TextField("Name", text: $"")
-      .focused($nil, equals: .name)
-      .textContentType(.name)
-      .textInputAutocapitalization(.words)
-      .submitLabel(.next)
-      .onSubmit({fn})
-    TextField("Email", text: $"")
-      .focused($nil, equals: .email)
-      .keyboardType(.emailAddress)
-      .textContentType(.emailAddress)
-      .autocorrectionDisabled()
…
```

## tests/RestOfSwiftUITests-11.swift

```diff
--- before
+++ after
@@ -1,3 +1,3 @@
 == start
-ContentView {space=(), focused=(), size=nil, n=0}
+ContentView {space=(), focused=(), size=DynamicTypeSize, n=0}
   Text(_literal: "n 0")
@@ -6,3 +6,3 @@
 == appeared (Text.onAppear@9)
-ContentView {space=(), focused=(), size=nil, n=1}
+ContentView {space=(), focused=(), size=DynamicTypeSize, n=1}
   Text(_literal: "n 1")
```

## tests/RestOfSwiftUITests-12.swift

```diff
--- before
+++ after
@@ -2,3 +2,3 @@
 ContentView {}
-  Inner {size=nil, direction=nil, scheme=.light}
+  Inner {size=DynamicTypeSize, direction=.leftToRight, scheme=.light}
     Text(_literal: "x")
@@ -9,5 +9,7 @@
 == appeared (Text.onAppear@7)
-error: Line 8: Can't compare nil and .xLarge
+console: size false false false
+console: direction false
+console: scheme false
 ContentView {}
-  Inner {size=nil, direction=nil, scheme=.light}
+  Inner {size=DynamicTypeSize, direction=.leftToRight, scheme=.light}
     Text(_literal: "x")
```

## tests/RestOfSwiftUITests-13.swift

```diff
--- before
+++ after
@@ -2,14 +2,14 @@
 ContentView {}
-  Inner {phase=nil}
+  Inner {phase=.active}
     Text(_literal: "x")
       .onAppear({fn})
-      .onChange(of: nil, {fn})
+      .onChange(of: .active, {fn})
     .environment(KeyPath, .active)
 == appeared (Text.onAppear@6)
-console: phase nil
+console: phase .active
 ContentView {}
-  Inner {phase=nil}
+  Inner {phase=.active}
     Text(_literal: "x")
       .onAppear({fn})
-      .onChange(of: nil, {fn})
+      .onChange(of: .active, {fn})
     .environment(KeyPath, .active)
```

## tests/RestOfSwiftUITests-14.swift

```diff
--- before
+++ after
@@ -9,6 +9,154 @@
       .transformPreference(Total, {fn})
-        content failed
     .onPreferenceChange(Total, {fn})
     .overlayPreferenceValue(Total, {fn})
-      Text(_literal: "nil")
-error: Line 12: Binary operator '+' can't be applied to nil and Int
+      Text(_literal: "0")
+== after Text.transformPreference@12
+ContentView {total=0}
+  VStack({fn})
+    Text(_literal: "a")
+      .preference(key: Total, value: 2)
+    Text(_literal: "b")
+      .preference(key: Total, value: 3)
+    Text(_literal: "c")
+      .transformPreference(Total, {fn})
+    .onPreferenceChange(Total, {fn})
+    .overlayPreferenceValue(Total, {fn})
+      Text(_literal: "0")
+== after VStack.onPreferenceChange@14
+console: total 0
+ContentView {total=0}
+  VStack({fn})
+    Text(_literal: "a")
+      .preference(key: Total, value: 2)
+    Text(_literal: "b")
+      .preference(key: Total, value: 3)
+    Text(_literal: "c")
+      .transformPreference(Total, {fn})
+    .onPreferenceChange(Total, {fn})
+    .overlayPreferenceValue(Total, {fn})
+      Text(_literal: "0")
+== after Text.transformPreference@12
+ContentView {total=0}
+  VStack({fn})
+    Text(_literal: "a")
+      .preference(key: Total, value: 2)
+    Text(_literal: "b")
+      .preference(key: Total, value: 3)
+    Text(_literal: "c")
+      .transformPreference(Total, {fn})
+    .onPreferenceChange(Total, {fn})
+    .overlayPreferenceValue(Total, {fn})
+      Text(_literal: "0")
+== after VStack.onPreferenceChange@14
+console: total 0
+ContentView {total=0}
+  VStack({fn})
+    Text(_literal: "a")
+      .preference(key: Total, value: 2)
+    Text(_literal: "b")
+      .preference(key: Total, value: 3)
+    Text(_literal: "c")
+      .transformPreference(Total, {fn})
+    .onPreferenceChange(Total, {fn})
+    .overlayPreferenceValue(Total, {fn})
+      Text(_literal: "0")
+== after Text.transformPreference@12
+ContentView {total=0}
+  VStack({fn})
+    Text(_literal: "a")
+      .preference(key: Total, value: 2)
+    Text(_literal: "b")
+      .preference(key: Total, value: 3)
+    Text(_literal: "c")
+      .transformPreference(Total, {fn})
+    .onPreferenceChange(Total, {fn})
+    .overlayPreferenceValue(Total, {fn})
+      Text(_literal: "0")
+== after VStack.onPreferenceChange@14
+console: total 0
+ContentView {total=0}
+  VStack({fn})
+    Text(_literal: "a")
+      .preference(key: Total, value: 2)
+    Text(_literal: "b")
+      .preference(key: Total, value: 3)
+    Text(_literal: "c")
+      .transformPreference(Total, {fn})
+    .onPreferenceChange(Total, {fn})
+    .overlayPreferenceValue(Total, {fn})
+      Text(_literal: "0")
+== after Text.transformPreference@12
+ContentView {total=0}
+  VStack({fn})
+    Text(_literal: "a")
+      .preference(key: Total, value: 2)
+    Text(_literal: "b")
+      .preference(key: Total, value: 3)
+    Text(_literal: "c")
+      .transformPreference(Total, {fn})
+    .onPreferenceChange(Total, {fn})
+    .overlayPreferenceValue(Total, {fn})
+      Text(_literal: "0")
+== after VStack.onPreferenceChange@14
+console: total 0
+ContentView {total=0}
+  VStack({fn})
+    Text(_literal: "a")
+      .preference(key: Total, value: 2)
+    Text(_literal: "b")
+      .preference(key: Total, value: 3)
+    Text(_literal: "c")
+      .transformPreference(Total, {fn})
+    .onPreferenceChange(Total, {fn})
+    .overlayPreferenceValue(Total, {fn})
+      Text(_literal: "0")
+== after Text.transformPreference@12
+ContentView {total=0}
+  VStack({fn})
+    Text(_literal: "a")
+      .preference(key: Total, value: 2)
+    Text(_literal: "b")
+      .preference(key: Total, value: 3)
+    Text(_literal: "c")
+      .transformPreference(Total, {fn})
+    .onPreferenceChange(Total, {fn})
…
```

## tests/RestOfSwiftUITests-15.swift

```diff
--- before
+++ after
@@ -1,3 +1,3 @@
 == start
-ContentView {openURL=nil}
+ContentView {openURL=OpenURLAction}
   Text(_literal: "x")
@@ -5,3 +5,3 @@
 == appeared (Text.onAppear@5)
-ContentView {openURL=nil}
+ContentView {openURL=OpenURLAction}
   Text(_literal: "x")
```

## tests/RestOfSwiftUITests-16.swift

```diff
--- before
+++ after
@@ -3,3 +3,427 @@
   VStack({fn})
-    content failed
-error: Line 44: Cannot find 'BarPlot' in scope
+    Chart([Sale(id: <uuid>, day: "Mon", amount: 3.0, kind: "A"), Sale(id: <uuid>, day: "Tue", amount: 5.0, kind: "B"), Sale(id: <uuid>, day: "Wed", amount: 2.0, kind: "A")], {fn})
+      BarMark(x: .value("Day", nil), y: .value("Amount", nil))
+        .foregroundStyle(by: .value("Kind", nil))
+        .cornerRadius(4)
+        .annotation(position: .top, {fn})
+          Text(_literal: "0")
+            .font(Font)
+      RuleMark(y: .value("Goal", 4))
+        .lineStyle(StrokeStyle)
+      .chartXSelection(value: $nil)
+      .chartForegroundStyleScale(domain: ["A", "B"], range: [Color, Color])
+      .chartYAxis({fn})
+        AxisMarks(position: .leading, {fn})
+          AxisGridLine()
+          AxisValueLabel()
+      .chartLegend(position: .bottom)
+    Chart({fn})
+      LinePlot(x: "x", y: "y", domain: 0...6.28, {fn})
+      PointMark(x: .value("x", 1.0), y: .value("y", 0.5))
+        .symbol(.diamond)
+        .symbolSize(60)
+      .chartXScale(domain: 0...6.28)
+      .chartScrollableAxes(.horizontal)
+      .chartXVisibleDomain(length: 3)
+    Chart({fn})
+      SectorMark(angle: .value("Share", 40), innerRadius: .ratio(0.6), angularInset: 2)
+        .foregroundStyle(Color)
+      SectorMark(angle: .value("Share", 60), innerRadius: .ratio(0.6), angularInset: 2)
+        .foregroundStyle(Color)
+    BarPlot([Sale(id: <uuid>, day: "Mon", amount: 3.0, kind: "A"), Sale(id: <uuid>, day: "Tue", amount: 5.0, kind: "B"), Sale(id: <uuid>, day: "Wed", amount: 2.0, kind: "A")], x: .value("Day", KeyPath), y: .value("Amount", KeyPath))
+== after LinePlot@34
+ContentView {selected=nil, sales=[Sale(id: <uuid>, day: "Mon", amount: 3.0, kind: "A"), Sale(id: <uuid>, day: "Tue", amount: 5.0, kind: "B"), Sale(id: <uuid>, day: "Wed", amount: 2.0, kind: "A")]}
+  VStack({fn})
+    Chart([Sale(id: <uuid>, day: "Mon", amount: 3.0, kind: "A"), Sale(id: <uuid>, day: "Tue", amount: 5.0, kind: "B"), Sale(id: <uuid>, day: "Wed", amount: 2.0, kind: "A")], {fn})
+      BarMark(x: .value("Day", nil), y: .value("Amount", nil))
+        .foregroundStyle(by: .value("Kind", nil))
+        .cornerRadius(4)
+        .annotation(position: .top, {fn})
+          Text(_literal: "0")
+            .font(Font)
+      RuleMark(y: .value("Goal", 4))
+        .lineStyle(StrokeStyle)
+      .chartXSelection(value: $nil)
+      .chartForegroundStyleScale(domain: ["A", "B"], range: [Color, Color])
+      .chartYAxis({fn})
+        AxisMarks(position: .leading, {fn})
+          AxisGridLine()
+          AxisValueLabel()
+      .chartLegend(position: .bottom)
+    Chart({fn})
+      LinePlot(x: "x", y: "y", domain: 0...6.28, {fn})
+      PointMark(x: .value("x", 1.0), y: .value("y", 0.5))
+        .symbol(.diamond)
+        .symbolSize(60)
+      .chartXScale(domain: 0...6.28)
+      .chartScrollableAxes(.horizontal)
+      .chartXVisibleDomain(length: 3)
+    Chart({fn})
+      SectorMark(angle: .value("Share", 40), innerRadius: .ratio(0.6), angularInset: 2)
+        .foregroundStyle(Color)
+      SectorMark(angle: .value("Share", 60), innerRadius: .ratio(0.6), angularInset: 2)
+        .foregroundStyle(Color)
+    BarPlot([Sale(id: <uuid>, day: "Mon", amount: 3.0, kind: "A"), Sale(id: <uuid>, day: "Tue", amount: 5.0, kind: "B"), Sale(id: <uuid>, day: "Wed", amount: 2.0, kind: "A")], x: .value("Day", KeyPath), y: .value("Amount", KeyPath))
+== after LinePlot@34
+ContentView {selected=nil, sales=[Sale(id: <uuid>, day: "Mon", amount: 3.0, kind: "A"), Sale(id: <uuid>, day: "Tue", amount: 5.0, kind: "B"), Sale(id: <uuid>, day: "Wed", amount: 2.0, kind: "A")]}
+  VStack({fn})
+    Chart([Sale(id: <uuid>, day: "Mon", amount: 3.0, kind: "A"), Sale(id: <uuid>, day: "Tue", amount: 5.0, kind: "B"), Sale(id: <uuid>, day: "Wed", amount: 2.0, kind: "A")], {fn})
+      BarMark(x: .value("Day", nil), y: .value("Amount", nil))
+        .foregroundStyle(by: .value("Kind", nil))
+        .cornerRadius(4)
+        .annotation(position: .top, {fn})
+          Text(_literal: "0")
+            .font(Font)
+      RuleMark(y: .value("Goal", 4))
+        .lineStyle(StrokeStyle)
+      .chartXSelection(value: $nil)
+      .chartForegroundStyleScale(domain: ["A", "B"], range: [Color, Color])
+      .chartYAxis({fn})
+        AxisMarks(position: .leading, {fn})
+          AxisGridLine()
+          AxisValueLabel()
+      .chartLegend(position: .bottom)
+    Chart({fn})
+      LinePlot(x: "x", y: "y", domain: 0...6.28, {fn})
+      PointMark(x: .value("x", 1.0), y: .value("y", 0.5))
+        .symbol(.diamond)
+        .symbolSize(60)
+      .chartXScale(domain: 0...6.28)
+      .chartScrollableAxes(.horizontal)
+      .chartXVisibleDomain(length: 3)
+    Chart({fn})
+      SectorMark(angle: .value("Share", 40), innerRadius: .ratio(0.6), angularInset: 2)
+        .foregroundStyle(Color)
+      SectorMark(angle: .value("Share", 60), innerRadius: .ratio(0.6), angularInset: 2)
+        .foregroundStyle(Color)
+    BarPlot([Sale(id: <uuid>, day: "Mon", amount: 3.0, kind: "A"), Sale(id: <uuid>, day: "Tue", amount: 5.0, kind: "B"), Sale(id: <uuid>, day: "Wed", amount: 2.0, kind: "A")], x: .value("Day", KeyPath), y: .value("Amount", KeyPath))
+== after LinePlot@34
+ContentView {selected=nil, sales=[Sale(id: <uuid>, day: "Mon", amount: 3.0, kind: "A"), Sale(id: <uuid>, day: "Tue", amount: 5.0, kind: "B"), Sale(id: <uuid>, day: "Wed", amount: 2.0, kind: "A")]}
+  VStack({fn})
+    Chart([Sale(id: <uuid>, day: "Mon", amount: 3.0, kind: "A"), Sale(id: <uuid>, day: "Tue", amount: 5.0, kind: "B"), Sale(id: <uuid>, day: "Wed", amount: 2.0, kind: "A")], {fn})
+      BarMark(x: .value("Day", nil), y: .value("Amount", nil))
+        .foregroundStyle(by: .value("Kind", nil))
+        .cornerRadius(4)
+        .annotation(position: .top, {fn})
+          Text(_literal: "0")
+            .font(Font)
+      RuleMark(y: .value("Goal", 4))
+        .lineStyle(StrokeStyle)
+      .chartXSelection(value: $nil)
+      .chartForegroundStyleScale(domain: ["A", "B"], range: [Color, Color])
+      .chartYAxis({fn})
+        AxisMarks(position: .leading, {fn})
+          AxisGridLine()
+          AxisValueLabel()
…
```

## tests/RestOfSwiftUITests-19.swift

```diff
--- before
+++ after
@@ -1,2 +1,403 @@
 == start
-error: Missing argument 'announced' in call to ContentView
+ContentView {announced=(), level=3}
+  VStack({fn})
+    Text(_literal: "Title")
+      .fontWidth(.condensed)
+      .allowsTightening(true)
+      .textScale(.secondary)
+    Text(_literal: "Body")
+      .typesettingLanguage(.init("en"))
+      .flipsForRightToLeftLayoutDirection(true)
+    Text(_literal: "Head")
+      .accessibilityHeading(.h1)
+      .accessibilityAddTraits(.isHeader)
+    Image(systemName: "star")
+      .accessibilityLabel("Favorite")
+      .accessibilityHint("Adds it")
+      .accessibilityValue("3 stars")
+      .accessibilityAdjustableAction({fn})
+      .accessibilityAction(named: "Reset", {fn})
+      .accessibilityFocused($())
+      .accessibilitySortPriority(2)
+    HStack({fn})
+      Text(_literal: "A")
+      Text(_literal: "B")
+      .accessibilityElement(children: .combine)
+      .accessibilityRotor("Letters", {fn})
+        AccessibilityRotorEntry("A", id: "a")
+    Text(_literal: "Hidden")
+      .accessibilityHidden(true)
+      .speechSpellsOutCharacters()
+    .dynamicTypeSize(nil...DynamicTypeSize)
+== after Image.accessibilityAdjustableAction@14
+ContentView {announced=(), level=1}
+  VStack({fn})
+    Text(_literal: "Title")
+      .fontWidth(.condensed)
+      .allowsTightening(true)
+      .textScale(.secondary)
+    Text(_literal: "Body")
+      .typesettingLanguage(.init("en"))
+      .flipsForRightToLeftLayoutDirection(true)
+    Text(_literal: "Head")
+      .accessibilityHeading(.h1)
+      .accessibilityAddTraits(.isHeader)
+    Image(systemName: "star")
+      .accessibilityLabel("Favorite")
+      .accessibilityHint("Adds it")
+      .accessibilityValue("1 stars")
+      .accessibilityAdjustableAction({fn})
+      .accessibilityAction(named: "Reset", {fn})
+      .accessibilityFocused($())
+      .accessibilitySortPriority(2)
+    HStack({fn})
+      Text(_literal: "A")
+      Text(_literal: "B")
+      .accessibilityElement(children: .combine)
+      .accessibilityRotor("Letters", {fn})
+        AccessibilityRotorEntry("A", id: "a")
+    Text(_literal: "Hidden")
+      .accessibilityHidden(true)
+      .speechSpellsOutCharacters()
+    .dynamicTypeSize(nil...DynamicTypeSize)
+== after Image.accessibilityAdjustableAction@14
+ContentView {announced=(), level=1}
+  VStack({fn})
+    Text(_literal: "Title")
+      .fontWidth(.condensed)
+      .allowsTightening(true)
+      .textScale(.secondary)
+    Text(_literal: "Body")
+      .typesettingLanguage(.init("en"))
+      .flipsForRightToLeftLayoutDirection(true)
+    Text(_literal: "Head")
+      .accessibilityHeading(.h1)
+      .accessibilityAddTraits(.isHeader)
+    Image(systemName: "star")
+      .accessibilityLabel("Favorite")
+      .accessibilityHint("Adds it")
+      .accessibilityValue("1 stars")
+      .accessibilityAdjustableAction({fn})
+      .accessibilityAction(named: "Reset", {fn})
+      .accessibilityFocused($())
+      .accessibilitySortPriority(2)
+    HStack({fn})
+      Text(_literal: "A")
+      Text(_literal: "B")
+      .accessibilityElement(children: .combine)
+      .accessibilityRotor("Letters", {fn})
+        AccessibilityRotorEntry("A", id: "a")
+    Text(_literal: "Hidden")
+      .accessibilityHidden(true)
+      .speechSpellsOutCharacters()
+    .dynamicTypeSize(nil...DynamicTypeSize)
+== after Image.accessibilityAdjustableAction@14
+ContentView {announced=(), level=1}
+  VStack({fn})
+    Text(_literal: "Title")
+      .fontWidth(.condensed)
+      .allowsTightening(true)
+      .textScale(.secondary)
+    Text(_literal: "Body")
+      .typesettingLanguage(.init("en"))
+      .flipsForRightToLeftLayoutDirection(true)
+    Text(_literal: "Head")
+      .accessibilityHeading(.h1)
+      .accessibilityAddTraits(.isHeader)
+    Image(systemName: "star")
+      .accessibilityLabel("Favorite")
+      .accessibilityHint("Adds it")
+      .accessibilityValue("1 stars")
+      .accessibilityAdjustableAction({fn})
+      .accessibilityAction(named: "Reset", {fn})
+      .accessibilityFocused($())
+      .accessibilitySortPriority(2)
+    HStack({fn})
+      Text(_literal: "A")
…
```

## tests/RestOfSwiftUITests-3.swift

```diff
--- before
+++ after
@@ -3,4 +3,63 @@
   Canvas({fn}, symbols: {fn})
-    If false
     Image(systemName: "star.fill")
       .tag(1)
+== after Canvas@5
+ContentView {}
+  Canvas({fn}, symbols: {fn})
+    Image(systemName: "star.fill")
+      .tag(1)
+== after Canvas@5
+ContentView {}
+  Canvas({fn}, symbols: {fn})
+    Image(systemName: "star.fill")
+      .tag(1)
+== after Canvas@5
+ContentView {}
+  Canvas({fn}, symbols: {fn})
+    Image(systemName: "star.fill")
+      .tag(1)
+== after Canvas@5
+ContentView {}
+  Canvas({fn}, symbols: {fn})
+    Image(systemName: "star.fill")
+      .tag(1)
+== after Canvas@5
+ContentView {}
+  Canvas({fn}, symbols: {fn})
+    Image(systemName: "star.fill")
+      .tag(1)
+== after Canvas@5
+ContentView {}
+  Canvas({fn}, symbols: {fn})
+    Image(systemName: "star.fill")
+      .tag(1)
+== after Canvas@5
+ContentView {}
+  Canvas({fn}, symbols: {fn})
+    Image(systemName: "star.fill")
+      .tag(1)
+== after Canvas@5
+ContentView {}
+  Canvas({fn}, symbols: {fn})
+    Image(systemName: "star.fill")
+      .tag(1)
+== after Canvas@5
+ContentView {}
+  Canvas({fn}, symbols: {fn})
+    Image(systemName: "star.fill")
+      .tag(1)
+== after Canvas@5
+ContentView {}
+  Canvas({fn}, symbols: {fn})
+    Image(systemName: "star.fill")
+      .tag(1)
+== after Canvas@5
+ContentView {}
+  Canvas({fn}, symbols: {fn})
+    Image(systemName: "star.fill")
+      .tag(1)
+== after Canvas@5
+ContentView {}
+  Canvas({fn}, symbols: {fn})
+    Image(systemName: "star.fill")
+      .tag(1)
```

## tests/RestOfSwiftUITests-6.swift

```diff
--- before
+++ after
@@ -3,4 +3,999 @@
   VStack({fn})
-    content failed
-    .transition(.blurReplace)
-error: Line 44: Cannot find 'MeshGradient' in scope
+    If false
+      RoundedRectangle(cornerRadius: 8)
+        .fill(Color)
+        .matchedGeometryEffect(id: "card", in: ())
+        .frame(width: 60, height: 60)
+    Text(_literal: "0")
+      .contentTransition(.numericText(0.0))
+      .font(Font)
+    Image(systemName: "bell")
+      .symbolEffect(.bounce.up.byLayer, options: .repeat(2), value: 0)
+    Image(systemName: "wifi")
+      .symbolEffect(.variableColor.iterative, isActive: false)
+    Image(systemName: "heart")
+      .phaseAnimator([1.0, 1.3, 1.0], trigger: 0, {fn}, animation: {fn})
+        NativeContent(AnyView)
+          .scaleEffect(1.0)
+        NativeContent(AnyView)
+          .scaleEffect(1.3)
+        NativeContent(AnyView)
+          .scaleEffect(1.0)
+    Text(_literal: "Keys")
+      .keyframeAnimator(initialValue: Values(scale: 1.0, lift: 0.0, angle: 0.0°), trigger: 0, {fn}, keyframes: {fn})
+        NativeContent(AnyView)
+          .scaleEffect(1.0)
+          .offset(y: 0.0)
+          .rotationEffect(0.0°)
+        KeyframeTrack(KeyPath, {fn})
+          LinearKeyframe(1.2, duration: 0.1)
+          SpringKeyframe(1.0, duration: 0.3, spring: Spring)
+        KeyframeTrack(KeyPath, {fn})
+          CubicKeyframe(-20, duration: 0.2)
+          MoveKeyframe(0)
+    Circle()
+      .union(<view>)
+        Rectangle()
+          .offset(x: 20)
+      .fill(Color)
+      .frame(width: 40, height: 40)
+    Capsule()
+      .inset(by: 4)
+      .rotation(20.0°)
+      .stroke(Color, lineWidth: 2)
+      .frame(width: 60, height: 30)
+    MeshGradient(width: 2, height: 2, points: [[0, 0], [1, 0], [0, 1], [1, 1]], colors: [Color, Color, Color, Color])
+      .frame(height: 40)
+    Text(_literal: "Glass")
+      .padding()
+      .glassEffect(.regular.tint.interactive, in: .capsule)
+    GlassEffectContainer(spacing: 8, {fn})
+      HStack({fn})
+        Text(_literal: "A")
+          .glassEffect()
+          .glassEffectID("a", in: ())
+        Text(_literal: "B")
+          .glassEffect()
+          .glassEffectUnion(id: "ab", namespace: ())
+    Text(_literal: "Blend")
+      .blendMode(.multiply)
+      .visualEffect({fn})
+        NativeContent(AnyView)
+          .offset(y: 4)
+    Text(_literal: "Tx")
+      .transaction({fn})
+    Rectangle()
+      .fill(<view>)
+        Color(Color)
+          .opacity(0.5)
+          .shadow(.drop(2))
+      .frame(height: 10)
+    Rectangle()
+      .fill(.linearGradient([Color, Color], .leading, .trailing))
+      .frame(height: 10)
+    Button("Go", {fn})
+    .transition(.blurReplace)
+== after Image.phaseAnimator@26
+ContentView {space=(), big=false, count=0, on=false}
+  VStack({fn})
+    If false
+      RoundedRectangle(cornerRadius: 8)
+        .fill(Color)
+        .matchedGeometryEffect(id: "card", in: ())
+        .frame(width: 60, height: 60)
+    Text(_literal: "0")
+      .contentTransition(.numericText(0.0))
+      .font(Font)
+    Image(systemName: "bell")
+      .symbolEffect(.bounce.up.byLayer, options: .repeat(2), value: 0)
+    Image(systemName: "wifi")
+      .symbolEffect(.variableColor.iterative, isActive: false)
+    Image(systemName: "heart")
+      .phaseAnimator([1.0, 1.3, 1.0], trigger: 0, {fn}, animation: {fn})
+        NativeContent(AnyView)
+          .scaleEffect(1.0)
+        NativeContent(AnyView)
+          .scaleEffect(1.3)
+        NativeContent(AnyView)
+          .scaleEffect(1.0)
+    Text(_literal: "Keys")
+      .keyframeAnimator(initialValue: Values(scale: 1.0, lift: 0.0, angle: 0.0°), trigger: 0, {fn}, keyframes: {fn})
+        NativeContent(AnyView)
+          .scaleEffect(1.0)
+          .offset(y: 0.0)
+          .rotationEffect(0.0°)
+        KeyframeTrack(KeyPath, {fn})
+          LinearKeyframe(1.2, duration: 0.1)
+          SpringKeyframe(1.0, duration: 0.3, spring: Spring)
+        KeyframeTrack(KeyPath, {fn})
+          CubicKeyframe(-20, duration: 0.2)
+          MoveKeyframe(0)
+    Circle()
+      .union(<view>)
+        Rectangle()
+          .offset(x: 20)
…
```

## tests/StreamsBridgeTests-5.swift

```diff
--- before
+++ after
@@ -7,3 +7,4 @@
 console: stream offline
-error: Line 9: Value of type 'URLSession' has no method 'webSocketTask'
+console: send offline
+console: receive offline
 ContentView {}
```

## tests/StreamsBridgeTests-6.swift

```diff
--- before
+++ after
@@ -7,4 +7,3 @@
 == appeared (List.task@9, List.task@15)
-error: Line 16: Value of type 'URLSession' has no method 'webSocketTask'
-ContentView {lines=[], socket=nil}
+ContentView {lines=[], socket=URLSessionWebSocketTask}
   List([], id: KeyPath, {fn})
```

## tests/WebBridgeTests-0.swift

```diff
--- before
+++ after
@@ -1,2 +1,336 @@
 == start
-error: Line 5: Cannot find 'WebPage' in scope
+ContentView {page=WebPage, answer="", showFind=false, position=ScrollPosition, offset=0.0}
+  NavigationStack({fn})
+    VStack({fn})
+      Text("")
+      ProgressView(value: 0.0)
+      Text("Idle")
+      Text("none")
+      WebView(WebPage)
+        .webViewBackForwardNavigationGestures(.enabled)
+        .webViewMagnificationGestures(.disabled)
+        .webViewLinkPreviews(.disabled)
+        .webViewTextSelection(.enabled)
+        .webViewContentBackground(.hidden)
+        .webViewElementFullscreenBehavior(.enabled)
+        .findNavigator(isPresented: $false)
+        .webViewScrollPosition($ScrollPosition)
+        .webViewOnScrollGeometryChange(for: Double, of: {fn}, {fn})
+      WebView(url: URL(https://example.com))
+        .frame(height: 100)
+      Text("")
+      Button("Back", {fn})
+      Button("Reload", {fn})
+      .task({fn})
+== appeared (VStack.task@36)
+ContentView {page=WebPage, answer="", showFind=false, position=ScrollPosition, offset=nil}
+  NavigationStack({fn})
+    VStack({fn})
+      Text("")
+      ProgressView(value: 0.1)
+      Text("Loading")
+      Text("about:blank")
+      WebView(WebPage)
+        .webViewBackForwardNavigationGestures(.enabled)
+        .webViewMagnificationGestures(.disabled)
+        .webViewLinkPreviews(.disabled)
+        .webViewTextSelection(.enabled)
+        .webViewContentBackground(.hidden)
+        .webViewElementFullscreenBehavior(.enabled)
+        .findNavigator(isPresented: $false)
+        .webViewScrollPosition($ScrollPosition)
+        .webViewOnScrollGeometryChange(for: Double, of: {fn}, {fn})
+      WebView(url: URL(https://example.com))
+        .frame(height: 100)
+      Text("")
+      Button("Back", {fn})
+      Button("Reload", {fn})
+      .task({fn})
+== after Button[Back]@31
+ContentView {page=WebPage, answer="", showFind=false, position=ScrollPosition, offset=nil}
+  NavigationStack({fn})
+    VStack({fn})
+      Text("")
+      ProgressView(value: 0.1)
+      Text("Loading")
+      Text("about:blank")
+      WebView(WebPage)
+        .webViewBackForwardNavigationGestures(.enabled)
+        .webViewMagnificationGestures(.disabled)
+        .webViewLinkPreviews(.disabled)
+        .webViewTextSelection(.enabled)
+        .webViewContentBackground(.hidden)
+        .webViewElementFullscreenBehavior(.enabled)
+        .findNavigator(isPresented: $false)
+        .webViewScrollPosition($ScrollPosition)
+        .webViewOnScrollGeometryChange(for: Double, of: {fn}, {fn})
+      WebView(url: URL(https://example.com))
+        .frame(height: 100)
+      Text("")
+      Button("Back", {fn})
+      Button("Reload", {fn})
+      .task({fn})
+== after Button[Reload]@34
+ContentView {page=WebPage, answer="", showFind=false, position=ScrollPosition, offset=nil}
+  NavigationStack({fn})
+    VStack({fn})
+      Text("")
+      ProgressView(value: 0.1)
+      Text("Loading")
+      Text("about:blank")
+      WebView(WebPage)
+        .webViewBackForwardNavigationGestures(.enabled)
+        .webViewMagnificationGestures(.disabled)
+        .webViewLinkPreviews(.disabled)
+        .webViewTextSelection(.enabled)
+        .webViewContentBackground(.hidden)
+        .webViewElementFullscreenBehavior(.enabled)
+        .findNavigator(isPresented: $false)
+        .webViewScrollPosition($ScrollPosition)
+        .webViewOnScrollGeometryChange(for: Double, of: {fn}, {fn})
+      WebView(url: URL(https://example.com))
+        .frame(height: 100)
+      Text("")
+      Button("Back", {fn})
+      Button("Reload", {fn})
+      .task({fn})
+== after Button[Back]@31
+ContentView {page=WebPage, answer="", showFind=false, position=ScrollPosition, offset=nil}
+  NavigationStack({fn})
+    VStack({fn})
+      Text("")
+      ProgressView(value: 0.1)
+      Text("Loading")
+      Text("about:blank")
+      WebView(WebPage)
+        .webViewBackForwardNavigationGestures(.enabled)
+        .webViewMagnificationGestures(.disabled)
+        .webViewLinkPreviews(.disabled)
+        .webViewTextSelection(.enabled)
+        .webViewContentBackground(.hidden)
+        .webViewElementFullscreenBehavior(.enabled)
+        .findNavigator(isPresented: $false)
+        .webViewScrollPosition($ScrollPosition)
+        .webViewOnScrollGeometryChange(for: Double, of: {fn}, {fn})
+      WebView(url: URL(https://example.com))
+        .frame(height: 100)
…
```
