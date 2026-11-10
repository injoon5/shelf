# Shelf — plan

An iPhone Home Screen for personal apps. Each app is a single Swift file stored on ij5.dev and run on device by [Kiln](https://github.com/haplollc/Kiln). Shelf should feel like Springboard on iOS 27: icons on a wallpaper, a Liquid Glass dock, apps that zoom out of their icon and back into it.

Two repos change. The prompts for making apps are in [`prompts/`](prompts).

- **ij5.dev**: adds an apps table, an API, an admin editor, and a small key-value store that apps can use for their data. None of this exists yet.
- **shelf**: adds the iOS app. It needs iOS 27 or later and uses Liquid Glass throughout. The Home Screen is UIKit and the rest is SwiftUI (§0.2).

---

## 0. Decisions

### 0.1 What the research found

| Finding | Source | Consequence |
|---|---|---|
| Kiln stores `@AppStorage` in `UserDefaults.standard` under `kiln.app.<key>`, which every app shares. | `Engine/KERenderer.swift` | Two apps that both use `@AppStorage("count")` would overwrite each other. Shelf rewrites each key to `<slug>.<key>` before running the app (§6.3). |
| Compile errors come back as `"Line N: message"` in `KilnResult.errors`. Errors inside a running body appear as Kiln's own red label and never reach the host. | `Engine/KEEngine.swift:62`, `KErrorView` | Shelf calls `Kiln.run` directly instead of `KilnView`, so it can show its own error screen with the failing line (§7). Render-time errors stay Kiln's to show. |
| `Kiln.run` is `@MainActor` and synchronous. `await URLSession…` inside an app blocks for up to 20 s. | README, Limitations | Shelf runs the app once per open, after the launch animation has settled (§6.2). App authors should use `dataTask` for network calls. |
| `Kiln.validate` fires every action once, side effects included. | `Kiln.swift` | Shelf never validates on device. Validation goes on the Later list. |
| The latest tag is `0.2.1`. `main` differs from it only in docs. | `git ls-remote`, `git diff 0.2.1 HEAD` | The fork in §0.2 starts from `0.2.1`. |
| The modern engine constructs `JSONEncoder()` but has no `encode` method. Calling it fails with "has no method 'encode'", and inside `try?` that failure is silent. | `Engine/KEBuiltins.swift:653`, no `encode` anywhere in `Engine/` | An app can't turn its own types into JSON, so nothing could be saved to `DB`. Kiln needs the method added (§0.2). |
| Kiln picks the old engine by substring: any source containing `GameCanvas(`, `.onTick(`, `.onSwipe`, `.dragToMove`, `BarChart(`, `LineChart(`, `Storage.save`, `Storage.load`, `Map(latitude` or `Map(markers`. `Kiln.engine = .modern` doesn't turn this off. | `KEEngine.isLegacyDialect`, `KEEngine.swift:99` | An app's own `WeeklyBarChart(` or `TodoStorage.load` trips it. The prompt bans those names (`prompts/rules.md`). |
| On iOS 26, interactive dismiss of SwiftUI's `.navigationTransition(.zoom)` with `fullScreenCover` has open bugs: the source icon disappears and frames are misaligned. | Apple Developer Forums [796279](https://developer.apple.com/forums/thread/796279), [807208](https://developer.apple.com/forums/thread/807208), [807715](https://developer.apple.com/forums/thread/807715) | Shelf uses UIKit's zoom transition, where the source view is handed over directly, and keeps a fallback behind one flag (§6.1). |
| Kiln gives apps `UserDefaults.standard` directly, under the prefix `kiln.`. | `Engine/KEBuiltins.swift` | Apps can read each other's `@AppStorage`. Shelf keeps its own state outside `UserDefaults.standard`, and real data goes in `DB` (§6.3). |
| No public source documents the iOS 26 or 27 Home Screen metrics in points. | Searches | Treat the metrics in §5 as starting values, and tune them by overlaying Shelf screenshots on real Springboard screenshots (§11). |
| No server API exists. | `ij5.dev/src/routes/api` | Build it with the conventions the links API already uses (§1). |
| `Kiln.register` bridges are read only by the old interpreter (`SwiftRunnerState.nativeBridges`). The modern engine never consults them. | `grep nativeBridges` | The app database can't be a native bridge. |
| The modern engine sends requests through the real `URLSession.shared` with a real `URLRequest`, and supports `httpMethod`, `httpBody` and `setValue(_:forHTTPHeaderField:)`. `data(from:)` waits on a semaphore on the main thread. | `Engine/KENetwork.swift` | A `URLProtocol` registered by Shelf can answer a private `db://` scheme on the phone. Apps get a database through the plain networking code Kiln already runs (§8). |
| iOS 27 refines Liquid Glass and adds a system setting that makes glass clearer or more tinted. | [MacRumors](https://macrumors.com/2026/06/10/how-liquid-glass-is-changing-in-ios-27), [BGR](https://bgr.com/2191219/ios-27-liquid-glass-fix-customization/) | Use only system glass: `UIGlassEffect` and `UIGlassContainerEffect` in UIKit, `glassEffect` and the glass button styles in SwiftUI, and the system's sheets and menus. Never a hand-made blur. The iOS 27 setting then applies on its own. |

### 0.2 What was decided

| Decision | Why |
|---|---|
| **iOS 27 only.** | It is the current release and has the refined Liquid Glass. Kiln itself needs iOS 17, and Shelf is a personal app, so dropping older versions costs nothing. |
| **The Home Screen is UIKit. Everything else is SwiftUI.** | The Home Screen has to match Springboard frame by frame, and each hard part is a direct UIKit feature: a paging collection view with an exact custom layout, a jiggle that Core Animation runs outside the app's main thread, a drag that starts with no system lift delay and moves between grid and dock, and a zoom transition that can be grabbed mid-flight. SwiftUI's `draggable`, `phaseAnimator` and `fullScreenCover` zoom each fall short of that. Connect, Settings, the New App sheet and the error screen are forms, where SwiftUI is shorter and speed isn't in question. Kiln returns a SwiftUI view, so the runner hosts it in a `UIHostingController`. |
| **Icons are drawn once into bitmaps.** | A cell is then one image view and one label. Paging, jiggle and drag move bitmaps and never redraw gradients or symbols (§5.3). |
| **The wallpaper doesn't move.** | A drifting mesh would redraw the whole screen every frame for as long as Shelf is open. Springboard's wallpaper is still. |
| **The app's code runs after the zoom settles.** | `Kiln.run` blocks the main thread, and a blocked main thread during the zoom drops frames. A launch screen covers the gap, as in a native app (§6.2). |
| **Kiln is pinned to a fork that adds `JSONEncoder().encode`.** | Stock Kiln can't encode (§0.1), and `DB` is useless without it. The method is the inverse of the `decode` Kiln already has, in `KENetwork.swift`. The fork is pinned by revision and offered upstream as a pull request. When upstream has it, the pin goes back to a release. |
| **App data is held in memory behind a lock.** | The `db://` protocol is called while Kiln blocks the main thread. It must answer without waiting on an actor or on the main thread, or the app deadlocks (§8.3). |
| **Tombstones are never purged.** | A purge would hide deletes from a device that was offline longer than the purge window. One user and one key per collection keep the table small. |
| **Data keys use `A–Z a–z 0–9 . _ -` only.** | A key is part of a URL on both the server and the `db://` scheme. `/`, `?`, `#` and spaces would each need escaping in app code. |
| **Dragging an icon doesn't start edit mode.** | Outside edit mode the long press belongs to the context menu. Mixing the system menu with a custom drag is where most Springboard copies feel wrong. Edit mode starts from the menu or from a long press on the wallpaper (§5.6). |
| **Prompts are files in `prompts/`.** | The app bundles the same files the repo shows, so there is one copy (§9.1). |
| **One Xcode project at the repo root.** | `project.yml`, `Shelf/` and `ShelfTests/` sit at the top level, with no `Shelf/Shelf/Shelf` nesting. |

---

## 1. Server (ij5.dev)

### 1.1 Migration `migrations/0009_apps.sql`

```sql
CREATE TABLE apps (
  slug       TEXT PRIMARY KEY,         -- SLUG_PATTERN
  name       TEXT NOT NULL,            -- label under the icon, ≤ 32 chars
  icon       TEXT,                     -- SF Symbol name; null → "app"
  tint       TEXT NOT NULL,            -- one of TINTS (see 1.2)
  source     TEXT NOT NULL,            -- ≤ 256 KB
  version    TEXT NOT NULL,            -- sha256 of the JSON array [name, icon, tint, source], base64url, 16 chars
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
```

`version` is a hash of the app's content, not a counter. Saving the same content twice leaves it unchanged, so the phone downloads nothing, and two edits racing each other can never produce the same version for different content. Name, icon and tint are part of the hash, so renaming an app also reaches the phone.

Apps live only under `/api/apps`. They take no root slug, and nothing in `RESERVED` needs to change.

### 1.2 `src/lib/server/apps.ts`

This file holds `listApps` (metadata only, so `source` is never read for the index), `getApp`, `putApp` and `deleteApp`, in the style of `pastes.ts`.

`TINTS` is a fixed list of named colours: `red orange yellow green mint teal cyan blue indigo purple pink brown gray`. Names rather than hex codes mean the phone maps each one to the matching `Color.red` and so on. Those system colours adapt to light and dark mode; a hex code would not.

### 1.3 API, with the same `authorize`, `apiJson` and `apiError` as links

| Method | Path | Body | Returns |
|---|---|---|---|
| GET | `/api/apps` | | `{ "apps": [AppMeta] }` with a strong `ETag`. `If-None-Match` gets a `304`. |
| GET | `/api/apps/{slug}` | | `AppFull` |
| PUT | `/api/apps/{slug}` | `{ name, icon?, tint, source }` | `201` if created, `200` if updated |
| DELETE | `/api/apps/{slug}` | | `{ slug, deleted: true }` |

```ts
type AppMeta = { slug: string; name: string; icon: string | null; tint: Tint; version: string; updated_at: number };
type AppFull = AppMeta & { source: string };
```

The ETag is a hash of every slug and version, in slug order. With it, the sync on every launch usually costs a single `304`.

Writes use `PUT` rather than `POST` plus `PATCH`, because an app is a whole document and uploading it again is the normal way to change it. A future CLI can then run `curl -T`.

### 1.4 Admin `/admin/apps`

- A list sorted by name, with an icon preview, the name and when it was last updated.
- An editor with name, an SF Symbol name and a live preview tile, a row of tint swatches, and a monospaced `source` textarea with a byte counter (`MAX_APP_BYTES`, shared through `$lib/types`).
- A row added to `/admin/api` for the new endpoints.

### 1.5 Tests (vitest, next to the existing ones)

- `apps.test.ts`:
  - version stability: same input gives the same hash, and any field change gives a new one
  - size limit
  - tint whitelist
  - a list query that never selects `source`
- A route test: `If-None-Match` returns `304`, and a wrong token returns `401` without echoing the token.

---

## 2. iOS project

```
project.yml              XcodeGen; the .xcodeproj is generated, not committed
prompts/                 new.md, change.md, rules.md, install-new.md, install-change.md,
                         current-source.md, current-outline.md (bundled as resources, §9.1)
fixtures/                api/, replies/, apps/ (§12.2)
Shelf/
  App/        AppDelegate.swift, SceneDelegate.swift
  Model/      AppMeta.swift, AppFull.swift, Tint.swift, Layout.swift
  Store/      Keychain.swift, Settings.swift, AppCache.swift, SyncEngine.swift, LibraryStore.swift
  Data/       AppData.swift, DataSync.swift, ShelfDBProtocol.swift, Prelude.swift
  Home/       HomeViewController.swift, HomeMetrics.swift, Motion.swift, IconGridLayout.swift,
              IconCell.swift, IconRenderer.swift, DockView.swift, Wallpaper.swift,
              SearchPill.swift, SearchController.swift, Banner.swift,
              EditController.swift, Jiggle.swift
  Runner/     RunnerViewController.swift, RunnerView.swift, SourceRewriter.swift, ErrorScreen.swift
  Create/     NewAppSheet.swift, ReplyParser.swift, Prompts.swift, Outline.swift
  Settings/   SettingsView.swift, ConnectView.swift
ShelfTests/   SyncEngineTests.swift, SourceRewriterTests.swift, LayoutTests.swift,
              AppDataTests.swift, PreludeTests.swift
```

- **UIKit and SwiftUI** (§0.2):
  - UIKit: the app lifecycle (`AppDelegate`, `SceneDelegate`), everything in `Home/`, and `RunnerViewController`.
  - SwiftUI: `RunnerView`, `ErrorScreen`, `Create/` and `Settings/`, each presented from UIKit in a `UIHostingController`.
  - `LibraryStore` is `@Observable`. UIKit reads it in `updateProperties()` and SwiftUI reads it in `body`, so both redraw from the same store with no glue code.
- The only dependency is Kiln, pinned as in §0.2.
- Strict concurrency is on (Swift 6 language mode).
- The UI targets portrait only, like Springboard on iPhone.

---

## 3. Connect and settings

- Stored settings:
  - the site URL in `UserDefaults(suiteName: "shelf")`, defaulting to `https://ij5.dev`. Nothing of Shelf's goes in `UserDefaults.standard`, which apps can reach (§6.3).
  - the token in the Keychain (`kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`)
- First run shows one screen: an app glyph, a token field and a Connect button. Connect checks the token with `GET /api/apps` before saving anything. A wrong token shakes the field and leaves no saved state.
- The Connect button uses `.buttonStyle(.glassProminent)`, over the Shelf wallpaper.
- Settings opens as a sheet from the gear icon in the dock (§5.4). At the medium detent the sheet is glass by default on iOS 26+, so it gets no custom background. It contains:
  - Site
  - Token (masked, with Change)
  - Sync Now, with a "last synced" time
  - Wallpaper (built-in, or a photo from `PhotosPicker`)
  - Icon Style (Automatic, Default, Dark, Clear, Tinted)
  - App Data: storage used by each app, with Delete Data per app
  - Reset Layout
  - Sign Out, which clears the token, the cache and each app's storage

---

## 4. Sync

`SyncEngine` is an `actor`. `LibraryStore` is a `@MainActor @Observable` that owns what the UI shows.

**Triggers:**

- launch
- `scenePhase == .active` once 10 minutes have passed since the last sync
- Sync Now in Settings
- the wallpaper's context menu

There is no pull-to-refresh: Springboard has none, and a downward swipe on the Home Screen means search.

**Steps:**

1. `GET /api/apps` with `If-None-Match: <stored etag>`. On `304`, stop here.
2. Compare each app's version with the cache. For each app that is new or changed, `GET /api/apps/{slug}`, with at most 4 requests at a time (`withThrowingTaskGroup`).
3. Write each source atomically to `Application Support/apps/{slug}.swift` with `.atomic` and `.completeFileProtectionUntilFirstUserAuthentication`.
4. Write `index.json` last. It records, per app, the version that is on disk, which is not always the version the server listed. When one app fails to download, its old version stays in the index and the next sync retries it.
5. Only after `index.json` is written, delete `{slug}.swift` files and AppStorage keys (`kiln.app.{slug}.*`) for apps that are no longer listed.
6. If step 1 fails (offline, `5xx`, `401`), the cache is left untouched, so the apps keep working offline. A `401` marks the token as invalid, and Settings says so.

Before the first frame, `LibraryStore` reads `index.json` synchronously, so the Home Screen never flashes empty on launch.

**How sync appears on the Home Screen:**

- While an app's source downloads, its icon shows the App Store install state: the icon dimmed, with a circular progress pie in the middle.
- After an app is added or updated, a blue dot sits before its label until the app is first opened, the same as a newly installed iOS app.
- When a sync fails and the app has a cache, a glass capsule drops from the top of the screen, like a system banner: an `exclamationmark.icloud` glyph and "Offline". It disappears after 3 s or on a tap.
- A `401` uses the same banner with "Token Expired", and tapping it opens Settings.
- On the first run, when there is no cache, the error replaces the grid as a `UIContentUnavailableConfiguration`.

---

## 5. Home Screen

The aim is that a screenshot of Shelf placed next to Springboard looks the same at a glance. Every number below is a starting value for the overlay check in §11.

`HomeViewController` owns four things: the wallpaper, one paging collection view for the icon pages, the dock, and the search pill. It has no navigation controller.

### 5.1 Wallpaper

- The default is a `MeshGradient` with 3×3 points in deep blue and violet tones, with separate palettes for light and dark mode. It is rendered once per appearance into an image (`ImageRenderer`) and shown in an image view. It doesn't move (§0.2).
- An optional photo from `PhotosPicker`, scaled to fill the way Springboard crops a wallpaper. The photo is downsampled to the screen's pixel size when it is picked, and that copy is what Shelf stores and shows.
- The wallpaper extends under the status bar and the home indicator.

### 5.2 Icon grid

- **Layout:** 4 columns and 6 rows per page, the iPhone default.
- **`IconGridLayout`:** a custom `UICollectionViewLayout` with one section per page. The frames come from one pure function of the bounds, the safe area and `HomeMetrics`, which `LayoutTests` covers.
- **Size:** `iconSize = 60pt` for a 393pt-wide screen, scaled by `width / 393` and rounded to whole points, so Pro Max models get about 64pt the way Springboard scales.
- **Horizontal spacing:** side insets of about 27pt, with the 4 columns spaced evenly in the remaining width.
- **Rows:**
  - The top row starts about 14pt below the status bar.
  - Rows are distributed evenly in the height between the status bar and the dock, which is how Springboard does it, rather than a fixed gap.
- **Paging:**
  - More than 24 apps continue on another page. The collection view scrolls horizontally with `isPagingEnabled`.
  - Page dots replace the search pill while the user swipes, then fade back after 1 s.

### 5.3 App icon

- **Rendering:** `IconRenderer` draws each icon into a bitmap with `UIGraphicsImageRenderer` and caches it by app version, icon style, size and appearance. `IconCell` is an image view and a label.
- **Shape:** a rounded rectangle with radius `size * 0.2237` and a continuous corner curve, which approximates Apple's superellipse mask. A circular-arc corner is not close enough.
- **Fill in light mode:** a vertical gradient from `tint` lightened by 12% at the top to `tint` at the bottom. The SF Symbol is white, about `size * 0.5`, `.medium` weight, centred optically, with hierarchical rendering so two-tone glyphs have depth.
- **Fill in dark mode:** follows iOS 18+ dark icons. The fill is a near-black gradient (`#2C2C2E` → `#1C1C1E`) and the glyph takes the tint colour.
- **Edge:** a 0.5pt inner stroke of white at 18% opacity, strongest on the top edge. It stands in for the specular rim that Liquid Glass icons have.
- **Shadow:** none. Springboard icons cast no drop shadow.
- **Label:**
  - 12pt at the default text size, scaled with `UIFontMetrics(forTextStyle: .caption2)`. `maximumContentSizeCategory = .extraLarge` stops it growing where Springboard's labels stop, so the grid never breaks.
  - white, on one line, truncated at the tail
  - 6pt below the icon, as wide as the icon plus 14pt
  - A soft shadow (black at 35%, radius 1.5, y 0.5) keeps it readable on light wallpapers. It is an `NSShadow` in the attributed text, so it is drawn with the glyphs. A layer shadow on a label is rendered offscreen every frame.
- **Icon style:** Settings has an Icon Style picker that mirrors the system's Home Screen options. Shelf can't read the system choice, so Automatic follows light or dark mode.
  - **Default:** the light-mode fill described above.
  - **Dark:** the dark-mode fill described above.
  - **Clear:** the squircle is a `UIVisualEffectView` with a clear `UIGlassEffect`, the glyph is white, and the tint is dropped. This is the iOS 26+ "Clear" icon look. Glass is live, so these two styles are not bitmaps.
  - **Tinted:** like Clear, but with a regular `UIGlassEffect` whose `tintColor` is a single accent the user picks.
- **Pressed state:** on touch-down the icon darkens by 25%, with no scale change. Springboard darkens icons rather than shrinking them. The cell shows a dimming layer in the icon's shape when `isHighlighted` is set, with no animation on the way down.
- **Haptic:** a light `UIImpactFeedbackGenerator`, prepared on touch-down and fired when the app launches.
- **Long-press:** a context menu (`contextMenuConfigurationForItemsAt`) with Edit Home Screen, Reload App and Copy Source. The targeted preview is the icon alone, in its own shape, like an app's quick-actions menu.

### 5.4 Dock

- **Contents:** up to 4 slots: the apps the user pins, plus Settings, which always stays in the dock with a gray gradient and the `gearshape.fill` glyph.
- **Container:** one view with a `UIGlassContainerEffect` holds the dock and the search pill, so the two glass shapes refract as one surface. The dock is a `UIVisualEffectView` with a regular `UIGlassEffect`, corner radius 32 with a continuous curve, inset about 12pt from the screen edges and about 8pt above the bottom safe area.
- **Corner radius:** inner radius = display corner radius − inset, so the dock is concentric with the screen corners. That concentricity is the detail that gives a fake dock away when it's wrong.
- **Labels:** dock icons show no labels, as on Springboard.

### 5.5 Search pill

- **Appearance:** a glass capsule above the dock showing a `magnifyingglass` glyph and "Search", the same as iOS 18+.
- **Opening search:** tapping the pill, or swiping down anywhere on the grid, opens search.
  - The pill and the search field are the same glass view. Opening animates its frame to the top of the screen with a spring and swaps the label for a text field. One view moves, so the animation can be reversed at any point.
  - The grid fades and the wallpaper dims.
  - The swipe is a pan recognizer on the grid that begins only when the movement is mostly vertical, so it never competes with paging.
- **Search behaviour:**
  - Results are the app icons whose names match, in a 4-column grid; the best match comes first and opens with Return.
  - Tapping outside the field or swiping down closes search.

### 5.6 Edit mode

Edit mode does what Springboard's does that still makes sense here. Apps come from the server, so they can't be deleted on the phone.

- **Entering:**
  - Edit Home Screen in an icon's context menu.
  - A long-press on empty wallpaper.
- **Jiggle:** each icon rotates ±1.6° and shifts ±0.6pt vertically. The period is 0.26 s with a random phase per icon, so the icons don't move in step. It is a repeating `CAKeyframeAnimation` on the cell's layer with a random `timeOffset`, so it costs the main thread nothing.
- **Reordering:** `EditController` owns one long-press recognizer on the Home Screen view. In edit mode, context menus are off and a 0.15 s press lifts an icon.
  - The lifted icon is a snapshot that follows the finger. The real cell is hidden until the drop.
  - As the finger crosses slots, the layout model changes and the other icons slide aside with a spring (duration 0.35, bounce 0.15).
  - Holding an icon at the screen edge for 0.6 s flips to the next page.
- **Dock:** dragging an icon into or out of the dock pins or unpins it. The grid and the dock share the one recognizer and the one layout model, so this is the same code path as a reorder.
- **Done:** a prominent glass button (`UIButton.Configuration.prominentGlass()`) in the top-right corner, plus a tap on empty wallpaper.
- **Storage:** the layout is saved locally in `layout.json` as `{ dock: [slug], pages: [[slug]] }`.
  - New apps go into the first empty slot on the last page, as on iOS.
  - Removed apps leave the layout.
  - Unknown slugs in the layout are ignored.

---

## 6. Runner

### 6.1 Presentation

- **Presentation:** `RunnerViewController` is presented full screen with `preferredTransition = .zoom`, and the source view provider returns the app's icon view.
  - The app grows out of its own icon and shrinks back into it. A drag down or a pinch closes it, and either can start while the open animation is still running.
  - The provider looks the icon up when the transition runs, so the app closes into the right place after a sync or a reorder. If the icon is gone, the system uses its plain dismissal.
  - This replaces the sheet in the original spec: a sheet leaves the Home Screen visible behind the app, which no iOS app does.
- **Navigation:** the runner is its own presentation context, so apps with a `NavigationStack` don't nest inside anything of Shelf's.
- **Fallback:** `Runner.presentation` is a flag that can be `.zoom` or `.sheet` (a page sheet at the large detent with a grabber). Check the zoom on iOS 27 in step 4 of the build order. If it misbehaves, switch the flag to the sheet. That is one line, and the rest of the runner is unchanged.
- **Drag conflicts:** `UIZoomTransitionOptions.interactiveDismissShouldBegin` decides when a drag closes the app. A drag that starts in the top 44pt always does. Elsewhere the system's rule applies: a scroll view that isn't at its top keeps the drag.
- **Background:** the runner's background is `systemBackground`, because many Kiln apps leave the background transparent.

### 6.2 Running

`RunnerViewController` hosts `RunnerView`, a SwiftUI view that shows one of three things: the launch screen, the app's view from Kiln, or `ErrorScreen` (§7).

1. **Tap.** Shelf presents the runner at once. In the background it reads the source from disk, runs `SourceRewriter.prepare` (§6.3) and starts the data pull (§8.3).
2. **Zoom.** The runner shows a launch screen in the app's tint: a solid background with the glyph centred at the icon's size.
3. **Run.** When the zoom has finished and the pull has returned or 1 s has passed since the tap, Shelf calls `Kiln.run` once and keeps the result.
4. **Swap.** The launch screen crossfades to the app, or to `ErrorScreen` if there is no view.

- The app runs once per open and once per version, so a sync during a session swaps in the new code only after the user closes and reopens the app. The same is true on iOS.
- Opening an app clears its blue dot.
- **Measure first.** Step 2 of the build order times `Kiln.run` on a 600-line fixture on a real phone. If it takes less than one frame (8 ms), run it before presenting and drop the launch screen for apps whose data is already fresh.

### 6.3 `SourceRewriter`

- **Rewrite:** `@AppStorage("key")` becomes `@AppStorage("<slug>.key")`. It uses one regex on string literals in the attribute position only.
- **Header:** the `// Name:`, `// Icon:` and `// Tint:` lines (§9) stay in the source. Kiln reads them as comments.
- **Prelude:** if the source mentions `DB.` and doesn't declare its own `enum DB`, the `DB` helper from §8.4 is added to the end of the source. Appending, rather than prepending, keeps the line numbers in error messages matching the author's file.
- **Tests:**
  - the plain form
  - `@AppStorage("k", store: …)`
  - an occurrence in a comment or a string elsewhere, which must stay untouched
- **Cleanup:** when an app is removed, `UserDefaults.standard` keys with the prefix `kiln.app.<slug>.` are deleted.
- **This isn't a security boundary.** Kiln gives apps `UserDefaults.standard` directly (`KEBuiltins.swift`: `UserDefaults.standard.set` and `.string(forKey:)` under the prefix `kiln.`). Any app can therefore read or write any other app's `@AppStorage` by spelling out the key. The key rewrite only prevents accidental clashes. So:
  - All of Shelf's own state lives elsewhere: settings in the `shelf` suite, the token in the Keychain, and the cache, layout and data in `Application Support`. Kiln exposes no API that reaches any of these.
  - The prompt limits `@AppStorage` to preferences that wouldn't matter if lost. Real data goes in `DB`, which is scoped to the running app by `ShelfDBProtocol`.
  - Shelf's own network calls (sync, data push and pull, minting keys) use a private `URLSession(configuration: .ephemeral)`. That keeps them separate from `URLSession.shared`, which apps use and where the `db` protocol is registered.

---

## 7. Errors

| Where | What the user sees |
|---|---|
| Compile error (`result.view == nil`) | `ErrorScreen` inside the runner. |
| Error inside the running app | Kiln's own inline label. Shelf can't intercept these. |
| Source file missing (deleted from the cache, or interrupted on the first sync) | The icon shows the install pie and fetches the source on tap. Offline, the icon is dimmed and shakes when tapped. |
| Sync | The banner in §4. |

`ErrorScreen` shows the app's icon at 60pt and the line "{name} couldn't open". Below them, the code around the failing line:

- The line number is parsed with the regex `^Line (\d+):` from the error string.
- Lines N−2 to N+2 are shown in a monospaced block, with line numbers in the gutter and the failing line on a tinted background.
- Kiln's message appears beneath the block.

When there is no line number, only the message is shown. The screen has no other text and no buttons; dragging down closes it.

---

## 8. App data

A small key-value database per app. Values are JSON and keys are strings. It stores what `@AppStorage` can't: lists, records, and data that should follow the user to another device or be readable from the web.

### 8.1 Server storage (ij5.dev)

`migrations/0010_app_data.sql`:

```sql
CREATE TABLE app_data (
  slug       TEXT NOT NULL,
  key        TEXT NOT NULL,            -- 1–128 chars of A–Z a–z 0–9 . _ -
  value      TEXT,                     -- JSON; NULL is a tombstone
  rev        INTEGER NOT NULL,         -- global, strictly increasing
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (slug, key)
);
CREATE INDEX app_data_rev ON app_data (slug, rev);
```

- **Why D1, not Workers KV:** Workers KV takes up to 60 s to show a write everywhere, so a value saved on the phone could read back stale on the web. D1 reads back its own writes immediately.
- **Revisions:** each write sets `rev = (SELECT COALESCE(MAX(rev), 0) + 1 FROM app_data)` in the same statement. D1 runs writes one at a time, so `rev` is a total order, and a client can resume from any `rev` it has seen.
- **Tombstones:** a delete sets `value = NULL` and keeps the row, so other devices learn about the delete on their next sync. Tombstones are never purged (§0.2).
- **Limits** (`$lib/types`):
  - a value of 64 KB at most
  - 1,000 live keys per app
  - 5 MB per app
  - Writes over a limit get `413` with the limit in the `error` sentence.
- **Deleting an app** in the admin asks whether to delete its data too. The default is to keep the data, so an app can be deleted and re-created without losing anything.

### 8.2 API

These endpoints use the same bearer token and helpers as the rest of the API.

| Method | Path | Body | Returns |
|---|---|---|---|
| GET | `/api/apps/{slug}/data` | | `{ "entries": { key: value }, "rev": n }` with live keys only |
| GET | `/api/apps/{slug}/data?since={rev}` | | `{ "changes": [{ key, value \| null, rev }], "rev": n }` with tombstones included |
| GET | `/api/apps/{slug}/data/{key}` | | the JSON value, or `404` |
| PUT | `/api/apps/{slug}/data/{key}` | any JSON | `{ key, rev }` |
| DELETE | `/api/apps/{slug}/data/{key}` | | `{ key, rev }` |
| POST | `/api/apps/{slug}/data` | `{ "set": { key: value }, "delete": [key] }` | `{ "rev": n }`, in one transaction (`DB.batch`) |

- **Writable without an app:** the slug doesn't need a row in `apps`. The store can also back a script or a page that has no app.
- **Conflicts:** the last write to reach the server wins, per key. There is one user, and the realistic conflict is the same person on two devices, so per-key last-write-wins is enough. Merging isn't worth its complexity.
- **Admin:** the app editor gets a Data tab. It lists the keys, their size and when each was updated, shows a value as formatted JSON that can be edited in place, and deletes keys.
- **Tests:**
  - `rev` increases across interleaved writes
  - `since` returns tombstones
  - the batch is atomic when one value is too large
  - the size limits
  - a `401` with no data in the body

### 8.3 On the phone

- **Store:** `AppData` holds the open app's entries in memory behind a lock (`Mutex`), so a read or a write is a dictionary lookup that never waits. It is not an actor and never touches the main actor. Kiln blocks the main thread while it waits for a `db://` answer, and anything that hopped there would deadlock.
- **On disk:** one JSON file per app in `Application Support/data/{slug}.json`, holding `{ entries: { key: { value, rev } }, dirty: [key], rev }`. `DataSync`, an actor, writes it 0.5 s after the last change, and at once when the app closes or Shelf leaves the foreground. It also does the pull and push below.
- **Local first:** reads and writes from an app go to this store and return at once, even offline.
- **Pull:**
  - On app open, `GET …/data?since={rev}`, capped at 1 s; after that the app opens with what is on the phone.
  - On every library sync (§4).
  - A pulled change never overwrites a key that is still dirty on the phone. The phone's value is pushed next.
- **Push:**
  - Dirty keys are pushed with the batch `POST`, 2 s after the last write, when the app closes, and when Shelf goes to the background (`beginBackgroundTask`).
  - A failed push leaves the keys dirty for the next attempt.
- **Cursor:** the `rev` in the file moves only on a pull. A push stores the returned `rev` on the keys it sent and leaves the cursor alone, so a write from another device that landed in between is still pulled.

### 8.4 How apps reach it

`ShelfDBProtocol` is a `URLProtocol` subclass that Shelf registers with `URLProtocol.registerClass` while an app runs. It handles only the `db` scheme. It answers from `AppData` without touching the network, so Kiln's blocking `await URLSession.shared.data(from:)` returns immediately.

| Request | Answer |
|---|---|
| `GET db://data/{key}` | `200` with the JSON value, or `404` |
| `PUT db://data/{key}` with a JSON body | `204` |
| `DELETE db://data/{key}` | `204` |
| `GET db://data/` | `200` with `{ key: value }` for every key |

- **Scoping:** the slug is never in the URL. The protocol answers for the app that is currently open, because Shelf runs one app at a time. An app therefore can't read or write another app's data, even by building its own URLs.
- **Token:** the token never enters an app. The protocol works locally, and `AppData` adds the token only when it syncs with the server.
- **Shared session:** the protocol is registered on `URLSession.shared`, the session Kiln uses, and removed when the runner closes.

The prelude Shelf appends (§6.3), so app code stays short:

```swift
enum DB {
    static func load(_ key: String) -> Data? {
        guard let url = URL(string: "db://data/" + key),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
    static func save(_ key: String, _ data: Data) {
        var request = URLRequest(url: URL(string: "db://data/" + key)!)
        request.httpMethod = "PUT"
        request.httpBody = data
        _ = try? await URLSession.shared.data(for: request)
    }
    static func remove(_ key: String) {
        var request = URLRequest(url: URL(string: "db://data/" + key)!)
        request.httpMethod = "DELETE"
        _ = try? await URLSession.shared.data(for: request)
    }
}
```

Usage in an app:

```swift
struct Todo: Codable, Identifiable { var id = UUID(); var title: String; var done = false }

@State private var todos: [Todo] = []

.onAppear {
    if let data = DB.load("todos") { todos = (try? JSONDecoder().decode([Todo].self, from: data)) ?? [] }
}
.onChange(of: todos) { if let data = try? JSONEncoder().encode(todos) { DB.save("todos", data) } }
```

**Check first.** Before building the rest of this, run the prelude and this example through `Kiln.validate` in a unit test. The test confirms that Kiln's engine accepts:

- a tuple pattern inside `guard let` (the parser has it)
- `try?` around `await`
- `as? HTTPURLResponse` followed by `.statusCode`
- `JSONEncoder().encode` on an array of structs, which needs the fork (§0.2), and a `decode` of the result that gives back equal values

If any of these fails, simplify the prelude to fit before writing anything that depends on it. This is step 2 of the build order.

## 9. Making apps

You never write Swift by hand. Shelf hands you a prompt, you paste it into any chat model or agent, and the app comes back either through the agent (with a one-time key in the prompt) or as a reply you paste into Shelf. All three ways in end with the same `PUT /api/apps/{slug}`.

| Where | How | When |
|---|---|---|
| **Shelf** (main path) | Copy the prompt, paste the reply, preview the app, install it | On the phone, from any chat app |
| **ij5.dev admin** | Paste the reply into New App | At a desk |
| **Agent** | The copied prompt carries a one-time install key (§9.5), and the agent runs `curl -X PUT` itself | Claude Code or any agent that can run commands |

### 9.1 The prompts

The prompts are the files in [`prompts/`](prompts). The app bundles them as resources, and `Prompts.swift` fills in the `{{…}}` placeholders at copy time.

| File | Is | Placeholders |
|---|---|---|
| `new.md` | the prompt for a new app: the idea and the reply format | `{{IDEA}}`, `{{RULES}}`, `{{INSTALL}}` |
| `change.md` | the prompt for changing an app: the change, the current app, and how to keep saved data loading | `{{CHANGE}}`, `{{CURRENT}}`, `{{RULES}}`, `{{INSTALL}}` |
| `rules.md` | `{{RULES}}`: what Kiln runs, `@AppStorage` and `DB`, what Kiln doesn't run, and the design rules | |
| `install-new.md`, `install-change.md` | `{{INSTALL}}`: the `curl` command for an agent with a shell (§9.5). Empty when there is no key. | `{{ORIGIN}}`, `{{KEY}}`, `{{EXPIRES}}`, `{{SLUG}}` |
| `current-source.md` | `{{CURRENT}}` with Include Source on | `{{SOURCE}}` |
| `current-outline.md` | `{{CURRENT}}` with Include Source off | `{{ORIGIN}}`, `{{SLUG}}`, `{{KEY}}`, `{{OUTLINE}}` |

Keep `rules.md` in step with the Kiln version pinned in §0.2. When Kiln is updated, re-check the "What works" and "What doesn't work" sections against its README and `STATUS.md`. A test (§9.4) catches the obvious drift: every feature listed under "What works" has a fixture app that must pass `Kiln.validate`.

### 9.2 In Shelf

**New app**

1. In edit mode, a glass `+` button (`UIButton.Configuration.glass()`) sits in the top-left corner, where Springboard puts its widget button.
2. It opens a New App sheet with one multi-line field, focused, with the placeholder "Describe the app".
3. **Copy Prompt** (`.glassProminent`) fills `{{IDEA}}` with the text and copies the prompt.
   - The button turns into "Copied" with a checkmark for 1.5 s, using the `contentTransition(.symbolEffect)` swap.
   - A `ShareLink` next to it sends the prompt straight to a chat app.
4. When you come back with the reply copied, a `PasteButton` appears. It is the system paste button, so iOS shows no "Allow Paste" prompt.
5. Shelf parses the reply:
   - `Kiln.swiftSource(fromMarkdown:)` extracts the Swift (a reply with no fences is used as it is).
   - The three header lines become the name, icon and tint.
   - The slug is the name in lowercase with hyphens, editable, and checked for clashes with installed apps.
6. A live preview runs the app with Kiln inside the sheet. Its data goes to a scratch `DB` store that is thrown away when the sheet closes.
   - Compile errors show the error screen from §7, so a broken reply can be sent back to the model with Copy Error. That copies the error and the lines around it.
7. **Install** saves the app with the `PUT` request.
   - The sheet closes and the new icon lands in the first empty slot. Its install pie fills and the blue dot appears, exactly as for a synced app.
   - Offline, Install is disabled and says "Offline".

**Change an app**

- An icon's context menu gains **Change…**, which opens the same sheet with a "Describe the change" field.
- Copy Prompt fills `change.md`. An **Include Source** toggle in the sheet decides what goes into `{{CURRENT}}`: `current-source.md` when on, `current-outline.md` when off. The toggle defaults to on and remembers its last setting.
  - **On:** the full source.
  - **Off:** an outline, and a `curl` command that lets an agent fetch the source itself with the install key. The source then never goes into the chat history, and an agent with a shell still sees all of it.
- The outline is built by `Outline.swift` with no model involved:
  - the header lines
  - every type that is saved (`Codable` types and the types they contain), with its full declaration, so the saved shape is kept
  - the `DB` and `@AppStorage` key names used, read from string literals
  - every other type and function as its signature only, with the body replaced by `{ … }`
- Paste, preview and **Update** work as for a new app. The preview uses a copy of the app's real data, so the change can be checked against it without touching the original.

### 9.3 In the ij5.dev admin

- **New App:** one textarea. Paste the reply and the form fills in name, icon, tint, slug and source using the same parsing rules. The fields are still editable before Save.
- The prompt is not shown in the admin. The phone owns the prompt, because the Kiln version on the phone decides what works. To start from a desk, copy `prompts/new.md` and `prompts/rules.md` from GitHub.

### 9.4 Parsing and tests

- **The parser** extracts the Swift blocks, reads the `// Name:`, `// Icon:` and `// Tint:` lines (case-insensitive, at the top of the file) and turns the name into a slug.
- **Two copies:** the parser exists in Swift (Shelf) and TypeScript (admin). Both run against the same fixture replies in `fixtures/replies/*.md`, and each fixture has the expected result next to it, so the two copies can't drift apart.
- **The header lines stay in the stored source.** They are harmless comments, and they make a copied app reinstallable as it is.
- **Unknown values:** an unknown tint falls back to `blue`, and an icon name that isn't an SF Symbol falls back to `app`. Shelf checks with `UIImage(systemName:)`; the admin warns but doesn't block.
- **Feature fixtures:** one small app per line under "What works" in `prompts/rules.md`, each of which must pass `Kiln.validate`.
- **Outline tests:** for each fixture app, the outline keeps every saved type in full and every key name, and contains no function body.

### 9.5 Install keys

Every copied prompt carries a one-time key, so an agent that can run commands (Claude Code, Codex and the like) installs the app itself. You don't need to paste anything back.

**Threat model.** A prompt pasted into a chat service lives in that service's history, and an agent can be steered by text it reads. So a key that leaks must be worth very little:

- **Scope:**
  - A key for a new app can create one app under a slug that is free. It can never overwrite an existing app.
  - A key from Change… can update one named slug.
  - A Change… key can also run `GET /api/apps/{slug}/source` for its own slug, which returns the raw file. Reading doesn't use up the key. That way an agent can fetch the source when Include Source is off.
  - Neither kind can read other apps, read or write data, mint keys, or reach any other API.
- **One use:** the first successful `PUT` consumes the key. A failed attempt (`400`, `409`, `413` or `422`) doesn't, so an agent can fix its code and retry. After 5 failed attempts the key is burned anyway.
- **Short life:** a key expires 30 minutes after it is minted.
- **Hashed at rest:** only a hash of the secret is stored, the same way `AUTH_HASH` is stored for the admin token.
- **No admin token in the prompt:** Shelf mints the key with the admin token, but only the key is copied.
- **Reversible:** every write keeps the app's previous version in `app_versions` (below), the last 10 per app. An install made through a key shows up in Shelf with the blue dot, and the icon's context menu offers Revert. Revert fetches the previous version and `PUT`s it back with the admin token, so it is an ordinary write and can itself be reverted. That gives an undo for a bad agent push.

**Key format.** The key is `shelf_ik_{id}_{secret}`:

- `id`: 8 random bytes, base64url. It is public, and Shelf uses it to check the key's status.
- `secret`: 32 random bytes, base64url, from `crypto.getRandomValues`.
- The `shelf_ik_` prefix sends the request to install-key checking without trying the admin hash. Secret scanners such as GitHub's can also be taught the prefix.

**Server**

`migrations/0011_install_keys.sql`:

```sql
CREATE TABLE install_keys (
  id          TEXT PRIMARY KEY,
  secret_hash TEXT NOT NULL,            -- sha256(secret), base64
  slug        TEXT,                     -- null: create one new app; set: update this app
  created_at  INTEGER NOT NULL,
  expires_at  INTEGER NOT NULL,
  attempts    INTEGER NOT NULL DEFAULT 0,
  used_at     INTEGER,
  used_slug   TEXT                      -- what it installed, for Shelf to pick up
);

CREATE TABLE app_versions (            -- history for Revert
  slug TEXT NOT NULL, version TEXT NOT NULL, name TEXT NOT NULL, icon TEXT, tint TEXT NOT NULL,
  source TEXT NOT NULL, origin TEXT NOT NULL,          -- 'admin' | 'key'
  created_at INTEGER NOT NULL,
  PRIMARY KEY (slug, version)
);
```

| Method | Path | Auth | Does |
|---|---|---|---|
| POST | `/api/install-keys` | admin | `{ slug? }` → `{ key, id, expires_at }`. Expired keys are purged here, and at most 20 live keys are allowed. |
| GET | `/api/install-keys/{id}` | admin | `{ status: "waiting" \| "used" \| "expired", slug? }` |
| DELETE | `/api/install-keys/{id}` | admin | Revokes the key. |
| GET | `/api/apps/{slug}/versions` | admin | `{ "versions": [{ version, name, origin, created_at }] }`, newest first |
| GET | `/api/apps/{slug}/versions/{version}` | admin | `AppFull` as it was |
| PUT | `/api/apps/{slug}` | admin **or** install key | Also accepts `Content-Type: text/x-swift`: the raw file, with name, icon and tint read from the header lines by the §9.4 parser. |

- **Consuming the key:** one conditional `UPDATE install_keys SET used_at = ?, used_slug = ? WHERE id = ? AND used_at IS NULL AND expires_at > ?` runs in the same `DB.batch` as the app write. Two requests racing with one key therefore can't both succeed. The one whose `UPDATE` changes no row rolls back with `401`.
- **Checking the secret:** the lookup is by `id`, and the secret's hash is compared with `eq()` in constant time.
- **Errors:** every failure with a key returns the same `401` sentence, "This key is used, expired or wrong", so a caller can't tell which.
- **Logging:** keys never reach the logs, and the response never echoes one.
- **Admin:** the Security page lists live keys (id, scope, expiry) with Revoke.

**In Shelf**

- **Minting:** the New App and Change… sheets mint a key when they open, so Copy Prompt stays instant.
  - Copy Prompt fills in `{{ORIGIN}}`, `{{KEY}}` and `{{EXPIRES}}` (local time, for example "3:42 PM"), plus `{{SLUG}}` in the change prompt.
  - If the key can't be minted, because Shelf is offline, `{{INSTALL}}` is empty and paste still works. Include Source is then on and can't be turned off, because the outline's `curl` needs a key.
- **Waiting for the agent:**
  - While the sheet is open and Shelf is in the foreground, Shelf checks the key's status every 3 s.
  - It also checks once when Shelf returns to the foreground, which is the usual case: you were in the agent's app.
  - When the status is `used`, Shelf syncs and closes the sheet. The icon lands with its install pie and blue dot.
- **Paste still works:** a pasted reply installs with the admin token as before, and Shelf revokes the unused key.
- **Closing the sheet** without an install leaves the key alive until it expires. The prompt may already be in an agent's hands, so revoking it then would break an install in progress.

**Tests (vitest)**
- A create key can't overwrite an existing app.
- An update key can't write a different slug.
- Two parallel `PUT`s with one key produce exactly one success.
- A failed `422` leaves the key usable, and the sixth failure burns it.
- The key works only on `PUT /api/apps/{slug}`, plus `GET /api/apps/{slug}/source` for an update key on its own slug. Every other route, and a read by a create key, returns `401`.
- An expired key returns `401`.
- A `text/x-swift` body parses its header the same way as the shared fixtures.

## 10. Build order

Each step ends in something that can be run. This is the order for one builder working alone. With agents, §12.3 runs the same steps in parallel waves.

1. **ij5.dev:** migrations, `apps.ts`, the apps API and the data API (§8.1–8.2), and tests. Deploy, then add one app with `curl`.
   Then install keys and `app_versions` (§9.5), with their tests.
2. **Kiln fork:** add `JSONEncoder().encode` with tests, and open the pull request upstream (§0.2).
   **shelf:** XcodeGen project, the Kiln fork pinned by revision, and models. A test runs `Kiln.run` on a fixture, and the `DB` prelude and example from §8.4 pass `Kiln.validate`.
   Then three throwaway spikes on a real phone, because the plan leans on each: the time `Kiln.run` takes on a 600-line app (§6.2), the UIKit zoom from a collection view cell into a hosted SwiftUI view (§6.1), and a `UIGlassContainerEffect` holding two glass views over a photo (§5.4).
3. `SyncEngine` with `URLProtocol` stub tests for 304, a partial failure, a deleted app, a `401` and offline.
4. A plain Home Screen: wallpaper, grid, icon, label, and the runner with the zoom transition. A real phone starts using it here.
5. The dock, Settings and the connect flow.
6. The detail pass: pressed state, blue dot, install pie, banner, dark icons, search pill and search.
7. Edit mode: jiggle, drag to reorder, dock pinning and paging.
8. The error screen and `SourceRewriter`.
9. App data on the phone: `AppData`, `ShelfDBProtocol` and the prelude, with tests that a write made offline syncs later and a dirty key survives a pull.
10. Making apps in Shelf (§9.2): the New App sheet, `PasteButton`, preview and install, then Change… with the edit prompt. Then minting install keys, waiting for the agent, and Revert (§9.5).
11. **ij5.dev:** the admin editor, with the Data tab and paste-to-fill (§9.3).
12. The overlay pass (§11).

---

## 11. Checking the details

- **Metrics:**
  - Screenshot Springboard and Shelf with the same wallpaper on the same device.
  - Overlay them at 50% opacity and adjust icon size, insets, row distribution, label offset, dock inset and radius until the edges line up.
  - Write the final numbers back into `HomeMetrics.swift`, the one place they live.
- **Motion:**
  - Record both screens at 60 fps and compare frame by frame:
    - app open and close
    - jiggle period
    - icon press darkening
    - the spring on reordered icons
  - Compare the curves, not just the durations.
- **Dark mode, every icon style and both ends of the iOS 27 glass setting:** check each the same way.

---

## 12. Working with agents

The plan is built by one lead agent and a group of subagents. The lead is the only agent that sees the whole plan at once. Every other agent gets a small piece with clear edges.

### 12.1 Roles and models

| Role | Model | Does | Never does |
|---|---|---|---|
| **Lead** | the strongest available (Opus) | Writes the contracts in §12.2, briefs each package, reviews every diff against the plan and §13, merges, runs the design passes in §11 | Writes large features itself while workers are running |
| **Builder** | Opus for UI and anything in §5, §6 or §9.5. Sonnet for plumbing with a clear spec (migrations, CRUD routes, Keychain) | One work package, inside its own files | Edits a file outside its package |
| **Test writer** | Sonnet | Writes tests from the plan and the contracts, **without reading the implementation**, so a misreading of the spec shows up as a failing test instead of being copied | Changes production code |
| **Test runner** | Haiku | Runs the suites, the `Kiln.validate` fixtures and the lint, and reports failures with the exact output, the file and the likely cause in one line | Fixes anything |
| **Reviewer** | Sonnet, then Opus for anything visual | Checks a diff against its brief and the §13 checklist, and lists gaps with `file:line` | Rewrites the diff |

- **Use the cheapest model that can do the job.** Running and triaging tests is Haiku's job, and writing tests against a clear spec is Sonnet's. Taste stays with Opus: visual judgement, motion, the final look of anything a person sees, and security in §9.5.
- **Escalate failures.** When a Haiku runner reports a failure it can't explain in one line, the lead hands it to a Sonnet or Opus agent with the output. The runner doesn't retry.

### 12.2 Contracts first (wave 0, lead only)

Before any worker starts, the lead commits the things more than one package depends on. After that, only the lead changes them. A worker that needs a change asks the lead and stops; it doesn't make the change itself.

- **ij5.dev**
  - The migration numbers, reserved in advance: `0009_apps`, `0010_app_data`, `0011_install_keys` (with `app_versions`). Each is an empty file with a header comment, so no two packages pick the same number.
  - In `src/lib/types.ts`: `AppMeta`, `AppFull`, `Tint`, `TINTS`, `MAX_APP_BYTES` and the data limits.
  - In `src/lib/server/api.ts`: the signature of `authorizeApp(request, env, { slug, action: 'read-source' | 'write' })`, as a stub that accepts only the admin token. Package S3 fills it in.
  - The JSON error shapes, which follow the existing `apiError`.
- **shelf**
  - `project.yml`, the Kiln pin, the target layout from §2 with empty files, and `Model/` complete: `AppMeta`, `AppFull`, `Tint`, `Layout`.
  - The interfaces between packages: `LibraryStore` (what the Home Screen reads), `AppData` (what the runner and the `db` protocol call), and `ReplyParser` (what the sheets call). Each comes with a fake that has preview data, so the UI can be built before the real store exists.
  - `HomeMetrics.swift` with every number in §5 as a named constant, and `Motion.swift` with every spring and duration from §5 and §6. Later work changes the values there, never in the view code.
- **Shared fixtures**
  - `fixtures/api/*.json`: real responses for every endpoint.
  - `fixtures/replies/*.md` with the results expected from parsing them.
  - `fixtures/apps/*.swift`: the feature apps from §9.4.
  - Both repos' tests read these.

### 12.3 Work packages

Each package owns its files, listed below, and nothing else. Two packages that need the same file run one after the other, never at the same time.

| # | Package | Owns | Depends on | Wave |
|---|---|---|---|---|
| S1 | Apps API, versions, ETag | `server/apps.ts`, `routes/api/apps/+server.ts`, `routes/api/apps/[slug]/+server.ts`, `[slug]/source/`, `0009` | contracts | 1 |
| S2 | Data API | `server/appdata.ts`, `routes/api/apps/[slug]/data/**`, `0010` | contracts | 1 |
| S3 | Install keys | `server/installkeys.ts`, `authorizeApp` in `api.ts`, `routes/api/install-keys/**`, `0011` | contracts | 1 |
| P | Reply parser and outline | `lib/replyParser.ts`, `Create/ReplyParser.swift`, `Create/Outline.swift` | fixtures | 1 |
| I1 | Store and sync | `Store/**` | contracts | 1 |
| I2 | Home Screen | `Home/**` except edit mode | `LibraryStore` fake | 1 |
| I3 | Runner and errors | `Runner/**` | contracts | 1 |
| I4 | App data on the phone | `Data/**` | `AppData` contract | 1 (the prelude check from §8.4 runs first, as a gate) |
| I5 | Edit mode | `Home/EditController.swift`, `Home/Jiggle.swift`, the edit hooks in `HomeViewController.swift` | I2 merged | 2 |
| I6 | New App and Change… sheets | `Create/NewAppSheet.swift`, `Create/Prompts.swift` | P, I3, S3 merged | 2 |
| I7 | Connect and Settings | `Settings/**` | I1 merged | 2 |
| A | Admin pages | `routes/admin/apps/**`, the rows added to `admin/api` and `admin/security` | S1–S3 merged | 2 |
| T | Tests from the spec | `*.test.ts`, `ShelfTests/**` for each package above | contracts | 1–2, alongside the package it tests |
| L | Integration and the §11 overlay pass | anything | everything | 3 |

- **Shared files:** some files are touched by more than one package (`api.ts`, `types.ts`, `RESERVED`, `project.yml`, `App/**`, `prompts/**`). They belong to the lead, or to one named package as shown in the table. Others ask for a change; they don't edit.
- **Isolation:** each worker runs in its own git worktree on its own branch (`isolation: "worktree"`). The lead merges in dependency order and runs every test suite after each merge.
- **Builds:** iOS packages need a Mac with Xcode. The server packages and the parser's TypeScript half can run in a cloud session.

### 12.4 Briefing a worker

Every brief has the same parts. A brief missing one of them isn't ready to send.

- **Goal:** one sentence.
- **Read:** the plan sections that apply, by number, and the contract files.
- **Owns:** the exact files the worker may change.
- **Must not touch:** everything else, especially the shared files in §12.3.
- **Done when:**
  - the package's tests pass
  - the §13 checklist items that apply to the package are met, with screenshots for UI
  - nothing outside the owned files has changed (`git diff --stat`)
- **Report:**
  - what changed
  - what was left undone, and why
  - any contract change it needs
  - the screenshots or test output that prove the "Done when" items

A worker that discovers the plan is wrong says so in its report. It doesn't quietly work around the problem.

---

## 13. Craft

Shelf is judged by how it feels in the hand. Every package is held to this section; the reviewer checks it and the lead enforces it.

### 13.1 Design engineering

- **No magic numbers.** Every size, inset, radius, duration and spring comes from `HomeMetrics` or `Motion`. A number in a view file is a review failure.
- **Springs, not curves.** Movement uses springs (`UIView.animate(springDuration:bounce:)` in UIKit, `.spring(duration:bounce:)` in SwiftUI), with no ease curve on anything spatial. Animations can be interrupted: tapping during an open or close reverses it from where it is, without snapping or queueing.
- **Shapes:**
  - Every rounded shape has a continuous corner curve (`cornerCurve = .continuous` in UIKit, `style: .continuous` in SwiftUI).
  - Nested shapes are concentric: the inner radius is the outer radius minus the inset.
  - Glass comes only from the system (§0.1).
- **Feedback is immediate.**
  - A press state shows on touch-down.
  - Haptics accompany a launch, the start of edit mode, a reorder snap and an install, and nothing else.
- **Nothing flashes or jumps.**
  - Spinners appear only after 300 ms, so fast loads show none.
  - Layout doesn't shift when data arrives: icons take their final place first and fill in after.
  - Text never reflows during a transition.
- **Every screen has every state.** Loading, empty, offline, error and success are each designed, not left to a default.
- **Optical alignment over arithmetic.** Glyphs are centred by eye (SF Symbols' alignment, plus a fixed offset where needed). Text and glyph weights match: a `.medium` glyph sits next to `.medium` text.
- **Dynamic Type everywhere.**
  - All text uses a text style (`.body`, `.headline`, `.footnote` and so on), or a scaled metric where a design needs a specific size: `@ScaledMetric(relativeTo:)` in SwiftUI, `UIFontMetrics` in UIKit.
  - A fixed, unscaled font size is a review failure.
  - Glyphs that sit next to text scale with it: SF Symbols in a `Label` or set with `.font(.body)`.
  - Layouts that could overflow at large sizes are capped at `.xxxLarge` (`.dynamicTypeSize(...)` or `maximumContentSizeCategory`), as Apple's apps do.
  - The only screens that cap lower are the Home Screen labels and the dock.
- **Hit targets:** at least 44×44 pt, even where the visible shape is smaller.
- **Words:**
  - Buttons are in Title Case, as in Apple's apps. Labels are short.
  - No taglines, helper text or secondary labels. If a screen needs them to make sense, fix the layout.
  - No all-caps text.
- **Performance:**
  - 120 fps on ProMotion devices while scrolling, jiggling and during the zoom transition, checked with the Instruments hitches tool.
  - No work on the main thread during a transition. Sources are parsed and data is pulled before the animation starts, or after it ends.
  - Nothing that moves has a layer mask or a layer shadow. Shapes come from `cornerRadius` with `cornerCurve`, and shadows are drawn into the bitmap.
  - The Home Screen builds no SwiftUI view per icon.

### 13.2 Definition of done for UI work

These are checked with screenshots attached to the report:

- [ ] light and dark mode
- [ ] Dynamic Type at the default size and at `.xxxLarge`: nothing clips or overlaps
- [ ] the offline and error states
- [ ] the overlay comparison from §11, for anything that has a Springboard equivalent
- [ ] for motion: a screen recording, compared frame by frame with the same motion on Springboard

### 13.3 Definition of done for server work

- [ ] errors follow `apiError`: one sentence a person can act on, no stack traces, no hint about whether a credential exists
- [ ] secrets and keys never appear in logs or responses
- [ ] every write keeps D1 and any mirror consistent, or rolls back, as `slugs.ts` already does
- [ ] tests for each status code the route can return
- [ ] the comments explain why, in the voice of the existing code

---

## Later

- Run `Kiln.validate` before an app can be saved. Validation needs Swift, so it runs either in Shelf as a "Check" action against a sandboxed copy of the app's storage, or in a small macOS CLI.
- Home Screen shortcuts per app through App Intents (`OpenShelfAppIntent` with an `AppEntity` per app), and Spotlight indexing through `IndexedEntity`.
- A device token in place of the admin token on the phone. It would be minted the same way as install keys, and could read apps, read and write data, and mint install keys, but nothing else on ij5.dev.
- Native bridges with `Kiln.register` (haptics, opening a URL), documented in the admin page for authors.
- Widgets that open an app directly.
- Live updates to app data while an app is open (a long-poll on `?since=`), so a change made on another device shows up without reopening the app.
- Data that several apps share, through a `db://shared/` namespace.
