# Plan: Shelf fixes, then Shelf's own Kiln

Shelf runs each app's Swift source on the phone with [Kiln](https://github.com/haplollc/Kiln), an interpreter. This plan first fixes Shelf itself, then takes Kiln in house and rebuilds it, then widens what apps can use, one round at a time, in order of difficulty:

0. **Shelf fixes (§0).** Audit the Home Screen's behaviour, delete apps, Automatic/Light/Dark icons in place of Clear, the dock's shape, a card that stays on screen during a swipe up, and a new launch screen.
1. **The rewrite (§1).** Kiln moves into this repo and is rebuilt on a design that can grow: one engine, real `async`, and one small bridge per component in a registry that also drives the checker, the prompt and a coverage report.
2. **Round 1: the rest of SwiftUI (§2).** Every public view and modifier in the iOS 27 SDK is either supported or on a written won't-do list.
3. **Round 2: APIs with no permission prompt (§3).** Haptics, share and paste, text parsing, unit conversion, audio playback, `WebView`, `Chart3D`, WebSockets.
4. **Round 3: device and permission APIs (§4).** Files, the photo picker, the camera, audio recording, Core Motion, location.
5. **Round 4: on-device intelligence (§5).** Vision, VisionKit, Foundation Models.
6. **Round 5: widgets on Shelf's Home Screen (§6).** Apps declare them with WidgetKit's API, and Shelf hosts them in process, beside the icons.

Maps stay out. The [won't-do list](#wont-do) has the reasons for everything else that's left out.

Nothing here is built yet.

---

## Research findings

| Finding | Source | What it changes |
|---|---|---|
| Upstream's latest tag is `0.2.1`, and every commit since it (the last on 6 Nov 2026) only changes documentation. It's MIT-licensed. | GitHub API | Fork it, keep the licence and credit, and don't wait on upstream. |
| Kiln is 21.8k lines. About 11k of them are the first interpreter (`Parser/`, `Runtime/`, `Renderer/`, `Interpreter/`, `SwiftRunner.swift`), which runs only when the source mentions `GameCanvas(`, `BarChart(` and the like, even in a comment. | `Engine/KEEngine.swift:37` | Delete it, along with the prompt's warning about those names. |
| Components and modifiers are string `case`s in three large files: `KERenderer.swift` (1,366 lines), `KEModifiers.swift` (718) and `KEBuiltins.swift` (1,898). Anything unknown is skipped silently. | Source | Covering all of SwiftUI needs a registry, not longer switches (§1.4). |
| `async` isn't real: `await` blocks the main thread (at most 20 s), `Task.sleep` returns at once, and `Task {}` runs straight through. | `KENetwork.swift:72`, `KEBuiltins.swift:494,815` | The rewrite has to suspend and resume (§1.3). The photo picker, Foundation Models, Vision, WebSockets, `WebPage` and `CLLocationUpdate` all need it. |
| Shelf's `DB` depends on that blocking: the prelude is Swift that `await`s `URLSession` inside a non-`async` function, and `ShelfDBProtocol` answers off the main actor because Kiln holds the main thread while it waits. | `Shelf/Data/Prelude.swift`, `ShelfDBProtocol.swift:17` | `DB` becomes a host bridge that reads the local store synchronously (§1.7). The prelude and the `db://` protocol go away. |
| `Kiln.register` bridges are read only by the old interpreter. | `grep nativeBridges` | The new registry has to accept bridges from the host too (§1.4). |
| `@AppStorage` lives in `UserDefaults.standard`, which every app shares, so Shelf rewrites keys in the source. | `SourceRewriter.swift` | Each run gets its own defaults suite instead (§1.7). |
| The SDK on this Mac (iOS 27.1, Xcode 27.1 beta) ships `SwiftUI.swiftinterface` and the cross-framework overlays (`_WebKit_SwiftUI`, `_PhotosUI_SwiftUI`, `_Translation_SwiftUI`, `_Vision_FoundationModels`…). | `xcrun --show-sdk-path` | The coverage report reads them (§1.9). That's what "all of SwiftUI" means. |
| iOS 27's SwiftUI adds `.swipeActions` outside `List` (with `swipeActionsContainer`), `.reorderable()` with `reorderContainer(for:)`, toolbar `visibilityPriority` and minimize behaviour, a cross-fade navigation transition, a `Document` protocol, and `@State` as a macro. | [What's new in SwiftUI, WWDC26](https://developer.apple.com/videos/play/wwdc2026/269/), [SwiftUI updates](https://developer.apple.com/documentation/updates/swiftui), [Swift with Majid](https://swiftwithmajid.com/2026/06/08/what-is-new-in-swiftui-after-wwdc26/) | These go in Round 1. Blogs disagree on some names, so the SDK interface decides. |
| iOS 27 has no new calendar control. The calendar is `DatePicker` with `.graphical`, which iOS 27 redraws, plus `MultiDatePicker`. | [HIG pickers, 26 vs 27](https://developerguidelines.com/human-interface-guidelines/version/27/pickers/) | Bridge every `DatePicker` style and `MultiDatePicker`. |
| SwiftUI has no camera view. `onCameraCaptureEvent` (iOS 26) handles the hardware button for an AVFoundation session, and `CameraCaptureAccessory` (iOS 27.1) decorates one. Apple's own camera sample wraps UIKit. | [WWDC25 session 253](https://developer.apple.com/videos/play/wwdc2025/253/), [CameraCaptureAccessory](https://developer.apple.com/documentation/swiftui/cameracaptureaccessory) | The camera comes from `UIImagePickerController` in a `UIViewControllerRepresentable`, which is what models write anyway (§4.3). |
| `WebView` and `WebPage`, `Chart3D` with `SurfacePlot`, and `TextEditor` bound to `AttributedString` are all iOS 26. | [WWDC25 sessions 256, 280 and 313](https://developer.apple.com/videos/play/wwdc2025/313/), [InfoQ](https://www.infoq.com/news/2025/06/swiftui-ios26-liquid-glass) | Rounds 1 and 2. |
| Foundation Models in iOS 27 adds a `LanguageModel` protocol, a Private Cloud Compute model, and built-in tools. The SDK has Vision's `OCRTool` and `BarcodeReaderTool`. `DynamicGenerationSchema` builds a schema at runtime. Apple says to re-test prompts on the iOS 27 model. | [WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/), [Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels), SDK | `@Generable` can work in an interpreter by building a dynamic schema from the struct (§5.3). |
| Vision's Swift API is `async`: `RecognizeTextRequest` (iOS 18) and `RecognizeDocumentsRequest` (iOS 26), each run with `perform(on:)`. | [Vision docs](https://developer.apple.com/documentation/vision), [WWDC25 session 272](https://developer.apple.com/videos/play/wwdc2025/272/) | Round 4, after real `async`. |
| `CLGeocoder` is deprecated in iOS 26 in favour of MapKit's `MKReverseGeocodingRequest` and `MKGeocodingRequest`, which don't draw a map. | [MKReverseGeocodingRequest](https://developer.apple.com/documentation/mapkit/mkreversegeocodingrequest), [forum 795687](https://developer.apple.com/forums/thread/795687) | Geocoding comes in with location. MapKit's views stay out. |
| `_CoreMotion_SwiftUI` is in the SDK, but its interface is empty. | SDK | Core Motion is bridged from `CoreMotion` itself. |

---

## 0. Shelf fixes, first

Six fixes to Shelf itself. None of them touches Kiln, so they come first and can run alongside the §1.3 spike. The order:

1. **The audit comes first.** Deleting apps and widgets both change edit mode and the layout, so the rules they build on should be right and under test first.
2. **Deleting apps next.** It's the biggest missing feature.
3. **Then the two visual fixes** (icons, dock).
4. **Then the two runner fixes** (swipe up, launch screen). Half of the launch screen work has to wait for the rewrite.

### 0.1 Audit the Home Screen's behaviour

Write down Springboard's rules as tests, then drive each case on the simulator with `agent-device` and compare it with `design/reference/springboard/`. Each finding becomes a test and a fix. The cases to check, none of them confirmed broken yet:

- **Layout:**
  - where a new app lands (the first free slot on the last page);
  - a drop on a full page pushing its last icon on, and that push cascading;
  - a full dock refusing a newcomer;
  - dragging the only icon off a page, so the page you're on disappears (`page` and the scroll position must follow);
  - the spare page in edit mode, and leaving edit mode with it empty.
- **Syncs that land mid-gesture:**
  - an app added or deleted elsewhere while icons are being dragged;
  - the dragged app itself deleted;
  - `reconcile` running during a drop.
- **Cards:**
  - an app deleted elsewhere while its card is open, or on its way home (it should land in the pill, which `CardMotion.landing` handles, and must never reopen a missing app);
  - a tap on another icon while a card is closing;
  - a tap on an app that hasn't downloaded;
  - a quick double tap;
  - a tap during a page scroll.
- **Long press:** the menu versus a drag (in and out of edit mode), a long press on the wallpaper while searching, and edit mode starting while search is open.
- **Search:** result order, and where a card opened from a result lands (an icon on another page leaves past that side of the screen; with no icon it lands in the pill).
- **Leaving Shelf:** going to the background during a drag (handled), with a card open, and with a sheet up. What each looks like on return.
- **Persistence:** when `commitLayout` writes, what a corrupt `layout.json` does, and whether the current page survives a relaunch.
- **Settings becomes an ordinary icon** (decided). Today it's fixed in the dock's last place, which Springboard has no equivalent of.
  - It moves like any icon, to any page or within the dock, and starts in the dock's last place.
  - It can't be deleted: no minus badge, no Delete App in its menu. Its menu has only Edit Home Screen.
  - `Layout` holds it under a reserved ID that can never be an app slug (slugs are lowercase letters, digits and hyphens, so something like `:settings`). `reconcile` always keeps it.
  - `dockSize` becomes 4, shared with Settings.
  - A v1 `layout.json` gains it at the end of the dock, or at the front of the first page if the dock is full.
  - A tap opens the Settings sheet, not a card, and search finds it, as Springboard's search finds Settings.
- **VoiceOver:** icon order, and custom actions to move and delete (Springboard has them).

**Done when:** every case has a test (in `LayoutTests`, or a new `HomeModelTests`), or a recorded simulator check, and the fixes are in.

### 0.2 Deleting apps

As on Springboard, with no App Library, so it's "Delete App", not "Remove App":

- **Where:**
  - a minus badge on every icon in edit mode (top left, ≈ 25 pt grey circle, `closeup-edit-badge-icon.png`), except Settings;
  - Delete App, in red, last in the icon's long-press menu (`longpress-menu-grid-photos.png`).
- **Confirming:** an alert, "Delete “Habits”?", saying that everything goes with it, on every device, and can't be undone. Delete or Cancel.
- **Deleting removes everything** (decided). There's no option to keep anything:
  - on the server: the app, every revision Revert could reach, its `DB` data, and its unused install keys;
  - on every phone: the source, the `DB` store with pending writes, the `@AppStorage` suite, the app's files (§4.1), its launch snapshot (§0.6), its permission grants (§4.0), and its widgets (§6).
- **The server:** `DELETE /api/apps/{slug}?data=delete` already exists on `shelf-apps` (`fixtures/api/app-delete.json`). Check that it also purges the revisions and the slug's install keys, and add that where it doesn't. A 404 means it's already gone, which counts as success.
- **Other devices:** they learn from their next sync that the app is gone, and run the same local cleanup. `SyncEngine` already removes the source and `@AppStorage` for apps that leave the index; that grows to everything in the list above.
- **On the phone:**
  - `API.deleteApp`, and `LibraryStore.delete`;
  - the icon shrinks and fades as Springboard's does, and the others close up;
  - everything local in the list above goes at once.
- **Offline:** the deletion is queued in a persisted list that the next sync sends before it lists apps. Until then, the listing hides those apps.
- **Failure** (other than offline or a 404): the icon comes back, and the failure follows the same rule as a failed sync or Revert.
- **Tests:** `APITests` against the fixture, and `LibraryStoreTests` for online, offline, and failure with the icon restored. `FakeServer` gains DELETE.

### 0.3 Icon appearance: Automatic, Light, Dark

- **Remove Clear:** `IconStyle.clear`, `IconGlass`, the Clear branch in `CardFace`, and the Icon Style picker. A stored `clear` reads as Automatic.
- **Add `IconAppearance`** (Automatic, Light, Dark) to `ShelfSettings`, shown in Settings as a segmented picker with a row of live icons.
  - Automatic follows the system.
  - Light and Dark hold the icons there whatever the system does, as Springboard's Customize panel does.
- **Resolve it once,** as an environment value (say `iconScheme`) that every icon reads instead of `colorScheme`:
  - the grid, the dock (Settings' icon included) and search results;
  - the long-press and drag previews;
  - the New App preview;
  - `CardFace`, so a card opens from and closes into the icon you see;
  - widgets later (§6.3).

  Labels, the dock's glass and the wallpaper follow the system, not this setting.
- **Tests:** each place resolves through the one value, a stored `clear` migrates, and screenshots in both appearances with the system in each.

### 0.4 The dock's shape

Today the dock is `.rect(cornerRadius: max(displayRadius − 17, iconRadius + padding), style: .continuous)`, 368 × 103.3 pt, and it doesn't read as Springboard's.

- **Measure it the way the icon corners were measured.** Take the inset of the dock's left edge on each pixel row, at 3x, in `home-page1-light.png` and `closeup-dock-left-corner.png`, and do the same on a Shelf screenshot from the same simulator. Overlay the two at 50%. Check the rim (a 1 px lighter hairline) and the fill too.
- **Then pick the shape from the numbers:**
  - iOS 26's `ConcentricRectangle` inside the display's container shape, which is likely what Springboard draws;
  - a larger radius, since the reference notes say "nearly a pill";
  - or a custom outline.
- **Apply it everywhere the dock's outline is used:** the glass, the drop target, and anything that animates against it.
- **Record** the table in `design/reference/README.md` next to the icon-corner one.

The real-device captures use non-default glass, so compare against the simulator stills only.

### 0.5 Swiping up: the card stays on screen

- **Today:** `CardMotion.tracked` keeps the point under the finger fixed as the card shrinks, and moves the card 1:1 with the finger. A long swipe up carries the card's top edge off the top of the screen. Springboard's card stays on screen.
- **The rule:**
  - the card's top edge is held at a limit near the top of the screen, past which vertical movement is rubber-banded;
  - the scale keeps following the drag, and horizontal movement is unchanged;
  - the release decision and the landing spring use the drag's real travel and velocity, so a flick still closes;
  - the drag down from the status bar gets the mirrored limit at the bottom edge.
- **Measure first.** The simulator can't perform the home gesture (see the reference README). Record a slow, long swipe up on a real iPhone, pull frames, and plot the card's top against the finger to get the limit and the resistance. Keep the recording and notes in `design/reference/springboard/`.
- **Tests in `MotionTests`:**
  - the card's top never passes the limit for any translation;
  - the point under the finger holds until the limit;
  - nothing jumps when crossing it;
  - a card caught mid-flight above the limit is picked up where it is.

### 0.6 The app's launch screen

**Today:** opening an app fills the screen with its tint and a white glyph (`AppStage.LaunchScreen`, and the card's face at full size). Kiln only starts building once the open has come to rest, because parsing on the main thread would make the motion stutter. So every open shows a saturated slab for at least the build time, then cuts to an app that's usually plain white or black. No system app opens like that.

**New:**

1. **The card's face crossfades from the icon to the launch surface early in the open,** within about the first third of its growth. That's Springboard's close crossfade (`app-close-frames.png`, #6–#8) in reverse.
2. **The launch surface is the app's last snapshot** when one is fresh: same source revision, same light or dark, same text size. It's taken when the card closes and cached per app in Caches. iOS does the same for apps it resumes.
3. **With no snapshot,** it's the system background, or the grouped background when the app's root is a `List` or `Form` (a cheap check of the source), with an empty navigation bar if the app has a `NavigationStack`. No glyph and no tint.
4. **The built app** replaces the surface with a short crossfade, and so does the error screen. The New App preview uses the same surface, without a snapshot.
5. **After the rewrite: build sooner.** With the VM, parsing and lowering can leave the main thread. Start them on touch-down, so the app is usually ready when the card comes to rest.

**Before merging:** screenshots of the open in light and dark, before and after, are approved. Items 1–4 come first; 5 lands after §1.

---

## 1. The rewrite

Kiln becomes Shelf's package. The parser and the value model are kept. The way code runs, the way components are bridged, and the host API are rebuilt. Nothing new is added until everything 0.2.1 runs still runs (§1.11).

### 1.1 Into the repo

- Copy Kiln 0.2.1 with `Vendor/kiln-0.2.1.patch` applied into `Packages/Kiln/` and commit it. Keep `LICENSE`, and credit upstream in `Packages/Kiln/README.md` and Shelf's README.
- Delete `Vendor/`, the clone-and-patch half of `Scripts/bootstrap.sh`, and the `Vendor/Kiln/` line in `.gitignore`. In `project.yml`, the package path becomes `Packages/Kiln`.
- The module stays `Kiln`, so `import Kiln` and Shelf's call sites don't change.
- Fixes that would help upstream are kept as separate commits, in case we offer them back. Nothing waits on that.

### 1.2 One engine

- Delete the old interpreter: `Parser/`, `Runtime/`, `Renderer/`, `Interpreter/`, `SwiftRunner.swift`, whatever in `Validator/` only it uses, the tests that only cover it, and `Kiln.engine`.
- Delete the dialect check in `KEEngine.swift`, and the prompt's "don't write `GameCanvas(`" rule.

### 1.3 Code that can wait: bytecode and a resumable VM

Code runs on a small bytecode VM instead of walking the syntax tree:

- **Lowering.** The parser (`KELexer`, `KEParser`, `KEAST`) stays. A lowering pass turns each function, closure, initializer, computed property and `body` into bytecode, keeping a line number for every instruction so errors still name the author's line.
- **Frames on the heap.** Calls push frames the VM owns, not Swift stack frames. So a running function can stop at an `await` and pick up later with its locals intact.
- **Everything runs on the main actor**, like a SwiftUI app's own code. A native `async` call (a URL load, `loadTransferable`, `respond(to:)`, a `perform(on:)`) parks the current task, runs natively, and resumes the VM on the main actor with the result or the error.
- **Code that can't wait.** `body`, computed properties and `init` run to the end, as in compiled Swift. An `await` there is a check-time error (§1.8).
- **What the app gets:**
  - `Task {}` and `Task.detached {}`, the latter still run on main.
  - `.task {}` and `.task(id:)`, cancelled when the view goes away.
  - `Task.sleep(for:)` and `Task.sleep(nanoseconds:)`, which really wait.
  - `Task.isCancelled` and `checkCancellation()`.
  - `async let`, and `withTaskGroup` and `withThrowingTaskGroup`.
  - `for await` over native `AsyncSequence`s and the app's own `AsyncStream`s.
  - `await MainActor.run {}`.
- **Budget.** The step limit applies to each stretch of code between two waits, not to the whole run. A long-lived task that waits between steps never trips it, and a runaway loop still stops with its line.
- **Speed.** Bytecode with resolved slots should beat dictionary lookups on a tree. Before the switch, measure 0.2.1 with `Tools/KilnBench` on the example apps and Shelf's fixtures. The VM must not be slower anywhere.
- **Risk.** This is the largest single piece. Spike it first: the VM runs `Examples/Apps` and Shelf's `fixtures/apps/` with output identical to 0.2.1's, with no bridges changed. If the VM stalls, the fallback is a second, `async` evaluator used only for code that contains `await` (Swift marks those places, so they're known when the source is read). It duplicates code but is less risky.

### 1.4 Bridges in a registry

Each native thing Kiln knows is a small bridge, declared in one place:

- **View bridges** (`DatePicker`, `WebView`, `Chart3D`…): one or more overloads, each a label list with argument kinds, availability, and a function that builds the real view.
- **Modifier bridges**, declared the same way.
- **Type bridges** for native types the app constructs or calls: initializers, static members, methods, properties (`Measurement`, `CMMotionManager`, `NLTagger`…). `async` methods return a suspension the VM waits on.
- **Protocol bridges**, so native code can call into the app's own types (§1.5).
- **Host bridges**: Shelf registers its own (`DB`, and later the permission gate) through the same API.

The rest is mechanical:

- **Files:** bridges live in `Packages/Kiln/Sources/Kiln/Bridges/<Family>/`. One family per file group: Controls, Layout, Lists, Navigation, Gestures, Drawing, Charts, Haptics, Sharing, Text, Units, Audio, Web, Files, Photos, Camera, Motion, Location, Vision, Intelligence, Widgets.
- **Arguments:** shared helpers decode and check them (`call.binding("selection", Date.self)`, `call.optional("in", ClosedRange<Date>.self)`, `call.content()`, `call.shapeStyle(0)`), so each bridge is a few lines and every error message reads the same.
- **Observation:** native `@Observable` objects (`WebPage`, `LanguageModelSession`, `CLServiceSession`…) are read inside the real SwiftUI `body` call, so SwiftUI's own observation tracking sees those reads. A test pins this down.
- **Porting:** every component, modifier and built-in in the three switch files is moved into the registry, and the switches are deleted.

### 1.5 Native code calling the app's code

Closures already cross from native code into the app (completion handlers, `Button` actions). The rewrite adds **protocol proxies**: a native class per bridged protocol that forwards each requirement to the matching method on the app's interpreted value. These are needed for:

- delegates: `CLLocationManagerDelegate`, `UIImagePickerControllerDelegate`, `DataScannerViewControllerDelegate`;
- `UIViewControllerRepresentable` with `makeCoordinator`, for an allowlist of bridged UIKit controllers;
- `Layout`, `Shape`, `Animatable`, `Transition`, `ViewModifier`;
- `Transferable` and `FileDocument`;
- Foundation Models' `Tool`;
- WidgetKit's `TimelineProvider` and `AppIntent`.

`async` requirements (a `Tool`'s `call`, an intent's `perform`) run as VM tasks the native side awaits. Proxies are declared in the registry, so the checker knows which protocols an app's types can adopt.

### 1.6 Swift that should work and doesn't

From the prompt's "What doesn't work", Shelf's fixtures, and the 0.2.1 patch:

- Protocol extensions and default implementations, and real conformance checks where behaviour depends on them (`Identifiable`, `Hashable`, `Comparable`, `CaseIterable`).
- `@resultBuilder`: at least `@ViewBuilder` functions and properties, and RegexBuilder (§3.3).
- Custom property wrappers: `wrappedValue` and `projectedValue`.
- Custom `init(from:)` and `encode(to:)`, and `Set` round-tripping as a set.
- Regex literals (`/\d+/`) in the lexer.
- A one-sided range in a `case` (`case 90...:`), calling a method straight on `allCases`, `$value.animation()`, and `Data(text.utf8)`.
- Fold in the 0.2.1 patch's three fixes: `JSONEncoder().encode`, `[T].self`, and a decoded `UUID` staying a `UUID`.
- Macros the engine reads as declarations: `@Observable` (already), `@Entry`, `@Animatable` (iOS 26), `@Generable` and `@Guide` (Round 4), plus `#Preview`, which is ignored.

### 1.7 A context for each run

`Kiln.run(source, context:)` replaces Shelf's workarounds. A context carries:

- **Identity:** the app's slug and display name, for errors and permission prompts.
- **Defaults:** a `UserDefaults` suite per app, which `@AppStorage` and `UserDefaults.standard` resolve to. `SourceRewriter`'s key rewriting is deleted.
- **Files:** the app's own folder, which `URL.documentsDirectory`, `.applicationSupportDirectory` and `FileManager` resolve into (§4.1).
- **Host bridges:** `DB.load`, `DB.save` and `DB.remove` become native and synchronous, over the local store that `AppData` already keeps. `Prelude.swift`, `ShelfDBProtocol` and the `DB-Key` header go away. Sync is unchanged.
- **Capabilities:** a gate the host answers per app (§4.0), and a stub mode for checking, so `validate` fires actions without touching sensors, files or the network.
- **Teardown:** when the card closes, Kiln cancels the app's tasks and stops motion, location, audio, WebSockets and web pages.
- **Errors:** check errors and runtime errors both reach the host, with lines. Today a runtime error in a `body` shows as Kiln's own red label, which Shelf never sees.

### 1.8 Checking before running

- `Kiln.check(source)`: static and fast. It resolves every type, member and modifier against the registry and the app's own declarations. An unsupported API is an error with a line number, not silence. It also reports `await` where waiting isn't allowed, missing protocol requirements, and the wrong types for bridged arguments.
- `Kiln.validate(source)`: the existing headless run of every view and action, now with the context's stubs, so it's safe on the phone. Shelf runs both in the New App preview before Install. That covers the old "validate before save" item.
- **A manifest.** The registry exports `kiln-manifest.json`: every supported symbol, its availability, and notes for authors. Shelf's prompt builds its "What works" section from it (§7), so the prompt can't promise what Kiln doesn't run.

### 1.9 The coverage report

`Packages/Kiln/Tools/coverage` reads the SDK's interfaces (`SwiftUI`, `Charts`, `_WebKit_SwiftUI`, `_PhotosUI_SwiftUI`, `_Translation_SwiftUI` and the other overlays) and lists every public `View` type, every `View` and `Shape` modifier, and every style. It compares them with the registry and writes `Packages/Kiln/COVERAGE.md`, with counts per family, everything missing, and a **won't-do** section where each entry has a one-line reason. Run it after each round and after each Xcode update.

### 1.10 Tests

- **Kiln Lab stays.** It shows the same app compiled natively and run by Kiln, and one UI test drives both and compares them. Each round adds an example app per family it touches.
- **Unit tests per bridge:** arguments decode, overloads resolve, the view builds, check errors read correctly.
- **Shelf's `fixtures/apps/`:** one app per section of the prompt, enforced by `everyPromptSectionHasAFixture`. The manifest-built prompt gets new sections, so each round adds fixtures.
- **Sensors in tests.** Motion, location, the camera and models come through the context. Tests and the simulator use fakes, and the real phone is checked by hand at the end of each round.
- **Performance:** `KilnBench` runs in `Tools/iterate.sh`, and a regression past 10% on any benchmark blocks the merge.

### 1.11 Done when

- Kiln's example apps match native in Lab, as they do on 0.2.1.
- Every one of Shelf's fixtures and `FeatureFixtureTests` passes, with `SourceRewriter`, `Prelude` and `ShelfDBProtocol` deleted.
- The 0.2.1 switch files are gone, and every bridge is in the registry.
- The coverage report runs, and its numbers are the baseline for Round 1.
- Real `async` works: a fixture that sleeps, fetches with `try await`, and streams with `for await`.
- The prompt is built from the manifest, and its "What doesn't work" section is regenerated from what actually fails.

---

## 2. Round 1: the rest of SwiftUI

Driven by the coverage report. "Done" means every public view and modifier in the iOS 27 SDK's SwiftUI is bridged or in won't-do. These are the families, with what's missing today or easy to miss:

- **Controls:**
  - every `DatePicker` style, including `.graphical` (iOS 27's calendar), and `MultiDatePicker`;
  - all `Picker` styles (`.palette`, `.inline`, `.navigationLink`);
  - `Slider` with tick marks (iOS 26), `ColorPicker` with opacity;
  - `Toggle` and `Gauge` styles;
  - `TextField(axis: .vertical)`, `SecureField`, and `TextEditor` bound to `AttributedString` (iOS 26);
  - `Text` from `AttributedString` and Markdown, and `Text(timerInterval:)`;
  - `Link`, `RenameButton`, `ControlGroup`, and a `Menu` with a `primaryAction`.
- **Layout:**
  - the `Layout` protocol (through a protocol proxy), `ViewThatFits`, and `Grid` alignment;
  - `containerRelativeFrame`, `safeAreaInset`, and `contentMargins`;
  - `scrollTargetBehavior`, `scrollPosition`, and `onScrollGeometryChange`;
  - `Group(subviews:)` and `ForEach(subviews:)`.
- **Lists and collections:**
  - `List` selection, `listRowBackground`, and `sectionIndexLabel`;
  - from iOS 27, `.swipeActions` on any view in a scroll container, with `swipeActionsContainer`, and `.reorderable()` with `reorderContainer(for:)`.
- **Navigation and presentation:**
  - `NavigationSplitView`, and `navigationTransition(.zoom)` with `matchedTransitionSource`;
  - iOS 27's cross-fade transition;
  - sheets with detents, `.popover`, `.fullScreenCover`, and `.inspector`;
  - toolbars with `ToolbarSpacer` (iOS 26), iOS 27's `visibilityPriority` and minimize behaviour, and every placement;
  - `TabView` with `Tab` and `Tab(role: .search)`, `tabViewBottomAccessory`, and `tabBarMinimizeBehavior`.
- **Gestures:**
  - `TapGesture`, `SpatialTapGesture`, `LongPressGesture`, `DragGesture`, `MagnifyGesture` and `RotateGesture`;
  - `.gesture`, `.simultaneousGesture` and `.highPriorityGesture`, `@GestureState` with `.updating`, and composed gestures.
  - Fixtures check they don't fight Shelf's own close gestures (a swipe up from the bottom edge, a drag down from the status bar).
- **Drawing and effects:**
  - `Canvas` with `GraphicsContext`, and `Path` as a view;
  - `matchedGeometryEffect` with `@Namespace`;
  - `glassEffect`, `GlassEffectContainer`, the `.glass` and `.glassProminent` button styles, and `backgroundExtensionEffect`;
  - `phaseAnimator` and `keyframeAnimator`, `contentTransition(.numericText())`, and `symbolEffect`;
  - `visualEffect` and `MeshGradient`;
  - custom `Animatable` and `Transition`, and `@Animatable` (iOS 26).
- **Focus and the keyboard:** `@FocusState` that really moves focus, `.focused`, `.onSubmit`, `.scrollDismissesKeyboard`, `.keyboardType`, and `.textContentType`.
- **Environment:**
  - `colorScheme`, `dynamicTypeSize`, `horizontalSizeClass`, and `openURL`;
  - `scenePhase`, which is `.active` while the app's card is open;
  - custom keys with `@Entry`, and the app's own `@Observable` types in `@Environment`.
- **Swift Charts:**
  - every mark, and `LinePlot` and `AreaPlot` for functions;
  - `chartXSelection` and `chartScrollableAxes`;
  - annotations, legends and axis customisation.

**Prompt:** each family gets its line in "What works", built from the manifest. **Fixtures:** one app per family. **Lab:** one example app that uses gestures, `Canvas` and focus, compared against native.

---

## 3. Round 2: APIs with no permission prompt

Needs §1.3 (`async`) and §1.4 (type bridges), but no Info.plist keys.

### 3.1 Haptics
- `.sensoryFeedback` in every form: with a trigger, with a condition closure, and returning a feedback from a closure.
- `UIImpactFeedbackGenerator`, `UINotificationFeedbackGenerator` and `UISelectionFeedbackGenerator`, because models write them.
- Out: custom Core Haptics patterns. They're on the Later list.

### 3.2 Share and paste
- `ShareLink` for `String`, `URL`, `Image` and `Data`, with `preview:`, `subject:`, `message:` and arrays of items.
- `PasteButton(payloadType:)`, `UIPasteboard.general` (`string`, `strings`, `url`, `image`, `hasStrings`), and `.textSelection(.enabled)`.
- `Transferable` for the app's own types, through the protocol proxy: `CodableRepresentation`, `DataRepresentation` and `ProxyRepresentation`.

### 3.3 Text parsing
- `Regex` from literals and from strings: `firstMatch`, `wholeMatch`, `matches(of:)`, `replacing(_:with:)`, `split(separator:)`, captures and named captures. Plus RegexBuilder (`Capture`, `TryCapture`, `OneOrMore`, `ZeroOrMore`, `Optionally`, `ChoiceOf`, `Anchor`, character classes), which needs §1.6's result builders.
- `NSRegularExpression`, `NSDataDetector` (dates, links, phone numbers, addresses), and `Scanner`.
- NaturalLanguage: `NLTokenizer`, `NLTagger` (lexical class, name type, lemma, sentiment), `NLLanguageRecognizer`, and `NLEmbedding`.
- Parse strategies: `Date(_:strategy:)`, `Double(_:format:)`, and `Decimal`.
- `AttributedString(markdown:)`, and `localizedStandardContains`.

### 3.4 Unit conversion
- `Measurement` with every `Dimension` Foundation ships (`UnitLength`, `UnitMass`, `UnitTemperature`, `UnitVolume`, `UnitSpeed`, `UnitDuration`, `UnitEnergy`, …).
- Conversion, arithmetic and comparison.
- `.formatted(.measurement(width:usage:))` and `MeasurementFormatter`.
- `Locale.current.measurementSystem`, and custom units with `UnitConverterLinear`.
- Out: subclassing `Dimension` in app code.

### 3.5 Audio playback
- `AVAudioPlayer(data:)` and `AVAudioPlayer(contentsOf:)` for files in the app's folder, and `AVPlayer(url:)` for streams.
- `AudioServicesPlaySystemSound`, and `AVSpeechSynthesizer` with its voices.
- Shelf owns `AVAudioSession`: playback, mixing with other audio, and stopped when the card closes.
- Out: real-time render callbacks (`AVAudioSourceNode`).

### 3.6 Web
- `WebView(url:)` and `WebView(page)`.
- `WebPage`: `load` from a URL, a request or HTML; `title`, `url`, `isLoading`, `estimatedProgress`; `reload`; back and forward; and `callJavaScript`, which is `async`.
- Modifiers: `webViewBackForwardNavigationGestures`, `webViewMagnificationGestures`, and `findNavigator`.
- Each app gets its own website data store, so cookies don't cross between apps.

### 3.7 Chart3D
- `Chart3D` with the 3D forms of `PointMark`, `RuleMark` and `RectangleMark`, plus `SurfacePlot`, `chart3DPose`, `chart3DCameraProjection`, and scales.
- `SurfacePlot`'s function runs once per sample. Benchmark it, and cap the sample count if the VM is too slow.

### 3.8 Networking, completed
- `URLSession.shared.data(from:)` and `data(for:)` become truly `async`, and the prompt stops steering apps to `dataTask`.
- `bytes(from:)` and `.lines`, for streamed responses.
- WebSockets: `webSocketTask(with:)`, `resume`, `send(.string)` and `send(.data)`, `receive()` in a loop, `sendPing`, and `cancel(with:reason:)`. Closed with the card.

**Done when:** fixtures and a Lab example for each section, the prompt regenerated, and a check on the phone for haptics, audio and the web.

---

## 4. Round 3: device and permission APIs

### 4.0 Permissions, per app

The system asks once for Shelf, and Shelf decides per app:

- **Info.plist usage strings:** `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSMotionUsageDescription`, `NSLocationWhenInUseUsageDescription`, and `NSPhotoLibraryAddUsageDescription` for saving. `PhotosPicker` needs none.
- **A ledger in Shelf.** The first time an app asks, Shelf's own sheet says "Run Tracker wants your location". Then, if needed, the system prompt follows. The answer is stored per app.
- **Settings › Permissions** lists each capability and the apps allowed to use it, each of which can be switched off. A switched-off app gets the "denied" answer the API would give.
- **The preview.** In the New App sheet, the app gets the real capabilities, after the same prompt.

### 4.1 Files
- **Each app's folder** is `Application Support/files/<slug>/`. `URL.documentsDirectory`, `.applicationSupportDirectory`, `.cachesDirectory` and `FileManager` resolve into it, and a path that leaves it is an error.
- **Files stay on the device.** `DB` is what syncs, and the prompt says so. The folder is deleted with the app.
- **The pickers:**
  - `.fileImporter`, which starts and stops security-scoped access for the app;
  - `.fileExporter` with `Transferable`, `Data` with a `UTType`, or the app's own `FileDocument` through the proxy;
  - `.fileMover`.
- **Also:** `UTType`, `.quickLookPreview`, `.draggable` and `.dropDestination`.

### 4.2 Photos
- `PhotosPicker` with single and multiple selection, `matching:` filters, and the inline style. Also the `.photosPicker` modifier.
- `PhotosPickerItem.loadTransferable(type: Data.self)` and `loadTransferable(type: Image.self)`, then `UIImage(data:)` and `Image(uiImage:)`.
- Saving to the library with `UIImageWriteToSavedPhotosAlbum`, behind the ledger.

### 4.3 Camera
- `UIViewControllerRepresentable` for an allowlist of UIKit controllers, starting with `UIImagePickerController` (`.camera`, and `.photoLibrary` for older code), plus its delegate through a `Coordinator`. This is the form models write.
- No live preview. Custom `AVCaptureSession` cameras are won't-do.

### 4.4 Audio recording
- `AVAudioRecorder` into the app's folder, with metering (`averagePower(forChannel:)`) for level meters.
- The microphone goes through the ledger, and recording stops when the card closes.

### 4.5 Core Motion
- **`CMMotionManager`:** the accelerometer, gyro, magnetometer, and device motion (attitude, rotation rate, gravity, user acceleration, heading).
  - Both forms models write: a handler with `start…Updates(to: .main) { data, error in }`, and reading `deviceMotion` from a `Timer` or `TimelineView`.
  - The update interval is clamped at 1/60 s or slower, so the VM can keep up.
- **`CMPedometer`:** queries, live updates, and the availability checks.
- **Also:** `CMAltimeter` (relative and absolute altitude), `CMMotionActivityManager`, and `CMHeadphoneMotionManager` for AirPods.
- Everything stops with the card. The simulator has no sensors, so fixtures use the context's fake motion source.

### 4.6 Location
- **Updates:**
  - `CLLocationUpdate.liveUpdates()` with `for await`, and `CLServiceSession(authorization: .whenInUse)`;
  - `CLLocationManager` with a delegate, and `requestLocation`;
  - `CLLocation` (distance, course, altitude), `CLLocationCoordinate2D`, and heading.
- **Geocoding:** `MKReverseGeocodingRequest` and `MKGeocodingRequest`, MapKit's types that draw nothing, with `CLGeocoder` kept for older code.
- **Limits:** while the app is open only. No background location and no region monitoring (`CLMonitor`). The system's approximate-location choice is respected.

**Done when:** a fixture per section (with fakes), a Lab example where the fakes make sense, the permission ledger tested, and each sensor checked by hand on an iPhone.

---

## 5. Round 4: on-device intelligence

### 5.1 Vision
- **Swift API:**
  - `RecognizeTextRequest`, `RecognizeDocumentsRequest` (iOS 26) and `DetectBarcodesRequest`;
  - `ClassifyImageRequest` and `DetectFaceRectanglesRequest`;
  - foreground masks (subject lifting) if the coverage list shows they're simple.
- **Inputs:** each runs with `perform(on:)` on `Data`, a `CGImage` or a `UIImage`'s `cgImage`.
- **Results:** observations are bridged with their bounding boxes, top candidates, strings and barcode payloads.
- **The older `VN…` API** (`VNRecognizeTextRequest` with `VNImageRequestHandler`) too, since models still write it.

### 5.2 VisionKit
- `DataScannerViewController` through the representable allowlist, with its delegate, `isSupported` and `isAvailable`, and the `recognizedItems` stream: live text and barcodes.
- `VNDocumentCameraViewController` for scanning documents.
- Both go through the camera's ledger entry.

### 5.3 Foundation Models
- **The basics:** `SystemLanguageModel.default.availability`, so an app can show `ContentUnavailableView` when Apple Intelligence is off or unsupported.
- **Sessions:** `LanguageModelSession(instructions:)`, `respond(to:)`, `streamResponse(to:)` with `for try await`, `isResponding`, `transcript`, and `GenerationOptions`.
- **Structured output:**
  - `@Generable` structs and enums with `@Guide` (descriptions, ranges, counts, `anyOf`). Kiln builds a `DynamicGenerationSchema` from the declaration and maps `GeneratedContent` back into the app's values.
  - Streaming a `@Generable` gives partial snapshots with every field optional.
- **Tools:** the app's own `Tool` types (arguments are `@Generable`, and `call` is `async`), through the protocol proxy. Also iOS 27's built-in `OCRTool` and `BarcodeReaderTool`.
- **Check while building:** iOS 27's `LanguageModel` protocol and the Private Cloud Compute model, and whether they need an entitlement or carry a quota for an app like Shelf. They come in only if they don't.
- **Tests:** a fake model in the context, plus a hand check on a phone with Apple Intelligence. The prompt has to tell authors to handle "unavailable".

**Done when:** a fixture and a phone check for each, plus a Lab example of a structured-output app (a recipe parser, say), comparing the parsed result rather than pixels.

---

## 6. Round 5: widgets on Shelf's Home Screen

Apps declare widgets in their own file, with ordinary WidgetKit code, and Shelf shows them on its own Home Screen next to the icons, as Springboard does. All of it runs inside Shelf. There's no widget extension, no App Group, and no memory limit beyond the app's own, and a widget reads the same `DB` as its app, in the same process.

It depends on §1 (protocol proxies for `TimelineProvider` and `AppIntent`, real `async`) and Round 1 (`containerBackground` and the rest of the widget-facing modifiers), but not on Rounds 2–4. So it can move ahead of them.

### 6.1 What an app writes
- `struct …: Widget` with `StaticConfiguration`, `.supportedFamilies`, `.configurationDisplayName` and `.description`. An app can declare several.
- A `TimelineProvider` (`placeholder`, `getSnapshot`, `getTimeline`, or the `async` `timeline(for:in:)`), a `TimelineEntry`, and `Timeline(entries:policy:)` with `.atEnd`, `.after(_:)` and `.never`.
- `@Environment(\.widgetFamily)`, `containerBackground(for: .widget)`, `widgetURL`, `Link`, and `Text(_:style:)` for live times.
- Interactive widgets: `Button(intent:)` and `Toggle(isOn:intent:)` with the app's own `AppIntent` structs (`@Parameter` properties and `perform()`).
- Later, if wanted: `AppIntentConfiguration` with a `WidgetConfigurationIntent`, with Shelf building the Edit Widget sheet from its `@Parameter`s.

Using WidgetKit's own API, not a Shelf one, means models already know how to write it.

### 6.2 In Kiln
- **WidgetKit types as Kiln bridges, implemented in Kiln itself.** Kiln provides `Widget`, `StaticConfiguration`, `Timeline` and the families as plain values. WidgetKit isn't linked, since nothing goes to the system.
- **Widget mode** renders an entry's view the way WidgetKit would:
  - no scrolling, text fields or animations;
  - taps go to `widgetURL`, a `Link` or an intent;
  - `check` reports views a widget can't use.
- **`Kiln.widgets(in:)`** lists what an app declares, for the gallery.
- **Shared runs.** An app's parsed program is shared between its card and its widgets, so ten widgets don't mean ten parses.

### 6.3 In Shelf
- **Layout v2.** A page becomes a list of items, each an icon or a widget of a size, flowed into the 4 × 6 grid by Springboard's rules:
  - widgets take aligned blocks (small 2 × 2, medium 4 × 2, large 4 × 4), and icons fill the cells around them in reading order;
  - the dock holds icons only (Settings included);
  - `layout.json` migrates from v1 on first launch.
  - `Layout`'s tests grow to cover the packing.
- **Size.** Measured from `home-page1-light.png`, where Springboard's small widget is 164 × 164 pt, along with its corner and its label (if any).
- **Adding.** In edit mode, the top-left button (New App today) becomes a menu with New App and Add Widget, as Springboard's Edit button is a menu. Add Widget opens a gallery: apps that declare widgets, each widget at each size it supports, previewed from its `placeholder` or snapshot. Drag one in, or tap to add it to the current page.
- **Editing:**
  - In edit mode, widgets jiggle, move, take the minus badge (§0.2) and get a resize handle, as in `edit-mode-page1-light.png`.
  - The long-press menu has the size row the real-device captures show.
  - Deleting an app removes its widgets.
- **Opening.** A tap opens the app's card from the widget's frame, not its icon's, and passes the `widgetURL` to the app's `.onOpenURL`. The card lands back on the widget when it closes.
- **Timelines.** Shelf runs each provider:
  - when the page loads;
  - after a sync changes the app's source or data;
  - after the app or an intent writes `DB`;
  - when the timeline's policy says so.

  Entries switch at their dates. This happens only while Shelf is in front, and only for the current page and its neighbours.
- **Intents.** `perform()` runs in Kiln, then that app's widgets reload.
- **Appearance.** Widgets follow the icon appearance setting (§0.3) for light and dark.
- **Budget.** Measure memory and first-render time with a page of four widgets from 600-line apps. If a page costs too much, render widgets that are off screen to images and keep only the visible page live.

### 6.4 Done when
- A habits app's widget shows today's progress. Checking a habit off in the widget updates the app, and the reverse.
- A countdown widget changes entries on schedule.
- Widgets survive a relaunch, a sync, an app change and an app delete.
- Fixtures and Layout tests cover the packing.
- The prompt has a Widgets section.

Widgets on the iPhone's own Home Screen (a WidgetKit extension) are on the Later list.

---

## 7. Shelf, along the way

- **Delete:** `SourceRewriter`'s `@AppStorage` rewriting, `Prelude`, `ShelfDBProtocol` and the `DB-Key` header path (§1.7). The server's `/api/apps/{slug}/data` API is unchanged.
- **Prompts:** "What works" and "What doesn't work" are built from `kiln-manifest.json` plus a short hand-written part (format, design, saving data). New sections per round: Files, Photos and Camera, Motion, Location, Intelligence, Widgets (for Shelf's Home Screen). `PromptsTests` checks the result. ij5.dev's admin doesn't show the prompt, so the server needs no change.
- **New App sheet:** runs `Kiln.check` and `Kiln.validate` on the pasted reply before Install, and shows the first error with its line.
- **Card lifecycle:** closing a card calls the context's teardown (§1.7).
- **Settings:** Permissions (§4.0), and per-app storage use (files plus `DB`).
- **README:** updated at the end of each phase.

---

## 8. Order and checkpoints

1. §0, the Shelf fixes, in their order: the audit, deleting apps, icon appearance, the dock, the swipe up, the launch screen. Each is its own branch. They don't touch Kiln, so the §1.3 spike can run alongside them.
2. §1.1 and §1.2: in the repo, one engine. Small, and it can merge on its own.
3. The §1.3 VM spike against the fixtures. Go, or switch to the fallback.
4. §1.4 to §1.11: the registry, porting, proxies, language fixes, context, checker, coverage. Merge when §1.11 holds. Then the second half of §0.6 (building off the main thread).
5. Round 1. Then Round 2, Round 3 and Round 4, each on its own branch, each merged when its "done when" holds.
6. Round 5, widgets on Shelf's Home Screen. It can move ahead of Rounds 2–4 if wanted.

For Kiln work, every merge includes: the coverage report regenerated, the prompt regenerated, new fixtures, Lab parity, no benchmark regressions, and the README updated.

---

## Won't do

| What | Why |
|---|---|
| MapKit views (`Map`, `Marker`, Look Around) | Too much for the value. Geocoding stays (§4.6). |
| Custom cameras with `AVCaptureSession` | A live preview layer and session management; `UIImagePickerController` covers taking a photo. |
| Real-time audio callbacks, Metal shaders (`colorEffect` with `ShaderLibrary`) | They run off the main thread at frame rate, or need a compiled Metal library. |
| SwiftData, Core Data | `DB` is the synced store. |
| iOS 27's `Document` protocol, multiple windows and scenes | A Shelf app is one screen inside a card. |
| Background modes (location, audio, refresh) | Apps run only while their card is open. |
| Subclassing native classes in app code (`UIView`, `Dimension`) | An interpreted type can't be a native subclass. Protocol proxies cover the common cases. |
| UIKit beyond the representable allowlist | Each controller is bridged on purpose. |
| Bluetooth, NFC, HealthKit, HomeKit | Entitlements, or delegate-heavy APIs for little use here. |

## Later

- Local notifications that open the app, EventKit, Speech (`SpeechAnalyzer`), AlarmKit, Translation, and Core Haptics patterns.
- Claude through ij5.dev, with the key kept on the server.
- Widgets on the iPhone's own Home Screen: a WidgetKit extension that runs Kiln, an App Group holding the sources and `DB`, one configurable "Shelf App" widget kind, and one compiled `RunAppIntent` for interactivity. Spike first: Kiln has to fit the extension's memory limit.
- Live Activities and Control Center controls, after that.
- A cheap symbol check at `PUT /api/apps/{slug}` from `kiln-manifest.json`, so an agent installing with `curl` gets a 422 that names an unsupported API.
- Offering the language fixes back to upstream Kiln.
